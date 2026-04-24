#!/usr/bin/env bash
# @file        scripts/ops/fix-dast-target-reachability.sh
# @module      ops/troubleshoot
# @description Fix DAST target reachability for the production cluster
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

H1=""
DOMAIN=""
P="https"

log_info "Fixing target reachability for ://ide. on ..."
