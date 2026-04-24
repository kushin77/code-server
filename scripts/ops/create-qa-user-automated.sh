#!/usr/bin/env bash
# @file        scripts/ops/create-qa-user-automated.sh
# @module      ops/iam
# @description Automated creation of QA users for CI/CD
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

DOMAIN="${APEX_DOMAIN}"
log_info "Setting up automated QA user for domain: ${DOMAIN}"
