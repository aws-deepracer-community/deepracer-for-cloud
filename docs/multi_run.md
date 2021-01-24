# Running Multiple Experiments

It is possible to run multiple experiments on one computer in parallel. This is possible both in `swarm` and `compose` mode, and is controlled by `DR_RUN_ID` in `run.env`.

The feature works by creating unique prefixes to the container names:
* In Swarm mode this is done through defining a stack name (default: deepracer-0)
* In Compose mode this is done through adding a project name.

## Suggested way to use the feature

By default `run.env` is loaded when DRfC is activated - but it is possible to load a separate configuration through `source bin/activate.sh <filename>`. 

The best way to use this feature is to have a bash-shell per experiment, and to load a separate configuration per shell.

After activating one can control each experiment independently through using the `dr-*` commands.

If using local or Azure the S3 / Minio instance will be shared, and is running only once.