#!/usr/bin/env bash
# @file        scripts/ops/fix-nas-systemd-units.sh
# @module      ops/hygiene
# @description Fix failed systemd units on NAS server
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "${SCRIPT_DIR}/scripts/fetch-gsm-secrets.sh"

NAS="${NAS_IP:-}"

log_info "Fixing systemd units on NAS ()..."
