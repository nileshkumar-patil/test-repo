terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.30"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# The user must provide these variables via CLI or a .tfvars file
provider "databricks" {
  host  = var.databricks_host
  token = var.databricks_token
}

# ==============================================================================
# AWS RESOURCES: Storage & IAM
# ==============================================================================

# Unified Data Lake Bucket (Combines Bronze, Silver, Gold into prefixes)
resource "aws_s3_bucket" "datalake" {
  bucket        = "${var.project_prefix}-datalake-poc-${var.environment}"
  force_destroy = true # Useful for a POC to easily tear down
}

# Optional: Enable versioning for data recovery
resource "aws_s3_bucket_versioning" "datalake_versioning" {
  bucket = aws_s3_bucket.datalake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------------------------------------------------------------
# IAM Cross-Account Role for Databricks Access
# ------------------------------------------------------------------------------

# 1. Trust Policy allowing Databricks AWS Account to assume this role
data "aws_iam_policy_document" "databricks_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "AWS"
      # This is the official Databricks AWS Account ID for cross-account roles
      identifiers = ["arn:aws:iam::414360345950:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_workspace_id]
    }
  }

  # Add Unity Catalog Trust Policy (Allows UC to assume this role for External Locations)
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::414360345950:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      # This is the Databricks Account ID used for Unity Catalog (you must pass this in)
      values   = [var.databricks_account_id]
    }
  }
}

resource "aws_iam_role" "databricks_data_access" {
  name               = "${var.project_prefix}-databricks-access-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.databricks_trust_policy.json
}

# 2. Data Access Policy allowing read/write to the Databricks Lake bucket
data "aws_iam_policy_document" "databricks_s3_policy" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.datalake.arn,
      "${aws_s3_bucket.datalake.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "databricks_s3_access" {
  name   = "databricks-s3-access"
  role   = aws_iam_role.databricks_data_access.id
  policy = data.aws_iam_policy_document.databricks_s3_policy.json
}

# 3. Create the Instance Profile for EC2 clusters (Legacy/Workflows)
resource "aws_iam_instance_profile" "databricks_profile" {
  name = "${var.project_prefix}-databricks-profile-${var.environment}"
  role = aws_iam_role.databricks_data_access.name
}

# ==============================================================================
# UNITY CATALOG: Storage Credentials & External Locations
# ==============================================================================

# 1. Create the Storage Credential mapping to the AWS IAM Role
resource "databricks_storage_credential" "datalake_cred" {
  name = "${var.project_prefix}-s3-cred-${var.environment}"
  aws_iam_role {
    role_arn = aws_iam_role.databricks_data_access.arn
  }
  comment = "Managed by Terraform: Credential for accessing the S3 Data Lake"
}

# 2. Create the External Location mapping to the S3 Bucket using the Credential
resource "databricks_external_location" "datalake_loc" {
  name            = "${var.project_prefix}-datalake-loc-${var.environment}"
  url             = "s3://${aws_s3_bucket.datalake.id}"
  credential_name = databricks_storage_credential.datalake_cred.id
  comment         = "Managed by Terraform: External Location for Bronze/Silver/Gold data"
}
