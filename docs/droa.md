# DeepRacer on AWS (DRoA) Integration

[DeepRacer on AWS](https://aws.amazon.com/solutions/implementations/deepracer-on-aws/) is the community-hosted replacement for the original AWS DeepRacer console. DRfC includes a set of `droa-*` commands that let you manage models in your DRoA installation directly from the command line.

## Prerequisites

### Install DRoA

Follow the [DeepRacer on AWS installation guide](https://github.com/aws-deepracer-community/deepracer-on-aws) to deploy DRoA into your own AWS account.

### Configure DRfC

In `system.env` set:

```bash
DR_DROA_URL=https://<your-droa-domain>   # e.g. https://deepracer.aws.example.com
DR_DROA_USERNAME=<your-droa-email>
```

`DR_DROA_URL` is the base URL of your DRoA deployment. At runtime, DRfC fetches `<DR_DROA_URL>/env.js` to discover the region, Cognito pools, API endpoint, and upload bucket automatically — no additional AWS config required.

> **Security**: never store your DRoA password in `system.env`. All commands prompt for it interactively (or accept `--password` on the CLI). Credentials are cached in `~/.droa-cache/` for the duration of the session token.

### Python environment

Run `bin/prepare.sh` to create the `.venv` virtual environment and install the required Python packages (`boto3`, `pyyaml`, `requests`, `deepracer-utils`). After `source bin/activate.sh` the venv is active and all `droa-*` commands are available.

---

## Commands

### `droa-list-models`

List all models in your DRoA installation, sorted newest-first.

```
droa-list-models [--json]
```

Output columns: `modelId`, `name`, `status`, `trainingStatus`, `createdAt`.

| Status | Meaning |
|--------|---------|
| `IMPORTING` | Import in progress |
| `READY` | Available for evaluation |
| `TRAINING` | Training job running |
| `ERROR` | Import or training failed |
| `DELETING` | Deletion in progress |

---

### `droa-get-model`

Show details of a single model.

```
droa-get-model <modelId> [--verbose] [--summary] [--json]
```

| Flag | Description |
|------|-------------|
| *(none)* | Identity, car config, training config, metadata |
| `--verbose` | Adds action space and reward function source |
| `--summary` | Adds mean training metrics (reward, progress) via DeepRacer Utils |
| `--json` | Raw JSON output |

---

### `droa-download-logs`

Download training or evaluation logs for a model.

```
droa-download-logs <modelId> [--asset-type TRAINING_LOGS|EVALUATION_LOGS|PHYSICAL_CAR_MODEL|VIRTUAL_MODEL|VIDEOS]
                              [--evaluation-id <id>]
                              [--output <file>]
                              [--summary]
```

| Flag | Description |
|------|-------------|
| `--asset-type` | Asset type (default: `TRAINING_LOGS`) |
| `--evaluation-id` | Required when `--asset-type EVALUATION_LOGS` |
| `--output` / `-o` | Output file path (default: derived from the presigned URL filename) |
| `--summary` | Print DeepRacer Utils stability summary after download (TRAINING_LOGS only) |

The command polls until the asset is ready (up to 5 minutes for `VIRTUAL_MODEL`).

---

### `droa-delete-model`

Delete a model. Only models with status `READY` or `ERROR` can be deleted.

```
droa-delete-model <modelId> [-y/--yes]
```

Without `--yes`, you are shown the model name and status and must type the model name to confirm. Deletion is asynchronous — the model transitions to `DELETING` status.

---

### `droa-import-model`

Import a locally trained DRFC model into DRoA.

```
droa-import-model (--model-prefix <prefix> | --model-dir <dir>)
                  [--model-name <name>]
                  [--model-description <text>]
                  [--best | --checkpoint <step>]
```

#### Source options

| Option | Description |
|--------|-------------|
| `--model-prefix` | Pull directly from local MinIO S3 (`DR_LOCAL_S3_BUCKET`). Defaults `--model-name` to the prefix. |
| `--model-dir` | Use a pre-assembled local directory containing all required model files. |

#### Checkpoint selection (`--model-prefix` only)

| Flag | Behaviour |
|------|-----------|
| *(none)* | Use the last checkpoint |
| `--best` | Use the best checkpoint |
| `--checkpoint STEP` | Use the checkpoint at the given training step |

#### What happens

1. Model files are pulled from MinIO (path-style S3, using `DR_MINIO_URL` and `DR_LOCAL_S3_PROFILE`).
2. `training_params.yaml` is copied from the bucket (`training_params_1.yaml` preferred for multi-worker runs). If missing, it is generated from `DR_*` environment variables.
3. `WORLD_NAME` direction suffixes (`_cw`, `_ccw`) are stripped and `TRACK_DIRECTION_CLOCKWISE` is added — required by DRoA's track validation.
4. Files are uploaded to the DRoA S3 transit bucket and the import API is called.

#### Required files (when using `--model-dir`)

- `model_metadata.json`
- `reward_function.py`
- `training_params.yaml`
- `hyperparameters.json`

---

## Environment variables reference

| Variable | Location | Description |
|----------|----------|-------------|
| `DR_DROA_URL` | `system.env` | Base URL of your DRoA deployment |
| `DR_DROA_USERNAME` | `system.env` | DRoA login email |
| `DR_MINIO_URL` | `system.env` | MinIO endpoint URL (e.g. `http://minio:9000`) |
| `DR_LOCAL_S3_PROFILE` | `system.env` | boto3 AWS profile name for MinIO access |
| `DR_LOCAL_S3_BUCKET` | `run.env` | Local S3 bucket name |
| `DR_LOCAL_S3_MODEL_PREFIX` | `run.env` | Default model prefix for `--model-prefix` |

All `droa-*` commands also accept `--url`, `--username`, and `--password` flags to override the environment variables.
