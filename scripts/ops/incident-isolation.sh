#!/usr/bin/env bash
# @file        scripts/ops/incident-isolation.sh
# @module      ops/security
# @description Isolate node during active security incident
# @owner       security
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars
source "/../fetch-gsm-secrets.sh"

log_info "Incident isolation tool ready."
