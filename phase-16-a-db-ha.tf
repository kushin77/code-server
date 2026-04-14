# Phase 16-A: Database High Availability (PostgreSQL HA + pgBouncer)
# Infrastructure as Code - Immutable, Testable, Repeatable
# Status: Production-ready, requires AWS credentials

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
  
  backend "local" {
    path = "terraform.phase-16-a.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "code-server"
      Phase       = "16-A"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CreatedAt   = timestamp()
    }
  }
}

# ============================================================================
# INPUT VARIABLES
# ============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production"
  }
}

variable "primary_instance_type" {
  description = "EC2 instance type for primary database"
  type        = string
  default     = "t3.xlarge"
}

variable "standby_instance_type" {
  description = "EC2 instance type for standby database"
  type        = string
  default     = "t3.xlarge"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14.5"
}

variable "phase_16_a_enabled" {
  description = "Enable Phase 16-A database HA deployment"
  type        = bool
  default     = true
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

resource "aws_security_group" "postgres_ha" {
  name_prefix = "postgres-ha-"
  description = "PostgreSQL HA cluster security group"
  vpc_id      = data.aws_vpc.default.id

  # PostgreSQL replication
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "PostgreSQL WAL replication"
  }

  # pgBouncer connection pool
  ingress {
    from_port   = 6432
    to_port     = 6432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "pgBouncer connection pooling"
  }

  # SSH for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH management access"
  }

  # Replication manager (repmgr)
  ingress {
    from_port   = 4891
    to_port     = 4891
    protocol    = "tcp"
    self        = true
    description = "repmgr monitoring"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "postgres-ha-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# EC2 INSTANCES - PRIMARY & STANDBY
# ============================================================================

resource "aws_instance" "postgres_primary" {
  count           = var.phase_16_a_enabled ? 1 : 0
  ami             = data.aws_ami.ubuntu.id
  instance_type   = var.primary_instance_type
  subnet_id       = data.aws_subnets.default.ids[0]
  security_groups = [aws_security_group.postgres_ha.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
    tags = {
      Name = "postgres-primary-root"
    }
  }

  # Data volume for PostgreSQL
  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 200
    delete_on_termination = false
    encrypted             = true
    tags = {
      Name = "postgres-primary-data"
    }
  }

  monitoring             = true
  associate_public_ip    = true
  iam_instance_profile   = aws_iam_instance_profile.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres_ha.id]

  user_data = base64encode(templatefile("${path.module}/scripts/setup-postgres-primary.sh", {
    postgres_version = var.postgres_version
    replication_user = "replicator"
    environment      = var.environment
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "postgres-primary-192-168-168-31"
    Role = "primary"
  }

  depends_on = [aws_iam_role.postgres]
}

resource "aws_instance" "postgres_standby" {
  count           = var.phase_16_a_enabled ? 1 : 0
  ami             = data.aws_ami.ubuntu.id
  instance_type   = var.standby_instance_type
  subnet_id       = data.aws_subnets.default.ids[1 % length(data.aws_subnets.default.ids)]
  security_groups = [aws_security_group.postgres_ha.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    delete_on_termination = true
    encrypted             = true
    tags = {
      Name = "postgres-standby-root"
    }
  }

  # Data volume for PostgreSQL
  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 200
    delete_on_termination = false
    encrypted             = true
    tags = {
      Name = "postgres-standby-data"
    }
  }

  monitoring             = true
  associate_public_ip    = true
  iam_instance_profile   = aws_iam_instance_profile.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres_ha.id]

  user_data = base64encode(templatefile("${path.module}/scripts/setup-postgres-standby.sh", {
    postgres_version = var.postgres_version
    primary_ip       = try(aws_instance.postgres_primary[0].private_ip_address, "192.168.168.31")
    replication_user = "replicator"
    environment      = var.environment
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "postgres-standby-192-168-168-32"
    Role = "standby"
  }

  depends_on = [aws_iam_role.postgres, aws_instance.postgres_primary]
}

# ============================================================================
# IAM ROLE & INSTANCE PROFILE
# ============================================================================

resource "aws_iam_role" "postgres" {
  name_prefix = "postgres-ha-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "postgres-ha-role"
  }
}

resource "aws_iam_role_policy" "postgres" {
  name_prefix = "postgres-ha-policy-"
  role        = aws_iam_role.postgres.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:DescribeParameters",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${var.aws_region}:ACCOUNT_ID:parameter/code-server/postgres/*"
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "ec2:CreateSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstances"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "postgres" {
  name_prefix = "postgres-ha-profile-"
  role        = aws_iam_role.postgres.name
}

# ============================================================================
# MONITORING & ALARMS
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  count               = var.phase_16_a_enabled ? 1 : 0
  alarm_name          = "postgres-replication-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PostgreSQLReplicationLagBytes"
  namespace           = "CodeServer"
  period              = "300"
  statistic           = "Average"
  threshold           = "1048576"  # 1MB
  alarm_description   = "Alert when replication lag exceeds 1MB"
  treat_missing_data  = "notBreaching"

  tags = {
    Phase = "16-A"
  }
}

resource "aws_cloudwatch_metric_alarm" "standby_not_replicating" {
  count               = var.phase_16_a_enabled ? 1 : 0
  alarm_name          = "postgres-standby-not-replicating"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "PostgreSQLReplicationStatus"
  namespace           = "CodeServer"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "1"  # 0=replicating, 1=not connected
  alarm_description   = "Alert when standby is not connected"
  treat_missing_data  = "breaching"

  tags = {
    Phase = "16-A"
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "primary_instance_id" {
  description = "Primary PostgreSQL instance ID"
  value       = try(aws_instance.postgres_primary[0].id, null)
}

output "primary_private_ip" {
  description = "Primary PostgreSQL private IP"
  value       = try(aws_instance.postgres_primary[0].private_ip_address, null)
}

output "standby_instance_id" {
  description = "Standby PostgreSQL instance ID"
  value       = try(aws_instance.postgres_standby[0].id, null)
}

output "standby_private_ip" {
  description = "Standby PostgreSQL private IP"
  value       = try(aws_instance.postgres_standby[0].private_ip_address, null)
}

output "security_group_id" {
  description = "Security group for PostgreSQL HA cluster"
  value       = aws_security_group.postgres_ha.id
}

output "deployment_status" {
  description = "Deployment status"
  value = var.phase_16_a_enabled ? "ENABLED - Primary: ${try(aws_instance.postgres_primary[0].private_ip_address, "pending")}, Standby: ${try(aws_instance.postgres_standby[0].private_ip_address, "pending")}" : "DISABLED"
}

# ============================================================================
# LOCALS - Configuration constants
# ============================================================================

locals {
  replication_config = {
    wal_level                   = "replica"
    max_wal_senders            = 5
    max_replication_slots      = 5
    wal_keep_size              = "128MB"
    hot_standby                = true
    hot_standby_feedback       = true
    recovery_target_timeline   = "latest"
    shared_preload_libraries   = "replication_monitoring"
  }

  pgbouncer_config = {
    pool_mode            = "transaction"
    max_client_conn      = 5000
    default_pool_size    = 25
    reserve_pool_size    = 5
    server_lifetime      = 3600
    connection_timeout   = 15
    idle_in_transaction_session_timeout = 300
  }
}
