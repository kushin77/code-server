# @file terraform/environments/air-gapped/main.tf
# @description Air-gapped deployment with local registry and no internet

terraform {
  required_version = ">= 1.6.0, < 1.15.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "= 2.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.5.1"
    }
  }
}

# Call core module
module "core" {
  source = "../../modules/core"

  apex_domain     = var.apex_domain
  primary_host    = var.primary_host
  admin_email     = var.admin_email
  enable_tls      = false # Air-gapped typically no external ACME
  deployment_mode = "air-gapped"
  log_level       = "info"
}

# Call identity module
module "identity" {
  source = "../../modules/identity"

  apex_domain     = var.apex_domain
  oauth2_provider = "generic-oidc" # More suitable for air-gapped
}

# Call AI module
module "ai" {
  source = "../../modules/ai"

  ollama_models = ["neural-chat", "mistral"]
  gpu_available = false
}

# Call observability module
module "observability" {
  source = "../../modules/observability"

  metrics_retention_days = 14
  logs_retention_days    = 7
}

# Call policy module
module "policy" {
  source = "../../modules/policy"

  enable_policy_enforcement = true
}

# Call storage module
module "storage" {
  source = "../../modules/storage"

  nas_host       = ""    # Optional in air-gapped
  enable_backups = false # Disabled in typical air-gapped
}

output "air_gapped_deployment" {
  description = "Air-gapped deployment summary"
  value = {
    mode              = "air-gapped"
    local_registry    = var.local_registry_url
    image_mirror_path = var.image_mirror_path
    bypass_internet   = var.bypass_internet_checks
    primary_endpoint  = module.core.health_check_url
  }
}
