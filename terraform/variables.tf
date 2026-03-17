variable "aws_region" {
  type    = string
  default = "ap-south-1" # Mumbai region for Telangana data
}

variable "project_prefix" {
  type    = string
  default = "tsnpdcl-analytics"
}

variable "environment" {
  type    = string
  default = "dev" # Can be strictly overridden in CI/CD (dev/prod)
}

variable "databricks_host" {
  type        = string
  description = "The URL of the Databricks Workspace"
}

variable "databricks_token" {
  type        = string
  description = "A Personal Access Token (PAT) for Databricks API"
  sensitive   = true
}

variable "databricks_workspace_id" {
  type        = string
  description = "The ID of the Databricks workspace (found in the URL)"
}

variable "databricks_account_id" {
  type        = string
  description = "The UUID of the Databricks Account for Unity Catalog"
}

variable "sql_warehouse_id" {
  type        = string
  description = "The ID of a Databricks SQL Warehouse to trigger dashboard refreshes"
  default     = "7474648073325275" # Optional if relying purely on Lakeview schedules
}

variable "workspace_code_path" {
  type        = string
  description = "The workspace path where the Databricks notebook code relies"
  default     = "/Workspace/Users/nileshkumar.patil@zemosolabs.com/TSNPDCL"
}
