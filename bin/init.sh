#!/usr/bin/env bash

trap ctrl_c INT

function ctrl_c() {
    echo "Requested to stop."
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

if [[ "$INSTALL_DIR" == *\ * ]]; then
    echo "Deepracer-for-Cloud cannot be installed in path with spaces. Exiting."
    exit 1
fi

OPT_ARCH="gpu"
OPT_CLOUD=""
OPT_STYLE="swarm"

while getopts ":m:c:a:s:" opt; do
    case $opt in
    a)
        OPT_ARCH="$OPTARG"
        ;;
    m)
        OPT_MOUNT="$OPTARG"
        ;;
    c)
        OPT_CLOUD="$OPTARG"
        ;;
    s)
        OPT_STYLE="$OPTARG"
        ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
        exit 1
        ;;
    esac
done

if [[ -z "$OPT_CLOUD" ]]; then
    source $SCRIPT_DIR/detect.sh
    OPT_CLOUD=$CLOUD_NAME
    echo "Detected cloud type to be $CLOUD_NAME"
fi

# Find CPU Level
CPU_LEVEL="cpu"

if [[ -f /proc/cpuinfo ]] && [[ "$(cat /proc/cpuinfo | grep avx2 | wc -l)" > 0 ]]; then
    CPU_LEVEL="cpu"
elif [[ "$(type sysctl 2>/dev/null)" ]] && [[ "$(sysctl -n hw.optional.avx2_0)" == 1 ]]; then
    CPU_LEVEL="cpu"
fi

# Check if Intel (to ensure MKN)
if [[ -f /proc/cpuinfo ]] && [[ "$(cat /proc/cpuinfo | grep GenuineIntel | wc -l)" > 0 ]]; then
    CPU_INTEL="true"
elif [[ "$(type sysctl 2>/dev/null)" ]] && [[ "$(sysctl -n machdep.cpu.vendor)" == "GenuineIntel" ]]; then
    CPU_INTEL="true"
fi

# Check GPU
if [[ "${OPT_ARCH}" == "gpu" ]]; then
    docker buildx build -t local/gputest - <$INSTALL_DIR/utils/Dockerfile.gpu-detect
    GPUS=$(docker run --rm --gpus all local/gputest 2>/dev/null | awk '/Device: ./' | wc -l)
    if [ $? -ne 0 ] || [ $GPUS -eq 0 ]; then
        echo "No GPU detected in docker. Using CPU".
        OPT_ARCH="cpu"
    fi
fi

cd $INSTALL_DIR

# create directory structure for docker volumes
mkdir -p $INSTALL_DIR/data $INSTALL_DIR/data/minio $INSTALL_DIR/data/minio/bucket
mkdir -p $INSTALL_DIR/data/logs $INSTALL_DIR/data/analysis $INSTALL_DIR/data/scripts $INSTALL_DIR/tmp
sudo mkdir -p /tmp/sagemaker
sudo chmod -R g+w /tmp/sagemaker

# create symlink to current user's home .aws directory
# NOTE: AWS cli must be installed for this to work
# https://docs.aws.amazon.com/cli/latest/userguide/install-linux-al2017.html
mkdir -p $(eval echo "~${USER}")/.aws $INSTALL_DIR/docker/volumes/
ln -sf $(eval echo "~${USER}")/.aws $INSTALL_DIR/docker/volumes/

# copy rewardfunctions
mkdir -p $INSTALL_DIR/custom_files
cp $INSTALL_DIR/defaults/hyperparameters.json $INSTALL_DIR/custom_files/
cp $INSTALL_DIR/defaults/model_metadata.json $INSTALL_DIR/custom_files/
cp $INSTALL_DIR/defaults/reward_function.py $INSTALL_DIR/custom_files/

cp $INSTALL_DIR/defaults/template-system.env $INSTALL_DIR/system.env
cp $INSTALL_DIR/defaults/template-run.env $INSTALL_DIR/run.env
if [[ "${OPT_CLOUD}" == "aws" ]]; then
    AWS_EC2_AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    AWS_REGION="$(echo $AWS_EC2_AVAIL_ZONE | sed 's/[a-z]$//')"
    sed -i "s/<AWS_DR_BUCKET>/not-defined/g" $INSTALL_DIR/system.env
    sed -i "s/<LOCAL_PROFILE>/default/g" $INSTALL_DIR/system.env
elif [[ "${OPT_CLOUD}" == "remote" ]]; then
    AWS_REGION="us-east-1"
    sed -i "s/<LOCAL_PROFILE>/minio/g" $INSTALL_DIR/system.env
    sed -i "s/<AWS_DR_BUCKET>/not-defined/g" $INSTALL_DIR/system.env
    echo "Please run 'aws configure --profile minio' to set the credentials"
    echo "Please define DR_REMOTE_MINIO_URL in system.env to point to remote minio instance."
else
    AWS_REGION="us-east-1"
    MINIO_PROFILE="minio"
    sed -i "s/<LOCAL_PROFILE>/$MINIO_PROFILE/g" $INSTALL_DIR/system.env
    sed -i "s/<AWS_DR_BUCKET>/not-defined/g" $INSTALL_DIR/system.env

    aws configure --profile $MINIO_PROFILE get aws_access_key_id >/dev/null 2>/dev/null

    if [[ "$?" -ne 0 ]]; then
        echo "Creating default minio credentials in AWS profile '$MINIO_PROFILE'"
        aws configure --profile $MINIO_PROFILE set aws_access_key_id $(openssl rand -base64 12)
        aws configure --profile $MINIO_PROFILE set aws_secret_access_key $(openssl rand -base64 12)
        aws configure --profile $MINIO_PROFILE set region us-east-1
    fi
fi
sed -i "s/<AWS_DR_BUCKET_ROLE>/to-be-defined/g" $INSTALL_DIR/system.env
sed -i "s/<CLOUD_REPLACE>/$OPT_CLOUD/g" $INSTALL_DIR/system.env
sed -i "s/<REGION_REPLACE>/$AWS_REGION/g" $INSTALL_DIR/system.env

if [[ "${OPT_ARCH}" == "gpu" ]]; then
    SAGEMAKER_TAG="gpu"
elif [[ -n "${CPU_INTEL}" ]]; then
    SAGEMAKER_TAG="cpu"
else
    SAGEMAKER_TAG="cpu"
fi

#set proxys if required
for arg in "$@"; do
    IFS='=' read -ra part <<<"$arg"
    if [ "${part[0]}" == "--http_proxy" ] || [ "${part[0]}" == "--https_proxy" ] || [ "${part[0]}" == "--no_proxy" ]; then
        var=${part[0]:2}=${part[1]}
        args="${args} --build-arg ${var}"
    fi
done

# Download docker images. Change to build statements if locally built images are desired.
COACH_VERSION=$(jq -r '.containers.rl_coach | select (.!=null)' $INSTALL_DIR/defaults/dependencies.json)
sed -i "s/<COACH_TAG>/$COACH_VERSION/g" $INSTALL_DIR/system.env

ROBOMAKER_VERSION=$(jq -r '.containers.robomaker  | select (.!=null)' $INSTALL_DIR/defaults/dependencies.json)
if [ -n $ROBOMAKER_VERSION ]; then
    ROBOMAKER_VERSION=$ROBOMAKER_VERSION-$CPU_LEVEL
else
    ROBOMAKER_VERSION=$CPU_LEVEL
fi
sed -i "s/<ROBO_TAG>/$ROBOMAKER_VERSION/g" $INSTALL_DIR/system.env

SAGEMAKER_VERSION=$(jq -r '.containers.sagemaker  | select (.!=null)' $INSTALL_DIR/defaults/dependencies.json)
if [ -n $SAGEMAKER_VERSION ]; then
    SAGEMAKER_VERSION=$SAGEMAKER_VERSION-$SAGEMAKER_TAG
else
    SAGEMAKER_VERSION=$SAGEMAKER_TAG
fi
sed -i "s/<SAGE_TAG>/$SAGEMAKER_VERSION/g" $INSTALL_DIR/system.env

docker pull awsdeepracercommunity/deepracer-rlcoach:$COACH_VERSION
docker pull awsdeepracercommunity/deepracer-robomaker:$ROBOMAKER_VERSION
docker pull awsdeepracercommunity/deepracer-sagemaker:$SAGEMAKER_VERSION

# create the network sagemaker-local if it doesn't exit
SAGEMAKER_NW='sagemaker-local'

if [[ "${OPT_STYLE}" == "swarm" ]]; then

    docker node ls >/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Swarm exists. Exiting."
        exit 1
    fi

    docker swarm init
    if [ $? -ne 0 ]; then

        DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')
        DEFAULT_IP=$(ip addr show $DEFAULT_IFACE | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)

        if [ -z "$DEFAULT_IP" ]; then
            echo "Could not determine default IP address. Exiting."
            exit 1
        fi

        echo "Error when creating swarm, trying again with advertise address $DEFAULT_IP."
        docker swarm init --advertise-addr $DEFAULT_IP
        if [ $? -ne 0 ]; then
            echo "Cound not create swarm. Exiting."
            exit 1
        fi
    fi

    SWARM_NODE=$(docker node inspect self | jq .[0].ID -r)
    docker node update --label-add Sagemaker=true $SWARM_NODE >/dev/null 2>/dev/null
    docker node update --label-add Robomaker=true $SWARM_NODE >/dev/null 2>/dev/null
    docker network ls | grep -q $SAGEMAKER_NW
    if [ $? -ne 0 ]; then
        docker network create $SAGEMAKER_NW -d overlay --attachable --scope swarm
    else
        docker network rm $SAGEMAKER_NW
        docker network create $SAGEMAKER_NW -d overlay --attachable --scope swarm --subnet=192.168.2.0/24
    fi

elif [[ "${OPT_STYLE}" == "compose" ]]; then

    docker network ls | grep -q $SAGEMAKER_NW
    if [ $? -ne 0 ]; then
        docker network create $SAGEMAKER_NW
    fi

else
    echo "Unknown docker style ${OPT_STYLE}. Exiting."
    exit 1
fi
sed -i "s/<DOCKER_STYLE>/${OPT_STYLE}/g" $INSTALL_DIR/system.env

# ensure our variables are set on startup - not for local setup.
if [[ "${OPT_CLOUD}" != "local" ]]; then
    NUM_IN_PROFILE=$(cat $HOME/.profile | grep "$INSTALL_DIR/bin/activate.sh" | wc -l)
    if [ "$NUM_IN_PROFILE" -eq 0 ]; then
        echo "source $INSTALL_DIR/bin/activate.sh" >>$HOME/.profile
    fi
fi

# mark as done
date | tee $INSTALL_DIR/DONE

## Optional auturun feature
# if using automation scripts to auto configure and run
# you must pass s3_training_location.txt to this instance in order for this to work
if [[ -f "$INSTALL_DIR/autorun.s3url" ]]; then
    ## read in first line.  first line always assumed to be training location regardless what else is in file
    TRAINING_LOC=$(awk 'NR==1 {print; exit}' $INSTALL_DIR/autorun.s3url)

    #get bucket name
    TRAINING_BUCKET=${TRAINING_LOC%%/*}
    #get prefix. minor exception handling in case there is no prefix and a root bucket is passed
    if [[ "$TRAINING_LOC" == *"/"* ]]; then
        TRAINING_PREFIX=${TRAINING_LOC#*/}
    else
        TRAINING_PREFIX=""
    fi

    ##check if custom autorun script exists in s3 training bucket.  If not, use default in this repo
    aws s3api head-object --bucket $TRAINING_BUCKET --key $TRAINING_PREFIX/autorun.sh || not_exist=true
    if [ $not_exist ]; then
        echo "custom file does not exist, using local copy"
    else
        echo "custom script does exist, use it"
        aws s3 cp s3://$TRAINING_LOC/autorun.sh $INSTALL_DIR/bin/autorun.sh
    fi
    chmod +x $INSTALL_DIR/bin/autorun.sh
    bash -c "source $INSTALL_DIR/bin/autorun.sh"
fi
