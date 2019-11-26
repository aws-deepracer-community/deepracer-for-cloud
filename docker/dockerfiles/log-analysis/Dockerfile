FROM nvcr.io/nvidia/tensorflow:19.06-py2

LABEL maintainer="alex.c.schultz@gmail.com" \
	  description="Log Analysis for DeepRacer Training Run" \
	  version=1.0

# Container Dependency Setup
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install software-properties-common libsm6 libxext6 libxrender-dev git wget python3-pip -y
RUN pip3 install virtualenv
RUN virtualenv venv
WORKDIR /workspace/venv
RUN mkdir -p /workspace/venv/data /workspace/venv/logs

# Install common pip packages
WORKDIR /workspace/venv
COPY requirements.txt ./
RUN ls -lrt
RUN . /workspace/venv/bin/activate && pip install -r requirements.txt

EXPOSE 8888
VOLUME ["/workspace/venv/data", "/workspace/venv/logs", "/root/.aws"]
CMD . /workspace/venv/bin/activate && jupyter lab --ip=0.0.0.0 --port=8888 --allow-root

