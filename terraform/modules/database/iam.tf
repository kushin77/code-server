/**
 * @file terraform/modules/database/iam.tf
 * @description IAM roles and policies for database monitoring
 * @governance OPS-003: Least privilege access for infrastructure services
 */

# IAM role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-rds-monitoring-role"
    }
  )
}

# Attach AWS managed policy for RDS Enhanced Monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IAM role for Lambda database migration execution
resource "aws_iam_role" "database_migration_lambda" {
  name = "${var.environment}-database-migration-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-database-migration-lambda-role"
    }
  )
}

# Policy for Lambda to access RDS
resource "aws_iam_role_policy" "database_migration_policy" {
  name   = "${var.environment}-database-migration-policy"
  role   = aws_iam_role.database_migration_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
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

# Output IAM role ARNs
output "rds_monitoring_role_arn" {
  value       = aws_iam_role.rds_monitoring.arn
  description = "RDS Enhanced Monitoring IAM role ARN"
}

output "database_migration_lambda_role_arn" {
  value       = aws_iam_role.database_migration_lambda.arn
  description = "Database migration Lambda IAM role ARN"
}
