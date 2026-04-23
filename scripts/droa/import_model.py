#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Import a locally trained DRFC model into DeepRacer on AWS (DRoA).

Two source modes
----------------
--model-dir DIR
    Upload from a pre-assembled local directory.  The directory must contain
    at minimum: model_metadata.json, reward_function.py, training_params.yaml,
    hyperparameters.json.  All files are uploaded as-is preserving relative
    paths.

--model-prefix PREFIX
    Pull the model from the DRFC local S3 bucket (MinIO), assemble the correct
    upload structure, and generate training_params.yaml from DR_* environment
    variables — replicating what scripts/upload/upload-model.sh and
    scripts/upload/prepare-config.py do.  If omitted, DR_LOCAL_S3_MODEL_PREFIX
    is used as the prefix.

Checkpoint selection (--model-prefix mode only)
-----------------------------------------------
  Default          last tested checkpoint  (last_checkpoint in deepracer_checkpoints.json)
  --best           best checkpoint         (best_checkpoint)
  --checkpoint N   specific checkpoint step number

Flow
----
  1. Authenticate with Cognito User Pool  →  ID token
  2. Exchange ID token via Identity Pool  →  temporary AWS credentials
  3. (--model-prefix) Download from local S3 into a temp dir;
     generate training_params.yaml from DR_* env vars
  4. Upload assembled directory to the DRoA upload S3 bucket
  5. POST /importmodel  →  modelId

Usage examples
--------------
  # Upload from a pre-assembled local directory:
  python import_model.py --model-dir /tmp/my-model --model-name my-model

  # Pull current model from local MinIO (uses DR_LOCAL_S3_MODEL_PREFIX):
  python import_model.py --model-prefix rl-deepracer-sagemaker --model-name my-model

  # Pull with best checkpoint:
  python import_model.py --model-prefix rl-deepracer-sagemaker --model-name my-model --best

Authentication
--------------
  DR_DROA_URL and DR_DROA_USERNAME (system.env) or --url / --username.
  Credential cache: ~/.droa-cache/

Environment variables (--model-prefix mode)
-------------------------------------------
  DR_LOCAL_S3_BUCKET       Local S3 bucket name
  DR_LOCAL_S3_MODEL_PREFIX Default model prefix (overridden by --model-prefix)
  DR_MINIO_URL             MinIO endpoint URL (e.g. http://minio:9000)
  DR_LOCAL_S3_PROFILE      AWS profile name for local S3 access (default: "default")
  DR_*                     Training config variables used to build training_params.yaml
"""

import argparse
import getpass
import json
import os
import re
import sys
import tempfile
import uuid
from pathlib import Path

import boto3
import requests
import yaml

from auth import (
    add_common_args, authenticate, build_auth, get_aws_credentials, load_droa_config,
    load_cached_credentials, save_credentials_to_cache,
)


EXCLUDED_FILES = {".DS_Store", "Thumbs.db", "desktop.ini", "._.DS_Store"}

# Required files when validating a user-supplied --model-dir
REQUIRED_FILES_DIR = {
    "model_metadata.json",
    "reward_function.py",
    "training_params.yaml",
    "hyperparameters.json",
}


# ---------------------------------------------------------------------------
# Content-type helper
# ---------------------------------------------------------------------------

def _content_type(file_path):
    name = file_path.name
    ext = file_path.suffix.lower()
    if name == "done":
        return "text/plain"
    mapping = {
        ".meta": "application/octet-stream",
        ".ckpt": "application/octet-stream",
        ".pb": "application/octet-stream",
        ".ready": "text/plain",
        ".json": "application/json",
        ".yaml": "application/x-yaml",
        ".yml": "application/x-yaml",
        ".py": "text/x-python",
        ".data": "application/octet-stream",
        ".index": "application/octet-stream",
    }
    return mapping.get(ext, "application/octet-stream")


# ---------------------------------------------------------------------------
# Local S3 client (MinIO via DR_MINIO_URL + DR_LOCAL_S3_PROFILE)
# ---------------------------------------------------------------------------

def _local_s3_client():
    """Return a boto3 S3 client pointed at the local MinIO instance."""
    profile = os.environ.get("DR_LOCAL_S3_PROFILE", "default")
    endpoint = os.environ.get("DR_MINIO_URL")  # e.g. http://minio:9000
    session = boto3.Session(profile_name=profile)
    kwargs = {"endpoint_url": endpoint} if endpoint else {}
    return session.client("s3", **kwargs)


def _s3_cp_down(s3, bucket, key, local_path):
    """Download a single S3 object to local_path."""
    print(f"    s3 cp  s3://{bucket}/{key}  →  {local_path}")
    Path(local_path).parent.mkdir(parents=True, exist_ok=True)
    s3.download_file(bucket, key, str(local_path))


def _s3_sync_down(s3, bucket, prefix, local_dir, include_pattern=None):
    """Download all objects under prefix into local_dir, optionally filtered."""
    print(f"    s3 sync  s3://{bucket}/{prefix}  →  {local_dir}")
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            name = key[len(prefix):].lstrip("/")
            if not name:
                continue
            if include_pattern and not any(name.startswith(p) for p in include_pattern):
                continue
            dest = Path(local_dir) / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            s3.download_file(bucket, key, str(dest))


# ---------------------------------------------------------------------------
# training_params.yaml generation  (replicates prepare-config.py)
# ---------------------------------------------------------------------------

def _build_training_params(work_dir, target_bucket, target_prefix):
    """Generate training_params.yaml from DR_* env vars into work_dir."""
    e = os.environ.get
    cfg = {
        "AWS_REGION":                  e("DR_AWS_APP_REGION", "us-east-1"),
        "JOB_TYPE":                    "TRAINING",
        "METRICS_S3_BUCKET":           target_bucket,
        "METRICS_S3_OBJECT_KEY":       f"{target_prefix}/TrainingMetrics.json",
        "MODEL_METADATA_FILE_S3_KEY":  f"{target_prefix}/model/model_metadata.json",
        "REWARD_FILE_S3_KEY":          f"{target_prefix}/reward_function.py",
        "SAGEMAKER_SHARED_S3_BUCKET":  target_bucket,
        "SAGEMAKER_SHARED_S3_PREFIX":  target_prefix,
        "BODY_SHELL_TYPE":             e("DR_CAR_BODY_SHELL_TYPE", "deepracer"),
        "CAR_NAME":                    e("DR_CAR_NAME", "MyCar"),
        "RACE_TYPE":                   e("DR_RACE_TYPE", "TIME_TRIAL"),
        # DRoA TrackId has no direction suffix; strip _cw/_ccw that DRFC appends
        "WORLD_NAME":                  re.sub(r'_(cw|ccw)$', '', e("DR_WORLD_NAME", "LGSWide")),
        "DISPLAY_NAME":                e("DR_DISPLAY_NAME", "racer1"),
        "RACER_NAME":                  e("DR_RACER_NAME", "racer1"),
        "ALTERNATE_DRIVING_DIRECTION": e("DR_TRAIN_ALTERNATE_DRIVING_DIRECTION",
                                         e("DR_ALTERNATE_DRIVING_DIRECTION", "false")),
        "CHANGE_START_POSITION":       e("DR_TRAIN_CHANGE_START_POSITION",
                                         e("DR_CHANGE_START_POSITION", "true")),
        "ROUND_ROBIN_ADVANCE_DIST":    e("DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST", "0.05"),
        "START_POSITION_OFFSET":       e("DR_TRAIN_START_POSITION_OFFSET", "0.00"),
        "ENABLE_DOMAIN_RANDOMIZATION": e("DR_ENABLE_DOMAIN_RANDOMIZATION", "false"),
        "MIN_EVAL_TRIALS":             e("DR_TRAIN_MIN_EVAL_TRIALS", "5"),
    }

    if cfg["BODY_SHELL_TYPE"] == "deepracer":
        cfg["CAR_COLOR"] = e("DR_CAR_COLOR", "Red")

    race_type = cfg["RACE_TYPE"]
    if race_type == "OBJECT_AVOIDANCE":
        cfg["NUMBER_OF_OBSTACLES"] = e("DR_OA_NUMBER_OF_OBSTACLES", "6")
        cfg["MIN_DISTANCE_BETWEEN_OBSTACLES"] = e(
            "DR_OA_MIN_DISTANCE_BETWEEN_OBSTACLES", "2.0")
        cfg["RANDOMIZE_OBSTACLE_LOCATIONS"] = e(
            "DR_OA_RANDOMIZE_OBSTACLE_LOCATIONS", "True")
        cfg["IS_OBSTACLE_BOT_CAR"] = e("DR_OA_IS_OBSTACLE_BOT_CAR", "false")
        positions_str = e("DR_OA_OBJECT_POSITIONS", "")
        if positions_str:
            positions = positions_str.split(";")
            cfg["OBJECT_POSITIONS"] = positions
            cfg["NUMBER_OF_OBSTACLES"] = str(len(positions))

    if race_type == "HEAD_TO_BOT":
        cfg["IS_LANE_CHANGE"] = e("DR_H2B_IS_LANE_CHANGE", "False")
        cfg["LOWER_LANE_CHANGE_TIME"] = e(
            "DR_H2B_LOWER_LANE_CHANGE_TIME", "3.0")
        cfg["UPPER_LANE_CHANGE_TIME"] = e(
            "DR_H2B_UPPER_LANE_CHANGE_TIME", "5.0")
        cfg["LANE_CHANGE_DISTANCE"] = e("DR_H2B_LANE_CHANGE_DISTANCE", "1.0")
        cfg["NUMBER_OF_BOT_CARS"] = e("DR_H2B_NUMBER_OF_BOT_CARS", "0")
        cfg["MIN_DISTANCE_BETWEEN_BOT_CARS"] = e(
            "DR_H2B_MIN_DISTANCE_BETWEEN_BOT_CARS", "2.0")
        cfg["RANDOMIZE_BOT_CAR_LOCATIONS"] = e(
            "DR_H2B_RANDOMIZE_BOT_CAR_LOCATIONS", "False")
        cfg["BOT_CAR_SPEED"] = e("DR_H2B_BOT_CAR_SPEED", "0.2")

    # TRACK_DIRECTION_CLOCKWISE: infer from the raw DR_WORLD_NAME (which still carries
    # the _cw/_ccw suffix) before that suffix is stripped for WORLD_NAME above.
    raw_world = e("DR_WORLD_NAME", "LGSWide")
    if raw_world.endswith("_cw"):
        cfg["TRACK_DIRECTION_CLOCKWISE"] = True
    elif raw_world.endswith("_ccw"):
        cfg["TRACK_DIRECTION_CLOCKWISE"] = False
    else:
        reverse = e("DR_TRAIN_REVERSE_DIRECTION",
                    "False").lower() in ("true", "1", "yes")
        cfg["TRACK_DIRECTION_CLOCKWISE"] = not reverse

    out = Path(work_dir) / "training_params.yaml"
    with open(out, "w") as fh:
        yaml.dump(cfg, fh, default_flow_style=False,
                  default_style="'", explicit_start=True)
    return out


# ---------------------------------------------------------------------------
# Pull from local S3 and assemble upload structure
# ---------------------------------------------------------------------------

def _build_from_s3_prefix(model_prefix, checkpoint_mode, checkpoint_num,
                          target_bucket, target_prefix):
    """
    Download model files from local DRFC S3 into a temp directory and return
    its path.  The caller is responsible for cleanup.

    checkpoint_mode: 'last' | 'best' | 'number'
    checkpoint_num:  step number (int) when mode == 'number'
    target_bucket / target_prefix: DRoA upload destination — needed to bake
    correct paths into training_params.yaml.
    """
    local_bucket = os.environ.get("DR_LOCAL_S3_BUCKET", "bucket")

    work = Path(tempfile.mkdtemp(prefix="droa-import-"))
    model_dir = work / "model"
    model_dir.mkdir()
    ip_dir = work / "ip"
    ip_dir.mkdir()
    metrics_dir = work / "metrics"
    metrics_dir.mkdir()

    print(f"Pulling model from s3://{local_bucket}/{model_prefix}")
    s3 = _local_s3_client()

    # --- metadata files ---
    # model_metadata.json must be at the root of the upload prefix (API reads it there)
    # also keep a copy inside model/ so sagemaker-artifacts structure is preserved
    _s3_cp_down(s3, local_bucket, f"{model_prefix}/model/model_metadata.json",
                work / "model_metadata.json")
    (model_dir / "model_metadata.json").write_bytes((work /
                                                     "model_metadata.json").read_bytes())
    _s3_cp_down(s3, local_bucket, f"{model_prefix}/ip/hyperparameters.json",
                ip_dir / "hyperparameters.json")

    # reward_function.py: try model root first, then DR_LOCAL_S3_REWARD_KEY
    local_reward_key = os.environ.get("DR_LOCAL_S3_REWARD_KEY",
                                      f"{model_prefix}/reward_function.py")
    try:
        _s3_cp_down(s3, local_bucket, f"{model_prefix}/reward_function.py",
                    work / "reward_function.py")
    except Exception:
        _s3_cp_down(s3, local_bucket, local_reward_key,
                    work / "reward_function.py")

    # metrics
    metrics_prefix = os.environ.get("DR_LOCAL_S3_METRICS_PREFIX",
                                    f"{model_prefix}/metrics")
    _s3_sync_down(s3, local_bucket, metrics_prefix, metrics_dir)

    # --- checkpoint index ---
    _s3_cp_down(s3, local_bucket, f"{model_prefix}/model/deepracer_checkpoints.json",
                model_dir / "deepracer_checkpoints.json")
    with open(model_dir / "deepracer_checkpoints.json") as fh:
        ckpt_index = json.load(fh)

    if checkpoint_mode == "best":
        ckpt_entry = ckpt_index.get(
            "best_checkpoint", ckpt_index.get("last_checkpoint"))
        print("Using best checkpoint.")
    elif checkpoint_mode == "number":
        # List model/ prefix and find the matching .ckpt.index key
        paginator = s3.get_paginator("list_objects_v2")
        match = None
        for page in paginator.paginate(Bucket=local_bucket,
                                       Prefix=f"{model_prefix}/model/"):
            for obj in page.get("Contents", []):
                fname = obj["Key"].split("/")[-1]
                if fname.startswith(f"{checkpoint_num}_Step-") and fname.endswith(".ckpt.index"):
                    match = fname[:-len(".index")]  # strip .index → .ckpt
                    break
            if match:
                break
        if not match:
            raise RuntimeError(
                f"No checkpoint found for step {checkpoint_num} "
                f"in s3://{local_bucket}/{model_prefix}/model/"
            )
        ckpt_entry = {"name": match}
        print(f"Using checkpoint {match}.")
    else:
        ckpt_entry = ckpt_index.get("last_checkpoint")
        print("Using last checkpoint.")

    if not ckpt_entry:
        raise RuntimeError(
            "Could not determine checkpoint from deepracer_checkpoints.json")

    ckpt_file = ckpt_entry["name"]       # e.g. "500_Step-500.ckpt"
    ckpt_step = ckpt_file.split("_")[0]  # e.g. "500"
    print(f"Checkpoint: {ckpt_file}")

    # Download checkpoint model files (prefix-filtered sync)
    _s3_sync_down(
        s3, local_bucket, f"{model_prefix}/model/", model_dir,
        include_pattern=[f"{ckpt_step}_Step-", f"model_{ckpt_step}.pb"],
    )

    # Write .coach_checkpoint
    (model_dir / ".coach_checkpoint").write_text(ckpt_file)

    # Rewrite deepracer_checkpoints.json to reference only chosen checkpoint
    new_ckpt_json = {"last_checkpoint": ckpt_entry,
                     "best_checkpoint": ckpt_entry}
    with open(model_dir / "deepracer_checkpoints.json", "w") as fh:
        json.dump(new_ckpt_json, fh)

    # --- training_params.yaml: copy from bucket, generate only if missing ---
    # Multi-worker training produces training_params_1.yaml, training_params_2.yaml, …
    # We prefer _1 (worker 1 is canonical), then the plain name, then generate.
    tp_dst = work / "training_params.yaml"
    tp_candidates = [
        f"{model_prefix}/training_params_1.yaml",
        f"{model_prefix}/training_params.yaml",
    ]
    tp_found = False
    for tp_key in tp_candidates:
        try:
            _s3_cp_down(s3, local_bucket, tp_key, tp_dst)
            print(f"Using {tp_key.split('/')[-1]} from bucket.")
            tp_found = True
            break
        except Exception:
            pass
    if not tp_found:
        print("training_params.yaml not found in bucket — generating from DR_* env vars.")
        _build_training_params(work, target_bucket, target_prefix)

    # Normalise training_params.yaml for DRoA:
    # 1. WORLD_NAME must not have a _cw/_ccw suffix (DRoA TrackId has none)
    # 2. TRACK_DIRECTION_CLOCKWISE must be present (DRFC never wrote it)
    with open(tp_dst) as fh:
        tp_data = yaml.safe_load(fh) or {}
    changed = False
    # Strip direction suffix from WORLD_NAME if present
    world_raw = tp_data.get("WORLD_NAME", "")
    world_clean = re.sub(r'_(cw|ccw)$', '', world_raw)
    if world_clean != world_raw:
        tp_data["WORLD_NAME"] = world_clean
        changed = True
        print(
            f"    Stripped direction suffix from WORLD_NAME: {world_raw} → {world_clean}")
    # Infer TRACK_DIRECTION_CLOCKWISE if missing
    if "TRACK_DIRECTION_CLOCKWISE" not in tp_data:
        # Prefer DR_WORLD_NAME env var which still carries the suffix
        dr_world = os.environ.get("DR_WORLD_NAME", world_raw)
        if dr_world.endswith("_cw") or world_raw.endswith("_cw"):
            tp_data["TRACK_DIRECTION_CLOCKWISE"] = True
        elif dr_world.endswith("_ccw") or world_raw.endswith("_ccw"):
            tp_data["TRACK_DIRECTION_CLOCKWISE"] = False
        else:
            reverse = os.environ.get(
                "DR_TRAIN_REVERSE_DIRECTION", "False").lower() in ("true", "1", "yes")
            tp_data["TRACK_DIRECTION_CLOCKWISE"] = not reverse
        changed = True
        print(
            f"    Set TRACK_DIRECTION_CLOCKWISE={tp_data['TRACK_DIRECTION_CLOCKWISE']}")
    if changed:
        with open(tp_dst, "w") as fh:
            yaml.dump(tp_data, fh, default_flow_style=False)

    return work


# ---------------------------------------------------------------------------
# Upload to DRoA S3
# ---------------------------------------------------------------------------

def upload_model_folder(cfg, model_dir, credentials, validate_required=True, s3_prefix=None):
    """Upload all eligible files from model_dir to the DRoA S3 bucket.

    If ``s3_prefix`` is provided the files are uploaded under that exact prefix
    (important when training_params.yaml already references that prefix).
    Otherwise a new UUID-based prefix is generated.
    """
    if validate_required:
        present = {f.name for f in Path(model_dir).rglob("*") if f.is_file()}
        missing = REQUIRED_FILES_DIR - present
        if missing:
            raise ValueError(
                f"Missing required model files: {', '.join(sorted(missing))}")

    if s3_prefix is None:
        s3_prefix = f"uploads/models/{uuid.uuid4()}"
    s3 = boto3.client(
        "s3",
        region_name=cfg.region,
        aws_access_key_id=credentials["access_key"],
        aws_secret_access_key=credentials["secret_key"],
        aws_session_token=credentials["session_token"],
    )

    for file_path in Path(model_dir).rglob("*"):
        if not file_path.is_file():
            continue
        if file_path.name in EXCLUDED_FILES:
            continue
        if file_path.suffix.lower() in {".gz", ".zip"}:
            continue
        relative = file_path.relative_to(model_dir)
        s3_key = f"{s3_prefix}/{relative}"
        print(f"    Uploading: {relative}")
        s3.upload_file(
            Filename=str(file_path),
            Bucket=cfg.upload_bucket,
            Key=s3_key,
            ExtraArgs={"ContentType": _content_type(file_path)},
        )

    print(
        f"[3/4] Uploaded model files to s3://{cfg.upload_bucket}/{s3_prefix}")
    return s3_prefix


# ---------------------------------------------------------------------------
# DRoA API call
# ---------------------------------------------------------------------------

def call_import_model_api(cfg, s3_path, model_name, model_description, credentials):
    """POST /importmodel and return the created modelId."""
    url = f"{cfg.api_endpoint}/importmodel"
    payload = {
        "s3Bucket": cfg.upload_bucket,
        "s3Path": s3_path,
        "modelName": model_name,
    }
    if model_description:
        payload["modelDescription"] = model_description

    response = requests.post(
        url,
        json=payload,
        auth=build_auth(url, credentials, cfg.region, cfg.site_url),
        headers={"Content-Type": "application/json"},
        timeout=30,
    )
    if not response.ok:
        raise RuntimeError(
            f"API call failed: {response.status_code} {response.reason}\n{response.text}"
        )
    model_id = response.json().get("modelId")
    if not model_id:
        raise RuntimeError(f"Unexpected API response: {response.text}")
    print(f"[4/4] Import job created. modelId: {model_id}")
    return model_id


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description="Import a locally trained DRFC model into DeepRacer on AWS.",
        epilog=(
            "examples:\n"
            "  %(prog)s --model-dir /tmp/my-model --model-name my-model\n"
            "  %(prog)s --model-prefix rl-deepracer-sagemaker\n"
            "  %(prog)s --model-prefix rl-deepracer-sagemaker --model-name my-model --best"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    add_common_args(parser)

    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument(
        "--model-dir", type=Path,
        help="Pre-assembled local directory containing model files",
    )
    src.add_argument(
        "--model-prefix",
        help="DRFC local S3 model prefix to pull from (default: DR_LOCAL_S3_MODEL_PREFIX)",
    )

    parser.add_argument(
        "--model-name", default=None,
        help="Name for the imported model (default: --model-prefix or directory name)",
    )
    parser.add_argument("--model-description", default=None,
                        help="Optional model description")

    ckpt = parser.add_mutually_exclusive_group()
    ckpt.add_argument(
        "--best", action="store_true",
        help="(--model-prefix) Use best checkpoint instead of last",
    )
    ckpt.add_argument(
        "--checkpoint", type=int, metavar="STEP",
        help="(--model-prefix) Use specific checkpoint step number",
    )

    return parser.parse_args()


def main():
    args = parse_args()

    username = args.username or os.environ.get("DR_DROA_USERNAME")
    if not username:
        print("Error: --username or DR_DROA_USERNAME required.", file=sys.stderr)
        sys.exit(1)

    if args.model_dir and not args.model_dir.is_dir():
        print(
            f"Error: --model-dir '{args.model_dir}' is not a directory.", file=sys.stderr)
        sys.exit(1)

    # Derive model name from source if not given explicitly
    if not args.model_name:
        if args.model_prefix:
            args.model_name = args.model_prefix
        elif args.model_dir:
            args.model_name = args.model_dir.name
        else:
            print(
                "Error: --model-name is required when source cannot be inferred.", file=sys.stderr)
            sys.exit(1)

    cfg = load_droa_config(args)

    credentials = load_cached_credentials(cfg.identity_pool_id, username)
    if credentials:
        print("[1/4] Using cached credentials.")
    else:
        password = args.password or getpass.getpass(
            f"Password for {username}: ")
        print("[1/4] Authenticating with Cognito User Pool...")
        id_token = authenticate(cfg.region, cfg.client_id, username, password)
        print("[2/4] Obtaining temporary AWS credentials...")
        credentials = get_aws_credentials(
            cfg.region, cfg.user_pool_id, cfg.identity_pool_id, id_token)
        save_credentials_to_cache(cfg.identity_pool_id, username, credentials)
        print("[2/4] Credentials obtained.")

    temp_dir = None
    upload_prefix = None
    try:
        if args.model_dir:
            source_dir = args.model_dir
            validate = True
        else:
            model_prefix = args.model_prefix or os.environ.get(
                "DR_LOCAL_S3_MODEL_PREFIX")
            if not model_prefix:
                print(
                    "Error: --model-prefix or DR_LOCAL_S3_MODEL_PREFIX required.", file=sys.stderr)
                sys.exit(1)
            # Generate the upload prefix now so training_params.yaml can reference it
            upload_prefix = f"uploads/models/{uuid.uuid4()}"
            checkpoint_mode = "best" if args.best else (
                "number" if args.checkpoint else "last")
            print("[3/4] Pulling model from local S3...")
            temp_dir = _build_from_s3_prefix(
                model_prefix, checkpoint_mode, args.checkpoint,
                cfg.upload_bucket, upload_prefix,
            )
            source_dir = temp_dir
            validate = False

        print("[3/4] Uploading to DRoA S3...")
        s3_path = upload_model_folder(
            cfg, source_dir, credentials, validate_required=validate,
            s3_prefix=upload_prefix if not args.model_dir else None)
        model_id = call_import_model_api(
            cfg, s3_path, args.model_name, args.model_description, credentials
        )
    finally:
        if temp_dir:
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)

    print(
        f"\nDone. Model '{args.model_name}' is being imported (id: {model_id})")
    print("Check the DeepRacer on AWS console or use: droa-get-model " + model_id)


if __name__ == "__main__":
    main()
