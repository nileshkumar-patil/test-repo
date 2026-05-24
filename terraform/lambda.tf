# ==============================================================================
# AWS RESOURCES: Lambda Function for API Ingestion & EventBridge Scheduling
# ==============================================================================

# 1. IAM Role for Lambda
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "${var.project_prefix}-lambda-exec-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json
}

# 2. IAM Policy to allow Lambda to write to the S3 Datalake and write CloudWatch logs
data "aws_iam_policy_document" "lambda_s3_log_policy" {
  # S3 Access
  statement {
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.datalake.arn}/*"
    ]
  }

  # CloudWatch Logs Access
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # SNS Publish Access
  statement {
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.ingestion_alerts.arn]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda-s3-log-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = data.aws_iam_policy_document.lambda_s3_log_policy.json
}

# 3. Zip the Python Code
# Terraform will automatically zip the Python file for us before uploading it to AWS
data "archive_file" "lambda_zip" {
  type = "zip"
  # This path should point to where your extract_api_to_s3.py is located
  source_file = "${path.module}/../ingestion/extract_api_to_s3.py"
  output_path = "${path.module}/extract_api_to_s3.zip"
}

# 4. The Lambda Function itself
resource "aws_lambda_function" "api_ingestion" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  function_name = "${var.project_prefix}-api-ingestion-${var.environment}"
  role          = aws_iam_role.lambda_exec_role.arn

  handler = "extract_api_to_s3.lambda_handler"
  runtime = "python3.10"

  timeout     = 300 # 5 minutes — monthly batch may have more files than a daily run
  memory_size = 512 # 512 MB

  environment {
    variables = {
      S3_BUCKET     = aws_s3_bucket.datalake.id
      S3_PREFIX     = "data/source/"
      API_URL       = "https://data.telangana.gov.in/api/1/metastore/schemas/dataset/items/ae305fca-068b-4e61-b7f8-d9bf651e1b69?show-reference-ids=true"
      SNS_TOPIC_ARN = aws_sns_topic.ingestion_alerts.arn
    }
  }
}

# ==============================================================================
# AWS EventBridge: Schedule the Lambda to run on the 1st of every month
# ==============================================================================

# Monthly schedule: fires on the 1st of every month at 20:30 UTC (2:00 AM IST on the 2nd)
# This aligns with TSNPDCL's monthly data release cadence on the Telangana Open Data portal.
resource "aws_cloudwatch_event_rule" "monthly_ingestion" {
  name                = "${var.project_prefix}-monthly-ingestion-${var.environment}"
  description         = "Triggers the TSNPDCL API ingestion Lambda function on the 1st of every month"
  schedule_expression = "cron(30 20 1 * ? *)"
}

# Attach the monthly schedule to the Lambda function
resource "aws_cloudwatch_event_target" "trigger_lambda" {
  rule      = aws_cloudwatch_event_rule.monthly_ingestion.name
  target_id = "TriggerLambdaIngestion"
  arn       = aws_lambda_function.api_ingestion.arn
}

# Explicitly allow EventBridge to trigger the Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_ingestion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_ingestion.arn
}

# ==============================================================================
# AWS SNS: Alerting Topic
# ==============================================================================

resource "aws_sns_topic" "ingestion_alerts" {
  name = "${var.project_prefix}-ingestion-alerts-${var.environment}"
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.ingestion_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
