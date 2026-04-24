#!/usr/bin/env bash
# @file        scripts/ci/check-terraform-backend-hardening.sh
# @module      ci/terraform
# @description Enforce remote backend, encryption, and locking posture in terraform backend configuration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

BACKEND_FILE="terraform/backend.tf"
require_file "$BACKEND_FILE"

fail=0

if ! grep -qE 'backend\s+"(s3|gcs|azurerm)"' "$BACKEND_FILE"; then
  log_error "No supported remote backend block found in $BACKEND_FILE" || true
  fail=1
fi

if ! grep -qE 'encrypt\s*=\s*true' "$BACKEND_FILE"; then
  log_error "Backend encryption must be enabled (encrypt = true)" || true
  fail=1
fi

if ! grep -qE 'use_lockfile\s*=\s*true|dynamodb_table\s*=' "$BACKEND_FILE"; then
  log_error "Backend locking requirement missing (use_lockfile=true or dynamodb_table=...)" || true
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  log_fatal "Terraform backend hardening check failed"
fi

log_info "Terraform backend hardening check passed"
