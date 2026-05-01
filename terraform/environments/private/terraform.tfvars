# @file terraform/environments/private/terraform.tfvars
# @description Private deployment environment overrides
# @governance GOV-002 - IaC consolidation (issue #1531, phase 2)
# @depends_on ../_common/terraform.tfvars (SSOT for shared values)
# @immutable VERSION PINNED - All container digests immutable for reproducibility
#
# NOTE: Common values inherited from terraform/environments/_common/terraform.tfvars
# Only environment-specific overrides are defined here.

# ============================================================
# PRIVATE ENVIRONMENT: DEPLOYMENT TARGETS
# ============================================================

# NETWORK HOSTS
primary_host    = "192.168.168.31"
replica_host    = "192.168.168.42"
nas_host        = "192.168.168.56"

# SERVICE REGISTRIES
registry_url    = "registry.kushnir.cloud:5000"

# HOST REPOSITORY PATHS
primary_repo_path = "/home/akushnir/code-server-enterprise"
replica_repo_path = "/home/akushnir/code-server-enterprise"

# KUBERNETES CONFIGURATION
kubeconfig_path = "~/.kube/config"

# ============================================================
# CREDENTIALS & SECRETS
# Sourced from .env.production + .env.cluster
# ============================================================

db_user                = "postgres"
db_name                = "code_server"
db_password            = "9ouxRSxNW8x^A(h0XTdFoQNZ"
redis_password         = "y7h$7DAWtmqo*X$JER!p2ya%"
grafana_admin_user     = "admin"
grafana_admin_password = "EyqrnYsY0O8dNKI&TPgQxu1z"
qdrant_api_key         = "jO4rm(JJsgwcDlnSWgSt54@("
scheduler_api_key      = "@HiPd0)pCjCxg3qqg#4gYabA"
oauth2_client_id       = "code-server-oauth2-client"
oauth2_client_secret   = "code-server-oauth2-secret"
oauth2_cookie_secret   = "1dPVh9zxPN1E38JnQx+axQzmnZxuPDXX"

# ============================================================
# COMMON VALUES (inherited from _common/terraform.tfvars)
# ============================================================
# apex_domain              = "kushnir.cloud"           (from _common)
# admin_email              = "ops@kushnir.cloud"       (from _common)
# deployment_mode          = "private"                 (from _common)
# aws_region               = "us-east-1"              (from _common)
# environment              = "production"              (from _common)
# app_image_tag            = "latest"                 (from _common)
# enable_tls               = false                    (from _common)
# enable_metrics           = true                     (from _common)
# enable_tracing           = false                    (from _common)
# enable_debug_endpoints   = false                    (from _common)
# postgres_pool_size       = 10                       (from _common)
# postgres_max_overflow    = 20                       (from _common)
# redis_max_memory         = "512mb"                  (from _common)
# prometheus_retention_days = 30                      (from _common)
# loki_retention_days      = 7                        (from _common)
# auto_rollback_on_failure = true                     (from _common)
# rollback_failure_threshold = 3                      (from _common)
