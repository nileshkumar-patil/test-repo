resource "databricks_job" "tsnpdcl_pipeline" {
  name = "${var.project_prefix}-end-to-end-pipeline-${var.environment}"

  job_cluster {
    job_cluster_key = "serverless_compute"

    new_cluster {
      spark_version = "14.3.x-scala2.12"
      node_type_id  = "serverless"

      aws_attributes {
        instance_profile_arn = aws_iam_instance_profile.databricks_profile.arn
      }
    }
  }

  email_notifications {
    on_success = ["nileshkumar.patil@zemosolabs.com"]
    on_failure = ["nileshkumar.patil@zemosolabs.com"]
  }

  # ---------------------------------------------------
  # Task 1: Bronze Layer (Raw Ingestion)
  # ---------------------------------------------------
  task {
    task_key = "bronze_ingestion"

    job_cluster_key = "serverless_compute"

    notebook_task {
      notebook_path = "${var.workspace_code_path}/etl/bronze.ipynb"
    }
  }

  # ---------------------------------------------------
  # Task 2: Silver Layer (Transformation)
  # ---------------------------------------------------
  task {
    task_key = "silver_incremental_load"

    depends_on {
      task_key = "bronze_ingestion"
    }

    job_cluster_key = "serverless_compute"

    notebook_task {
      notebook_path = "${var.workspace_code_path}/etl/silver.ipynb"
    }
  }

  # ---------------------------------------------------
  # Task 3: Data Quality Checks
  # ---------------------------------------------------
  task {
    task_key = "data_quality_checks"

    depends_on {
      task_key = "silver_incremental_load"
    }

    job_cluster_key = "serverless_compute"

    notebook_task {
      notebook_path = "${var.workspace_code_path}/tests/test_data_quality.ipynb"
    }
  }

  # ---------------------------------------------------
  # Task 4: Gold Layer (Business Aggregation)
  # ---------------------------------------------------
  task {
    task_key = "gold_batch_aggregation"

    depends_on {
      task_key = "data_quality_checks"
    }

    job_cluster_key = "serverless_compute"

    notebook_task {
      notebook_path = "${var.workspace_code_path}/etl/gold.ipynb"
    }
  }



  # Trigger on S3 file arrival
  trigger {
    file_arrival {
      url = "s3://${aws_s3_bucket.datalake.id}/trigger/"
    }
  }
}

# ------------------------------------------------------------------------------
# 3. Automated Lakeview Dashboard creation via Terraform
# ------------------------------------------------------------------------------
resource "databricks_dashboard" "executive_summary" {
  display_name = "TSNPDCL Smart Grid Executive Summary"
  warehouse_id = var.sql_warehouse_id
  parent_path  = "/Workspace/Users/nileshkumar.patil@zemosolabs.com/Dashboards"
  
  serialized_dashboard = jsonencode({
    "name" : "TSNPDCL Smart Grid Executive Summary",
    "pages" : [
      {
        "name" : "Page_1",
        "displayName": "Page 1",
        "widgets" : []
      }
    ],
    "datasets" : [
      {
        "name" : "District_Efficiency",
        "displayName": "District Efficiency",
        "query" : "SELECT Circle, Units_Billed_per_Service as `Efficiency Score` FROM tsnpdcl_prod.gold.district_performance ORDER BY `Efficiency Score` DESC"
      },
      {
         "name" : "MoM_Growth",
         "displayName": "MoM Growth",
         "query": "SELECT Circle, extraction_month as Month, MoM_Growth_Rate FROM tsnpdcl_prod.gold.growth_trends WHERE extraction_year = YEAR(CURRENT_DATE())"
      }
    ]
  })
}
