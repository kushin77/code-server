/**
 * @file terraform/environments/air-gapped/backend.tf
 * @description P1 #2421: Remote S3 backend for air-gapped environment
 * @governance GOV-002: State must be encrypted, locked, and backed up even in air-gapped deployments
 * 
 * Note: For air-gapped environments without AWS access, this should be replaced with:
 * - Local S3-compatible storage (MinIO) running within the air-gapped network
 * - Or local file backend with Git-based versioning as fallback
 */

terraform {
  backend "s3" {
    bucket         = "code-server-enterprise-tfstate-air-gapped"
    key            = "environments/air-gapped/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "alias/terraform-state-air-gapped"
    dynamodb_table = "code-server-enterprise-tfstate-lock-air-gapped"
    
    skip_credentials_validation = false
    skip_metadata_api_check     = false
    skip_region_validation      = false
  }
}
