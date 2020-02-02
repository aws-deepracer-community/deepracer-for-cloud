FROM  nvidia/cuda:10.0-cudnn7-runtime-ubuntu18.04

LABEL maintainer="lars@ludvig.no" \
	  description="Log Analysis for DeepRacer Training Run" \
	  version=1.0

# Container Dependency Setup
RUN apt-get update && apt-get upgrade -y && \ 
	apt-get install --no-install-recommends software-properties-common libsm6 libxext6 libxrender-dev git wget python3-pip -y && \
	apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH /usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda-10.0/targets/x86_64-linux/lib

RUN pip3 install virtualenv && virtualenv /workspace/venv
WORKDIR /workspace/venv
RUN mkdir -p /workspace/venv/data /workspace/venv/logs /workspace/venv/workbook

# Install common pip packages
WORKDIR /workspace/venv
COPY requirements.txt ./
RUN . /workspace/venv/bin/activate && pip install --no-cache-dir -r requirements.txt

EXPOSE 8888
VOLUME ["/workspace/venv/data", "/workspace/venv/logs", "/root/.aws", "/workspace/venv/workbook"]
CMD . /workspace/venv/bin/activate && jupyter lab --ip=0.0.0.0 --port=8888 --allow-root

