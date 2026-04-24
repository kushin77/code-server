#!/usr/bin/env bash
# @file        scripts/ops/benchmark-10g-network.sh
# @module      ops/performance
# @description Benchmark 10G network throughput between cluster nodes
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars for replica IPs
source "/../fetch-gsm-secrets.sh"

SOURCE_IP=""
TARGET_IP=""

log_info "Benchmarking network between  and ..."
