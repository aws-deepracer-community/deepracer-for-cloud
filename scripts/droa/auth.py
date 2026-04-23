#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
"""
Shared authentication and configuration utilities for DRoA (DeepRacer on AWS) scripts.

Provides:
  fetch_env_config(site_url)          — fetch and parse <site_url>/env.js
  authenticate(...)                   — Cognito User Pool sign-in → ID token
  get_aws_credentials(...)            — Identity Pool → temporary AWS credentials
  load_droa_config(args)              — resolve config from env vars + CLI args
  build_auth(url, credentials, region) — create a SigV4 AWSRequestsAuth instance
  add_common_args(parser)             — add shared CLI flags to an argparse parser
"""

import datetime
import json
import hashlib
import os
import re
import sys
import uuid
from urllib.parse import urlparse

import boto3
import requests
import requests.auth
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest


# ---------------------------------------------------------------------------
# Config discovery
# ---------------------------------------------------------------------------

def fetch_env_config(site_url: str) -> dict:
    """Fetch <site_url>/env.js and parse the window.EnvironmentConfig object."""
    env_js_url = site_url.rstrip("/") + "/env.js"
    response = requests.get(env_js_url, timeout=10)
    if not response.ok:
        raise RuntimeError(
            f"Could not fetch env.js from {env_js_url}: "
            f"{response.status_code} {response.reason}"
        )
    match = re.search(
        r"window\.EnvironmentConfig\s*=\s*(\{.+\})\s*;", response.text, re.DOTALL)
    if not match:
        raise RuntimeError(f"Could not find EnvironmentConfig in {env_js_url}")
    raw = match.group(1)
    try:
        config = json.loads(raw)
    except json.JSONDecodeError:
        # Convert JS object literal to strict JSON
        js = raw
        js = re.sub(r'([{,]\s*)([A-Za-z_]\w*)\s*:', r'\1"\2":', js)
        js = re.sub(r"'([^']*)'", r'"\1"', js)
        js = re.sub(r',(\s*})', r'\1', js)
        try:
            config = json.loads(js)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Could not parse EnvironmentConfig from {env_js_url}.\n"
                f"Parse error: {exc}\nRaw content:\n{raw}"
            ) from exc
    return config


# ---------------------------------------------------------------------------
# Cognito authentication
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
    return id_token


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
    if os.environ.get("DR_DROA_DEBUG"):
        sts = boto3.client(
            "sts",
            region_name=region,
            aws_access_key_id=creds_response["Credentials"]["AccessKeyId"],
            aws_secret_access_key=creds_response["Credentials"]["SecretKey"],
            aws_session_token=creds_response["Credentials"]["SessionToken"],
        )
        identity = sts.get_caller_identity()
        print(
            f"  STS identity: Account={identity['Account']} Arn={identity['Arn']}", file=sys.stderr)

    return {
        "access_key": creds["AccessKeyId"],
        "secret_key": creds["SecretKey"],
        "session_token": creds["SessionToken"],
        "expiry": creds["Expiration"],
    }


# ---------------------------------------------------------------------------
# Credential cache
# ---------------------------------------------------------------------------

def _credential_cache_path(identity_pool_id: str, username: str) -> str:
    key = hashlib.sha256(
        f"{identity_pool_id}:{username}".encode()).hexdigest()[:16]
    cache_dir = os.path.expanduser("~/.droa-cache")
    os.makedirs(cache_dir, mode=0o700, exist_ok=True)
    return os.path.join(cache_dir, f"{key}.json")


def load_cached_credentials(identity_pool_id: str, username: str) -> dict | None:
    """Return cached AWS credentials if they have more than 60 seconds of validity left."""
    path = _credential_cache_path(identity_pool_id, username)
    if not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            data = json.load(f)
        expiry = datetime.datetime.fromisoformat(data["expiry"])
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=datetime.timezone.utc)
        if expiry <= datetime.datetime.now(tz=datetime.timezone.utc) + datetime.timedelta(seconds=60):
            return None
        return {k: v for k, v in data.items() if k != "expiry"}
    except (KeyError, ValueError, json.JSONDecodeError, OSError):
        return None


def save_credentials_to_cache(identity_pool_id: str, username: str, credentials: dict) -> None:
    """Save AWS credentials (including 'expiry') to a 0600 cache file."""
    expiry = credentials.get("expiry")
    if expiry is None:
        return
    path = _credential_cache_path(identity_pool_id, username)
    try:
        data = {
            k: v for k, v in credentials.items() if k != "expiry"
        }
        data["expiry"] = expiry.isoformat() if hasattr(
            expiry, "isoformat") else str(expiry)
        with open(path, "w") as f:
            json.dump(data, f)
        os.chmod(path, 0o600)
    except OSError:
        pass  # Non-fatal


# ---------------------------------------------------------------------------
# Config resolution
# ---------------------------------------------------------------------------

class DRoAConfig:
    """Resolved DRoA endpoint configuration."""

    def __init__(
        self,
        region: str,
        user_pool_id: str,
        client_id: str,
        identity_pool_id: str,
        api_endpoint: str,
        upload_bucket: str,
        site_url: str | None = None,
    ) -> None:
        self.region = region
        self.user_pool_id = user_pool_id
        self.client_id = client_id
        self.identity_pool_id = identity_pool_id
        self.api_endpoint = api_endpoint.rstrip("/")
        self.upload_bucket = upload_bucket
        self.site_url = site_url


def load_droa_config(args) -> "DRoAConfig":
    """
    Resolve DRoA configuration in priority order:
      1. Explicit CLI override flags on ``args``
      2. env.js fetched from --url / DR_DROA_URL environment variable

    Exits with a descriptive error if any required value is missing.
    """
    site_url = getattr(args, "url", None) or os.environ.get("DR_DROA_URL")
    env: dict = {}
    if site_url:
        env = fetch_env_config(site_url)
        print(f"Loaded configuration from {site_url}/env.js")

    region = getattr(args, "region", None) or env.get("region")
    user_pool_id = getattr(args, "user_pool_id", None) or env.get("userPoolId")
    client_id = getattr(args, "user_pool_client_id",
                        None) or env.get("userPoolClientId")
    identity_pool_id = getattr(
        args, "identity_pool_id", None) or env.get("identityPoolId")
    api_endpoint = getattr(args, "api_endpoint",
                           None) or env.get("apiEndpointUrl")
    upload_bucket = getattr(args, "upload_bucket",
                            None) or env.get("uploadBucketName")

    missing = [
        name for name, val in [
            ("region", region),
            ("user-pool-id", user_pool_id),
            ("user-pool-client-id", client_id),
            ("identity-pool-id", identity_pool_id),
            ("api-endpoint", api_endpoint),
            ("upload-bucket", upload_bucket),
        ]
        if not val
    ]
    if missing:
        print(
            f"Error: could not resolve: {', '.join(missing)}.\n"
            "Set DR_DROA_URL in system.env or pass --url.",
            file=sys.stderr,
        )
        sys.exit(1)

    return DRoAConfig(
        region=region,
        user_pool_id=user_pool_id,
        client_id=client_id,
        identity_pool_id=identity_pool_id,
        api_endpoint=api_endpoint,
        upload_bucket=upload_bucket,
        site_url=site_url,
    )


# ---------------------------------------------------------------------------
# SigV4 auth helper
# ---------------------------------------------------------------------------

def build_auth(url: str, credentials: dict, region: str, site_url: str | None = None) -> requests.auth.AuthBase:
    """Create a requests AuthBase that SigV4-signs each request via botocore."""
    origin = site_url.rstrip("/") if site_url else None
    session = boto3.Session(
        aws_access_key_id=credentials["access_key"],
        aws_secret_access_key=credentials["secret_key"],
        aws_session_token=credentials["session_token"],
        region_name=region,
    )
    frozen_creds = session.get_credentials().get_frozen_credentials()

    class _Auth(requests.auth.AuthBase):
        def __call__(self, r: requests.PreparedRequest) -> requests.PreparedRequest:
            body = r.body or b""
            if isinstance(body, str):
                body = body.encode("utf-8")

            sign_headers = {
                "accept": "*/*",
                "accept-encoding": "gzip, deflate, br",
                "accept-language": "en-US,en;q=0.9,de-DE;q=0.8,de;q=0.7",
                "amz-sdk-invocation-id": str(uuid.uuid4()),
                "amz-sdk-request": "attempt=1; max=3",
                "cache-control": "no-cache",
                "pragma": "no-cache",
                "sec-ch-ua": '"Microsoft Edge";v="147", "Not.A/Brand";v="8", "Chromium";v="147"',
                "sec-ch-ua-mobile": "?0",
                "sec-ch-ua-platform": '"Windows"',
                "sec-fetch-dest": "empty",
                "sec-fetch-mode": "cors",
                "sec-fetch-site": "cross-site",
                "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 Edg/147.0.0.0",
                "x-amz-content-sha256": hashlib.sha256(body).hexdigest(),
                "x-amz-user-agent": "aws-sdk-js/1.0.0 ua/2.0 os/Windows#NT-10.0 lang/js md/browser#Microsoft-Edge_147.0.0.0",
            }
            if origin:
                sign_headers["origin"] = origin
                sign_headers["referer"] = origin + "/"
            aws_request = AWSRequest(
                method=r.method, url=r.url, data=body, headers=sign_headers)
            SigV4Auth(frozen_creds, "execute-api",
                      region).add_auth(aws_request)
            r.headers.update(dict(aws_request.headers))

            if os.environ.get("DR_DROA_DEBUG"):
                print("\n--- DEBUG: signed request ---", file=sys.stderr)
                print(f"  {r.method} {r.url}", file=sys.stderr)
                print(
                    f"  (access key: {credentials['access_key']})", file=sys.stderr)
                for k, v in sorted(r.headers.items()):
                    display = v[:40] + \
                        "..." if k.lower() == "x-amz-security-token" and len(v) > 40 else v
                    print(f"  {k}: {display}", file=sys.stderr)
                print("-----------------------------\n", file=sys.stderr)
            return r

    return _Auth()


# ---------------------------------------------------------------------------
# Shared argparse helpers
# ---------------------------------------------------------------------------

def add_common_args(parser) -> None:
    """Add shared DRoA connection/auth arguments to an argparse parser."""
    parser.add_argument(
        "--url",
        help="DeepRacer on AWS site URL (defaults to DR_DROA_URL env var). "
             "All AWS config is read automatically from <url>/env.js.",
    )
    parser.add_argument("--region", help="Override: AWS region")
    parser.add_argument(
        "--user-pool-id", help="Override: Cognito User Pool ID")
    parser.add_argument("--user-pool-client-id",
                        help="Override: Cognito App Client ID")
    parser.add_argument("--identity-pool-id",
                        help="Override: Cognito Identity Pool ID")
    parser.add_argument(
        "--api-endpoint", help="Override: API Gateway base URL")
    parser.add_argument("--upload-bucket",
                        help="Override: S3 upload bucket name")
    parser.add_argument(
        "--username",
        help="Cognito username / email (defaults to DR_DROA_USERNAME env var)",
    )
    parser.add_argument(
        "--password", help="Cognito password (prompted if omitted)")
