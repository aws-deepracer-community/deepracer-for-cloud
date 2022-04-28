# Installing on Windows

## Prerequisites

The basic installation steps to get a NVIDIA GPU / CUDA enabled Ubuntu subsystem on Windows can be found in the [Cuda on WSL User Guide](https://docs.nvidia.com/cuda/wsl-user-guide/index.html).  Ensure your windows has an updated [nvidia cuda enabled driver](https://developer.nvidia.com/cuda/wsl/download) that will work with WSL.

The further instructions assume that you have a basic working WSL using the default Ubuntu distribution.


## Additional steps

The typical `bin/prepare.sh` script will not work for a Ubuntu WSL installation, hence alternate steps will be required.

### Adding required packages

Install additional packages with the following command:

```
sudo apt-get install jq awscli python3-boto3 docker-compose
```

### Install and configure docker and nvidia-docker
```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update && sudo apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io

distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

cat /etc/docker/daemon.json | jq 'del(."default-runtime") + {"default-runtime": "nvidia"}' | sudo tee /etc/docker/daemon.json
sudo usermod -a -G docker $(id -un)
```


### Install DRfC

You can now run `bin/init.sh -a gpu -c local` to setup DRfC, and follow the typical DRfC startup instructions

## Known Issues

* `init.sh` is not able to detect the GPU given differences in the Nvidia drivers, and the WSL2 Linux Kernel. You need to manually set the GPU image in `system.env`.
* Docker does not start automatically when you launch Ubuntu. Start it manually with `sudo service docker start` 

     You can also configure the service to start automatically using the Windows Task Scheduler
     
     *1)* Create a new file at /etc/init-wsl  (sudo vi /etc/init-wsl) with the following contents.
     
     ```
     #!/bin/sh
     service start docker
     ```
 
     *2)* Make the script executable `sudo chmod +x /etc/init-wsl`
       
     *3)* Open Task Scheduler in Windows 10
       
     - On the left, click **Task Scheduler Library** option, and then on the right, click **Create Task**
          
     - In **General** Tab, Enter Name **WSL Startup**, and select **Run whether user is logged on or not** and **Run with highest privileges** options.
         
     - In **Trigger** tab, click New ... > Begin the task: **At startup** > OK
        
     - In **Actions** tab, click New ... > Action: **Start a program**
                            
       program/script:  **wsl**
                   
       add arguments:  **-u root /etc/init-wsl**
                   
     - Click OK to exit
          
     *4)* You can run the task manually to confirm, or after Windows reboot docker should now automatically start.

* Video streams may not load using the localhost address.  To access the html video streams from your windows browser, you may need to use the IP address of the WSL VM.  From a WSL terminal, determine your IP address by the command 'ip addr' and look for **eth0** then **inet** (e.g. ip = 172.29.38.21).  Then from your windows browser (edge, chrome, etc) navigate to **ip:8080** (e.g. 172.29.38.21:8080)
     
