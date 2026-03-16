import os
import requests
import boto3
from concurrent.futures import ThreadPoolExecutor, as_completed
from io import BytesIO

# --- Configuration ---
S3_BUCKET = "zemoso-s3-poc"
S3_PREFIX = "data/source/"
API_URL = "https://data.telangana.gov.in/api/1/metastore/schemas/dataset/items/ae305fca-068b-4e61-b7f8-d9bf651e1b69?show-reference-ids=true"

# Initialize Boto3 client
# Note: If running in Databricks with an Instance Profile or inside AWS Lambda, 
# you don't need to pass credentials here. It will automatically use the IAM role.
s3_client = boto3.client('s3')

def get_download_links():
    print("Fetching dataset metadata...")
    response = requests.get(API_URL).json()
    resources = response.get('distribution', [])
    links = [r["data"]["downloadURL"] for r in resources if "csv" in r["data"]["downloadURL"].lower()]
    return links

def check_s3_file_exists(bucket, key):
    """Check if a file already exists in S3 with a size > 0."""
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response['ContentLength'] > 0
    except Exception:
        return False

def download_and_upload_to_s3(link):
    """Streams a single file from the API directly to S3."""
    filename = link.split("/")[-1]
    s3_key = f"{S3_PREFIX}{filename}"

    # 1. Check if it already exists
    if check_s3_file_exists(S3_BUCKET, s3_key):
        return False, f"Skipped {filename} (already exists in S3)"

    # 2. Stream download and upload
    try:
        # stream=True prevents loading the entire file into memory at once
        with requests.get(link, stream=True, timeout=60) as r:
            r.raise_for_status()
            
            # Using upload_fileobj to stream directly to S3
            s3_client.upload_fileobj(
                Fileobj=r.raw,
                Bucket=S3_BUCKET,
                Key=s3_key
            )
            return True, f"Successfully uploaded {filename} to s3://{S3_BUCKET}/{s3_key}"
            
    except Exception as e:
        return False, f"Failed to transfer {filename}: {e}"

def main():
    download_links = get_download_links()
    print(f"Found {len(download_links)} CSV files to process.")

    max_workers = 20
    files_downloaded = 0

    print(f"Starting concurrent transfers with {max_workers} threads...")

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all tasks
        tasks = [executor.submit(download_and_upload_to_s3, link) for link in download_links]
        
        # Process results as they finish
        for future in as_completed(tasks):
            was_downloaded, message = future.result()
            print(message)
            if was_downloaded:
                files_downloaded += 1

    print(f"Total new files transferred to S3: {files_downloaded}")

if __name__ == "__main__":
    main()
