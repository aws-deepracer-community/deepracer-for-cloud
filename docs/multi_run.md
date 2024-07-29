# Managing experiments

Often when training a model you may find that you want to run different training experiments with different settings, reward functions, action spaces, etc. 

By default DRfC will assume that you store all the settings in run.env and in the files inside the `custom_files/` directory, however when running multiple sequential experiments these folders can get cluttered with many files and it can be tricky to keep track of what settings or files were used for a particular training run.

DRfC has an optional feature which can be enabled to store all the config files for a particular training run in a dedicated sub-directory. 

## To enable experiment sub-directories
1. create the initial directory structure for your experiments. The top level directory must be called `experiments/` and must be in the root of your DRfC installation, along with a further subdir for your first experiment which must then contain a subdir called `custom_files`. 

    `mkdir` using the `-p` flag can create this for you in a single easy command (be sure to run from inside the main DRfC directory):

    ```
    mkdir -p experiments/test-1/custom_files
    ```
2. Move (or copy) run.env into the experiment directory
    ```
    mv run.env experiments/test-1
    ```

    If you are using multiple workers then also move the `worker-#.env` files. 
3. Create (or move) the files in the new experiment's custom_files directory for reward function, model metadata and hyperparameters.
    ```
    cp custom_files/* experiments/test-1/custom_files
    ```
4. Uncomment the `DR_EXPERIMENT_NAME` line from system.env and set it to your experiment name (which must match the name of your new subdir inside `experiments`, in this example it should be set to `test-1`)
5. Run `dr-update` or restart your shell and re-source `bin/activate.sh`
6. Start training as normal using `dr-start-training`

## To iterate on an experiment

To create a new experiment based on a previous one just copy the entire experiment subdir to a new name and update the `DR_EXPERIMENT_NAME` line in system.env.

```
cp -av experiments/test-1 experiments/test-2
```

You should edit the `run.env` inside the new experiment folder to update the `DR_LOCAL_S3_MODEL_PREFIX` (and `DR_LOCAL_S3_PRETRAINED_PREFIX` if you are cloning the previous experiment's model).

Don't forget to run `dr-update` after changing any files. 

# Running Multiple Parallel Experiments

It is possible to run multiple experiments on one computer in parallel. This is possible both in `swarm` and `compose` mode, and is controlled by `DR_RUN_ID` in `run.env`.

The feature works by creating unique prefixes to the container names:
* In Swarm mode this is done through defining a stack name (default: deepracer-0)
* In Compose mode this is done through adding a project name.

## Suggested way to use the feature

By default `run.env` is loaded when DRfC is activated - but it is possible to load a separate configuration through `source bin/activate.sh <filename>`. 

The best way to use this feature is to have a bash-shell per experiment, and to load a separate configuration per shell.

After activating one can control each experiment independently through using the `dr-*` commands.

If using local or Azure the S3 / Minio instance will be shared, and is running only once.