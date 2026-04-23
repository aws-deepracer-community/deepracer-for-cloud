#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Get details of a specific model from DeepRacer on AWS (DRoA).

Retrieves the full model record from GET /models/{modelId} and prints it in
a human-readable key-value format.  Use --json for machine-readable output.

Usage examples
--------------
  # Basic summary (status, training config, sensors, hyperparameters):
  python get_model.py 2w7R6h2PNexQ9kC

  # Include reward function, action space and Metrics URL:
  python get_model.py 2w7R6h2PNexQ9kC --verbose

  # Raw JSON (suitable for piping to jq):
  python get_model.py 2w7R6h2PNexQ9kC --json | jq .status

  # Override site URL and username on the command line:
  python get_model.py 2w7R6h2PNexQ9kC --url https://my.droa.example.com --username alice

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


def get_model(cfg, credentials: dict, model_id: str) -> dict:
    url = f"{cfg.api_endpoint}/models/{model_id}"
    response = requests.get(
        url, auth=build_auth(url, credentials, cfg.region, cfg.site_url), timeout=30
    )
    if not response.ok:
        raise RuntimeError(
            f"API error: {response.status_code} {response.reason}\n{response.text}"
        )
    data = response.json()
    return data.get("model", data)


def _fmt_bytes(n) -> str:
    if n is None:
        return ""
    for unit, threshold in (("GB", 1024**3), ("MB", 1024**2), ("KB", 1024)):
        if n >= threshold:
            return f"{n / threshold:.1f} {unit}"
    return f"{n} B"


def _kv(key: str, value, indent: int = 0) -> None:
    if value is None or value == "":
        return
    pad = "  " * indent
    print(f"{pad}{key:<22}: {value}")


def print_model(model: dict, verbose: bool = False) -> None:
    _kv("Model ID", model.get("modelId"))
    _kv("Name", model.get("name"))
    _kv("Description", model.get("description"))
    _kv("Status", model.get("status"))
    _kv("Training Status", model.get("trainingStatus"))
    created = (model.get("createdAt") or "")[:19].replace("T", " ")
    _kv("Created At", created)
    _kv("File Size", _fmt_bytes(model.get("fileSizeInBytes")))
    _kv("Packaging Status", model.get("packagingStatus"))
    if model.get("importErrorMessage"):
        _kv("Import Error", model["importErrorMessage"])

    car = model.get("carCustomization") or {}
    if car:
        print()
        print("Car Customization")
        _kv("Color", car.get("carColor"), indent=1)
        _kv("Shell", car.get("carShell"), indent=1)

    tc = model.get("trainingConfig") or {}
    if tc:
        print()
        print("Training Config")
        track = tc.get("trackConfig") or {}
        _kv("Track", track.get("trackId"), indent=1)
        _kv("Direction", track.get("trackDirection"), indent=1)
        _kv("Race Type", tc.get("raceType"), indent=1)
        _kv("Max Time (min)", tc.get("maxTimeInMinutes"), indent=1)

    meta = model.get("metadata") or {}
    if meta:
        print()
        print("Metadata")
        _kv("Algorithm", meta.get("agentAlgorithm"), indent=1)
        sensors = meta.get("sensors") or {}
        _kv("Camera", sensors.get("camera"), indent=1)
        _kv("Lidar", sensors.get("lidar"), indent=1)
        hp = meta.get("hyperparameters") or {}
        if hp:
            print("  Hyperparameters")
            for k, v in hp.items():
                _kv(k, v, indent=2)
        if verbose:
            action_space = meta.get("actionSpace") or {}
            if action_space:
                print()
                print("Action Space")
                cont = action_space.get("continous") or {}
                disc = action_space.get("discrete") or []
                if cont:
                    _kv("Type", "continuous", indent=1)
                    _kv("Speed range", f"{cont.get('lowSpeed')} – {cont.get('highSpeed')} m/s", indent=1)
                    _kv("Steering range", f"{cont.get('lowSteeringAngle')}° – {cont.get('highSteeringAngle')}°", indent=1)
                elif disc:
                    _kv("Type", f"discrete ({len(disc)} actions)", indent=1)
                    for i, a in enumerate(disc):
                        _kv(f"Action {i}", f"speed={a.get('speed')} m/s, steering={a.get('steeringAngle')}°", indent=2)
            rf = meta.get("rewardFunction")
            if rf:
                print()
                print("Reward Function")
                print(rf)

    if verbose:
        metrics_url = model.get("trainingMetricsUrl")
        if metrics_url:
            print()
            _kv("Metrics URL", metrics_url)
    video_url = model.get("trainingVideoStreamUrl")
    if video_url:
        print()
        _kv("Video Stream URL", video_url)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Get details of a model in DeepRacer on AWS.",
        epilog=(
            "examples:\n"
            "  %(prog)s 2w7R6h2PNexQ9kC\n"
            "  %(prog)s 2w7R6h2PNexQ9kC --verbose\n"
            "  %(prog)s 2w7R6h2PNexQ9kC --json | jq .status"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    add_common_args(parser)
    parser.add_argument("model_id", help="Model ID to retrieve")
    parser.add_argument(
        "--json", dest="output_json", action="store_true",
        help="Output raw JSON instead of formatted view",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Also print reward function, action space, and Metrics URL",
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
    model = get_model(cfg, credentials, args.model_id)
    if args.output_json:
        print(json.dumps(model, indent=2, default=str))
    else:
        print_model(model, verbose=args.verbose)


if __name__ == "__main__":
    main()
