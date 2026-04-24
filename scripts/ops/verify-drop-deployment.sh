#!/usr/bin/env bash
# @file        scripts/ops/verify-drop-deployment.sh
# @module      ops/verify
# @description Verify "Drop" deployment state and observability
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

A_D="${APEX_DOMAIN}"
I_D="ide.${A_D}"
P_D="prometheus.${A_D}"
G_D="grafana.${A_D}"
L_D="loki.${A_D}"

log_info "Verifying Drop deployment: ${I_D}, ${P_D}, ${G_D}, ${L_D}"
