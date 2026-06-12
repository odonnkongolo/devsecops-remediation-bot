# 1. Package the Python Bot into a Zip file automatically
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/remediate.py"
  output_path = "${path.module}/remediate.zip"
}

# 2. Deploy the Python Bot to AWS Lambda
resource "aws_lambda_function" "remediator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "devsecops-sg-remediator"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "remediate.handler"
  runtime          = "python3.10"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  # Add this line to give the bot 15 seconds to finish its job
  timeout = 15
}

# 3. The Detective: AWS Config Rule for Port 22
resource "aws_config_config_rule" "restricted_ssh" {
  name = "restricted-ssh"
  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

# 4. The Nervous System: EventBridge listening for the exact compliance failure
resource "aws_cloudwatch_event_rule" "config_trigger" {
  name        = "trigger-remediation-on-ssh"
  description = "Fires Lambda when AWS Config detects open SSH"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      messageType    = ["ComplianceChangeNotification"]
      configRuleName = [aws_config_config_rule.restricted_ssh.name]
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })
}

# 5. Connect EventBridge to the Lambda Bot
resource "aws_cloudwatch_event_target" "trigger_lambda" {
  rule      = aws_cloudwatch_event_rule.config_trigger.name
  target_id = "RemediateLambda"
  arn       = aws_lambda_function.remediator.arn
}

# 6. Explicitly allow EventBridge to trigger the Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_trigger.arn
}