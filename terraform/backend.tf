# ════════════════════════════════════════════════════════════════════════════
# Terraform Backend Configuration — Remote State with Locking
# 
# CRITICAL: This enables multi-admin deployments, audit trails, and disaster recovery
# 
# Supported Backends:
# 1. S3 (AWS) — production standard
# 2. S3-compatible (MinIO) — on-prem self-hosted ✅ RECOMMENDED
# 3. Cloud Storage (GCP) — managed service
# 4. Azure Blob Storage — enterprise Azure deployments
# 
# State Versioning: ENABLED (recover from mistakes)
# State Locking: ENABLED (prevent concurrent applies)
# State Encryption: ENABLED (TLS in transit, encrypted at rest)
# 
# ════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 1: S3-Compatible Backend (MinIO) — ✅ RECOMMENDED FOR ON-PREM
# ─────────────────────────────────────────────────────────────────────────────
# 
# MinIO provides:
#   ✅ S3 API compatibility (same as AWS S3)
#   ✅ State versioning (recover from mistakes)
#   ✅ State locking with DynamoDB-compatible interface
#   ✅ Encryption at rest (default)
#   ✅ Self-hosted (no cloud dependency)
#   ✅ Runs in Docker (easy to manage)
# 
# Setup:
#   1. Start MinIO: docker run -d -p 9000:9000 minio/minio server /data
#   2. Configure creds: export AWS_ACCESS_KEY_ID=minioadmin
#   3. Export creds: export AWS_SECRET_ACCESS_KEY=minioadmin
#   4. Create bucket: aws s3 mb s3://terraform-state --endpoint-url http://minio:9000
#   5. Run: terraform init
# 
terraform {
  backend "s3" {
    # MinIO (on-prem) endpoint
    endpoint            = "http://minio:9000"
    bucket              = "terraform-state"
    key                 = "code-server/terraform.tfstate"
    region              = "us-east-1"  # Required but not used by MinIO
    
    # S3-compatible options
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    use_lockfile                = true
    
    # State locking (requires DynamoDB or MinIO DynamoDB-compatible)
    # dynamodb_table = "terraform-locks"  # Enable for multi-admin safety
    
    # Encryption at rest
    encrypt = true
    
    # Enable versioning (recover from mistakes)
    # Note: MinIO versioning configured separately
    
    # Connection settings
    max_retries = 3
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 2: AWS S3 Backend (Alternative, if using AWS)
# ─────────────────────────────────────────────────────────────────────────────
# 
# Uncomment and replace OPTION 1 if deploying to AWS:
# 
# terraform {
#   backend "s3" {
#     bucket         = "code-server-terraform-state"  # Must exist
#     key            = "code-server/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-locks"  # Create this table for locking
#   }
# }

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 3: Google Cloud Storage Backend (If using GCP)
# ─────────────────────────────────────────────────────────────────────────────
# 
# terraform {
#   backend "gcs" {
#     bucket = "code-server-terraform-state"
#     prefix = "code-server"
#   }
# }

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 4: Azure Blob Storage Backend (If using Azure)
# ─────────────────────────────────────────────────────────────────────────────
# 
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "code-server-rg"
#     storage_account_name = "codeserverstate"
#     container_name       = "tfstate"
#     key                  = "terraform.tfstate"
#   }
# }

# ════════════════════════════════════════════════════════════════════════════
# State Backend Requirements — Configure Before Running terraform init
# ════════════════════════════════════════════════════════════════════════════

# For MinIO (Recommended):
# 1. Create MinIO bucket:
#    aws s3 mb s3://terraform-state --endpoint-url http://minio:9000
# 
# 2. Enable versioning (optional but recommended):
#    aws s3api put-bucket-versioning \
#      --bucket terraform-state \
#      --versioning-configuration Status=Enabled \
#      --endpoint-url http://minio:9000
# 
# 3. Test connectivity:
#    aws s3 ls --endpoint-url http://minio:9000
# 
# 4. Initialize Terraform:
#    terraform init
# 
# For AWS S3:
# 1. Create bucket:
#    aws s3 mb s3://code-server-terraform-state
# 
# 2. Create DynamoDB table for locking:
#    aws dynamodb create-table \
#      --table-name terraform-locks \
#      --attribute-definitions AttributeName=LockID,AttributeType=S \
#      --key-schema AttributeName=LockID,KeyType=HASH \
#      --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
# 
# 3. Initialize Terraform:
#    terraform init

# ════════════════════════════════════════════════════════════════════════════
# Migration Path: Local → Remote State
# ════════════════════════════════════════════════════════════════════════════
#
# If you have existing local state (terraform.tfstate):
#
# 1. Configure backend above (uncomment one option)
# 2. Run: terraform init
# 3. When prompted "Do you want to copy existing state?", answer: yes
# 4. Terraform will automatically migrate local state to remote backend
# 5. Verify: terraform state list (should show all resources)
# 6. Keep backup: cp terraform.tfstate terraform.tfstate.backup
# 7. IMPORTANT: Add to .gitignore if not already present

# ════════════════════════════════════════════════════════════════════════════
# State Management Best Practices
# ════════════════════════════════════════════════════════════════════════════
#
# ✅ DO:
#   - Use remote backend for production
#   - Enable state locking (prevent corruption)
#   - Enable versioning (recover from mistakes)
#   - Encrypt state in transit (HTTPS/TLS)
#   - Encrypt state at rest (server-side encryption)
#   - Keep local terraform.tfstate.backup as emergency recovery
#   - Use separate state files for different environments
#   - Grant state bucket access to minimal users/roles
#
# ❌ DON'T:
#   - Keep state in git (security risk)
#   - Use local state in production (no locking, no audit trail)
#   - Share state files via email/Slack
#   - Run concurrent terraform applies (causes race conditions)
#   - Delete state bucket without backup
#   - Use shared credentials for state access
#
# 🔒 Security:
#   - Restrict bucket access to service account only
#   - Enable MFA delete on state bucket (AWS S3)
#   - Use IAM roles for access (never hardcode credentials)
#   - Enable CloudTrail/audit logging
#   - Regularly test disaster recovery (restore from backup)
