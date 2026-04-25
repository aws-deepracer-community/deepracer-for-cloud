# Managing Experiments

## Experiment sub-directories

When iterating on a model you typically need different reward functions, action spaces, hyperparameters, and track settings across runs. By default DRfC stores all of this in `run.env` and `custom_files/` at the root of the installation, which can become difficult to manage over time.

The **experiment sub-directory** feature lets you keep every config and custom file for a training run in its own folder under `experiments/`. DRfC then picks up those files automatically when you activate with the experiment name.

### Directory structure

```
deepracer-for-cloud/
├── experiments/
│   ├── sprint-v1/
│   │   ├── run.env
│   │   ├── worker-2.env          # optional – multi-worker only
│   │   └── custom_files/
│   │       ├── reward_function.py
│   │       ├── model_metadata.json
│   │       └── hyperparameters.json
│   └── sprint-v2/
│       ├── run.env
│       └── custom_files/
│           └── ...
├── system.env
└── ...
```

The `experiments/` directory is excluded from git (via `.gitignore`) to avoid committing sensitive configuration and credentials.

### Setting up your first experiment

1. Create the directory structure (run from the DRfC root):

    ```bash
    mkdir -p experiments/sprint-v1/custom_files
    ```

2. Copy your current run configuration into the experiment:

    ```bash
    cp run.env experiments/sprint-v1/
    cp custom_files/* experiments/sprint-v1/custom_files/
    ```

    If you are using multiple workers, copy the worker env files too:

    ```bash
    cp worker-*.env experiments/sprint-v1/
    ```

3. Activate with the experiment name using the `-e` flag:

    ```bash
    source bin/activate.sh -e sprint-v1
    ```

### Activating an experiment

There are two ways to select an experiment:

**Option A — `-e` flag (recommended)**

Pass the experiment name when sourcing the activation script. This takes precedence over anything in `system.env`:

```bash
source bin/activate.sh -e sprint-v1
```

**Option B — `DR_EXPERIMENT_NAME` in `system.env`**

Uncomment and set the variable in `system.env`:

```
DR_EXPERIMENT_NAME=sprint-v1
```

Then run `dr-update` or re-source `bin/activate.sh`. Use this option if you want the experiment to persist across shell sessions automatically.

When `DR_EXPERIMENT_NAME` is set (by either method), DRfC will:
- Load `run.env` from `experiments/<name>/run.env`
- Load `worker-N.env` from `experiments/<name>/worker-N.env` (multi-worker)
- Sync `custom_files` to/from `experiments/<name>/custom_files/`
- Show `Experiment: <name>` in `dr-summary`

If the experiment directory does not exist, activation will abort with an error.

### Iterating to a new experiment

Copy the entire experiment folder to a new name and update the model prefix in `run.env`:

```bash
cp -av experiments/sprint-v1 experiments/sprint-v2
```

Edit `experiments/sprint-v2/run.env` to update `DR_LOCAL_S3_MODEL_PREFIX` (and `DR_LOCAL_S3_PRETRAINED_PREFIX` if you want to continue training from the previous experiment's model), then activate the new experiment:

```bash
source bin/activate.sh -e sprint-v2
```

### Custom files upload and download

`dr-upload-custom-files` and `dr-download-custom-files` are experiment-aware. When an experiment is active they sync against `experiments/<name>/custom_files/` instead of the root `custom_files/` directory.

---

# Running Multiple Parallel Experiments

It is possible to run multiple experiments on one computer in parallel. This is possible both in `swarm` and `compose` mode, and is controlled by `DR_RUN_ID` in `run.env`.

The feature works by creating unique prefixes to the container names:
* In Swarm mode this is done through defining a stack name (default: deepracer-0)
* In Compose mode this is done through adding a project name.

## Suggested way to use the feature

By default `run.env` is loaded when DRfC is activated - but it is possible to load a separate configuration through `source bin/activate.sh <filename>`, or through `source bin/activate.sh -e <experiment-name>` when using experiment sub-directories.

The best way to use this feature is to have a bash-shell per experiment, and to load a separate configuration per shell.

After activating one can control each experiment independently through using the `dr-*` commands.

If using local or Azure the S3 / Minio instance will be shared, and is running only once.
