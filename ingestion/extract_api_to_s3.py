import json
import requests
import boto3
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

import os

S3_BUCKET = os.environ.get("S3_BUCKET", "tsnpdcl-analytics-datalake-poc-dev")
S3_PREFIX = os.environ.get("S3_PREFIX", "data/source/")
API_URL = os.environ.get("API_URL", "https://data.telangana.gov.in/api/1/metastore/schemas/dataset/items/ae305fca-068b-4e61-b7f8-d9bf651e1b69?show-reference-ids=true")

s3_client = boto3.client("s3")


def get_download_links():
    response = requests.get(API_URL).json()
    resources = response.get("distribution", [])
    links = [r["data"]["downloadURL"] for r in resources if "csv" in r["data"]["downloadURL"].lower()]
    return links


def check_s3_file_exists(bucket, key):
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response["ContentLength"] > 0
    except:
        return False


def download_and_upload_to_s3(link):
    filename = link.split("/")[-1]
    s3_key = f"{S3_PREFIX}{filename}"

    if check_s3_file_exists(S3_BUCKET, s3_key):
        return "skipped", filename

    try:
        with requests.get(link, stream=True, timeout=60) as r:
            r.raise_for_status()

            s3_client.upload_fileobj(
                Fileobj=r.raw,
                Bucket=S3_BUCKET,
                Key=s3_key
            )

        return "downloaded", filename

    except Exception as e:
        return "failed", filename


def lambda_handler(event, context):

    download_links = get_download_links()

    max_workers = 10
    files_downloaded = 0
    skipped_files = 0
    failed_files = 0

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        tasks = [executor.submit(download_and_upload_to_s3, link) for link in download_links]

        for future in as_completed(tasks):

            status, filename = future.result()

            if status == "downloaded":
                files_downloaded += 1

            elif status == "skipped":
                skipped_files += 1

            else:
                failed_files += 1

    # Trigger Databricks if new files arrived
    if files_downloaded > 0:

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        trigger_file_key = f"trigger/run_{timestamp}.txt"

        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=trigger_file_key,
            Body=f"Triggering pipeline. Processed {files_downloaded} new files."
        )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "files_downloaded": files_downloaded,
            "files_skipped": skipped_files,
            "files_failed": failed_files
        })
    }