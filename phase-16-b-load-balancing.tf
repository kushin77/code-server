# Phase 16-B: Load Balancing & Auto-Scaling (HAProxy + Keepalived + ASG)
# Infrastructure as Code - Production-ready, IaC-driven
# Status: Ready for deployment

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.phase-16-b.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "code-server"
      Phase       = "16-B"
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
}

variable "haproxy_instance_type" {
  description = "EC2 instance type for HAProxy"
  type        = string
  default     = "t3.medium"
}

variable "backend_instance_type" {
  description = "EC2 instance type for backend app servers"
  type        = string
  default     = "t3.medium"
}

variable "asg_min_size" {
  description = "Auto-Scaling Group minimum size"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Auto-Scaling Group desired capacity"
  type        = number
  default     = 10
}

variable "asg_max_size" {
  description = "Auto-Scaling Group maximum size"
  type        = number
  default     = 50
}

variable "phase_16_b_enabled" {
  description = "Enable Phase 16-B load balancing deployment"
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

resource "aws_security_group" "haproxy" {
  name_prefix = "haproxy-"
  description = "HAProxy load balancer security group"
  vpc_id      = data.aws_vpc.default.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH management"
  }

  # Keepalived VRRP
  ingress {
    from_port   = 112
    to_port     = 112
    protocol    = "112"
    self        = true
    description = "VRRP (Keepalived)"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "haproxy-sg"
  }
}

resource "aws_security_group" "backend" {
  name_prefix = "code-server-backend-"
  description = "Backend application servers security group"
  vpc_id      = data.aws_vpc.default.id

  # From HAProxy
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.haproxy.id]
    description     = "From HAProxy load balancer"
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Health check
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.haproxy.id]
    description     = "Health check"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-sg"
  }
}

# ============================================================================
# NETWORK INTERFACES & ELASTIC IPs
# ============================================================================

# Primary HAProxy ENI
resource "aws_network_interface" "haproxy_primary" {
  count              = var.phase_16_b_enabled ? 1 : 0
  subnet_id          = data.aws_subnets.default.ids[0]
  security_groups    = [aws_security_group.haproxy.id]
  private_ips        = ["192.168.1.33"]
  private_ips_count  = 1

  tags = {
    Name = "haproxy-primary-eni"
  }
}

# Standby HAProxy ENI
resource "aws_network_interface" "haproxy_standby" {
  count              = var.phase_16_b_enabled ? 1 : 0
  subnet_id          = data.aws_subnets.default.ids[1 % length(data.aws_subnets.default.ids)]
  security_groups    = [aws_security_group.haproxy.id]
  private_ips        = ["192.168.1.34"]
  private_ips_count  = 1

  tags = {
    Name = "haproxy-standby-eni"
  }
}

# Virtual IP for Keepalived (VIP)
resource "aws_network_interface" "keepalived_vip" {
  count           = var.phase_16_b_enabled ? 1 : 0
  subnet_id       = data.aws_subnets.default.ids[0]
  security_groups = [aws_security_group.haproxy.id]
  private_ips     = ["192.168.1.35"]

  tags = {
    Name = "keepalived-vip"
  }
}

# ============================================================================
# EC2 INSTANCES - HAPROXY NODES
# ============================================================================

resource "aws_instance" "haproxy_primary" {
  count           = var.phase_16_b_enabled ? 1 : 0
  ami             = data.aws_ami.ubuntu.id
  instance_type   = var.haproxy_instance_type
  subnet_id       = data.aws_subnets.default.ids[0]
  security_groups = [aws_security_group.haproxy.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
  }

  monitoring             = true
  associate_public_ip    = true
  iam_instance_profile   = aws_iam_instance_profile.haproxy.name
  vpc_security_group_ids = [aws_security_group.haproxy.id]

  user_data = base64encode(file("${path.module}/scripts/setup-haproxy-primary.sh"))

  tags = {
    Name = "haproxy-primary-192-168-168-33"
    Role = "haproxy-primary"
  }

  depends_on = [aws_iam_role.haproxy]
}

resource "aws_instance" "haproxy_standby" {
  count           = var.phase_16_b_enabled ? 1 : 0
  ami             = data.aws_ami.ubuntu.id
  instance_type   = var.haproxy_instance_type
  subnet_id       = data.aws_subnets.default.ids[1 % length(data.aws_subnets.default.ids)]
  security_groups = [aws_security_group.haproxy.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
  }

  monitoring             = true
  associate_public_ip    = true
  iam_instance_profile   = aws_iam_instance_profile.haproxy.name
  vpc_security_group_ids = [aws_security_group.haproxy.id]

  user_data = base64encode(file("${path.module}/scripts/setup-haproxy-standby.sh"))

  tags = {
    Name = "haproxy-standby-192-168-168-34"
    Role = "haproxy-standby"
  }

  depends_on = [aws_iam_role.haproxy, aws_instance.haproxy_primary]
}

# ============================================================================
# IAM ROLE & POLICIES
# ============================================================================

resource "aws_iam_role" "haproxy" {
  name_prefix = "haproxy-role-"

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
}

resource "aws_iam_role_policy" "haproxy" {
  name_prefix = "haproxy-policy-"
  role        = aws_iam_role.haproxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeLoadBalancers"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "haproxy" {
  name_prefix = "haproxy-profile-"
  role        = aws_iam_role.haproxy.name
}

# ============================================================================
# LAUNCH TEMPLATE & AUTO-SCALING GROUP
# ============================================================================

resource "aws_launch_template" "backend" {
  count           = var.phase_16_b_enabled ? 1 : 0
  name_prefix     = "code-server-backend-"
  image_id        = data.aws_ami.ubuntu.id
  instance_type   = var.backend_instance_type
  security_groups = [aws_security_group.backend.id]

  monitoring {
    enabled = true
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.backend.name
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(file("${path.module}/scripts/setup-backend-app.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "code-server-backend"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "code-server-backend-volume"
    }
  }

  depends_on = [aws_iam_role.backend]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "backend" {
  count               = var.phase_16_b_enabled ? 1 : 0
  name_prefix         = "code-server-asg-"
  min_size            = var.asg_min_size
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size
  default_cooldown    = 300
  health_check_type   = "ELB"
  health_check_grace_period = 300

  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.backend[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "code-server-backend"
    propagate_launch_template = true
  }

  tag {
    key                 = "Phase"
    value               = "16-B"
    propagate_launch_template = true
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_launch_template.backend]
}

# ============================================================================
# APP-TIER IAM ROLE
# ============================================================================

resource "aws_iam_role" "backend" {
  name_prefix = "backend-app-role-"

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
}

resource "aws_iam_role_policy" "backend" {
  name_prefix = "backend-app-policy-"
  role        = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "ssm:DescribeParameters",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${var.aws_region}:ACCOUNT_ID:parameter/code-server/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backend" {
  name_prefix = "backend-app-profile-"
  role        = aws_iam_role.backend.name
}

# ============================================================================
# AUTO-SCALING POLICIES
# ============================================================================

resource "aws_autoscaling_policy" "scale_up" {
  count                  = var.phase_16_b_enabled ? 1 : 0
  name                   = "code-server-scale-up"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.backend[0].name
  adjustment             = 5

  cooldown = 300
}

resource "aws_autoscaling_policy" "scale_down" {
  count                  = var.phase_16_b_enabled ? 1 : 0
  name                   = "code-server-scale-down"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.backend[0].name
  adjustment             = -3

  cooldown = 300
}

# ============================================================================
# CLOUDWATCH ALARMS FOR SCALING
# ============================================================================

# Scale UP: CPU > 75% for 2 min
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.phase_16_b_enabled ? 1 : 0
  alarm_name          = "code-server-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "Scale up when CPU >75%"
  alarm_actions       = [aws_autoscaling_policy.scale_up[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.backend[0].name
  }
}

# Scale DOWN: CPU < 20% for 5 min
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  count               = var.phase_16_b_enabled ? 1 : 0
  alarm_name          = "code-server-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "Scale down when CPU <20%"
  alarm_actions       = [aws_autoscaling_policy.scale_down[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.backend[0].name
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "haproxy_primary_id" {
  description = "Primary HAProxy instance ID"
  value       = try(aws_instance.haproxy_primary[0].id, null)
}

output "haproxy_standby_id" {
  description = "Standby HAProxy instance ID"
  value       = try(aws_instance.haproxy_standby[0].id, null)
}

output "asg_name" {
  description = "Auto-Scaling Group name"
  value       = try(aws_autoscaling_group.backend[0].name, null)
}

output "asg_current_size" {
  description = "ASG current capacity"
  value       = try(aws_autoscaling_group.backend[0].desired_capacity, null)
}

output "deployment_status" {
  description = "Deployment status"
  value       = var.phase_16_b_enabled ? "ENABLED - HAProxy: ${try(aws_instance.haproxy_primary[0].private_ip_address, "pending")}, ASG: ${try(aws_autoscaling_group.backend[0].desired_capacity, 0)}/50 instances" : "DISABLED"
}

# ============================================================================
# LOCALS - Configuration
# ============================================================================

locals {
  haproxy_config = {
    max_connections      = 50000
    timeout_connect      = "10s"
    timeout_client       = "30s"
    timeout_server       = "30s"
    rate_limit_per_ip    = 1000
    rate_limit_per_minute = true
  }

  keepalived_config = {
    virtual_router_id   = 51
    priority_master     = 100
    priority_backup     = 90
    advertisement_int   = 1
    check_interval      = 2
  }
}
