#!/usr/bin/env python3

import sys
import getopt
import os
import traceback
import pickle
import urllib.request

import boto3
from botocore.exceptions import ClientError

try:
    import pandas as pd
    from deepracer import boto3_enhancer
except ImportError:
    print("You need to install pandas and deepracer-utils to use this utility.")
    sys.exit(1)

dr = None


def main():

    # Parse Arguments
    try:
        opts, _ = getopt.getopt(
            sys.argv[1:],
            "lvsghm:b:",
            ["logs", "verbose", "summary", "graphics", "help", "model=", "board="],
        )
    except getopt.GetoptError as err:
        # print help information and exit:
        print(err)  # will print something like "option -x not recognized"
        usage()
        sys.exit(2)

    logs_path = "{}/data/logs/leaderboards".format(os.environ.get("DR_DIR", None))

    download_logs = False
    download_videos = False
    verbose = False
    create_summary = False
    model_name = None
    leaderboard_guid = None
    leaderboard_arn = None

    for opt, arg in opts:
        if opt in ("-l", "--logs"):
            download_logs = True
        elif opt in ("-g", "--graphics"):
            download_videos = True
        elif opt in ("-v", "--verbose"):
            verbose = True
        elif opt in ("-s", "--summary"):
            create_summary = True
        elif opt in ("-m", "--model"):
            model_name = arg.strip()
        elif opt in ("-b", "--board"):
            leaderboard_guid = arg.strip()
        elif opt in ("-h", "--help"):
            usage()
            sys.exit()

    # Prepare Boto3
    profile_name=os.environ.get("DR_UPLOAD_S3_PROFILE", None)

    if (profile_name is None or len(profile_name) == 0):
        session = boto3.session.Session(
            region_name="us-east-1"
        )
    else:
        session = boto3.session.Session(
            region_name="us-east-1",
            profile_name=profile_name
        )

    global dr
    dr = boto3_enhancer.deepracer_client(session=session)

    # Find the ARN for my model
    my_model = find_model(model_name)

    if my_model is not None:
        my_model_arn = my_model["ModelArn"].values[0]
        if verbose:
            print("Found ModelARN for model {}: {}".format(model_name, my_model_arn))
    else:
        print("Did not find model with name {}".format(model_name))
        sys.exit(1)

    if leaderboard_guid.startswith('arn'):
        leaderboard_arn = leaderboard_guid

    # Find the leaderboard
    if not leaderboard_arn:
        leaderboard_arn = find_leaderboard(leaderboard_guid)

    if leaderboard_arn is not None:
        if verbose:
            print("Found Leaderboard with ARN {}".format(leaderboard_arn))
    else:
        print("Did not find Leaderboard with ARN {}".format(leaderboard_arn))
        sys.exit(1)

    # Load summary from file if we are interested in it!
    if create_summary:

        pkl_f = "{}/{}/summary.pkl".format(logs_path, leaderboard_guid)
        if os.path.isfile(pkl_f):
            infile = open(pkl_f, "rb")
            my_submissions = pickle.load(infile)
            infile.close()
        else:
            my_submissions = {}
            my_submissions["LeaderboardSubmissions"] = []

            dir_path = os.path.dirname(pkl_f)
            os.makedirs(dir_path, exist_ok=True)

    # Collect data about latest submission
    submission_response = dr.get_latest_user_submission(LeaderboardArn=leaderboard_arn)
    latest_submission = submission_response["LeaderboardSubmission"]
    if latest_submission:
        jobid = latest_submission["ActivityArn"].split("/", 1)[1]
        print(
            "Job {} has status {}".format(
                jobid, latest_submission["LeaderboardSubmissionStatusType"]
            )
        )

        if latest_submission["LeaderboardSubmissionStatusType"] == "SUCCESS":
            if download_logs:
                try:
                    f_url = dr.get_asset_url(
                        Arn=latest_submission["ActivityArn"],
                        AssetType="LOGS",
                    )["Url"]
                    download_file(
                        "{}/{}/robomaker-{}-{}.tar.gz".format(
                            logs_path,
                            leaderboard_guid,
                            latest_submission["SubmissionTime"],
                            jobid,
                        ),
                        f_url,
                    )
                except ClientError:
                    print(("WARNING: Logfile for job {} not available.").format(jobid))
                    traceback.print_exc()

            if download_videos:
                download_file(
                    "{}/{}/video-{}-{}.mp4".format(
                        logs_path,
                        leaderboard_guid,
                        latest_submission["SubmissionTime"],
                        jobid,
                    ),
                    latest_submission["SubmissionVideoS3path"],
                )

            # Submit again
            _ = dr.create_leaderboard_submission(
                ModelArn=my_model_arn, LeaderboardArn=leaderboard_arn
            )
            print("Submitted {} to {}.".format(model_name, leaderboard_arn))

        elif latest_submission["LeaderboardSubmissionStatusType"] == "ERROR" or latest_submission["LeaderboardSubmissionStatusType"] == "FAILED":
            print("Error in previous submission")
            if download_logs:
                try:
                    f_url = dr.get_asset_url(
                        Arn=latest_submission["ActivityArn"],
                        AssetType="LOGS",
                    )["Url"]
                    download_file(
                        "{}/{}/robomaker-{}-{}.tar.gz".format(
                            logs_path,
                            leaderboard_guid,
                            latest_submission["SubmissionTime"],
                            jobid,
                        ),
                        f_url,
                    )
                except ClientError:
                    print(("WARNING: Logfile for job {} not available.").format(jobid))
                    traceback.print_exc()

            # Submit again
            _ = dr.create_leaderboard_submission(
                ModelArn=my_model_arn, LeaderboardArn=leaderboard_arn
            )
            print("Submitted {} to {}.".format(model_name, leaderboard_arn))

    # Maintain our summary
    if create_summary:
        for idx, i in enumerate(my_submissions["LeaderboardSubmissions"]):
            if "SubmissionTime" in i:
                if i["SubmissionTime"] == latest_submission["SubmissionTime"]:
                    del my_submissions["LeaderboardSubmissions"][idx]
            else:
                del my_submissions["LeaderboardSubmissions"][idx]
        my_submissions["LeaderboardSubmissions"].append(latest_submission)

        # Save summary
        outfile = open(pkl_f, "wb")
        pickle.dump(my_submissions, outfile)
        outfile.close()

        # Display summary
        if verbose:
            display_submissions(my_submissions)


def download_file(f_name, url):

    dir_path = os.path.dirname(f_name)
    os.makedirs(dir_path, exist_ok=True)
    if not os.path.isfile(f_name):
        print("Downloading {}".format(os.path.basename(f_name)))
        urllib.request.urlretrieve(url, f_name)


def find_model(model_name):

    m_response = dr.list_models(ModelType="REINFORCEMENT_LEARNING", MaxResults=25)
    model_dict = m_response["Models"]
    models = pd.DataFrame.from_dict(model_dict)
    my_model = models[models["ModelName"] == model_name]

    if my_model.size > 0:
        return my_model

    while "NextToken" in m_response:
        m_response = dr.list_models(
            ModelType="REINFORCEMENT_LEARNING",
            MaxResults=50,
            NextToken=m_response["NextToken"],
        )
        model_dict = m_response["Models"]

        models = pd.DataFrame.from_dict(model_dict)
        my_model = models[models["ModelName"] == model_name]
        if my_model.size > 0:
            return my_model

    return None


def find_leaderboard(leaderboard_guid):
    leaderboard_arn = "arn:aws:deepracer:::leaderboard/{}".format(leaderboard_guid)

    l_response = dr.list_leaderboards(MaxResults=25)
    lboards_dict = l_response["Leaderboards"]
    leaderboards = pd.DataFrame.from_dict(l_response["Leaderboards"])
    if leaderboards[leaderboards["Arn"] == leaderboard_arn].size > 0:
        return leaderboard_arn

    while "NextToken" in l_response:
        l_response = dr.list_leaderboards(
            MaxResults=50, NextToken=l_response["NextToken"]
        )
        lboards_dict = l_response["Leaderboards"]

        leaderboards = pd.DataFrame.from_dict(lboards_dict)
        if leaderboards[leaderboards["Arn"] == leaderboard_arn].size > 0:
            return leaderboard_arn

    return None


def display_submissions(submissions_dict):
    # Display status
    my_columns = [
        "SubmissionTime",
        "TotalLapTime",
        "BestLapTime",
        "ResetCount",
        "CollisionCount",
        "OffTrackCount",
        "Model",
        "JobId",
        "Status",
    ]
    my_submissions_df = pd.DataFrame.from_dict(
        submissions_dict["LeaderboardSubmissions"]
    )
    my_submissions_df["SubmissionTime"] = (
        my_submissions_df["SubmissionTime"]
        .values.astype(dtype="datetime64[ms]")
        .astype(dtype="datetime64[s]")
    )
    my_submissions_df["TotalLapTime"] = my_submissions_df["TotalLapTime"].values.astype(
        dtype="datetime64[ms]"
    )
    my_submissions_df["TotalLapTime"] = (
        my_submissions_df["TotalLapTime"].dt.strftime("%M:%S.%f").str[:-4]
    )
    my_submissions_df["BestLapTime"] = my_submissions_df["BestLapTime"].values.astype(
        dtype="datetime64[ms]"
    )
    my_submissions_df["BestLapTime"] = (
        my_submissions_df["BestLapTime"].dt.strftime("%M:%S.%f").str[:-4]
    )
    my_submissions_df["JobId"] = my_submissions_df["ActivityArn"].str.split("/").str[1]
    my_submissions_df["Status"] = my_submissions_df["LeaderboardSubmissionStatusType"]
    my_submissions_df[[None, None, "Model"]] = my_submissions_df.ModelArn.str.split(
        "/", expand=True,
    )

    # Display
    print("")
    print(my_submissions_df[my_columns])


def usage():
    print(
        "Usage: submit-monitor.py [-v] [-s] [-l] [-g] -m <model-name> -b <leaderboard guid>"
    )
    print("        -v                Verbose output.")
    print("        -s                Store a summary of all submissions.")
    print("        -l                Download robomaker logfiles.")
    print("        -g                Download video recordings.")
    print("        -m                Display name of the model to submit.")
    print("        -b                GUID or ARN of the leaderboard to submit to.")
    sys.exit(1)


if __name__ == "__main__":
    main()
