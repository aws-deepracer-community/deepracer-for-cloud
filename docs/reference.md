# Deepracer-for-Cloud Reference

## Environment Variables

The scripts assume that two files `system.env` containing constant configuration values and  `run.env` with run specific values is populated with the required values. Which values go into which file is not really important.

| Variable | Description |
|----------|-------------|
| `DR_RUN_ID` | Used if you have multiple independent training jobs only a single DRfC instance. This is an advanced configuration and generally you should just leave this as the default `0`.|
| `DR_WORLD_NAME` | Defines the track to be used.|
| `DR_RACE_TYPE` | Valid options are `TIME_TRIAL`, `OBJECT_AVOIDANCE`, and `HEAD_TO_BOT`.|
| `DR_CAR_COLOR` | Valid options are `Black`, `Grey`, `Blue`, `Red`, `Orange`, `White`, and `Purple`.|
| `DR_CAR_NAME` | Display name of car; shows in Deepracer Console when uploading.|
| `DR_ENABLE_DOMAIN_RANDOMIZATION` | If `True`, this cycles through different environment colors and lighting each episode.  This is typically used to make your model more robust and generalized instead of tightly aligned with the simulator|
| `DR_UPLOAD_S3_PREFIX` | Prefix of the target location. (Typically starts with `DeepRacer-SageMaker-RoboMaker-comm-`|
| `DR_EVAL_NUMBER_OF_TRIALS` | How many laps to complete for evaluation simulations.|
| `DR_EVAL_IS_CONTINUOUS` | If False, your evaluation trial will end if you car goes off track or is in a collision. If True, your car will take the penalty times as configured in those parameters, but continue evaluating the trial.|
| `DR_EVAL_OFF_TRACK_PENALTY` | Number of seconds penalty time added for an off track during evaluation.  Only takes effect if `DR_EVAL_IS_CONTINUOUS` is set to True.|
| `DR_EVAL_COLLISION_PENALTY` | Number of seconds penalty time added for a collision during evaluation.  Only takes effect if `DR_EVAL_IS_CONTINUOUS` is set to True.|
| `DR_EVAL_SAVE_MP4` | Set to `True` to save MP4 of an evaluation run. |
| `DR_EVAL_REVERSE_DIRECTION` | Set to `True` to reverse the direction in which the car traverses the track.|
| `DR_TRAIN_CHANGE_START_POSITION` | Determines if the racer shall round-robin the starting position during training sessions. (Recommended to be `True` for initial training.)|
| `DR_TRAIN_ALTERNATE_DRIVING_DIRECTION` | `True` or `False`.  If `True`, the car will alternate driving between clockwise and counter-clockwise each episode.|
| `DR_TRAIN_START_POSITION_OFFSET` | Used to control where to start the training from on first episode.|
| `DR_TRAIN_ROUND_ROBIN_ADVANCE_DISTANCE` | How far to progress each episode in round robin.  0.05 is 5% of the track.  Generally best to try and keep this to even numbers that match with your total number of episodes to allow for even distribution around the track.  For example, if 20 episodes per iternation, .05 or .10 or .20  would be good.|
| `DR_TRAIN_MULTI_CONFIG` | `True` or `False`.  This is used if you want to use different run.env configurations for each worker in a multi worker training run.  See multi config documentation for more details on how to set this up.|
| `DR_TRAIN_MIN_EVAL_TRIALS` | The minimum number of evaluation trials run between each training iteration.  Evaluations will continue as long as policy training is occuring and may be more than this number.  This establishes the minimum, and is generally useful if you want to speed up training especially when using gpu sagemaker containers.|
| `DR_TRAIN_REVERSE_DIRECTION` | Set to `True` to reverse the direction in which the car traverses the track. |
| `DR_TRAIN_BEST_MODEL_METRIC` | Can be used to control which model is kept as the "best" model. Set to `progress` to select the model with the highest evaluation completion percentage, set to `reward` to select the model with the highest evaluation reward.|
| `DR_TRAIN_MAX_STEPS_PER_ITERATION` | Can be used to control the max number of steps per iteration to use for learning, the excess steps will be discarded to avoid out-of-memory situations, default is 10000. |
| `DR_LOCAL_S3_PRETRAINED` | Determines if training or evaluation shall be based on the model created in a previous session, held in `s3://{DR_LOCAL_S3_BUCKET}/{LOCAL_S3_PRETRAINED_PREFIX}`, accessible by credentials held in profile `{DR_LOCAL_S3_PROFILE}`.|
| `DR_LOCAL_S3_PRETRAINED_PREFIX` | Prefix of pretrained model within S3 bucket.|
| `DR_LOCAL_S3_MODEL_PREFIX` | Prefix of model within S3 bucket.|
| `DR_LOCAL_S3_BUCKET` | Name of S3 bucket which will be used during the session.|
| `DR_LOCAL_S3_CUSTOM_FILES_PREFIX` | Prefix of configuration files within S3 bucket.|
| `DR_LOCAL_S3_TRAINING_PARAMS_FILE` | Name of YAML file that holds parameters sent to robomaker container for configuration during training. Filename is relative to `s3://{DR_LOCAL_S3_BUCKET}/{LOCAL_S3_PRETRAINED_PREFIX}`.|
| `DR_LOCAL_S3_EVAL_PARAMS_FILE` | Name of YAML file that holds parameters sent to robomaker container for configuration during evaluations.  Filename is relative to `s3://{DR_LOCAL_S3_BUCKET}/{LOCAL_S3_PRETRAINED_PREFIX}`.|
| `DR_LOCAL_S3_MODEL_METADATA_KEY` | Location where the `model_metadata.json` file is stored.|
| `DR_LOCAL_S3_HYPERPARAMETERS_KEY` | Location where the `hyperparameters.json` file is stored.|
| `DR_LOCAL_S3_REWARD_KEY` | Location where the `reward_function.py` file is stored.|
| `DR_LOCAL_S3_METRICS_PREFIX` | Location where the metrics will be stored.|
| `DR_OA_NUMBER_OF_OBSTACLES` | For Object Avoidance, the number of obstacles on the track.|
| `DR_OA_MIN_DISTANCE_BETWEEN_OBSTACLES` | Minimum distance in meters between obstacles.|
| `DR_OA_RANDOMIZE_OBSTACLE_LOCATIONS` | If True, obstacle locations will randomly change after each episode.|
| `DR_OA_IS_OBSTACLE_BOT_CAR` | If True, obstacles will appear as a stationary car instead of a box.|
| `DR_OA_OBJECT_POSITIONS` | Positions of boxes on the track. Tuples consisting of progress (fraction [0..1]) and inside or outside lane (-1 or 1). Example: `"0.23,-1;0.46,1"`|
| `DR_H2B_IS_LANE_CHANGE` | If True, bot cars will change lanes based on configuration.|
| `DR_H2B_LOWER_LANE_CHANGE_TIME` | Minimum time in seconds before car will change lanes.|
| `DR_H2B_UPPER_LANE_CHANGE_TIME` | Maximum time in seconds before car will change langes.|
| `DR_H2B_LANE_CHANGE_DISTANCE` | Distance in meters how long it will take the car to change lanes.|
| `DR_H2B_NUMBER_OF_BOT_CARS` | Number of bot cars on the track.|
| `DR_H2B_MIN_DISTANCE_BETWEEN_BOT_CARS` | Minimum distance between bot cars.|
| `DR_H2B_RANDOMIZE_BOT_CAR_LOCATIONS` | If True, bot car locations will randomly change after each episode.|
| `DR_H2B_BOT_CAR_SPEED` | How fast the bot cars go in meters per second.|
| `DR_CLOUD` | Can be `azure`, `aws`, `local` or `remote`; determines how the storage will be configured.|
| `DR_AWS_APP_REGION` | (AWS only) Region for other AWS resources (e.g. Kinesis) |
| `DR_UPLOAD_S3_PROFILE` | AWS Cli profile to be used that holds the 'real' S3 credentials needed to upload a model into AWS DeepRacer.|
| `DR_UPLOAD_S3_BUCKET` | Name of the AWS DeepRacer bucket where models will be uploaded. (Typically starts with `aws-deepracer-`.)|
| `DR_LOCAL_S3_PROFILE` | Name of AWS profile with credentials to be used. Stored in `~/.aws/credentials` unless AWS IAM Roles are used.|
| `DR_GUI_ENABLE` | Enable or disable the Gazebo GUI in Robomaker |
| `DR_KINESIS_STREAM_NAME` | Kinesis stream name. Used if you actually publish to the AWS KVS service. Leave blank if you do not want this. |
| `DR_KINESIS_STREAM_ENABLE` | Enable or disable 'Kinesis Stream', True both publishes to a AWS KVS stream (if name not None), and to the topic `/racecar/deepracer/kvs_stream`. Leave True if you want to watch the car racing. |
| `DR_SAGEMAKER_IMAGE` | Determines which sagemaker image will be used for training.|
| `DR_ROBOMAKER_IMAGE` | Determines which robomaker image will be used for training or evaluation.|
| `DR_MINIO_IMAGE` | Determines which Minio image will be used. |
| `DR_COACH_IMAGE` | Determines which coach image will be used for training.|
| `DR_WORKERS` | Number of Robomaker workers to be used for training.  See additional documentation for more information about this feature.|
| `DR_ROBOMAKER_MOUNT_LOGS` | True to get logs mounted to `$DR_DIR/data/logs/robomaker/$DR_LOCAL_S3_MODEL_PREFIX`|
| `DR_ROBOMAKER_MOUNT_SIMAPP_DIR` | Path to the altered Robomaker bundle, e.g. `/home/ubuntu/deepracer-simapp/bundle`.|
| `DR_CLOUD_WATCH_ENABLE` | Send log files to AWS CloudWatch.|
| `DR_CLOUD_WATCH_LOG_STREAM_PREFIX` | Add a prefix to the CloudWatch log stream name.|
| `DR_DOCKER_STYLE` | Valid Options are `Swarm` and `Compose`.  Use Compose for openGL optimized containers.|
| `DR_HOST_X` | Uses the host X-windows server, rather than starting one inside of Robomaker. Required for OpenGL images.|
| `DR_WEBVIEWER_PORT` | Port for the web-viewer proxy which enables the streaming of all robomaker workers at once.|
| `CUDA_VISIBLE_DEVICES` | Used in multi-GPU configurations. See additional documentation for more information about this feature.|
| `DR_TELEGRAF_HOST` | The hostname to send real-time metrics to. Uncommenting this will enable real-time metrics collection using Telegraf. The telegraf/influxdb/grafana compose stack must already be running (use `dr-start-metrics`) for this to work, and it should usually be set to `telegraf` to send metrics to the telegraf container.
| `DR_TELEGRAF_PORT` | Defines the UDP port to send real-time metrics to. Should usually remain set as 8092.  

## Commands

| Command | Description |
|---------|-------------|
| `dr-update` | Loads in all scripts and environment variables again.|
| `dr-update-env` | Loads in all environment variables from `system.env` and `run.env`.|
| `dr-upload-custom-files` | Uploads changed configuration files from `custom_files/` into `s3://{DR_LOCAL_S3_BUCKET}/custom_files`.|
| `dr-download-custom-files` | Downloads changed configuration files from `s3://{DR_LOCAL_S3_BUCKET}/custom_files` into `custom_files/`.|
| `dr-start-training` | Starts a training session in the local VM based on current configuration.|
| `dr-increment-training` | Updates configuration, setting the current model prefix to pretrained, and incrementing a serial.|
| `dr-stop-training` | Stops the current local training session. Uploads log files.|
| `dr-start-evaluation` | Starts a evaluation session in the local VM based on current configuration.|
| `dr-stop-evaluation` | Stops the current local evaluation session. Uploads log files.|
| `dr-start-loganalysis` | Starts a Jupyter log-analysis container, available on port 8888.|
| `dr-stop-loganalysis` | Stops the Jupyter log-analysis container.|
| `dr-start-viewer` | Starts an NGINX proxy to stream all the robomaker streams; accessible remotly.|
| `dr-stop-viewer` | Stops the NGINX proxy.|
| `dr-logs-sagemaker` | Displays the logs from the running Sagemaker container.|
| `dr-logs-robomaker` | Displays the logs from the running Robomaker container.|
| `dr-list-aws-models` | Lists the models that are currently stored in your AWS DeepRacer S3 bucket. |
| `dr-set-upload-model` | Updates the `run.env` with the prefix and name of your selected model. |
| `dr-upload-model` | Uploads the model defined in `DR_LOCAL_S3_MODEL_PREFIX` to the AWS DeepRacer S3 prefix defined in `DR_UPLOAD_S3_PREFIX` |
| `dr-download-model` | Downloads a file from a 'real' S3 location into a local prefix of choice. |
