#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Programmatic Import Model script for DeepRacer on AWS.

Replicates the browser flow:
  1. Authenticate with Cognito User Pool  →  ID token
  2. Exchange ID token via Identity Pool  →  temporary AWS credentials (session token)
  3. Upload model folder to the upload S3 bucket using those credentials
  4. Call POST /importmodel (SigV4-signed) with the uploaded S3 path

Usage:
    pip install boto3 requests aws-requests-auth

    python import_model.py \
        --url https://xxxxxxxxxxxx.cloudfront.net \
        --username myuser@example.com \
        --password 'MyPassword123!' \
        --model-dir /path/to/model/folder \
        --model-name my-imported-model \
        --model-description "Optional description"

All AWS configuration (region, user pool, identity pool, API endpoint, upload
bucket) is read automatically from <url>/env.js, which is the public config
file served by the DeepRacer on AWS CloudFront distribution.

Individual flags (--region, --user-pool-id, etc.) can optionally be provided
to override specific values from env.js.

Required files inside --model-dir:
    model_metadata.json
    reward_function.py
    training_params.yaml
    hyperparameters.json
"""

import argparse
import getpass
import json
import re
import sys
import uuid
from pathlib import Path
from urllib.parse import urlparse

import boto3
import requests
from aws_requests_auth.aws_auth import AWSRequestsAuth


# ---------------------------------------------------------------------------
# Config discovery: fetch env.js from the site URL
# ---------------------------------------------------------------------------

def fetch_env_config(site_url: str) -> dict:
    """
    Fetch <site_url>/env.js and parse the window.EnvironmentConfig object.
    This file is publicly served by every DeepRacer on AWS CloudFront distribution.
    """
    env_js_url = site_url.rstrip("/") + "/env.js"
    response = requests.get(env_js_url, timeout=10)
    if not response.ok:
        raise RuntimeError(
            f"Could not fetch env.js from {env_js_url}: "
            f"{response.status_code} {response.reason}"
        )
    # Parse:  window.EnvironmentConfig = {...};
    # Greedy + DOTALL so the full object is captured across multiple lines and
    # even if values contain '}' characters.  The greedy .+ backtracks to the
    # last '}' that is followed by optional whitespace then ';'.
    match = re.search(r"window\.EnvironmentConfig\s*=\s*(\{.+\})\s*;", response.text, re.DOTALL)
    if not match:
        raise RuntimeError(f"Could not find EnvironmentConfig in {env_js_url}")
    raw = match.group(1)
    try:
        config = json.loads(raw)
    except json.JSONDecodeError:
        # env.js uses a JS object literal (unquoted keys, single-quoted values,
        # trailing comma) rather than strict JSON — convert it.
        js = raw
        # Quote unquoted object keys:  { key:  →  { "key":
        js = re.sub(r'([{,]\s*)([A-Za-z_]\w*)\s*:', r'\1"\2":', js)
        # Replace single-quoted string values with double-quoted
        js = re.sub(r"'([^']*)'", r'"\1"', js)
        # Remove trailing commas before closing brace
        js = re.sub(r',(\s*})', r'\1', js)
        try:
            config = json.loads(js)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Could not parse EnvironmentConfig from {env_js_url}.\n"
                f"Parse error: {exc}\n"
                f"Raw content captured:\n{raw}"
            ) from exc
    print(f"[0/4] Loaded configuration from {env_js_url}")
    return config


# ---------------------------------------------------------------------------
# Step 1: Cognito User Pool authentication
# ---------------------------------------------------------------------------

def authenticate(region: str, client_id: str, username: str, password: str) -> str:
    """Sign in to Cognito User Pool and return an ID token."""
    client = boto3.client("cognito-idp", region_name=region)
    response = client.initiate_auth(
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={"USERNAME": username, "PASSWORD": password},
        ClientId=client_id,
    )
    result = response.get("AuthenticationResult") or {}
    id_token = result.get("IdToken")
    if not id_token:
        raise RuntimeError("Authentication failed – no ID token in response.")
    print("[1/4] Authenticated with Cognito User Pool.")
    return id_token


# ---------------------------------------------------------------------------
# Step 2: Cognito Identity Pool → temporary AWS credentials
# ---------------------------------------------------------------------------

def get_aws_credentials(
    region: str,
    user_pool_id: str,
    identity_pool_id: str,
    id_token: str,
) -> dict:
    """Exchange a Cognito ID token for temporary STS credentials via Identity Pool."""
    cognito_identity = boto3.client("cognito-identity", region_name=region)
    login_key = f"cognito-idp.{region}.amazonaws.com/{user_pool_id}"

    identity_response = cognito_identity.get_id(
        IdentityPoolId=identity_pool_id,
        Logins={login_key: id_token},
    )
    identity_id = identity_response["IdentityId"]

    creds_response = cognito_identity.get_credentials_for_identity(
        IdentityId=identity_id,
        Logins={login_key: id_token},
    )
    creds = creds_response["Credentials"]
    print("[2/4] Obtained temporary AWS credentials from Identity Pool.")
    return {
        "access_key": creds["AccessKeyId"],
        "secret_key": creds["SecretKey"],
        "session_token": creds["SessionToken"],
    }


# ---------------------------------------------------------------------------
# Step 3: Upload model files to the upload S3 bucket
# ---------------------------------------------------------------------------

EXCLUDED_FILES = {".DS_Store", "Thumbs.db", "desktop.ini", "._.DS_Store"}
REQUIRED_FILES = {
    "model_metadata.json",
    "reward_function.py",
    "training_params.yaml",
    "hyperparameters.json",
}


def _content_type(file_path: Path) -> str:
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


def upload_model_folder(
    region: str,
    bucket: str,
    model_dir: Path,
    credentials: dict,
) -> str:
    """
    Upload all eligible files from model_dir to S3 and return the s3Path prefix.
    Mirrors the browser's uploadModelFiles() in uploadUtils.ts.
    """
    # Validate required files are present (searched recursively)
    present = {f.name for f in model_dir.rglob("*") if f.is_file()}
    missing = REQUIRED_FILES - present
    if missing:
        raise ValueError(f"Missing required model files: {', '.join(sorted(missing))}")

    s3_prefix = f"uploads/models/{uuid.uuid4()}"

    s3 = boto3.client(
        "s3",
        region_name=region,
        aws_access_key_id=credentials["access_key"],
        aws_secret_access_key=credentials["secret_key"],
        aws_session_token=credentials["session_token"],
    )

    files = [f for f in model_dir.rglob("*") if f.is_file()]
    for file_path in files:
        if file_path.name in EXCLUDED_FILES:
            continue
        if file_path.suffix.lower() in {".gz", ".zip"}:
            continue

        # Preserve relative path inside the uploaded prefix
        relative = file_path.relative_to(model_dir)
        s3_key = f"{s3_prefix}/{relative}"

        print(f"    Uploading: {relative}")
        s3.upload_file(
            Filename=str(file_path),
            Bucket=bucket,
            Key=s3_key,
            ExtraArgs={"ContentType": _content_type(file_path)},
        )

    print(f"[3/4] Uploaded model files to s3://{bucket}/{s3_prefix}")
    return s3_prefix


# ---------------------------------------------------------------------------
# Step 4: Call POST /importmodel with SigV4 signing
# ---------------------------------------------------------------------------

def call_import_model_api(
    region: str,
    api_endpoint: str,
    bucket: str,
    s3_path: str,
    model_name: str,
    model_description: str | None,
    credentials: dict,
) -> str:
    """POST /importmodel and return the created modelId."""
    url = api_endpoint.rstrip("/") + "/importmodel"

    payload: dict = {
        "s3Bucket": bucket,
        "s3Path": s3_path,
        "modelName": model_name,
    }
    if model_description:
        payload["modelDescription"] = model_description

    auth = AWSRequestsAuth(
        aws_access_key=credentials["access_key"],
        aws_secret_access_key=credentials["secret_key"],
        aws_host=_extract_host(url),
        aws_region=region,
        aws_service="execute-api",
        aws_token=credentials["session_token"],
    )

    response = requests.post(
        url,
        json=payload,
        auth=auth,
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


def _extract_host(url: str) -> str:
    return urlparse(url).netloc


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import a DeepRacer model via the DeepRacer on AWS API."
    )
    # Primary config source
    parser.add_argument(
        "--url",
        help="DeepRacer on AWS site URL (e.g. https://xxxx.cloudfront.net). "
             "All AWS config is read automatically from <url>/env.js.",
    )
    # Optional overrides (take precedence over env.js values when provided)
    parser.add_argument("--region", help="Override: AWS region")
    parser.add_argument("--user-pool-id", help="Override: Cognito User Pool ID")
    parser.add_argument("--user-pool-client-id", help="Override: Cognito App Client ID")
    parser.add_argument("--identity-pool-id", help="Override: Cognito Identity Pool ID")
    parser.add_argument("--api-endpoint", help="Override: API Gateway base URL")
    parser.add_argument("--upload-bucket", help="Override: S3 upload bucket name")
    # Credentials and model details
    parser.add_argument("--username", required=True, help="Cognito username / email")
    parser.add_argument("--password", help="Cognito password (prompted if omitted)")
    parser.add_argument(
        "--model-dir",
        required=True,
        type=Path,
        help="Local folder containing model files",
    )
    parser.add_argument("--model-name", required=True, help="Name for the imported model")
    parser.add_argument("--model-description", default=None, help="Optional model description")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not args.url and not all([args.region, args.user_pool_id, args.user_pool_client_id,
                                  args.identity_pool_id, args.api_endpoint, args.upload_bucket]):
        print(
            "Error: provide --url (site URL) or supply all of: "
            "--region, --user-pool-id, --user-pool-client-id, "
            "--identity-pool-id, --api-endpoint, --upload-bucket",
            file=sys.stderr,
        )
        sys.exit(1)

    # Resolve config: env.js first, then CLI overrides
    env = fetch_env_config(args.url) if args.url else {}
    region           = args.region             or env.get("region")
    user_pool_id     = args.user_pool_id        or env.get("userPoolId")
    client_id        = args.user_pool_client_id or env.get("userPoolClientId")
    identity_pool_id = args.identity_pool_id    or env.get("identityPoolId")
    api_endpoint     = args.api_endpoint        or env.get("apiEndpointUrl")
    upload_bucket    = args.upload_bucket       or env.get("uploadBucketName")

    missing = [name for name, val in [
        ("region", region), ("user-pool-id", user_pool_id),
        ("user-pool-client-id", client_id), ("identity-pool-id", identity_pool_id),
        ("api-endpoint", api_endpoint), ("upload-bucket", upload_bucket),
    ] if not val]
    if missing:
        print(f"Error: could not resolve: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

    password = args.password or getpass.getpass(f"Password for {args.username}: ")

    if not args.model_dir.is_dir():
        print(f"Error: --model-dir '{args.model_dir}' is not a directory.", file=sys.stderr)
        sys.exit(1)

    # 1. Authenticate
    id_token = authenticate(region, client_id, args.username, password)

    # 2. Get temporary credentials from Identity Pool
    credentials = get_aws_credentials(region, user_pool_id, identity_pool_id, id_token)

    # 3. Upload model files
    s3_path = upload_model_folder(region, upload_bucket, args.model_dir, credentials)

    # 4. Call the import API
    model_id = call_import_model_api(
        region=region,
        api_endpoint=api_endpoint,
        bucket=upload_bucket,
        s3_path=s3_path,
        model_name=args.model_name,
        model_description=args.model_description,
        credentials=credentials,
    )

    print(f"\nDone. Model is being imported with id: {model_id}")
    print("Check the DeepRacer on AWS UI or poll GET /models/{modelId} for import status.")


if __name__ == "__main__":
    main()
