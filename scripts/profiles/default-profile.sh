#!/bin/bash

function ctrl_c() {
        echo "Requested to stop."
        exit 1
}


    read -r -p "This will overwrite your current configuration. Are you sure? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        echo "Aborting."
        exit 1
    fi


WORK_DIR=${DR_DIR}

#[ -e $WORK_DIR/worker-* ] && rm $WORK_DIR/worker-*

cp $WORK_DIR/defaults/template-run.env $WORK_DIR/run.env
cp $WORK_DIR/defaults/template-system.env $WORK_DIR/system.env
cp $WORK_DIR/defaults/hyperparameters.json $WORK_DIR/custom_files/hyperparameters.json
cp $WORK_DIR/defaults/model_metadata.json $WORK_DIR/custom_files/model_metadata.json
cp $WORK_DIR/defaults/reward_function.py $WORK_DIR/custom_files/reward_function.py

if [ -e $WORK_DIR/worker-2.env ]
then rm $WORK_DIR/worker-*
fi
