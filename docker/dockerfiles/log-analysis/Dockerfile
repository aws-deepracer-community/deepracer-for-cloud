FROM tensorflow/tensorflow:latest-gpu

LABEL maintainer="lars@ludvig.no" \
	  description="Log Analysis for DeepRacer Training Run" \
	  version=1.0

# Container Dependency Setup
RUN apt-get update && apt-get upgrade -y && \ 
	apt-get install software-properties-common libsm6 libxext6 libxrender-dev git wget python3-pip -y && \
	rm -rf /var/lib/apt/lists/*

RUN pip3 install virtualenv
RUN virtualenv /workspace/venv
WORKDIR /workspace/venv
RUN mkdir -p /workspace/venv/data /workspace/venv/logs /workspace/venv/workbook

# Install common pip packages
WORKDIR /workspace/venv
COPY requirements.txt ./
RUN ls -lrt
RUN . /workspace/venv/bin/activate && pip install -r requirements.txt

EXPOSE 8888
VOLUME ["/workspace/venv/data", "/workspace/venv/logs", "/root/.aws", "/workspace/venv/workbook"]
CMD . /workspace/venv/bin/activate && jupyter lab --ip=0.0.0.0 --port=8888 --allow-root

