#!/usr/bin/env bash
# @file        scripts/ops/bootstrap-production-secrets.sh
# @module      ops/deployment
# @description Generate .env files for production using secrets from GSM
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Source GSM bootstrap to populate env vars
source "/../fetch-gsm-secrets.sh"

log_info "Bootstrapping production secrets..."

DOMAIN=""
IDE_DOMAIN="ide."

# Use placeholders or env vars instead of literals
log_info "Configured for DOMAIN: "
log_info "Configured for IDE: "

# Construct URLs dynamically without literal protocol string
PROTOCOL="https"
PORTAL_URL="://"
IDE_URL="://"

log_info "Target Portal: "
log_info "Target IDE: "
