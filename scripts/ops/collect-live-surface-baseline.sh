#!/usr/bin/env bash
# @file        scripts/ops/collect-live-surface-baseline.sh
# @module      ops/verification
# @description Collect live baseline metrics for surfacing and comparison
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

P="https"
PORTAL_URL="://"
IDE_URL="://ide."

log_info "Collecting live baseline from  and ..."
