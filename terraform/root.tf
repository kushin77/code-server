# Infrastructure as Code - Cluster Deployment
# Root module for complete production deployment
# Provider configuration and versions defined in versions.tf

# ============================================================================
# MODULES
# ============================================================================

module "infrastructure" {
  source = "./modules/infrastructure"

  cluster_name = var.cluster_name
  environment  = var.environment
}

module "observability" {
  source = "./modules/observability"

  cluster_name = var.cluster_name
  environment  = var.environment
  network_id   = module.infrastructure.network_id

  depends_on = [module.infrastructure]
}

module "api_gateway" {
  source = "./modules/api_gateway"

  cluster_name = var.cluster_name
  environment  = var.environment
  network_id   = module.infrastructure.network_id

  depends_on = [module.infrastructure]
}

module "microservices" {
  source = "./modules/microservices"

  cluster_name = var.cluster_name
  environment  = var.environment
  network_id   = module.infrastructure.network_id

  depends_on = [
    module.infrastructure,
    module.database
  ]
}

# ============================================================================
# VARIABLES
# ============================================================================

variable "cluster_name" {
  description = "Cluster name"
  type        = string
  default     = "code-server-enterprise"
}

# environment variable defined in variables.tf

# ============================================================================
# OUTPUTS
# ============================================================================

output "cluster_info" {
  description = "Cluster deployment information"
  value = {
    name        = var.cluster_name
    environment = var.environment
    network     = module.infrastructure.network_name
  }
}

output "database_services" {
  description = "Database services deployed"
  value       = module.database.services
}

output "observability_services" {
  description = "Observability services deployed"
  value       = module.observability.services
}

output "api_gateway" {
  description = "API Gateway information"
  value       = module.api_gateway.services
}

output "microservices_deployed" {
  description = "Microservices deployed"
  value       = module.microservices.services
}
