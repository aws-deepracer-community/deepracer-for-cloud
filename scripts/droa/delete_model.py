#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Delete a model from DeepRacer on AWS (DRoA).

Sends DELETE /models/{modelId}.  Before issuing the request the script fetches
the model record and verifies its status — the API only permits deletion when
the model is in READY or ERROR state.  Any other status results in a clear
error message without making the DELETE call.

Deletion is asynchronous on the server: the model status transitions to
DELETING immediately, then S3 artifacts, training records and evaluation
records are removed in the background.  If any step fails the server reverts
the status to ERROR for manual cleanup.

Usage examples
--------------
  # Interactive confirmation (shows model name and current status):
  python delete_model.py 2w7R6h2PNexQ9kC

  # Skip confirmation prompt (use in scripts):
  python delete_model.py 2w7R6h2PNexQ9kC --yes

  # Override site URL and username on the command line:
  python delete_model.py 2w7R6h2PNexQ9kC --url https://my.droa.example.com --username alice

Authentication
--------------
Credentials are obtained via the Cognito Identity Pool embedded in the DRoA
site's /env.js.  A password prompt is shown on the first call; subsequent
calls within the credential lifetime (~1 h) reuse a cache stored in
~/.droa-cache/.

The site URL is read from DR_DROA_URL and the username from DR_DROA_USERNAME
(both set in system.env), or supplied via --url / --username.

Deletable status values
-----------------------
  READY   Model trained successfully and ready for use
  ERROR   Model encountered an error during a previous operation

All other statuses (TRAINING, EVALUATING, IMPORTING, QUEUED, STOPPING,
SUBMITTING, DELETING) are rejected by the API with HTTP 400.
"""

import argparse
import getpass
import os
import sys

import requests

from auth import (
    add_common_args, authenticate, build_auth, get_aws_credentials, load_droa_config,
    load_cached_credentials, save_credentials_to_cache,
)

_DELETABLE_STATUSES = {"READY", "ERROR"}


def fetch_model(cfg, credentials: dict, model_id: str) -> dict:
    url = f"{cfg.api_endpoint}/models/{model_id}"
    response = requests.get(
        url, auth=build_auth(url, credentials, cfg.region, cfg.site_url), timeout=30
    )
    if not response.ok:
        raise RuntimeError(
            f"API error fetching model: {response.status_code} {response.reason}\n{response.text}"
        )
    data = response.json()
    return data.get("model", data)


def delete_model(cfg, credentials: dict, model_id: str) -> None:
    url = f"{cfg.api_endpoint}/models/{model_id}"
    response = requests.delete(
        url, auth=build_auth(url, credentials, cfg.region, cfg.site_url), timeout=30
    )
    if not response.ok:
        raise RuntimeError(
            f"API error: {response.status_code} {response.reason}\n{response.text}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Delete a model from DeepRacer on AWS.",
        epilog=(
            "examples:\n"
            "  %(prog)s 2w7R6h2PNexQ9kC\n"
            "  %(prog)s 2w7R6h2PNexQ9kC --yes"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    add_common_args(parser)
    parser.add_argument("model_id", help="Model ID to delete")
    parser.add_argument(
        "-y", "--yes", action="store_true", help="Skip confirmation prompt"
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    username = args.username or os.environ.get("DR_DROA_USERNAME")
    if not username:
        print("Error: --username or DR_DROA_USERNAME required.", file=sys.stderr)
        sys.exit(1)

    cfg = load_droa_config(args)

    credentials = load_cached_credentials(cfg.identity_pool_id, username)
    if credentials:
        print("Using cached credentials.", file=sys.stderr)
    else:
        password = args.password or getpass.getpass(
            f"Password for {username}: ")
        id_token = authenticate(cfg.region, cfg.client_id, username, password)
        credentials = get_aws_credentials(
            cfg.region, cfg.user_pool_id, cfg.identity_pool_id, id_token)
        save_credentials_to_cache(cfg.identity_pool_id, username, credentials)

    model = fetch_model(cfg, credentials, args.model_id)
    name = model.get("name", args.model_id)
    status = model.get("status", "UNKNOWN")

    if status not in _DELETABLE_STATUSES:
        print(
            f"Error: model '{name}' has status {status} and cannot be deleted.\n"
            f"Only models with status READY or ERROR may be deleted.",
            file=sys.stderr,
        )
        sys.exit(1)

    if not args.yes:
        print(f"Model name : {name}")
        print(f"Model ID   : {args.model_id}")
        print(f"Status     : {status}")
        print()
        confirm = input(
            f"Type the model name to confirm deletion: "
        ).strip()
        if confirm != name:
            print("Aborted.")
            sys.exit(0)

    print(f"Deleting model '{name}' ({args.model_id})...")
    delete_model(cfg, credentials, args.model_id)
    print("Delete request accepted. The model will be removed shortly (status → DELETING).")


if __name__ == "__main__":
    main()
