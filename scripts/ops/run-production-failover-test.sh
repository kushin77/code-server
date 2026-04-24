#!/usr/bin/env bash
# @file        scripts/ops/run-production-failover-test.sh
# @module      ops/resilience
# @description Run production failover test across all replicas
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

A_D="${APEX_DOMAIN}"

log_info "Running failover test for ${A_D} cluster"
