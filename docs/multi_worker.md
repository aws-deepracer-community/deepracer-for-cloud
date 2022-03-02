# Using multiple Robomaker workers

One way to accelerate training is to launch multiple Robomaker workers that feed into one Sagemaker instance.

The number of workers is configured through setting `system.env` `DR_WORKERS` to the desired number of workers. The result is that the number of episodes (hyperparameter `num_episodes_between_training`) will be divivided over the number of workers. The theoretical maximum number of workers equals `num_episodes_between_training`.

The training can be started as normal.

## How many workers do I need?

One Robomaker worker requires 2-4 vCPUs. Tests show that a `c5.4xlarge` instance can run 3 workers and the Sagemaker without a drop in performance. Using OpenGL images reduces the number of vCPUs required per worker.

To avoid issues with the position from which evaluations are run ensure that `( num_episodes_between_training / DR_WORKERS) * DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST = 1.0`. 

Example: With 3 workers set `num_episodes_between_training: 30` and `DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST=0.1`.

Note; Sagemaker will stop collecting experiences once you have reached 10.000 steps (3-layer CNN) in an iteration. For longer tracks with 600-1000 steps per completed episodes this will define the upper bound for the number of workers and episodes per iteration.

## Training with different parameters for each worker

It is also possible to use different configurations between workers, such as different tracks (WORLD_NAME).  To enable, set DR_TRAIN_MULTI_CONFIG=True inside run.env, then make copies of defaults/template-worker.env in the main deepracer-for-cloud directory with format worker-2.env, worker-3.env, etc.  (So alongside run.env, you should have woker-2.env, worker-3.env, etc.  run.env is still used for worker 1)  Modify the worker env files with your desired changes, which can be more than just the world_name.  These additional worker env files are only used if you are training with multiple workers.

## Watching the streams

If you want to watch the streams -- and are in `compose` mode you can use the script `utils/start-local-browser.sh` to dynamically create a HTML that streams the KVS stream from ALL workers at a time.
