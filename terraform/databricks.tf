# ==============================================================================
# DATABRICKS RESOURCES: Compute, Workflows & Dashboards
# ==============================================================================

# 1. Pipeline Source Code Location
# (Assuming the code exists in a Databricks Git folder or Workspace path)
# Note: For production, point this to a databricks_git_credential and databricks_repo
variable "workspace_code_path" {
  type    = string
  default = "/Workspace/Users/nilx181298@gmail.com/TSNPDCL"
  
}

# ------------------------------------------------------------------------------
# 2. Automated Workflow (Job)
# ------------------------------------------------------------------------------

resource "databricks_job" "tsnpdcl_pipeline" {
  name = "${var.project_prefix}-end-to-end-pipeline-${var.environment}"

  # Define Job-level Serverless Compute
  # The user requested Serverless. Databricks Jobs now support 
  # "Serverless Compute for Workflows" natively.
  job_clusters {
    job_cluster_key = "serverless_compute"
    new_cluster {
      spark_version = "14.3.x-scala2.12"
      node_type_id  = "serverless" # Magic string for Workflows Serverless
      
      # Attach the AWS IAM Instance Profile we created in main.tf
      aws_attributes {
        instance_profile_arn = aws_iam_instance_profile.databricks_profile.arn
      }
    }
  }

  # Email notifications for success and failure
  email_notifications {
    on_success = ["nileshkumarcpatil@gmail.com"]
    on_failure = ["nileshkumarcpatil@gmail.com"]
  }

  # Task 1: Ingestion (API to S3)
  task {
    task_key = "ingest_api_to_bronze"
    job_cluster_key = "serverless_compute"
    
    # Updated to notebook_task as requested
    notebook_task {
      notebook_path = "${var.workspace_code_path}/ingestion/bronze.ipynb"
    }
  }

  # Task 2: Silver Incremental Load
  task {
    task_key = "silver_incremental_load"
    depends_on {
      task_key = "ingest_api_to_bronze"
    }
    job_cluster_key = "serverless_compute"
    
    notebook_task {
      notebook_path = "${var.workspace_code_path}/etl/silver.ipynb"
    }
  }

  # Task 3:  Batch Aggregation
  task {
    task_key = "gold_batch_aggregation"
    depends_on {
      task_key = "silver_incremental_load"
    }
    job_cluster_key = "serverless_compute"
    
    notebook_task {
      notebook_path = "${var.workspace_code_path}/etl/gold.ipynb"
      
    }
  }

  # Task 3: Gold Batch Aggregation
  task {
    task_key = "gold_batch_aggregation"
    depends_on {
      task_key = "silver_incremental_load"
    }
    job_cluster_key = "serverless_compute"
    
    notebook_task {
      notebook_path = "${var.workspace_code_path}/etl/gold.ipynb"
      
    }
  }

  

  # Task 4: Automated Dashboard Refresh
  # This triggers the Lakeview/SQL Dashboard to update its cache
  task {
    task_key = "refresh_executive_dashboard"
    depends_on {
      task_key = "gold_batch_aggregation"
    }
    
    # Send a request to the Databricks SQL Warehouse to refresh the dashboard
    run_job_task {
      job_id = databricks_job.dashboard_refresher.id
    }
  }

  # --- OPTION 1: Trigger by File Arrival ---
  # Triggers the pipeline when a new file lands in the specified S3 path
  trigger {
    file_arrival {
      url = "s3://${aws_s3_bucket.datalake.id}/data/source/"
    }
  }

  # --- OPTION 2: Schedule (Monthly) ---
  # Run on the 3rd of every month at 2:00 AM
  # schedule {
  #   quartz_cron_expression = "0 0 2 3 * ?"
  #   timezone_id            = "Asia/Kolkata"
  # }
}

# ------------------------------------------------------------------------------
# 3. Automated Lakeview Dashboard creation via Terraform
# ------------------------------------------------------------------------------
# We can create Lakeview Dashboard objects in Databricks using the databricks_dashboard resource
resource "databricks_dashboard" "executive_summary" {
  name        = "TSNPDCL Smart Grid Executive Summary"
  parent_path = "/Workspace/Users/tsnpdcl_admin/Dashboards"
  
  # A Lakeview Dashboard is defined via a JSON payload of queries and widgets.
  # For brevity in the POC, we provide the skeletal layout which you can fine-tune in the UI.
  serialized_dashboard = jsonencode({
    "name" : "TSNPDCL Smart Grid Executive Summary",
    "pages" : [
      {
        "name" : "Page 1",
        "widgets" : [
            # Placeholders for the visual blocks
        ]
      }
    ],
    "datasets" : [
      {
        "name" : "District Efficiency",
        "query" : "SELECT Circle, Units_Billed_per_Service as `Efficiency Score` FROM tsnpdcl_prod.gold.district_performance ORDER BY `Efficiency Score` DESC"
      },
      {
         "name" : "MoM Growth",
         "query": "SELECT Circle, extraction_month as Month, MoM_Growth_Rate FROM tsnpdcl_prod.gold.growth_trends WHERE extraction_year = YEAR(CURRENT_DATE())"
      }
    ]
  })
}

# A dummy job used historically to trigger SQL dashboard refreshes via API
# (In modern Databricks, attach this to the primary workflow's sql_task if using legacy dashboards, 
# or manage via Lakeview dashboard schedules directly.)
resource "databricks_job" "dashboard_refresher" {
  name = "${var.project_prefix}-dashboard-refresh"
  task {
    task_key = "refresh"
    # Using a small SQL warehouse for the refresh
    sql_task {
      dashboard {
        dashboard_id = databricks_dashboard.executive_summary.id
      }
      warehouse_id = var.sql_warehouse_id
    }
  }
}
