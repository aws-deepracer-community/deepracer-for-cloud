# Installing Deepracer-for-Cloud

## Requirements

Depending on your needs as well as specific needs of the cloud platform you can configure your VM to your liking. Both CPU-only as well as GPU systems are supported.

**AWS**:

* EC2 instance of type G3, G4, P2 or P3 - recommendation is g4dn.2xlarge - for GPU enabled training. C5 or M6 types - recommendation is c5.2xlarge - for CPU training.
  * Ubuntu 20.04
  * Minimum 30 GB, preferred 40 GB of OS disk.
  * Ephemeral Drive connected
  * Minimum of 8 GB GPU-RAM if running with GPU.
  * Recommended at least 6 VCPUs
* S3 bucket. Preferrably in same region as EC2 instance.
* The internal `sagemaker-local` docker network runs by default on `192.168.2.0/24`. Ensure that your AWS IPC does not overlap with this subnet.

**Azure**:

* N-Series VM that comes with NVIDIA Graphics Adapter - recommendation is NC6_Standard
  * Ubuntu 20.04
  * Standard 30 GB OS drive is sufficient to get started.
  * Recommended to add an additional 32 GB data disk if you want to use the Log Analysis container.
  * Minimum 8 GB GPU-RAM
  * Recommended at least 6 VCPUs
* Storage Account with one Blob container configured for Access Key authentication.

**Local**:

* A modern, comparatively powerful, Intel based system.
  * Ubuntu 20.04, other Linux-dristros likely to work.
  * 4 core-CPU, equivalent to 8 vCPUs; the more the better.
  * NVIDIA Graphics adapter with minimum 8 GB RAM for Sagemaker to run GPU. Robomaker enabled GPU instances need ~1 GB each.
  * System RAM + GPU RAM should be at least 32 GB.
* Running DRfC Ubuntu 20.04 on Windows using Windows Subsystem for Linux 2 is possible. See [Installing on Windows](windows.md)

## Installation

The package comes with preparation and setup scripts that would allow a turn-key setup for a fresh virtual machine.

```shell
git clone https://github.com/aws-deepracer-community/deepracer-for-cloud.git
```

**For cloud setup** execute:

```shell
cd deepracer-for-cloud && ./bin/prepare.sh
```

This will prepare the VM by partitioning additional drives as well as installing all prerequisites. After a reboot it will continuee to run `./bin/init.sh` setting up the full repository and downloading the core Docker images. Depending on your environment this may take up to 30 minutes. The scripts will create a file `DONE` once completed.

The installation script will adapt `.profile` to ensure that all settings are applied on login. Otherwise run the activation with `source bin/activate.sh`.

**For local install** it is recommended *not* to run the `bin/prepare.sh` script; it might do more changes than what you want. Rather ensure that all prerequisites are set up and run `bin/init.sh` directly.

See also the [following article](https://awstip.com/deepracer-for-cloud-drfc-local-setup-3c6418b2c75a) for guidance.

The Init Script takes a few parameters:

| Variable | Description |
|----------|-------------|
| `-c <cloud>` | Sets the cloud version to be configured, automatically updates the `DR_CLOUD` parameter in `system.env`. Options are `azure`, `aws` or `local`. Default is `local` |
| `-a <arch>` | Sets the architecture to be configured. Either `cpu` or `gpu`. Default is `gpu`. |

## Environment Setup

The initialization script will attempt to auto-detect your environment (`Azure`, `AWS` or `Local`), and store the outcome in the `DR_CLOUD` parameter in `system.env`. You can also pass in a `-c <cloud>` parameter to override it, e.g. if you want to run the minio-based `local` mode in the cloud.

The main difference between the mode is based on authentication mechanisms and type of storage being configured. The next chapters will review each type of environment on its own.

### AWS

In AWS it is possible to set up authentication to S3 in two ways: Integrated sign-on using [IAM Roles](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html) or using access keys.

#### IAM Role

To use IAM Roles:

* An empty S3 bucket in the same region as the EC2 instance.
* An IAM Role that has permissions to:
  * Access both the *new* S3 bucket as well as the DeepRacer bucket.
  * AmazonVPCReadOnlyAccess
  * AmazonKinesisVideoStreamsFullAccess if you want to stream to Kinesis
  * CloudWatch
* An EC2 instance with the defined IAM Role assigned.
* Configure `system.env` as follows:
  * `DR_LOCAL_S3_PROFILE=default`
  * `DR_LOCAL_S3_BUCKET=<bucketname>`
  * `DR_UPLOAD_S3_PROFILE=default`
  * `DR_UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update` for configuration to take effect.

#### Manual setup

For access with IAM user:

* An empty S3 bucket in the same region as the EC2 instance.
* A real AWS IAM user set up with access keys:
  * User should have permissions to access the *new* bucket as well as the dedicated DeepRacer S3 bucket.
  * Use `aws configure` to configure this into the default profile.
* Configure `system.env` as follows:
  * `DR_LOCAL_S3_PROFILE=default`
  * `DR_LOCAL_S3_BUCKET=<bucketname>`
  * `DR_UPLOAD_S3_PROFILE=default`
  * `DR_UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update` for configuration to take effect.

### Azure

Minio has deprecated the gateway feature that exposed an Azure Blob Storage as an S3 bucket. Azure mode now sets up minio in the same way as in local mode.

If you want to use awscli (`aws`) to manually move files then use `aws $DR_LOCAL_PROFILE_ENDPOINT_URL s3 ...`, as this will set both `--profile` and `--endpoint-url` parameters to match your configuration.

### Local

Local mode runs a minio server that hosts the data in the `docker/volumes` directory. It is otherwise command-compatible with the Azure setup; as the data is accessible via Minio and not via native S3.

In Local mode the script-set requires the following:

* Configure the Minio credentials with `aws configure --profile minio`. The default configuration will use the `minio` profile to configure MINIO. You can choose any username or password, but username needs to be at least length 3, and password at least length 8.
* A real AWS IAM user configured with `aws configure` to enable upload of models into AWS DeepRacer.
* Configure `system.env` as follows:
  * `DR_LOCAL_S3_PROFILE=default`
  * `DR_LOCAL_S3_BUCKET=<bucketname>`
  * `DR_UPLOAD_S3_PROFILE=default`
  * `DR_UPLOAD_S3_BUCKET=<your-aws-deepracer-bucket>`
* Run `dr-update` for configuration to take effect.

## First Run

For the first run the following final steps are needed. This creates a training run with all default values in

* Define your custom files in `custom_files/` - samples can be found in `defaults` which you must copy over:
  * `hyperparameters.json` - definining the training hyperparameters
  * `model_metadata.json` - defining the action space and sensors
  * `reward_function.py` - defining the reward function
* Upload the files into the bucket with `dr-upload-custom-files`. This will also start minio if required.
* Start training with `dr-start-training`

After a while you will see the sagemaker logs on the screen.

## Troubleshooting

Here are some hints for troubleshooting specific issues you may encounter

### Local training troubleshooting

| Issue        | Troubleshooting hint |
|------------- | ---------------------|
Get messages like "Sagemaker is not running" | Run `docker -ps a` to see if the containers are running or if they stopped due to some errors. If running after a fresh install, try restarting the system.
Check docker errors for specific container | Run `docker logs -f <containerid>`
Get message "Error response from daemon: could not choose an IP address to advertise since this system has multiple addresses on interface <your_interface> ..." when running `./bin/init.sh -c local -a cpu` | It means you have multiple IP addresses and you need to specify one within `./bin/init.sh`.<br> If you don't care which one to use, you can get the first one by running ```ifconfig \| grep $(route \| awk '/^default/ {print $8}') -a1 \| grep -o -P '(?<=inet ).*(?= netmask)```.<br> Edit   `./bin/init.sh` and locate line `docker swarm init` and change it to `docker swarm init --advertise-addr <your_IP>`.<br> Rerun  `./bin/init.sh -c local -a cpu`
I don't have any of the `dr-*` commands | Run `source bin/activate.sh`.
