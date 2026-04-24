#!/usr/bin/env bash
# @file        scripts/ops/harden-pgbouncer-sql.sh
# @module      ops/db
# @description Rotate PostgreSQL and PgBouncer credentials across cluster
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

log_info "Hardening PgBouncer SQL on  and ..."
