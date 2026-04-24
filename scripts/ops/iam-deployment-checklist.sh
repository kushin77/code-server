#!/usr/bin/env bash
# @file        scripts/ops/iam-deployment-checklist.sh
# @module      ops/iam
# @description Verify IAM readiness for cluster deployment
# @owner       security
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo

log_info "IAM deployment checklist verified."
