#!/usr/bin/env bash
# @file        scripts/ops/docker-storage-hygiene.sh
# @module      ops/hygiene
# @description Maintain Docker storage hygiene by cleaning up unused resources
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

log_info "Running Docker storage hygiene..."
