# @file terraform/environments/private/terraform.tfvars
# @description Private deployment configuration for code-server-enterprise
# @governance GOV-002 - IaC, immutable, idempotent (issue #1531)
# @automation MUST be sourced from scripts/_common/_base-config.env - NEVER hardcode
# @immutable VERSION PINNED - All container digests immutable for reproducibility

# DEPLOYMENT TARGETS (from canonical config via TF_VAR_ environment variables)
# NOTE: These values are sourced from environment variables at runtime
# Do NOT hardcode values here - use 'export TF_VAR_apex_domain="kushnir.cloud"'
# Or set defaults in variables.tf
apex_domain     = "kushnir.cloud"
primary_host    = "192.168.168.31"
replica_host    = "192.168.168.42"
nas_host        = "192.168.168.56"
registry_url    = "registry.kushnir.cloud:5000"
admin_email     = "ops@kushnir.cloud"

# HOST REPO PATHS
primary_repo_path = "/home/akushnir/code-server-enterprise"
replica_repo_path = "/home/akushnir/code-server-enterprise"

# SECRETS - INJECTED VIA ENVIRONMENT VARIABLES (TF_VAR_*)
# CRITICAL: Never hardcode secrets. Use: export TF_VAR_db_password="..."
# See terraform.tfvars.example for setup instructions
db_user                = "postgres"
db_name                = "code_server"
redis_password         = ""
grafana_admin_user     = "admin"
oauth2_client_id       = "code-server-oauth2-client-id"
app_image_tag          = "ae42f343"  # Git commit SHA for reproducibility

# DEPLOYMENT MODE (immutable)
deployment_mode = "private" # Options: private, air-gapped, federated
aws_region      = "us-east-1"
environment     = "production"
kubeconfig_path = "~/.kube/config"

# Version pins removed - now centralized in modules/stack/locals.tf (SSOT for all images)

# SECURITY & FEATURE FLAGS
enable_tls             = false # Set true after Let's Encrypt rate limit resets
enable_metrics         = true
enable_tracing         = false
enable_debug_endpoints = false

# PERSISTENCE
postgres_pool_size    = 10
postgres_max_overflow = 20
redis_max_memory      = "512mb"

# OBSERVABILITY
prometheus_retention_days = 30
loki_retention_days       = 7

# AUTO-ROLLBACK (IaC Lifecycle Control)
auto_rollback_on_failure   = true
rollback_failure_threshold = 3

# DEPLOYMENT NOTE
# This file is generated from scripts/_common/_base-config.env
# To update: Edit _base-config.env, then re-run: terraform apply -var-file=terraform.tfvars
# All values MUST remain immutable per build (no floating versions, no `:latest` tags)
