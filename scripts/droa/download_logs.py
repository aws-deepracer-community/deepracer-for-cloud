#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Download logs or assets for a model from DeepRacer on AWS (DRoA).

Calls GET /models/{modelId}/getasset to obtain a presigned S3 URL, then
downloads the file.  For VIRTUAL_MODEL the server packages the artifact
asynchronously — the script polls until the URL is ready (up to
POLL_TIMEOUT seconds).  All other asset types return a URL immediately
or a 400 error if the underlying job has not yet completed.

Usage examples
--------------
  # Download training logs (default):
  python download_logs.py 2w7R6h2PNexQ9kC

  # Download and immediately print a training stability summary:
  python download_logs.py 2w7R6h2PNexQ9kC --summary

  # Download training logs to a specific file:
  python download_logs.py 2w7R6h2PNexQ9kC -o training.tar.gz

  # Download evaluation logs (evaluation ID required):
  python download_logs.py 2w7R6h2PNexQ9kC --asset-type EVALUATION_LOGS --evaluation-id <evalId>

  # Download virtual model artifact (polls until packaging completes):
  python download_logs.py 2w7R6h2PNexQ9kC --asset-type VIRTUAL_MODEL

  # Override site URL and username on the command line:
  python download_logs.py 2w7R6h2PNexQ9kC --url https://my.droa.example.com --username alice

Asset types
-----------
  TRAINING_LOGS       Logs from the training job (job must be COMPLETED or FAILED)
  EVALUATION_LOGS     Logs from an evaluation run (requires --evaluation-id;
                      job must be COMPLETED or FAILED)
  PHYSICAL_CAR_MODEL  Physical car model artifact
  VIRTUAL_MODEL       Virtual model package (packaged asynchronously; script polls)
  VIDEOS              Evaluation video recordings

Authentication
--------------
Credentials are obtained via the Cognito Identity Pool embedded in the DRoA
site's /env.js.  A password prompt is shown on the first call; subsequent
calls within the credential lifetime (~1 h) reuse a cache stored in
~/.droa-cache/.

The site URL is read from DR_DROA_URL and the username from DR_DROA_USERNAME
(both set in system.env), or supplied via --url / --username.
"""

import argparse
import getpass
import os
import sys
import time
from urllib.parse import urlparse

import requests

from auth import (
    add_common_args, authenticate, build_auth, get_aws_credentials, load_droa_config,
    load_cached_credentials, save_credentials_to_cache,
)

ASSET_TYPES = ["TRAINING_LOGS", "EVALUATION_LOGS", "PHYSICAL_CAR_MODEL", "VIRTUAL_MODEL", "VIDEOS"]
POLL_INTERVAL = 5    # seconds between status checks
POLL_TIMEOUT  = 300  # seconds before giving up (packaging can take a while)


def get_asset_url(cfg, credentials, model_id, asset_type, evaluation_id=None):
    """Call GET /models/{modelId}/getasset, polling while status is QUEUED."""
    url = f"{cfg.api_endpoint}/models/{model_id}/getasset"
    params = {"assetType": asset_type}
    if evaluation_id:
        params["evaluationId"] = evaluation_id

    deadline = time.monotonic() + POLL_TIMEOUT
    while True:
        response = requests.get(
            url, params=params,
            auth=build_auth(url, credentials, cfg.region, cfg.site_url),
            timeout=30,
        )
        if not response.ok:
            raise RuntimeError(
                f"API error: {response.status_code} {response.reason}\n{response.text}"
            )
        data = response.json()
        if data.get("url"):
            return data["url"]
        # Only VIRTUAL_MODEL returns status:QUEUED while packaging
        status = data.get("status", "UNKNOWN")
        if status != "QUEUED":
            raise RuntimeError(
                f"No URL returned and unexpected status '{status}'. "
                f"The asset may not be available yet."
            )
        if time.monotonic() > deadline:
            raise RuntimeError(f"Timed out waiting for asset after {POLL_TIMEOUT}s.")
        print(f"  Packaging in progress (status: {status}) — retrying in {POLL_INTERVAL}s...", file=sys.stderr)
        time.sleep(POLL_INTERVAL)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Download logs/assets from a DeepRacer on AWS model.",
        epilog=(
            "examples:\n"
            "  %(prog)s 2w7R6h2PNexQ9kC\n"
            "  %(prog)s 2w7R6h2PNexQ9kC --asset-type EVALUATION_LOGS --evaluation-id <evalId>\n"
            "  %(prog)s 2w7R6h2PNexQ9kC --asset-type VIRTUAL_MODEL -o model.tar.gz"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    add_common_args(parser)
    parser.add_argument("model_id", help="Model ID")
    parser.add_argument(
        "--asset-type", default="TRAINING_LOGS", choices=ASSET_TYPES,
        help="Asset type to download (default: TRAINING_LOGS)",
    )
    parser.add_argument(
        "--evaluation-id", default=None,
        help="Evaluation ID — required when --asset-type is EVALUATION_LOGS",
    )
    parser.add_argument(
        "--output", "-o", default=None,
        help="Output file path (default: derived from the presigned URL filename)",
    )
    parser.add_argument(
        "--summary", action="store_true",
        help="After downloading, load the archive with DeepRacer Utils and print a training stability summary (TRAINING_LOGS only)",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    username = args.username or os.environ.get("DR_DROA_USERNAME")
    if not username:
        print("Error: --username or DR_DROA_USERNAME required.", file=sys.stderr)
        sys.exit(1)

    if args.asset_type == "EVALUATION_LOGS" and not args.evaluation_id:
        print("Error: --evaluation-id is required for EVALUATION_LOGS.", file=sys.stderr)
        sys.exit(1)

    cfg = load_droa_config(args)

    credentials = load_cached_credentials(cfg.identity_pool_id, username)
    if credentials:
        print("Using cached credentials.", file=sys.stderr)
    else:
        password = args.password or getpass.getpass(f"Password for {username}: ")
        id_token = authenticate(cfg.region, cfg.client_id, username, password)
        credentials = get_aws_credentials(cfg.region, cfg.user_pool_id, cfg.identity_pool_id, id_token)
        save_credentials_to_cache(cfg.identity_pool_id, username, credentials)

    print(f"Requesting {args.asset_type} for model {args.model_id}...", file=sys.stderr)
    presigned_url = get_asset_url(
        cfg, credentials, args.model_id, args.asset_type, args.evaluation_id
    )

    dl_response = requests.get(presigned_url, timeout=120, stream=True)
    if not dl_response.ok:
        raise RuntimeError(f"Download failed: {dl_response.status_code} {dl_response.reason}")

    out_path = args.output
    if not out_path:
        url_filename = os.path.basename(urlparse(presigned_url).path)
        out_path = url_filename or f"{args.model_id}_{args.asset_type.lower()}.bin"

    with open(out_path, "wb") as f:
        for chunk in dl_response.iter_content(chunk_size=65536):
            f.write(chunk)

    print(f"Downloaded to: {out_path}", file=sys.stderr)

    if args.summary:
        if args.asset_type != "TRAINING_LOGS":
            print(
                f"Warning: --summary is only supported for TRAINING_LOGS, skipping.",
                file=sys.stderr,
            )
        else:
            try:
                from deepracer.logs import DeepRacerLog, TarFileHandler
            except ImportError:
                print(
                    "Error: deepracer-utils is not installed. "
                    "Run: pip install deepracer-utils",
                    file=sys.stderr,
                )
                sys.exit(1)
            print(file=sys.stderr)
            fh = TarFileHandler(archive_path=out_path)
            log = DeepRacerLog(filehandler=fh, verbose=True)
            log.load_training_trace()
            log.stability.print_summary()


if __name__ == "__main__":
    main()
