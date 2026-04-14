# Consolidated AWS Data Sources
# Shared across all infrastructure modules for consistency and DRY principle
# All infrastructure layers reference these data sources; no duplicates in individual modules

data "aws_vpc" "primary" {
  default = false
  tags = {
    Name = "kushnir-prod-vpc"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:Type"
    values = ["Private"]
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

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_sns_topic" "alerts" {
  name = "kushnir-production-alerts"
}

data "aws_caller_identity" "current" {}
