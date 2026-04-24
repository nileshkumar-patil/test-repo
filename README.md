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

This project strictly follows the industry standard split architecture: **Terraform** for AWS Infrastructure, and **Databricks Asset Bundles (DABs)** for Data Workloads.

1.  **AWS Infrastructure (Terraform)**: 
    * Navigate to `/terraform` and run `./deploy.sh`. 
    * This securely provisions the S3 Data Lake, Unity Catalog privileges, and the scheduled AWS Lambda Ingestion function.
2.  **Data Workloads (Databricks CLI)**: 
    * Authenticate your Databricks Workspace (`databricks configure`).
    * Run `databricks bundle deploy` at the project root to automatically package and deploy the Medallion ETL pipeline (Bronze -> Silver -> Gold).
3.  **Dashboards (UI + DABs Sync)**: 
    * Build the dashboard visually in the Databricks Lakeview UI.
    * Run `databricks bundle generate dashboard --existing-id <id>` to source-control the dashboard into the codebase.

## DataOps & Quality
- **Idempotency**: Leveraging Delta Lake and Spark Structured Streaming checkpoints ensuring data logic can run concurrently without creating duplicate records.
- **Resiliency**: Utilizing `try/except` blocks and PySpark schema enforcement, with bad records intelligently funneled to quarantine S3 buckets without crashing the entire pipeline.
- **Fail-Safes**: Built-in volume checks verifying chronological data freshness.
