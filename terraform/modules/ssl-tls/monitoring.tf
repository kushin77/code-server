/**
 * @file terraform/modules/ssl-tls/monitoring.tf
 * @description Certificate expiration monitoring and alerting
 * @governance OPS-002: Certificate lifecycle alerts
 */

# EventBridge rule for certificate expiration monitoring
resource "aws_cloudwatch_event_rule" "certificate_expiration_check" {
  count               = var.enable_certificate_monitoring ? 1 : 0
  name                = "${var.environment}-certificate-expiration-check"
  description         = "Daily check for certificate expiration status"
  schedule_expression = var.renewal_check_frequency

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-certificate-expiration-check"
    }
  )
}

# Lambda function for certificate expiration checks
resource "aws_lambda_function" "certificate_checker" {
  count            = var.enable_certificate_monitoring ? 1 : 0
  filename         = "${path.module}/lambda/certificate-checker.zip"
  function_name    = "${var.environment}-certificate-checker"
  role             = aws_iam_role.certificate_checker[0].arn
  handler          = "index.handler"
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      CERTIFICATE_ARN           = aws_acm_certificate.main.arn
      SNS_TOPIC_ARN             = var.sns_topic_arn
      EXPIRATION_ALARM_DAYS     = var.certificate_expiration_alarm_days
      ENVIRONMENT               = var.environment
      RENEWAL_DAYS_BEFORE_EXPIRY = var.certificate_renewal_days_before_expiry
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-certificate-checker"
    }
  )
}

# Lambda execution role
resource "aws_iam_role" "certificate_checker" {
  count = var.enable_certificate_monitoring ? 1 : 0
  name  = "${var.environment}-certificate-checker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-certificate-checker-role"
    }
  )
}

# Policy for Lambda to check certificates and publish to SNS
resource "aws_iam_role_policy" "certificate_checker" {
  count  = var.enable_certificate_monitoring ? 1 : 0
  name   = "${var.environment}-certificate-checker-policy"
  role   = aws_iam_role.certificate_checker[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListCertificates"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# EventBridge target: Lambda
resource "aws_cloudwatch_event_target" "certificate_checker" {
  count     = var.enable_certificate_monitoring ? 1 : 0
  rule      = aws_cloudwatch_event_rule.certificate_expiration_check[0].name
  target_id = "CertificateChecker"
  arn       = aws_lambda_function.certificate_checker[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_certificate_monitoring ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.certificate_checker[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.certificate_expiration_check[0].arn
}

# CloudWatch Alarms for certificate status
resource "aws_cloudwatch_metric_alarm" "certificate_expiration" {
  count               = var.enable_certificate_monitoring ? 1 : 0
  alarm_name          = "${var.environment}-certificate-expiration-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CertificateDaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = "3600"
  statistic           = "Minimum"
  threshold           = var.certificate_expiration_alarm_days
  alarm_description   = "Alert when certificate expires in ${var.certificate_expiration_alarm_days} days"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    CertificateArn = aws_acm_certificate.main.arn
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-certificate-expiration-alarm"
    }
  )
}

# CloudWatch Log Group for monitoring
resource "aws_cloudwatch_log_group" "certificate_checker" {
  count             = var.enable_certificate_monitoring ? 1 : 0
  name              = "/aws/lambda/${var.environment}-certificate-checker"
  retention_in_days = 30

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-certificate-checker-logs"
    }
  )
}

output "certificate_checker_lambda_arn" {
  value       = try(aws_lambda_function.certificate_checker[0].arn, "")
  description = "Certificate checker Lambda ARN"
}

output "certificate_expiration_alarm_arn" {
  value       = try(aws_cloudwatch_metric_alarm.certificate_expiration[0].arn, "")
  description = "Certificate expiration alarm ARN"
}
