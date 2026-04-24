#!/usr/bin/env bash
# @file        scripts/ops/verify-e2e-qa-setup.sh
# @module      ops/verify
# @description Verify E2E QA setup and accessibility
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

QA_E="qa@${APEX_DOMAIN}"

log_info "Verifying E2E QA setup for ${QA_E}"
