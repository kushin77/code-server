/**
 * @file terraform/environments/private/backend.tf
 * @description P1 #2421: Remote S3 backend with DynamoDB state locking
 * @governance GOV-002: State must be encrypted, locked, and backed up
 * 
 * BOOTSTRAP REQUIREMENT:
 * Before running 'terraform init', the following AWS resources must exist:
 * 1. S3 bucket: code-server-enterprise-tfstate (with versioning enabled)
 * 2. DynamoDB table: code-server-enterprise-tfstate-lock (with LockID key)
 * 3. KMS key: alias/terraform-state (for encryption)
 * 
 * Bootstrap script:
 * aws s3api create-bucket --bucket code-server-enterprise-tfstate --region us-east-1
 * aws s3api put-bucket-versioning --bucket code-server-enterprise-tfstate --versioning-configuration Status=Enabled
 * aws dynamodb create-table --table-name code-server-enterprise-tfstate-lock \
 *   --attribute-definitions AttributeName=LockID,AttributeType=S \
 *   --key-schema AttributeName=LockID,KeyType=HASH \
 *   --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
 * aws kms create-alias --alias-name alias/terraform-state --target-key-id <key-id>
 */

terraform {
  backend "s3" {
    bucket         = "code-server-enterprise-tfstate"
    key            = "environments/private/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "alias/terraform-state"
    dynamodb_table = "code-server-enterprise-tfstate-lock"
    
    # Additional safeguards
    skip_credentials_validation = false
    skip_metadata_api_check     = false
    skip_region_validation      = false
  }
}
