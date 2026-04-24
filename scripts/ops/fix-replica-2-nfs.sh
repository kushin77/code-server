#!/usr/bin/env bash
# @file        scripts/ops/fix-replica-2-nfs.sh
# @module      ops/storage
# @description Fix NFS mount issues specifically on Replica 2
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

H2=""
NAS=""

log_info "Fixing NFS on  targeting NAS ..."
