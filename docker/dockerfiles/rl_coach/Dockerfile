FROM python:3.7.3-stretch
LABEL maintainer "Lars Ludvigsen <lars@ludvig.no>"

# install docker
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
RUN apt-get update && apt-get install -y docker-ce-cli && rm -rf /var/lib/apt/lists/*

# create sagemaker configuration
RUN mkdir /root/.sagemaker
COPY deepracer/config.yaml /root/.sagemaker/config.yaml
RUN mkdir /robo && mkdir /robo/container

# add required deepracer directories to the container
# RUN mkdir -p /deepracer && mkdir -p /deepracer/rl_coach && mkdir -p /deepracer/sagemaker-python-sdk
WORKDIR /deepracer
ADD deepracer/rl_coach /deepracer/rl_coach
ADD deepracer/sagemaker-python-sdk /deepracer/sagemaker-python-sdk

# install dependencies
RUN pip install -U /deepracer/sagemaker-python-sdk/ awscli ipython pandas "urllib3==1.22" "pyyaml==3.13" "python-dateutil==2.8.0"

# set command
CMD (cd rl_coach; ipython rl_deepracer_coach_robomaker.py)
