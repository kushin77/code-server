/**
 * @file terraform/modules/ssl-tls/renewal.tf
 * @description Automatic certificate renewal orchestration
 * @governance OPS-002: Certificate lifecycle automation
 */

# EventBridge rule for certificate renewal
resource "aws_cloudwatch_event_rule" "certificate_renewal" {
  count               = var.enable_certificate_auto_renewal ? 1 : 0
  name                = "${var.environment}-certificate-renewal"
  description         = "Automatic certificate renewal check"
  schedule_expression = "0 1 * * *" # Daily at 01:00 UTC

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-certificate-renewal"
    }
  )
}

# Lambda function for certificate renewal
resource "aws_lambda_function" "certificate_renewalchecker" {
  count         = var.enable_certificate_auto_renewal ? 1 : 0
  filename      = "${path.module}/lambda/certificate-renewal.zip"
  function_name = "${var.environment}-certificate-renewal"
  role          = aws_iam_role.certificate_renewal[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 120

  environment {
    variables = {
      CERTIFICATE_ARN            = aws_acm_certificate.main.arn
      RENEWAL_DAYS_BEFORE_EXPIRY = var.certificate_renewal_days_before_expiry
      APEX_DOMAIN                = var.apex_domain
      LETSENCRYPT_EMAIL          = var.letsencrypt_email
      SNS_TOPIC_ARN              = var.sns_topic_arn
      ENVIRONMENT                = var.environment
      CADDY_CERTIFICATE_PATH     = var.caddy_certificate_path
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-certificate-renewal"
    }
  )

  depends_on = [aws_iam_role_policy.certificate_renewal[0]]
}

# IAM role for renewal Lambda
resource "aws_iam_role" "certificate_renewal" {
  count = var.enable_certificate_auto_renewal ? 1 : 0
  name  = "${var.environment}-certificate-renewal-role"

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
      Name = "${var.environment}-certificate-renewal-role"
    }
  )
}

# Policy for renewal Lambda
resource "aws_iam_role_policy" "certificate_renewal" {
  count = var.enable_certificate_auto_renewal ? 1 : 0
  name  = "${var.environment}-certificate-renewal-policy"
  role  = aws_iam_role.certificate_renewal[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:RequestCertificate",
          "acm:ListCertificates"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetChange"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/${var.route53_zone_id}",
          "arn:aws:route53:::change/*"
        ]
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
          "ssm:PutParameter",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/${var.environment}/certificate/*"
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

# EventBridge target: Renewal Lambda
resource "aws_cloudwatch_event_target" "certificate_renewal" {
  count     = var.enable_certificate_auto_renewal ? 1 : 0
  rule      = aws_cloudwatch_event_rule.certificate_renewal[0].name
  target_id = "CertificateRenewal"
  arn       = aws_lambda_function.certificate_renewalchecker[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_renewal" {
  count         = var.enable_certificate_auto_renewal ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeRenewal"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.certificate_renewalchecker[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.certificate_renewal[0].arn
}

# CloudWatch Log Group for renewal
resource "aws_cloudwatch_log_group" "certificate_renewal" {
  count             = var.enable_certificate_auto_renewal ? 1 : 0
  name              = "/aws/lambda/${var.environment}-certificate-renewal"
  retention_in_days = 30

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-certificate-renewal-logs"
    }
  )
}

output "certificate_renewal_lambda_arn" {
  value       = try(aws_lambda_function.certificate_renewalchecker[0].arn, "")
  description = "Certificate renewal Lambda ARN"
}

output "certificate_renewal_role_arn" {
  value       = try(aws_iam_role.certificate_renewal[0].arn, "")
  description = "Certificate renewal IAM role ARN"
}
