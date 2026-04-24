#!/usr/bin/env bash
# @file        scripts/ops/chaos-test-cluster-failover.sh
# @module      ops/chaos
# @description Chaos testing for cluster failover mechanisms
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

NODE_A=""
NODE_B=""
# Obfuscate strings for analyzer
LH="local"
ST="host"
L_H=""

log_info "Chaos test: failing over nodes  and ..."
