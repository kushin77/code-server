#!/usr/bin/env bash
# @file        scripts/ops/kubernetes-log-triage.sh
# @module      ops/troubleshoot
# @description Triage logs from Kubernetes orchestration layer
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "${SCRIPT_DIR}/../_common/init.sh"
init_repo

log_info "Kubernetes log triage tool initialized."
