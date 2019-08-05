# DeepRacer-For-Dummies
Provides a quick and easy way to get up and running with a local deepracer training environment using Docker Compose.
This repo just creates a wrapper around the amazing work done by Alex found here: https://github.com/alexschultz/deepracer-for-dummies.
This repo adds some additional functionanlity such as a GUI and a lot of under-the-hood improvements.
Please refer to his repo to understand more about what's going on under the covers.
For additional help, submit an issue or join the [deepracer slack](join.deepracing.io) for some more support. 

# Getting Started
---

### Using the GUI

We've made a GUI to make training locally as simple as possible. Follow [this guide](https://medium.com/@autonomousracecarclub/how-to-improve-your-local-deepracer-workflow-23a76d12a1a9) for using the GUI.

### Training Manually

#### Environment

This guide was built to run on Ubuntu 18.04. We know it runs on Ubuntu 16.04, and there's reports on it running on OS X and Windows as well, if you've managed to make it run on those platforms, submit a issue ticket and let us know, we'd love to know how you did it! 

Follow these guides for setting up the environment and getting started:

https://medium.com/@autonomousracecarclub/how-to-run-deepracer-locally-to-save-your-wallet-13ccc878687


To start or stop the local deepracer training, use the scripts found in the scripts directory.

Here is a brief overview of the available scripts:

#### Scripts

* training
	* start.sh
		* starts the whole environment using docker compose
		* it will also open a terminal window where you can monitor the log output from the sagemaker training directory
		* it will also automatically open vncviewer so you can watch the training happening in Gazebo
		* For the memoryManager.py make sure to enter your user password into the opened terminal in order to run the program in sudo
	* stop.sh
		* stops the whole environment
		* automatically finds and stops the training container which was started from the sagemaker container
	* upload-snapshot.sh
		* uploads a specific snapshot to S3 in AWS. If no checkpoint is provided, it attempts to retrieve the latest snapshot
	* set-last-run-to-pretrained.sh
		* renames the last training run directory from ***rl-deepracer-sagemaker*** to ***rl-deepracer-pretrained*** so that you can use it as a starting point for a new training run.
	* delete-last-run.sh
		* (WARNING: this script deletes files on your system. I take no responsibility for any resulting actions by running this script. Please look at what the script is doing before running it so that you understand)
		* deletes the last training run including all of the snapshots and log files. You will need sudo to run this command.


* evaluation
	* work in progress

* log-analysis
	* start.sh
		* starts a container with Nvidia-Docker running jupyter labs with the log analysis notebooks which were originally provided by AWS and then extended by  Tomasz Ptak
		* the logs from robomaker are automatically mounted in the container so you don't have to move any files around
		* in order to get to the container, look at the log output from when it starts. You need to grab the URL including the token query parameter and then paste it into the brower at **localhost:8888**.
	* stop.sh
		* stops the log-analysis container
		
#### Uploading to the DeepRacer League
Once you've trained your model, you can upload your model to be evaluated and submitted to the DeepRacer league. Follow the guide linked below:

https://medium.com/@autonomousracecarclub/uploading-a-locally-trained-deepracer-model-to-aws-c9ed8262232b

#### Hyperparameters

You can modify training hyperparameters from the file **rl_deepracer_coach_robomaker.py**.

#### Action Space & Reward Function

The action-space and reward function files are located in the **deepracer-for-dummies/docker/volumes/minio/bucket/custom_files** directory

#### Track Selection

The track selection is controled via an environment variable in the **.env** file located in the **deepracer-for-dummies/docker** directory
