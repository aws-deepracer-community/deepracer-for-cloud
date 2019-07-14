FROM python:3.7.3-stretch

# install docker
RUN apt-get update
RUN apt-get -y install apt-transport-https ca-certificates curl gnupg2 software-properties-common
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

RUN apt-get update
RUN apt-get -y install docker-ce

# add required deepracer directories to the container
RUN mkdir /deepracer
RUN mkdir /deepracer/rl_coach
RUN mkdir /deepracer/sagemaker-python-sdk
WORKDIR /deepracer
ADD rl_coach rl_coach
ADD sagemaker-python-sdk sagemaker-python-sdk

# create sagemaker configuration
RUN mkdir /root/.sagemaker
COPY config.yaml /root/.sagemaker/config.yaml

RUN mkdir /robo
RUN mkdir /robo/container

# install dependencies
RUN pip install -U sagemaker-python-sdk/ awscli ipython pandas "urllib3==1.22" "pyyaml==3.13"

# set command
CMD (cd rl_coach; ipython rl_deepracer_coach_robomaker.py)