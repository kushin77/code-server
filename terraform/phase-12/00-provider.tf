# Phase 12.1: Terraform Provider and Backend Configuration
# Manages remote state and GCP provider setup

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.20"
    }
  }

  backend "gcs" {
    bucket  = "code-server-terraform-state"
    prefix  = "phase-12/infrastructure"
  }
}

# Google Cloud Provider
provider "google" {
  project = var.gcp_project_id
  region  = var.primary_region

  user_project_override = true
  billing_project       = var.gcp_project_id
}

# Google Cloud Provider Beta
provider "google-beta" {
  project = var.gcp_project_id
  region  = var.primary_region
}

# Terraform Cloud Backend (optional, for team collaboration)
# Uncomment to enable Terraform Cloud
/*
cloud {
  organization = "kushin77-org"

  workspaces {
    name = "code-server-phase-12"
  }
}
*/

# ============================================================================
# Data Sources
# ============================================================================

# Get current GCP project
data "google_client_config" "current" {}

# Get available zones per region (for spreading resources)
data "google_compute_zones" "available" {
  for_each = {
    us-west     = "us-west1"
    eu-west    = "eu-west1"
    eu-central = "europe-west1"
    ap-south   = "asia-southeast1"
    ap-northeast = "asia-northeast1"
  }

  project = var.gcp_project_id
  region  = each.value
}

# ============================================================================
# Local Values
# ============================================================================

locals {
  project_id   = var.gcp_project_id
  federation_id = var.federation_name
  timestamp    = formatdate("YYYY-MM-DD-hh-mm-ss", timestamp())

  # Common labels for all resources
  common_labels = merge(
    var.labels,
    {
      terraform   = "true"
      phase       = "12-infrastructure"
      federation  = local.federation_id
      created_at  = local.timestamp
    }
  )

  # Region configuration
  regions = {
    us-west     = "us-west1"
    eu-west    = "eu-west1"
    eu-central = "europe-west1"
    ap-south   = "asia-southeast1"
    ap-northeast = "asia-northeast1"
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "terraform_config" {
  description = "Terraform configuration details"
  value = {
    version         = terraform.version
    backend_type    = "gcs"
    state_bucket    = "code-server-terraform-state"
    state_prefix    = "phase-12/infrastructure"
    project_id      = var.gcp_project_id
    federation_name = var.federation_name
  }
}

output "gcp_region" {
  description = "Primary GCP region"
  value       = var.primary_region
}

output "available_zones" {
  description = "Available zones per region"
  value = {
    for region, zones in data.google_compute_zones.available :
    region => zones.names
  }
}
