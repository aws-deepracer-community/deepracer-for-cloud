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