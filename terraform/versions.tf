terraform {
  required_version = ">= 1.6.0, < 1.8.0"

  # Pinned provider versions for reproducibility and security
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Provider configurations
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "code-server-enterprise"
      Governance  = "GOV-002"
      ManagedBy   = "Terraform"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "local" {
  # No configuration needed
}