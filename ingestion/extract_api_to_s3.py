import json
import urllib.request
import urllib.error
import time
import ssl
import boto3
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

import os

S3_BUCKET = os.environ.get("S3_BUCKET", "tsnpdcl-analytics-datalake-poc-dev")
S3_PREFIX = os.environ.get("S3_PREFIX", "data/source/")
API_URL = os.environ.get("API_URL", "https://data.telangana.gov.in/api/1/metastore/schemas/dataset/items/ae305fca-068b-4e61-b7f8-d9bf651e1b69?show-reference-ids=true")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")

s3_client = boto3.client("s3")
sns_client = boto3.client("sns")


def get_download_links():
    req = urllib.request.Request(API_URL)
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
    resources = data.get("distribution", [])
    links = [r["data"]["downloadURL"] for r in resources if "csv" in r["data"]["downloadURL"].lower()]
    return links


def check_s3_file_exists(bucket, key):
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response["ContentLength"] > 0
    except:
        return False


def download_and_upload_to_s3(link, max_retries=3):
    filename = link.split("/")[-1]
    s3_key = f"{S3_PREFIX}{filename}"

    if check_s3_file_exists(S3_BUCKET, s3_key):
        return "skipped", filename

    # Create unverified context to bypass strict SSL cipher checks that fail under load
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(link)
            with urllib.request.urlopen(req, timeout=60, context=ctx) as response:
                s3_client.upload_fileobj(
                    Fileobj=response,
                    Bucket=S3_BUCKET,
                    Key=s3_key
                )

            return "downloaded", filename

        except Exception as e:
            if attempt == max_retries - 1:
                return "failed", filename
            time.sleep(2 ** attempt)  # Exponential backoff


def lambda_handler(event, context):

    try:
        download_links = get_download_links()
    except Exception as e:
        if SNS_TOPIC_ARN:
            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject="CRITICAL: TSNPDCL API Ingestion Failed",
                Message=f"The Telangana API failed to respond or returned invalid data.\nError: {str(e)}"
            )
        raise e

    max_workers = 3
    files_downloaded = 0
    skipped_files = 0
    failed_files = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        tasks = [executor.submit(download_and_upload_to_s3, link) for link in download_links]

        for future in as_completed(tasks):

            status, filename = future.result()

            if status == "downloaded":
                files_downloaded += 1

            elif status == "skipped":
                skipped_files += 1

            else:
                failed_files.append(filename)

    if failed_files and SNS_TOPIC_ARN:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="WARNING: Partial TSNPDCL Ingestion Failure",
            Message=f"{len(failed_files)} file(s) failed to transfer to S3.\nFailed files: {', '.join(failed_files)}"
        )

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
            "files_failed": len(failed_files)
        })
    }