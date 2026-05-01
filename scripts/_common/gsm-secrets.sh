#!/usr/bin/env bash
# @file        scripts/_common/gsm-secrets.sh
# @module      secrets/gsm-manager
# @description Unified Google Secret Manager (GSM) interface for secrets operations
#
# Provides consolidated functions for:
# - Retrieve secrets from GSM with fallback to env vars
# - Store/rotate secrets in GSM
# - Verify secrets exist and are valid
# - Audit secret access
# - List all secrets by category
#
# Usage:
#   source scripts/_common/gsm-secrets.sh
#   
#   # Retrieve secret
#   GITHUB_TOKEN=$(gsm_get_secret "github-fine-grained-token")
#   
#   # Store secret
#   gsm_set_secret "database-password" "$new_password"
#   
#   # Verify secret exists
#   gsm_secret_exists "oauth2-cookie-secret" || exit 1
#   
#   # List all secrets by category
#   gsm_list_secrets "database"

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.gsm.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh" 2>/dev/null || true

# ============================================================================
# Configuration
# ============================================================================

# GCP Project ID (from environment or gcloud config)
export GSM_PROJECT_ID="${GSM_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"

# GSM replication policy (default: automatic)
export GSM_REPLICATION_POLICY="${GSM_REPLICATION_POLICY:-automatic}"

# Log audit access to GSM
export GSM_AUDIT_ENABLED="${GSM_AUDIT_ENABLED:-true}"

# Retry attempts for GSM operations
export GSM_MAX_RETRIES="${GSM_MAX_RETRIES:-3}"
export GSM_RETRY_DELAY="${GSM_RETRY_DELAY:-2}"

# ============================================================================
# Secret Categories & Standards
# ============================================================================

# Database secrets
declare -a GSM_SECRETS_DATABASE=(
  "postgres-admin-password"
  "postgres-user-password"
  "postgres-replication-password"
  "redis-password"
)

# API/External service secrets
declare -a GSM_SECRETS_API=(
  "github-fine-grained-token"
  "github-app-id"
  "github-app-secret"
  "slack-webhook-url"
  "slack-bot-token"
)

# OAuth2/Authentication secrets
declare -a GSM_SECRETS_OAUTH=(
  "oauth2-cookie-secret"
  "oauth2-client-id"
  "oauth2-client-secret"
  "oauth2-redirect-uri"
)

# TLS/Certificate secrets
declare -a GSM_SECRETS_TLS=(
  "tls-cert"
  "tls-key"
  "tls-ca-cert"
)

# Application secrets
declare -a GSM_SECRETS_APP=(
  "paperclip-encryption-master-key"
  "session-secret"
  "jwt-signing-key"
)

# ============================================================================
# Core Functions
# ============================================================================

#
# Get secret from GSM with fallback to environment variable
#
# Args:
#   $1 = secret name (e.g., "github-fine-grained-token")
#   $2 = fallback env var name (optional, defaults to uppercase secret name)
#
# Returns:
#   Secret value, or empty string if not found
#
gsm_get_secret() {
  local secret_name="${1:?Secret name required}"
  local fallback_var="${2:-$(echo "$secret_name" | tr '[:lower:]-' '[:upper:]_')}"
  
  # Prefer environment variable if set
  if [[ -n "${!fallback_var:-}" ]]; then
    echo "${!fallback_var}"
    return 0
  fi
  
  # Try GSM retrieval
  if ! command -v gcloud &>/dev/null; then
    log_warn "gcloud not available, cannot retrieve $secret_name from GSM"
    return 1
  fi
  
  local secret_value
  secret_value=$(gcloud secrets versions access latest --secret="$secret_name" 2>/dev/null || true)
  
  if [[ -z "$secret_value" ]]; then
    log_error "Secret not found: $secret_name (tried GSM and env var $fallback_var)"
    return 1
  fi
  
  # Audit access
  if [[ "${GSM_AUDIT_ENABLED:-true}" == "true" ]]; then
    gsm_audit_access "$secret_name" "read"
  fi
  
  echo "$secret_value"
}

#
# Set or rotate secret in GSM
#
# Args:
#   $1 = secret name
#   $2 = secret value (if empty, reads from stdin)
#
# Returns:
#   0 on success, 1 on failure
#
gsm_set_secret() {
  local secret_name="${1:?Secret name required}"
  local secret_value="${2:-}"
  
  if [[ -z "$secret_value" ]]; then
    # Read from stdin if not provided
    read -r secret_value || {
      log_error "No secret value provided"
      return 1
    }
  fi
  
  log_info "Storing secret in GSM: $secret_name"
  
  # Check if secret exists
  if gcloud secrets describe "$secret_name" &>/dev/null; then
    log_info "  → Updating existing secret (adding new version)"
    echo -n "$secret_value" | gcloud secrets versions add "$secret_name" --data-file=- || {
      log_error "Failed to update secret"
      return 1
    }
  else
    log_info "  → Creating new secret"
    echo -n "$secret_value" | gcloud secrets create "$secret_name" \
      --replication-policy="$GSM_REPLICATION_POLICY" \
      --data-file=- || {
      log_error "Failed to create secret"
      return 1
    }
  fi
  
  # Audit access
  if [[ "${GSM_AUDIT_ENABLED:-true}" == "true" ]]; then
    gsm_audit_access "$secret_name" "write"
  fi
  
  log_info "✓ Secret stored successfully"
  return 0
}

#
# Check if secret exists in GSM
#
# Args:
#   $1 = secret name
#
# Returns:
#   0 if exists, 1 if not
#
gsm_secret_exists() {
  local secret_name="${1:?Secret name required}"
  gcloud secrets describe "$secret_name" &>/dev/null
}

#
# List all secrets in GSM, optionally filtered by prefix
#
# Args:
#   $1 = filter prefix (optional, e.g., "github", "database", "oauth2")
#
# Returns:
#   One secret name per line
#
gsm_list_secrets() {
  local filter="${1:-}"
  local filter_pattern=""
  
  if [[ -n "$filter" ]]; then
    filter_pattern="--filter=name:$filter*"
  fi
  
  gcloud secrets list $filter_pattern --format="value(name,created,updated)" 2>/dev/null || {
    log_error "Failed to list secrets"
    return 1
  }
}

#
# Delete/destroy a secret from GSM (with confirmation)
#
# Args:
#   $1 = secret name
#   $2 = force flag (optional, -f to skip confirmation)
#
# Returns:
#   0 on success, 1 on failure
#
gsm_delete_secret() {
  local secret_name="${1:?Secret name required}"
  local force="${2:-}"
  
  if [[ "$force" != "-f" ]]; then
    log_warn "About to DELETE secret: $secret_name"
    read -p "Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
      log_info "Cancelled"
      return 1
    fi
  fi
  
  log_info "Deleting secret: $secret_name"
  gcloud secrets delete "$secret_name" --quiet || {
    log_error "Failed to delete secret"
    return 1
  }
  
  log_info "✓ Secret deleted"
  return 0
}

#
# Destroy specific version of a secret (for rotation)
#
# Args:
#   $1 = secret name
#   $2 = version id (optional, defaults to oldest version)
#
# Returns:
#   0 on success, 1 on failure
#
gsm_destroy_version() {
  local secret_name="${1:?Secret name required}"
  local version="${2:-}"
  
  # If version not specified, destroy oldest version
  if [[ -z "$version" ]]; then
    version=$(gcloud secrets versions list "$secret_name" --format="value(name)" | tail -1)
    log_info "No version specified, destroying oldest: $version"
  fi
  
  log_info "Destroying secret version: $secret_name (version: $version)"
  gcloud secrets versions destroy "$version" --secret="$secret_name" --quiet || {
    log_error "Failed to destroy version"
    return 1
  }
  
  log_info "✓ Version destroyed"
  return 0
}

#
# Prune old secret versions (keep only N most recent)
#
# Args:
#   $1 = secret name
#   $2 = keep count (default: 3)
#
# Returns:
#   0 on success, 1 on failure
#
gsm_prune_versions() {
  local secret_name="${1:?Secret name required}"
  local keep_count="${2:-3}"
  
  local total_versions
  total_versions=$(gcloud secrets versions list "$secret_name" --format="value(name)" | wc -l)
  
  if (( total_versions <= keep_count )); then
    log_info "Secret has $total_versions versions (keeping $keep_count), no pruning needed"
    return 0
  fi
  
  log_info "Pruning old versions of $secret_name (keeping $keep_count most recent of $total_versions)"
  
  local versions_to_destroy=$((total_versions - keep_count))
  gcloud secrets versions list "$secret_name" --format="value(name)" | head -n "$versions_to_destroy" | while read -r version; do
    log_info "  → Destroying version $version"
    gsm_destroy_version "$secret_name" "$version" || true
  done
  
  log_info "✓ Pruned $versions_to_destroy versions"
  return 0
}

#
# Verify secret meets requirements (not empty, not default value, etc.)
#
# Args:
#   $1 = secret name
#   $2 = validation check (optional: "not-empty", "not-default", "length:N", etc.)
#
# Returns:
#   0 if valid, 1 if not
#
gsm_verify_secret() {
  local secret_name="${1:?Secret name required}"
  local check="${2:-not-empty}"
  
  local secret_value
  secret_value=$(gsm_get_secret "$secret_name") || return 1
  
  case "$check" in
    not-empty)
      if [[ -z "$secret_value" ]]; then
        log_error "Secret is empty: $secret_name"
        return 1
      fi
      ;;
    not-default)
      if [[ "$secret_value" == "default" || "$secret_value" == "changeme" || "$secret_value" == *"secret"* ]]; then
        log_error "Secret has default/placeholder value: $secret_name"
        return 1
      fi
      ;;
    length:*)
      local required_length="${check#length:}"
      if [[ ${#secret_value} -lt $required_length ]]; then
        log_error "Secret too short: $secret_name (${#secret_value} < $required_length)"
        return 1
      fi
      ;;
  esac
  
  log_info "✓ Secret valid: $secret_name"
  return 0
}

#
# Audit log secret access
#
# Args:
#   $1 = secret name
#   $2 = action (read|write|delete)
#
# Returns:
#   always 0 (advisory only)
#
gsm_audit_access() {
  local secret_name="${1:-unknown}"
  local action="${2:-unknown}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local user="${USER:-$(whoami)}"
  local host="${HOSTNAME:-localhost}"
  
  log_debug "GSM_AUDIT: $timestamp | user=$user | host=$host | secret=$secret_name | action=$action"
}

#
# Initialize GSM for project (one-time setup)
#
# Returns:
#   0 on success, 1 on failure
#
gsm_init_project() {
  if [[ -z "$GSM_PROJECT_ID" ]]; then
    log_error "GSM_PROJECT_ID not set"
    return 1
  fi
  
  log_info "Initializing GSM for project: $GSM_PROJECT_ID"
  
  # Verify gcloud is configured
  if ! gcloud config get-value project &>/dev/null; then
    log_error "gcloud not configured. Run: gcloud init"
    return 1
  fi
  
  # Verify Secret Manager API is enabled
  log_info "Verifying Secret Manager API..."
  if ! gcloud services list --enabled --filter="name:secretmanager.googleapis.com" &>/dev/null; then
    log_info "Enabling Secret Manager API..."
    gcloud services enable secretmanager.googleapis.com || {
      log_error "Failed to enable Secret Manager API"
      return 1
    }
  fi
  
  log_info "✓ GSM initialized"
  return 0
}

#
# Generate standard documentation for operator setup
#
gsm_generate_setup_guide() {
  cat <<'EOF'
# GSM Secrets Setup Guide

## Prerequisites

```bash
# Install gcloud CLI
curl https://sdk.cloud.google.com | bash

# Initialize and authenticate
gcloud init
gcloud auth application-default login

# Set default project
gcloud config set project YOUR_PROJECT_ID
```

## Common Operations

### Create a new secret

```bash
echo "my-secret-value" | gcloud secrets create my-secret --data-file=-
```

### Retrieve a secret

```bash
gcloud secrets versions access latest --secret="my-secret"
```

### Rotate a secret (add new version)

```bash
echo "new-secret-value" | gcloud secrets versions add my-secret --data-file=-
```

### Prune old versions

```bash
# Keep only 3 most recent versions
gcloud secrets versions list my-secret --format="value(name)" | head -n -3 | while read v; do
  gcloud secrets versions destroy "$v" --secret="my-secret" --quiet
done
```

### List all secrets

```bash
gcloud secrets list
```

### Delete a secret

```bash
gcloud secrets delete my-secret --quiet
```

## IAM Permissions

Grant service account access:

```bash
SERVICE_ACCOUNT="ci-bot@my-project.iam.gserviceaccount.com"
SECRET_NAME="my-secret"

gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"
```

## Using in Scripts

```bash
source scripts/_common/gsm-secrets.sh

# Get secret (with fallback to env var)
TOKEN=$(gsm_get_secret "github-token" GITHUB_TOKEN)

# Verify secret exists
gsm_secret_exists "database-password" || exit 1

# Store new secret
gsm_set_secret "new-secret" "value123"
```

EOF
}

# ============================================================================
# Exports (make functions available to sourcing scripts)
# ============================================================================

export -f gsm_get_secret
export -f gsm_set_secret
export -f gsm_secret_exists
export -f gsm_list_secrets
export -f gsm_delete_secret
export -f gsm_destroy_version
export -f gsm_prune_versions
export -f gsm_verify_secret
export -f gsm_audit_access
export -f gsm_init_project
export -f gsm_generate_setup_guide

# ============================================================================
# Self-Test (if run directly)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "GSM Secrets Module - Self Test"
  echo "=============================="
  echo ""
  
  echo "Available functions:"
  echo "  gsm_get_secret <name> [fallback_var]"
  echo "  gsm_set_secret <name> [value]"
  echo "  gsm_secret_exists <name>"
  echo "  gsm_list_secrets [prefix]"
  echo "  gsm_delete_secret <name> [-f]"
  echo "  gsm_prune_versions <name> [keep_count]"
  echo "  gsm_verify_secret <name> [check]"
  echo "  gsm_init_project"
  echo ""
  
  echo "Secret categories:"
  echo "  Database:  ${GSM_SECRETS_DATABASE[*]}"
  echo "  API:       ${GSM_SECRETS_API[*]}"
  echo "  OAuth2:    ${GSM_SECRETS_OAUTH[*]}"
  echo "  TLS:       ${GSM_SECRETS_TLS[*]}"
  echo "  App:       ${GSM_SECRETS_APP[*]}"
  echo ""
  
  echo "Usage:"
  echo "  source scripts/_common/gsm-secrets.sh"
  echo "  TOKEN=\$(gsm_get_secret 'github-fine-grained-token')"
  echo ""
  
  gsm_generate_setup_guide
fi
