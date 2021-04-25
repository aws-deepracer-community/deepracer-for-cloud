# Upload Model to AWS Console

Starting end July 2020 the AWS DeepRacer Console was re-designed which is now changing the way
that models need to be uploaded to enable them to be evaluated or submitted to the AWS hosted Summit or Virtual League events.

## Create Upload Bucket

The recommendation is to create a unique bucket in `us-east-1` which is used as 'transit' between your training bucket, local or in an AWS region close to your EC2 instances.

The bucket needs to be defined so that 'Objects can be public'; AWS will create a specific IAM policy to access the data in your bucket as part of the import.

## Configure Upload Bucket

In `system.env` set `DR_UPLOAD_S3_BUCKET` to the name of your created bucket.

In `run.env` set the `DR_UPLOAD_S3_PREFIX` to any prefix of your choice.

## Upload Model

After configuring the system you can run `dr-upload-model`; it will copy out the required parts of `s3://DR_LOCAL_S3_BUCKET/DR_LOCAL_S3_PREFIX` into `s3://DR_UPLOAD_S3_BUCKET/DR_UPLOAD_S3_PREFIX`.

Once uploaded you can use the [Import model](https://console.aws.amazon.com/deepracer/home?region=us-east-1#models/importModel) feature of the AWS DeepRacer console to load the model into the model store.

## Things to know

### Upload switches
There are several useful switches to the upload command:
  * f - this will force upload, no confirmation question if you want to proceed with upload
  * w - wipes the target AWS DeepRacer model structure before upload in the designated bucket/prefix
  * d - dry-Run mode, does not perform any write or delete operatios on target
  * b - uploads best checkpoint instead of default which is last checkpoint
  * p prefix - uploads model into specified S3 prefix
  * i - imports model using the prefix as the model name
  * I name - import model with a specific model name"

### Import
If you want to use the import switches (`-i` or `-I`) there are a few pre-requisites.

* Python packages to be installed with `pip install`:
  * pandas
  * deepracer-utils
* Install boto3 service `deepracer` with `python -m deepracer install-cli --force`.
* Create an IAM Role which the Deepracer service can use to access S3. Declare the ARN in `DR_UPLOAD_S3_ROLE` in `system.env`.

### Managing your models
You should decide how you're going to manage your models. Upload to AWS does not preserve all the files created locally so if you delete your local files you will find it hard to go back to a previous model and resume training.

### Create file formatted for physical car, and upload to S3
You can also create the file in the format necessary to run on the physical car directly from DRfC, without going through the AWS console.
This is executed by running 'dr-upload-car-zip';  it will copy files out of the running sagemaker container, format them into the proper .tar.gz file, and upload that file to `s3://DR_LOCAL_S3_BUCKET/DR_LOCAL_S3_PREFIX`.    One of the limitations of this approach is that it only uses the latest checkpoint, and does not have the option to use the "best" checkpoint, or an earlier checkpoint.   Another limitation is that the sagemaker container must be running at the time this command is executed.
