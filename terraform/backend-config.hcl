# Backend Configuration for MinIO S3-Compatible Remote State
# Usage: terraform init -backend-config=backend-config.hcl
# Purpose: Enable team collaboration, state locking, and backup for Terraform state
#
# IMPORTANT: Set AWS credentials as environment variables before init:
#   export AWS_ACCESS_KEY_ID=minio_user
#   export AWS_SECRET_ACCESS_KEY=$(openssl rand -base64 32)
#   terraform init -backend-config=backend-config.hcl

# MinIO S3 Backend (on-premises)
bucket         = "code-server-tfstate"
key            = "prod/terraform.tfstate"
region         = "us-east-1"

# MinIO endpoint (S3-compatible)
# Use endpoints.s3 (new format) instead of deprecated endpoint
endpoints = {
  s3 = "http://minio:9000"
}

# Skip AWS-specific validations (not using real AWS)
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
skip_region_validation      = true

# Optional: Enable state locking with DynamoDB (when ready for team deployments)
# dynamodb_table = "terraform-locks"
# lock_table_name = "terraform-locks"

