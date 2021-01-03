# Head-to-Head Race (Beta)

It is possible to run a head-to-head race, similar to the races in the brackets 
run by AWS in the Virtual Circuits to  determine the winner of the head-to-bot races.

This replaces the "Tournament Mode".

## Introduction

The concept is that you have two models racing each other, one Purple and one Orange Car. One car
is powered by our primary configured model, and the second car is powered by the model in `DR_EVAL_OPP_S3_MODEL_PREFIX`

## Configuration

### run.env

Configure `run.env` with the following parameters:
* `DR_RACE_TYPE` should be `HEAD_TO_MODEL`.
* `DR_EVAL_OPP_S3_MODEL_PREFIX` will be the S3 prefix for the secondary model.
* `DR_EVAL_OPP_CAR_NAME` is the display name of this model.

Metrics, Traces and Videos will be stored in each models' prefix.

## Run

Run the race with `dr-start-evaluation`; one race will be run. 