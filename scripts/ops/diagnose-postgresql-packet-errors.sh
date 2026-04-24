#!/usr/bin/env bash
# @file        scripts/ops/diagnose-postgresql-packet-errors.sh
# @module      ops/troubleshoot
# @description Diagnose PostgreSQL network packet errors between cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

H1=""
H2=""

log_info "Diagnosing PostgreSQL packets between  and ..."
