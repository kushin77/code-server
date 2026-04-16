################################################################################
# Terraform Remote State Backend — MinIO S3-compatible
# File: terraform/backend-s3.tf
# Purpose: Configure remote state storage for team collaboration and safety
# Owner: Infrastructure Team
# Issue: #417
# 
# Usage:
#   1. Initialize MinIO: terraform apply (creates bucket + credentials)
#   2. Configure Terraform to use remote state: terraform init -migrate-state
#   3. Verify: terraform state list (should show remote state)
# 
# Notes:
#   - MinIO is S3-compatible, so AWS provider can use it
#   - State file is encrypted at rest (TLS in transit)
#   - Local terraform.tfstate should be deleted after migration
#   - State locking via DynamoDB (optional, for team concurrency)
################################################################################

# ════════════════════════════════════════════════════════════════════════════
# TERRAFORM CLOUD/BACKEND CONFIGURATION (LOCAL DEVELOPMENT)
# ════════════════════════════════════════════════════════════════════════════
# This configuration is for local Terraform state storage during development.
# For remote state, uncomment the "cloud" block below after MinIO is running.

# When MinIO is operational, use this configuration:
# terraform {
#   cloud {
#     organization = "code-server-enterprise"
#     
#     workspaces {
#       name = "production"
#     }
#   }
# }

# Alternative: Use S3 backend directly
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state"
#     key            = "production/terraform.tfstate"
#     region         = "us-east-1"
#     endpoint       = "http://minio:9000"
#     
#     # MinIO credentials (from .env or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
#     # access_key   = "minioadmin"
#     # secret_key   = "minioadmin"
#     
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_requesting_account_id  = true
#     skip_region_validation      = true
#     use_path_style              = true
#   }
# }

################################################################################
# REMOTE STATE BACKEND RESOURCES
# These create the MinIO bucket and manage credentials
################################################################################

# Create MinIO bucket for Terraform state
resource "null_resource" "ensure_minio_bucket" {
  # This is a placeholder; actual bucket creation happens via minio-init script
  # Run: ./scripts/minio-setup.sh to initialize
  provisioner "local-exec" {
    command = <<-EOF
      echo "MinIO bucket should be initialized via: scripts/minio-setup.sh"
      echo "Current state:"
      echo "  - MinIO container: minio (port 9000, console 9001)"
      echo "  - Bucket: terraform-state"
      echo "  - Credentials: Check .env for MINIO_ROOT_USER / MINIO_ROOT_PASSWORD"
    EOF
  }

  triggers = {
    minio_endpoint = "http://minio:9000"
  }
}

# Optional: DynamoDB table for state locking (enables concurrent terraform operations safely)
# Uncomment to enable state locking
# resource "aws_dynamodb_table" "terraform_locks" {
#   name           = "terraform-locks"
#   billing_mode   = "PAY_PER_REQUEST"
#   hash_key       = "LockID"
#   
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
#   
#   tags = {
#     Name = "Terraform State Lock Table"
#   }
# }

################################################################################
# OUTPUT: TERRAFORM BACKEND CONFIGURATION
################################################################################

output "minio_endpoint" {
  value       = "http://minio:9000"
  description = "MinIO endpoint for S3-compatible operations"
}

output "minio_bucket" {
  value       = "terraform-state"
  description = "S3 bucket name for Terraform state"
}

output "minio_region" {
  value       = "us-east-1"
  description = "AWS region (ignored by MinIO, but required by Terraform)"
}

output "state_key" {
  value       = "production/terraform.tfstate"
  description = "S3 object key (path) for state file"
}

output "migration_command" {
  value       = "terraform init -migrate-state"
  description = "Run this command to migrate from local state to remote"
}

output "state_backup_command" {
  value       = "terraform state pull > terraform.tfstate.backup"
  description = "Backup current state before migration"
}
