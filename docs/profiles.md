# Profiles

Profiles contain the main configuration files used in a DRfC training job.   This features allows you save your configuration files and load them on another computer, or to switch back and forth between different types of training.

## How to use profiles features:

**To Save a New Profile**

Simple example usage:  ```dr-save-profile -n <insert_your_profile_name>```

This will upload files to S3, using your DR_UPLOAD_S3_BUCKET, under a new folder called drfc_profiles
    
* Files to be uploaded are:
  * run.env
  * system.env
  * custom_files/reward_function.py
  * custom_files/hyperparameters.json
  * custom_files/model_metadata.json
  * worker-*.env (if multiple workers)
  * (Optional) upload of checkpoint files


* Optional flags (-n name is required)

  **-f**        Force upload; no confirmation question<br/>
  **-n**        Name of profile<br/>
  **-w**        Wipes the target profile location before saving.<br/>
  **-d**        Dry-Run mode; does not perform any write or delete operations on target<br/>
  **-c**        Include latest checkpoint<br/>
  **-b**        Include best checkpoint<br/>

<br/>
<br/>

**To Load an Existing Profile**

Simple example usage:  ```dr-load-profile -n <insert_your_profile_name>```


* Optional flags (-n <name> is required)
    
  **-f**        Force upload; no confirmation question<br/>
  **-l**        List available profiles<br/>
  **-n**        Name of profile<br/>
  **-d**        Dry-Run mode. Does not perform any write or delete operations on target.<br/>
    
