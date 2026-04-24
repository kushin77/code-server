#!/usr/bin/env bash
# @file        scripts/ops/setup-ci-qa-credentials.sh
# @module      ops/iam
# @description Set up QA credentials for CI/CD authentication
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

QA_U="qa-automated@${APEX_DOMAIN}"

log_info "Setting up CI QA credentials for ${QA_U}"
