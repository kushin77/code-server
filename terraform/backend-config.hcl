# Backend Configuration for MinIO S3-Compatible Remote State
# Usage: terraform init -backend-config=backend-config.hcl
# Purpose: Enable team collaboration, state locking, and backup for Terraform state

# MinIO S3 Backend (on-premises)
bucket         = "code-server-tfstate"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
endpoint       = "http://minio:9000"

# Credentials: Use environment variables for security
# AWS_ACCESS_KEY_ID=minio_user
# AWS_SECRET_ACCESS_KEY=$(openssl rand -base64 32)
# Or pass: -backend-config="access_key=minio_user" -backend-config="secret_key=..."

skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
skip_region_validation      = true

# Optional: Enable state locking with DynamoDB (when ready for team deployments)
# dynamodb_table = "terraform-locks"
# lock_table_name = "terraform-locks"
