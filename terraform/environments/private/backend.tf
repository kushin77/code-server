/**
 * @file terraform/environments/private/backend.tf
 * @description P1 #2421: Local Terraform state for on-prem private deployment
 * @governance GOV-002: State file stored locally with version control backup
 * 
 * For on-prem/air-gapped deployments, we use local state with .gitignore exclusion.
 * For AWS deployments, configure S3 backend with DynamoDB locking.
 */

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
