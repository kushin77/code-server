#!/usr/bin/env bash
# @file        scripts/ops/isolate-replica-2-nvme-failure.sh
# @module      infrastructure/incident-response
# @description Execute P0 #1635 Phase 1 isolation - block all traffic to Replica 2 to prevent NVMe data corruption
# @owner       On-call ops
# @status      Emergency procedure - requires passwordless sudo

set -euo pipefail

SCRIPT_DIR=""
BASE_DIR=""
source "/scripts/_common/init.sh"
init_repo

REPLICA_2_HOST=""
REPLICA_1_HOST=""

# ────────────────────────────────────────────────────────────────────────────
# STEP 1: Verify Replica 2 is accessible and NVMe is actually failed
# ────────────────────────────────────────────────────────────────────────────
log_info "Phase 1.1: Verify Replica 2 accessibility and NVMe status"

ssh -i ~/.ssh/id_rsa_onprem akushnir@ "echo 
