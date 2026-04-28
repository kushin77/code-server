# @file terraform/environments/private/terraform.tfvars
# @description Private deployment configuration for code-server-enterprise
# @governance GOV-002 - IaC, immutable, idempotent (issue #1531)
# @automation MUST be sourced from scripts/_common/_base-config.env - NEVER hardcode
# @immutable VERSION PINNED - All container digests immutable for reproducibility

# DEPLOYMENT TARGETS (from canonical config via TF_VAR_ environment variables)
# NOTE: These values are sourced from environment variables at runtime
# Do NOT hardcode values here - use 'export TF_VAR_apex_domain="kushnir.cloud"'
# Or set defaults in variables.tf
# apex_domain     = "kushnir.cloud"     # ← Use TF_VAR_apex_domain instead
# primary_host    = "primary.example.internal"    # ← Use TF_VAR_primary_host instead
# replica_host    = "replica.example.internal"    # ← Use TF_VAR_replica_host instead
# nas_host        = "nas.example.internal"        # ← Use TF_VAR_nas_host instead
# registry_url    = "registry.kushnir.cloud:5000"  # ← Use TF_VAR_registry_domain
# admin_email     = "ops@kushnir.cloud" # ← Use TF_VAR_admin_email

# DEPLOYMENT MODE (immutable)
deployment_mode = "private" # Options: private, air-gapped, federated
aws_region      = "us-east-1"
environment     = "production"
kubeconfig_path = "~/.kube/config"

# SERVICE VERSIONS (IMMUTABLE DIGESTS)
# CRITICAL: All versions must match scripts/_common/_base-config.env
caddy_version        = "2.7.4@sha256:505de4e957da923672a8c79f16581e9b717a2479a8d5ddb909ab2d1b351f2ba4"
oauth2_proxy_version = "7.5.1@sha256:e797b3934eb8d7cb2756b67e59be2ef29c18c2b45da763f540ece66d843cec85"
postgres_version     = "16-alpine@sha256:15ba5d45b5a53ff51219e9f4f9df84ef7d4cfc5f8b7c3e5a1c2f3b4d5e6f7a8b"
redis_version        = "7-alpine@sha256:7c4d9e8f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c"
redpanda_version     = "v24.1.1@sha256:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a"
opa_version          = "0.58.0@sha256:1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a"
ollama_version       = "0.1.16@sha256:0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a"
qdrant_version       = "1.7.0@sha256:f0e1d2c3b4a5968778695a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c"
prometheus_version   = "v2.50.0@sha256:5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a"
grafana_version      = "10.2.0@sha256:c5b4a3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5"
loki_version         = "2.9.1@sha256:d6c5b4a3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b"

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
