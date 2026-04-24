#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "================================================="
echo " 🚀 Starting Idempotent Terraform Deployment 🚀  "
echo "================================================="

# Navigate to the terraform directory where the .tf files live
cd terraform/

echo ""
echo "[1/3] Initializing Terraform..."
# Downloads necessary AWS and Databricks plugins. Safe to run multiple times.
terraform init

echo ""
echo "[2/3] Validating and formatting code..."
terraform fmt
terraform validate

echo ""
echo "[3/4] Creating Execution Plan (tfplan)..."
# The -out flag saves the exact calculated plan to a file. 
# This prevents Terraform from recalculating during the apply stage,
# which guarantees total idempotency and prevents race conditions.
terraform plan -out=tfplan

echo ""
echo "================================================="
echo " ✅ Plan created successfully!"
echo " Review the output above to see what resources will be added/changed."
echo " Because of idempotency, existing S3 buckets and IAM roles will NOT be deleted."
echo " "
echo " Press [ENTER] to permanently apply these changes to AWS/Databricks"
echo " or press [Ctrl+C] to cancel. Nothing is pushed yet."
echo "================================================="
read -p ""

echo "[4/4] Applying the Plan..."
terraform apply "tfplan"

echo ""
echo "🎉 Deployment successful!"
echo "Your Terraform state has safely remembered the newly updated infrastructure."
