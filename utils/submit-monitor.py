#!/usr/bin/env python3

import boto3
import sys
import getopt
import os
import time
import json
import io
import yaml
import pickle
import urllib.request
from botocore.loaders import UnknownServiceError

try:
    import pandas as pd
    import deepracer
except ImportError:
    print("You need to install pandas and deepracer-utils to use this utility.")
    exit(1)


def usage():
    print("usage")


def main():

    # Parse Arguments
    try:
        opts, _ = getopt.getopt(sys.argv[1:], "lvshm:b:", [
                                   "logs", "videos", "summary", "help", "model=", "board="])
    except getopt.GetoptError as err:
        # print help information and exit:
        print(err)  # will print something like "option -a not recognized"
        usage()
        sys.exit(2)

    logs_path = '{}/data/logs/leaderboards'.format(os.environ.get('DR_DIR', None))

    download_logs = False
    download_videos = False
    create_summary = False
    model_name = None
    leaderboard_arn = None

    for o, a in opts:
        if o in ("-l", "--logs"):
            download_logs = True
        elif o in ("-v", "--videos"):
            download_videos = True
        elif o in ("-s", "--summary"):
            create_summary = True
        elif o in ("-m", "--model"):
            model_name = a
        elif o in ("-b", "--board"):
            leaderboard_arn = a
        elif o in ("-h", "--help"):
            usage()
            sys.exit()

    # Prepare Boto3
    session = boto3.session.Session(
        region_name='us-east-1', profile_name=os.environ.get('DR_UPLOAD_S3_PROFILE', None))

    try:
        dr = session.client('deepracer')
    except UnknownServiceError:
        print("Boto3 service 'deepracer' is not installed. Cannot import model.")
        print("Install with 'pip install deepracer-utils' and 'python -m deepracer install-cli --force'")
        exit(1)

    # Find the ARN for my model
    m_response = dr.list_models(
        ModelType='REINFORCEMENT_LEARNING', MaxResults=50)
    model_dict = m_response['Models']
    while "NextToken" in m_response:
        m_response = dr.list_models(
            ModelType='REINFORCEMENT_LEARNING', MaxResults=50, NextToken=m_response["NextToken"])
        model_dict.extend(m_response['Models'])

    models = pd.DataFrame.from_dict(model_dict)
    my_model =  models[models['ModelName'] == model_name]
    if my_model.size > 0:
        my_model_arn = models[models['ModelName'] == model_name]['ModelArn'].values[0]
        print("Found model ARN for model {}: {}".format(model_name, my_model_arn))
    else:
        print("Did not find model with name {}".format(model_name))
        exit(1)

    # Find the leaderboard
    l_response = dr.list_leaderboards(MaxResults=50)
    lboards_dict = l_response['Leaderboards']
    while "NextToken" in l_response:
        l_response = dr.list_leaderboards(MaxResults=50, NextToken=l_response["NextToken"])
        lboards_dict.extend(l_response['Leaderboards'])

    leaderboards = pd.DataFrame.from_dict(lboards_dict)
    if leaderboards[leaderboards['Arn'] == leaderboard_arn].size > 0:
        print("Found Leaderboard with ARN {}".format(leaderboard_arn))
        leaderboard_guid = leaderboard_arn.split('/', 1)[1]
    else:
        print("Did not find Leaderboard with ARN {}".format(leaderboard_arn))
        exit(1)

    # Load summary from file if we are interested in it!
    if create_summary:

        pkl_f = '{}/{}/summary.pkl'.format(logs_path, leaderboard_guid)
        if os.path.isfile(pkl_f):
            infile = open(pkl_f,'rb')
            my_submissions = pickle.load(infile)
            infile.close()
        else:
            my_submissions = {}
            my_submissions['LeaderboardSubmissions'] = []


    # Collect data about latest submission
    submission_response = dr.get_latest_user_submission(LeaderboardArn=leaderboard_arn)
    latest_submission = submission_response['LeaderboardSubmission']
    if latest_submission:
        jobid = latest_submission['ActivityArn'].split('/',1)[1]
        if latest_submission['LeaderboardSubmissionStatusType'] == 'SUCCESS':   
            if download_logs:
                download_file('{}/{}/robomaker-{}.log'.format(logs_path, leaderboard_guid, latest_submission['SubmissionTime']), 
                    dr.get_asset_url(Arn=latest_submission['ActivityArn'], AssetType='ROBOMAKER_CLOUDWATCH_LOG')['Url'])
            if download_videos:
                download_file('{}/{}/video-{}.mp4'.format(logs_path, leaderboard_guid, latest_submission['SubmissionTime']), 
                    latest_submission['SubmissionVideoS3path'])

            # Submit again
            _ = dr.create_leaderboard_submission(ModelArn=my_model_arn, LeaderboardArn=leaderboard_arn)


    # Maintain our summary
    if create_summary:
        for idx, i in enumerate(my_submissions['LeaderboardSubmissions']):
            if i['SubmissionTime'] == latest_submission['SubmissionTime']:
                del my_submissions['LeaderboardSubmissions'][idx]
        my_submissions['LeaderboardSubmissions'].append(latest_submission)

        my_submissions_df = pd.DataFrame.from_dict(my_submissions['LeaderboardSubmissions'])       
        print(my_submissions_df)

        # Save summary
        outfile = open(pkl_f,'wb')
        pickle.dump(my_submissions, outfile)
        outfile.close()

def download_file(f_name, url):

    dirPath = os.path.dirname(f_name)
    os.makedirs(dirPath, exist_ok=True)
 
    urllib.request.urlretrieve(url, f_name)


if __name__ == "__main__":
    main()
