# Phase 16-B: Load Balancing & HA (HAProxy + Keepalived + ASG)
# Independent Terraform module for Layer 7 load balancing and virtual IP failover
# Deployment: Parallel with Phase 16-A (database HA)
# Status: Production-ready, idempotent, immutable

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "haproxy_instance_class" {
  description = "EC2 instance type for HAProxy"
  type        = string
  default     = "t3.xlarge"
}

variable "keepalived_vip" {
  description = "Virtual IP for keepalived failover"
  type        = string
  default     = "10.0.1.100"
}

variable "asg_min_size" {
  description = "Auto Scaling Group minimum size"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Auto Scaling Group maximum size"
  type        = number
  default     = 6
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "haproxy" {
  name        = "kushnir-haproxy-sg"
  description = "Security group for HAProxy load balancers"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from anywhere"
  }

  ingress {
    from_port   = 8404
    to_port     = 8404
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "HAProxy stats (internal only)"
  }

  ingress {
    from_port   = 112
    to_port     = 112
    protocol    = "112"
    cidr_blocks = ["10.0.0.0/8"]
    description = "VRRP heartbeat for keepalived"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "kushnir-haproxy-sg"
    Environment = var.environment
    Phase       = "16-B"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# LAUNCH TEMPLATE FOR HAPROXY INSTANCES
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_launch_template" "haproxy" {
  name_prefix   = "kushnir-haproxy-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.haproxy_instance_class

  vpc_security_group_ids = [aws_security_group.haproxy.id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  monitoring {
    enabled = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# AUTO SCALING GROUP
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "haproxy" {
  name              = "kushnir-haproxy-asg"
  vpc_zone_identifier = data.aws_subnets.public.ids
  
  launch_template {
    id      = aws_launch_template.haproxy.id
    version = "$Latest"
  }

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = 3

  vpc_zone_identifier = data.aws_subnets.public.ids
  health_check_type   = "EC2"
  health_check_grace_period = 300
  termination_policies = ["OldestInstance"]

  tag {
    key                 = "Name"
    value               = "kushnir-haproxy-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# APPLICATION LOAD BALANCER
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "primary" {
  name               = "kushnir-lb-primary"
  load_balancer_type = "application"
  internal           = false
  
  security_groups = [aws_security_group.haproxy.id]
  subnets         = data.aws_subnets.public.ids

  enable_deletion_protection = true
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "kushnir-lb-primary"
    Environment = var.environment
    Phase       = "16-B"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────────────────────

data "aws_vpc" "primary" {
  default = false
  tags = {
    Name = "kushnir-prod-vpc"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:Type"
    values = ["Public"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.primary.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.primary.arn
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.haproxy.name
}

output "virtual_ip" {
  description = "Virtual IP for keepalived VIP"
  value       = var.keepalived_vip
}
