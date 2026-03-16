# TSNPDCL Smart Grid Analytics Platform ⚡

## Overview

The Northern Power Distribution Company of Telangana (TSNPDCL) Smart Grid Analytics Platform is an end-to-end data engineering pipeline designed to ingest, process, and analyze massive volumes of monthly grid utility data. This repository contains the Infrastructure as Code (Terraform), Data Ingestion logic (PySpark/Databricks), CI/CD pipelines, and SQL Queries for the Business Intelligence Dashboards.

## Architecture & Technology Stack

*   **Cloud Provider**: AWS (S3 object storage for data lake)
*   **Data Processing**: Databricks (PySpark)
*   **Format**: Delta Lake / Parquet (Medallion Architecture)
*   **Dashboarding Server**: Amazon Athena
*   **IaC**: Terraform
*   **CI/CD**: GitHub / GitLab Actions

### Medallion Architecture Implementation

1.  **Bronze (Raw)**: Utilizes Databricks AutoLoader (`cloudFiles`) to ingest raw CSVs from AWS S3 incrementally. AutoLoader handles schema drift via `schemaEvolutionMode="addNewColumns"`. We enforce strict schema and pipe bad data to a quarantine/dead-letter queue queue. Data is stored directly back in AWS S3 in Delta format.
2.  **Silver (Cleaned)**: Standardizes names (e.g., uppercase geographical areas), quarantines rows that violate data contracts (null `Load` or `Units`), casts data types, incorporates Time-Intelligence (Seasons), and aggressively deduplicates records. Partitioned by Year and saved directly to AWS S3.
3.  **Gold (Curated Datamarts)**: Pre-aggregated tables specifically engineered for Business Intelligence, calculating District Efficiency, MoM Growth Rates (via Window functions), and Recovery Indexes. Served via AWS S3 to Amazon Athena for cost-efficient dashboarding.

## Repository Structure

```text
tsnpdcl_analytics/
├── .github/workflows/   # CI/CD deployment scripts
├── terraform/           # Infrastructure as Code (AWS S3)
├── etl/                 # Databricks PySpark logic mapping the Medallion flow (bronze.py, silver.py, gold.py)
├── dashboard/           # SQL logic supporting the final BI Dashboards
└── tests/               # Quality and validity tests
```

## Setup & Deployment (AWS + Databricks)

1.  **AWS S3 Setup**: Create an AWS S3 bucket to act as the Data Lake (`tsnpdcl-datalake-poc`).
2.  **IAM Integration**: Apply an AWS Instance Profile to the Databricks cluster allowing it read/write access to the specific S3 bucket.
3.  **Run Pipeline**: Execute the notebooks in `etl/` (Bronze -> Silver -> Gold) sequentially on a Databricks Single-Node interactive cluster. Ensure the `S3_BUCKET` variable in the scripts points to your bucket.
4.  **Amazon Athena**: Run an AWS Glue crawler over the `s3://.../gold/` paths to populate the AWS Glue Data Catalog. Open Amazon Athena and query the Gold data for pennies.

## DataOps & Quality
- **Idempotency**: Leveraging Delta Lake and Spark Structured Streaming checkpoints ensuring data logic can run concurrently without creating duplicate records.
- **Resiliency**: Utilizing `try/except` blocks and PySpark schema enforcement, with bad records intelligently funneled to quarantine S3 buckets without crashing the entire pipeline.
- **Fail-Safes**: Built-in volume checks verifying chronological data freshness.
