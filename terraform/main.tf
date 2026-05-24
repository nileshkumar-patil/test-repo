

#remote backend configuration terraform state is stored in S3 bucket and a DynamoDB table acts as a distributed lock.
#This means multiple developers or CI/CD runs can never currupt the state file simultaneously.

terraform {
  backend "s3" {
    bucket         = "tsnpdcl-terraform-state-backend"
    key            = "state/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "tsnpdcl-terraform-state-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.30"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
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
# This simplifies IAM management and Unity Catalog configuration significantly

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

# Create the internal trigger directory to satisfy Databricks job validation
resource "aws_s3_object" "trigger_dir" {
  bucket = aws_s3_bucket.datalake.id
  key    = "trigger/"
}

# ------------------------------------------------------------------------------
# IAM Cross-Account Role for Databricks Access
# ------------------------------------------------------------------------------


data "aws_caller_identity" "current" {}

data "databricks_aws_assume_role_policy" "workspace" {
  external_id = var.databricks_workspace_id
}

data "databricks_aws_unity_catalog_assume_role_policy" "uc" {
  aws_account_id = data.aws_caller_identity.current.account_id
  role_name      = "${var.project_prefix}-databricks-access-${var.environment}"
  external_id    = var.databricks_account_id
}

# Combine the Workspaces and Unity Catalog trust policies dynamically
data "aws_iam_policy_document" "databricks_trust_policy" {
  source_policy_documents = [
    data.databricks_aws_assume_role_policy.workspace.json,
    data.databricks_aws_unity_catalog_assume_role_policy.uc.json
  ]

  # Explicitly allow self-assume to satisfy Unity Catalog storage credential validation
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_prefix}-databricks-access-${var.environment}"]
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

# Add a 60-second delay to ensure AWS IAM Policy propagation globally
resource "time_sleep" "wait_for_iam" {
  depends_on = [
    aws_iam_role_policy.databricks_s3_access,
    aws_iam_role.databricks_data_access
  ]
  create_duration = "60s"
}

# 1. Create the Storage Credential mapping to the AWS IAM Role
resource "databricks_storage_credential" "datalake_cred" {
  name = "${var.project_prefix}-data-cred-${var.environment}"
  aws_iam_role {
    role_arn = aws_iam_role.databricks_data_access.arn
  }
  comment = "Managed by Terraform: Credential for accessing the S3 Data Lake"
  depends_on = [
    time_sleep.wait_for_iam
  ]
}

# 2. Create the External Location mapping to the S3 Bucket using the Credential
resource "databricks_external_location" "datalake_loc" {
  name            = "${var.project_prefix}-datalake-loc-${var.environment}"
  url             = "s3://${aws_s3_bucket.datalake.id}"
  credential_name = databricks_storage_credential.datalake_cred.id
  comment         = "Managed by Terraform: External Location for Bronze/Silver/Gold data"
  skip_validation = true
  force_destroy   = true
  depends_on = [
    databricks_storage_credential.datalake_cred
  ]
}
