# Installing on Windows

## Prerequisites

The basic installation steps to get a NVIDIA GPU / CUDA enabled Ubuntu subsystem on Windows can be found in the [Cuda on WSL User Guide](https://docs.nvidia.com/cuda/wsl-user-guide/index.html).

The further instructions assume that you have a working Nvidia enabled Docker.

## Additional steps

The `bin/prepare.sh` will not work for a Ubuntu WSL installation, hence additional steps will be required.

### Adding required packages

Install the additional packages with the following command:

```
sudo apt-get install jq awscli python3-boto3 docker-compose
```

### Configure Docker

To ensure we always have a GPU enabled Docker container, run:
```
cat /etc/docker/daemon.json | jq 'del(."default-runtime") + {"default-runtime": "nvidia"}' | sudo tee /etc/docker/daemon.json
sudo usermod -a -G docker $(id -un)
```

### Install DRfC

You can now run `bin/init.sh -a gpu -c local` to setup DRfC.

## Known Issues

* `init.sh` is not able to detect the GPU given differences in the Nvidia drivers, and the WSL2 Linux Kernel. You need to manually set the GPU image in `system.env`.
* Docker does not start automatically when you launch Ubuntu. Start it with `sudo service docker start`.