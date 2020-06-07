# Deepracer-for-Cloud Reference

## Environment Variables
The scripts assume that two files `systen.env` containing constant configuration values and  `run.env` with run specific values is populated with the required values. Which values go into which file is not really important.

| Variable | Description |
|----------|-------------|
| `DR_CLOUD` | Can be `azure`, `aws` or `local`; determines how the storage will be configured.|
| `DR_WORLD_NAME` | Defines the track to be used.| 
| `DR_NUMBER_OF_TRIALS` | Defines the number of trials in an evaluation session.| 
| `DR_CHANGE_START_POSITION` | Determines if the racer shall round-robin the starting position during training sessions. (Recommended to be `True` for initial training.)| 
| `DR_LOCAL_S3_PROFILE` | Name of AWS profile with credentials to be used. Stored in `~/.aws/credentials` unless AWS IAM Roles are used.|
| `DR_LOCAL_S3_BUCKET` | Name of S3 bucket which will be used during the session.|
| `DR_LOCAL_S3_MODEL_PREFIX` | Prefix of model within S3 bucket.|
| `DR_LOCAL_S3_CUSTOM_FILES_PREFIX` | Prefix of configuration files within S3 bucket.|
| `DR_LOCAL_S3_PRETRAINED` | Determines if training or evaluation shall be based on the model created in a previous session, held in `s3://{DR_LOCAL_S3_BUCKET}/{LOCAL_S3_PRETRAINED_PREFIX}`, accessible by credentials held in profile `{DR_LOCAL_S3_PROFILE}`.| 
| `DR_LOCAL_S3_PRETRAINED_PREFIX` | Prefix of pretrained model within S3 bucket.|
| `DR_LOCAL_S3_PARAMS_FILE` | YAML file path used to configure Robomaker relative to `s3://{DR_LOCAL_S3_BUCKET}/{LOCAL_S3_PRETRAINED_PREFIX}`.| 
| `DR_UPLOAD_S3_PROFILE` | AWS Cli profile to be used that holds the 'real' S3 credentials needed to upload a model into AWS DeepRacer.|
| `DR_UPLOAD_S3_BUCKET` | Name of the AWS DeepRacer bucket where models will be uploaded. (Typically starts with `aws-deepracer-`.)|
| `DR_UPLOAD_S3_PREFIX` | Prefix of the target location. (Typically starts with `DeepRacer-SageMaker-RoboMaker-comm-`|
| `DR_UPLOAD_MODEL_NAME` | Display name of model, not currently used; `dr-set-upload-model` sets it for readability purposes.|
| `DR_CAR_COLOR` | Color of car | 
| `DR_CAR_NAME` | Display name of car; shows in Deepracer Console when uploading. |
| `DR_AWS_APP_REGION` | (AWS only) Region for other AWS resources (e.g. Kinesis) |
| `DR_KINESIS_STREAM_NAME` | Kinesis stream name | 
| `DR_KINESIS_STREAM_ENABLE` | Enable or disable Kinesis Stream | 
| `DR_GUI_ENABLE` | Enable or disable the Gazebo GUI in Robomaker | 
| `DR_GPU_AVAILABLE` | Is GPU enabled? | 
| `DR_DOCKER_IMAGE_TYPE` | `cpu` or `gpu`; docker images will be used based on this | 

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
| `dr-start-loganalysis` | Stops the Jupyter log-analysis container.|
| `dr-logs-sagemaker` | Displays the logs from the running Sagemaker container.|
| `dr-logs-robomaker` | Displays the logs from the running Robomaker container.|
| `dr-list-aws-models` | Lists the models that are currently stored in your AWS DeepRacer S3 bucket. |
| `dr-set-upload-model` | Updates the `run.env` with the prefix and name of your selected model. |
| `dr-upload-model` | Uploads the model defined in `DR_LOCAL_S3_MODEL_PREFIX` to the AWS DeepRacer S3 prefix defined in `DR_UPLOAD_S3_PREFIX` |
