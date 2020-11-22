# Head-to-Head Tournament (Beta)

It is possible to run a head-to-head tournament, similar to the elimination brackets 
run by AWS in the Virtual Circuits to  determine the winner of the head-to-bot races.

## Introduction

The concept for tournament is that you have a set of models, each in their own path 
(S3 bucket + prefix). Additionally you define one prefix where all the outcomes will be stored.

Each race in the tournament will require you to start and stop the tournament execution; the code will update the outcome prefix with the current status.

## Configuration

### run.env

Configure `run.env` with the following parameters:
* `DR_LOCAL_S3_MODEL_PREFIX` will be the path where all the outcomes are stored.
* `DR_LOCAL_S3_TOURNAMENT_JSON_FILE` is the local filesystem path to your tournament configuation
* `DR_LOCAL_S3_TOURNAMENT_PARAMS_FILE` is the path where the generated tournament parameters are uploaded
   in S3. Can be left unchanged in most cases.
* `DR_EVAL_NUMBER_OF_TRIALS`, `DR_EVAL_IS_CONTINUOUS`, `DR_EVAL_OFF_TRACK_PENALTY`,
  `DR_EVAL_COLLISION_PENALTY` and `DR_EVAL_SAVE_MP4` to be configured as a normal evaluation run.


### tournament.json

Create a `tournament.json` based on `defaults/sample-tournament.json`. You will have one entry per model.
Required configuration per racer is:
* `racer_name`: The display name of the racer
* `s3_bucket`: The S3 bucket where the model for this racer is stored
* `s3_prefix`: The S3 prefix where the model for this racer is stored.

## Run

Run the tournament with `dr-start-tournament`; one race will be run. Once completed you need to do `dr-stop-tournament` and `dr-start-tournament` to make it run the next race. Iterate until done.