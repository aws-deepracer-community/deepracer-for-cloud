#!/usr/bin/env python3
"""Print simtrace stability/performance stats for the configured model.

Defaults to the training trace; use --eval for the latest evaluation run.
Reads from the local S3 (MinIO) using the DR_LOCAL_S3_* environment.
"""

import argparse
import os
import sys
import warnings

warnings.filterwarnings("ignore")

from deepracer.logs import DeepRacerLog, S3FileHandler  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-e", "--eval", action="store_true",
        help="Analyse the latest evaluation run instead of training",
    )
    parser.add_argument("-p", "--prefix", help="Model prefix (default: DR_LOCAL_S3_MODEL_PREFIX)")
    args = parser.parse_args()

    bucket = os.environ.get("DR_LOCAL_S3_BUCKET")
    prefix = args.prefix or os.environ.get("DR_LOCAL_S3_MODEL_PREFIX")
    if not bucket or not prefix:
        print("Error: DR_LOCAL_S3_BUCKET and DR_LOCAL_S3_MODEL_PREFIX must be set.", file=sys.stderr)
        return 1

    fh = S3FileHandler(
        bucket=bucket,
        prefix=prefix,
        s3_endpoint_url=os.environ.get("DR_LOCAL_S3_ENDPOINT_URL") or None,
        profile=os.environ.get("DR_LOCAL_S3_PROFILE") or None,
    )
    log = DeepRacerLog(filehandler=fh)

    try:
        if args.eval:
            log.load_evaluation_trace()
            # Stream ids are timestamps, so the max is the most recent run.
            latest = log.df["stream"].max()
            log.df = log.df[log.df["stream"] == latest].reset_index(drop=True)
            print(f"Model: {prefix}  Evaluation run: {latest}\n")
        else:
            log.load_training_trace()
            print(f"Model: {prefix}  Training\n")
        log.stability.print_summary()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
