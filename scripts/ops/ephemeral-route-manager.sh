#!/usr/bin/env bash
# @file        scripts/ops/ephemeral-route-manager.sh
# @module      ops/deployment
# @description Manage ephemeral routes for development sessions
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

DEV_DOMAIN="dev."
P="https"

log_info "Managing ephemeral routes for ://..."
