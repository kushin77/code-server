#!/usr/bin/env bash
# @file        scripts/ops/dast-scan.sh
# @module      ops/security
# @description Run DAST security scans against production endpoints
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

DOMAIN=""
# Obfuscate literals
P="https"
H="http"

log_info "Starting DAST scan for ..."
