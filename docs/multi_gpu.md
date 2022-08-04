# Training on a Computer with more than one GPU

In some cases you might end up with having a computer with more than one GPU. This may be common on a workstation
which may have one GPU for general graphics (e.g. GTX 10-series, RTX 20-series), as well as a data center GPU 
like a Tesla K40, K80 or M40.

In this setting it can get a bit chaotic as DeepRacer will 'greedily' put any workload on any GPU - which will 
lead to Out-of-Memory somewhere down the road.

## Checking available GPUs

You can use Tensorflow to give you an overview of available devices running `utils/cuda-check.sh`.

It will say something like:
```
2020-07-04 12:25:55.179580: I tensorflow/core/platform/cpu_feature_guard.cc:141] Your CPU supports instructions that this TensorFlow binary was not compiled to use: AVX2 FMA
2020-07-04 12:25:55.547206: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1411] Found device 0 with properties: 
name: GeForce GTX 1650 major: 7 minor: 5 memoryClockRate(GHz): 1.68
pciBusID: 0000:04:00.0
totalMemory: 3.82GiB freeMemory: 3.30GiB
2020-07-04 12:25:55.732066: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1411] Found device 1 with properties: 
name: Tesla M40 24GB major: 5 minor: 2 memoryClockRate(GHz): 1.112
pciBusID: 0000:81:00.0
totalMemory: 22.41GiB freeMemory: 22.30GiB
2020-07-04 12:25:55.732141: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1490] Adding visible gpu devices: 0, 1
2020-07-04 12:25:56.745647: I tensorflow/core/common_runtime/gpu/gpu_device.cc:971] Device interconnect StreamExecutor with strength 1 edge matrix:
2020-07-04 12:25:56.745719: I tensorflow/core/common_runtime/gpu/gpu_device.cc:977]      0 1 
2020-07-04 12:25:56.745732: I tensorflow/core/common_runtime/gpu/gpu_device.cc:990] 0:   N N 
2020-07-04 12:25:56.745743: I tensorflow/core/common_runtime/gpu/gpu_device.cc:990] 1:   N N 
2020-07-04 12:25:56.745973: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1103] Created TensorFlow device (/job:localhost/replica:0/task:0/device:GPU:0 with 195 MB memory) -> physical GPU (device: 0, name: GeForce GTX 1650, pci bus id: 0000:04:00.0, compute capability: 7.5)
2020-07-04 12:25:56.750352: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1103] Created TensorFlow device (/job:localhost/replica:0/task:0/device:GPU:1 with 1147 MB memory) -> physical GPU (device: 1, name: Tesla M40 24GB, pci bus id: 0000:81:00.0, compute capability: 5.2)
2020-07-04 12:25:56.774305: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1490] Adding visible gpu devices: 0, 1
2020-07-04 12:25:56.774408: I tensorflow/core/common_runtime/gpu/gpu_device.cc:971] Device interconnect StreamExecutor with strength 1 edge matrix:
2020-07-04 12:25:56.774425: I tensorflow/core/common_runtime/gpu/gpu_device.cc:977]      0 1 
2020-07-04 12:25:56.774436: I tensorflow/core/common_runtime/gpu/gpu_device.cc:990] 0:   N N 
2020-07-04 12:25:56.774446: I tensorflow/core/common_runtime/gpu/gpu_device.cc:990] 1:   N N 
2020-07-04 12:25:56.774551: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1103] Created TensorFlow device (/device:GPU:0 with 195 MB memory) -> physical GPU (device: 0, name: GeForce GTX 1650, pci bus id: 0000:04:00.0, compute capability: 7.5)
2020-07-04 12:25:56.774829: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1103] Created TensorFlow device (/device:GPU:1 with 1147 MB memory) -> physical GPU (device: 1, name: Tesla M40 24GB, pci bus id: 0000:81:00.0, compute capability: 5.2)
['/device:GPU:0', '/device:GPU:1']
```
In this case the CUDA device #0 is the GTX 1650 and the CUDA device #1 is the Tesla M40.

### Selecting Device

To control the CUDA assignment for Sagemaker abd Robomaker then the following to variables in `system.env`:

```
DR_ROBOMAKER_CUDA_DEVICES=0
DR_SAGEMAKER_CUDA_DEVICES=1
``` 

The number is the CUDA number of the GPU you want the containers to use.

