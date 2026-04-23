#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
List all models in DeepRacer on AWS (DRoA).

Fetches the full paginated model list from GET /models and prints it as a
table.  Use --json for machine-readable output.

Usage examples
--------------
  # Print table of all models:
  python list_models.py

  # Raw JSON (suitable for piping to jq):
  python list_models.py --json | jq '[.[] | {id: .modelId, name: .name}]'

  # Override site URL and username on the command line:
  python list_models.py --url https://my.droa.example.com --username alice

Table columns
-------------
  Model ID        15-char alphanumeric model identifier
  Name            Model name (up to 64 chars)
  Status          Current model lifecycle status
  Training        Training job status
  Created At      Creation timestamp (UTC, second precision)

Authentication
--------------
Credentials are obtained via the Cognito Identity Pool embedded in the DRoA
site's /env.js.  A password prompt is shown on the first call; subsequent
calls within the credential lifetime (~1 h) reuse a cache stored in
~/.droa-cache/.

The site URL is read from DR_DROA_URL and the username from DR_DROA_USERNAME
(both set in system.env), or supplied via --url / --username.

Model status values
-------------------
  DELETING  ERROR  EVALUATING  IMPORTING  QUEUED  READY
  STOPPING  SUBMITTING  TRAINING

Training status values
----------------------
  CANCELED  COMPLETED  FAILED  IN_PROGRESS  INITIALIZING  QUEUED  STOPPING
"""

import argparse
import getpass
import json
import os
import sys

import requests

from auth import (
    add_common_args, authenticate, build_auth, get_aws_credentials, load_droa_config,
    load_cached_credentials, save_credentials_to_cache,
)


def list_models(cfg, credentials: dict) -> list:
    """Fetch all models, auto-paginating via token."""
    url = f"{cfg.api_endpoint}/models"
    models = []
    token = None
    while True:
        params = {"token": token} if token else {}
        response = requests.get(
            url, params=params, auth=build_auth(url, credentials, cfg.region, cfg.site_url), timeout=30
        )
        if not response.ok:
            raise RuntimeError(
                f"API error: {response.status_code} {response.reason}\n"
                f"Headers: {dict(response.headers)}\n"
                f"Body: {response.text}"
            )
        data = response.json()
        models.extend(data.get("models", []))
        token = data.get("token")
        if not token:
            break
    return models


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="List models in DeepRacer on AWS.",
        epilog=(
            "examples:\n"
            "  %(prog)s\n"
            "  %(prog)s --json | jq '[.[] | {id: .modelId, name: .name}]'"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    add_common_args(parser)
    parser.add_argument(
        "--json", dest="output_json", action="store_true",
        help="Output raw JSON instead of a table",
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
        password = args.password or getpass.getpass(f"Password for {username}: ")
        id_token = authenticate(cfg.region, cfg.client_id, username, password)
        credentials = get_aws_credentials(cfg.region, cfg.user_pool_id, cfg.identity_pool_id, id_token)
        save_credentials_to_cache(cfg.identity_pool_id, username, credentials)
    models = list_models(cfg, credentials)

    if args.output_json:
        print(json.dumps(models, indent=2, default=str))
        return

    if not models:
        print("No models found.")
        return

    id_w, name_w, status_w, tstatus_w = 15, 40, 16, 16
    header = (
        f"{'Model ID':<{id_w}}  {'Name':<{name_w}}  "
        f"{'Status':<{status_w}}  {'Training':<{tstatus_w}}  Created At"
    )
    print(header)
    print("-" * (id_w + name_w + status_w + tstatus_w + 30))
    for m in models:
        created = m.get("createdAt", "")[:19].replace("T", " ")
        print(
            f"{m.get('modelId', ''):<{id_w}}  "
            f"{m.get('name', ''):<{name_w}}  "
            f"{m.get('status', ''):<{status_w}}  "
            f"{m.get('trainingStatus', ''):<{tstatus_w}}  "
            f"{created}"
        )


if __name__ == "__main__":
    main()
