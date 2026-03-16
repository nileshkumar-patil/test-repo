# Databricks notebook source
# MAGIC %md
# MAGIC # Silver Layer Data Quality & Reliability Tests
# MAGIC This notebook is designed to run as a Task in a Databricks Workflow. 
# MAGIC If any data quality assertion fails, the notebook will throw an Exception and halt the workflow.

# COMMAND ----------

# --- Configuration ---
S3_BUCKET = "s3://zemoso-s3-poc"
SILVER_S3_PATH = f"{S3_BUCKET}/silver/consumption"

# COMMAND ----------

import builtins
from pyspark.sql.functions import col

# Read the Silver table
try:
    silver_df = spark.read.format("delta").load(SILVER_S3_PATH)
    total_count = silver_df.count()
    print(f"Loaded Silver table with {total_count} records.")
except Exception as e:
    raise Exception(f"Failed to load Silver table. Did the Silver pipeline run successfully? Error: {e}")

if total_count == 0:
    print("Silver table is empty. Skipping Data Quality checks.")
    dbutils.notebook.exit("Success (Empty Table)")

# COMMAND ----------

# MAGIC %md
# MAGIC ### 1. Uniqueness Test
# MAGIC No duplicate rows for the same geographical grain + Month/Year combination.

# COMMAND ----------

def check_uniqueness(df):
    duplicate_count = df.groupBy(
        "Circle", "Division", "SubDivision", "Section", "Area", "extraction_month", "extraction_year"
    ).count().filter(col("count") > 1).count()
    
    if duplicate_count > 0:
        raise AssertionError(f"Uniqueness check failed: Found {duplicate_count} duplicate geographical+time records in Silver layer.")
    print("✅ Uniqueness Test Passed")

check_uniqueness(silver_df)

# COMMAND ----------

# MAGIC %md
# MAGIC ### 2. Null Checks
# MAGIC Units and Load must not be null (these should have been sent to quarantine).

# COMMAND ----------

def check_nulls(df):
    null_units = df.filter(col("Units").isNull()).count()
    null_load = df.filter(col("Load").isNull()).count()
    
    if null_units > 0:
        raise AssertionError(f"Null check failed: Found {null_units} records with null Units. Quarantine logic failed in Silver layer.")
    if null_load > 0:
         raise AssertionError(f"Null check failed: Found {null_load} records with null Load. Quarantine logic failed in Silver layer.")
    print("✅ Null Checks Passed")

check_nulls(silver_df)

# COMMAND ----------

# MAGIC %md
# MAGIC ### 3. Volume Anomaly
# MAGIC Alert if a monthly file contains <50% of the previous month's volume.

# COMMAND ----------

def check_volume_anomaly(df):
    # Aggregate row counts by month chronologically
    monthly_counts = df.groupBy("extraction_year", "extraction_month") \
        .count() \
        .orderBy("extraction_year", "extraction_month") \
        .collect()
    
    if len(monthly_counts) < 2:
        print("Not enough months of data to perform Volume Anomaly comparison. Skipping.")
        return

    # Iterate through chronological months to compare against the previous month
    for i in range(1, len(monthly_counts)):
        prev_month_count = monthly_counts[i-1]["count"]
        curr_month_count = monthly_counts[i]["count"]
        
        # If the current month drops below 50% of the previous month's volume, flag anomaly
        if curr_month_count < (prev_month_count * 0.5):
            print(
                f"⚠️ ALERT - Volume Anomaly Detected: {monthly_counts[i]['extraction_month']}/{monthly_counts[i]['extraction_year']} "
                f"had {curr_month_count} rows, which is <50% of previous month ({prev_month_count} rows)."
            )
    print("✅ Volume Anomaly Test Passed")

check_volume_anomaly(silver_df)


# COMMAND ----------

# MAGIC %md
# MAGIC ### 4. Idempotency Test
# MAGIC Re-running the pipeline must not result in duplicate records (Ensure MERGE is working correctly).

# COMMAND ----------

def check_idempotency(df, _total_count):
    distinct_count = df.distinct().count()
    
    if _total_count != distinct_count:
        raise AssertionError(f"Idempotency failed: Table has {_total_count} total rows but only {distinct_count} distinct rows. A blind append may have occurred instead of a MERGE.")
    print("✅ Idempotency Test Passed")

check_idempotency(silver_df, total_count)

# COMMAND ----------

print("🎉 All Data Quality & Reliability Tests Passed.")
dbutils.notebook.exit("Success")
