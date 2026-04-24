#!/usr/bin/env bash
# @file        scripts/ops/install-k6-on-hosts.sh
# @module      ops/setup
# @description Install k6 load testing tool on cluster hosts
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

# Load secret vars
source "/../fetch-gsm-secrets.sh"

H1=""
H2=""

PR="https"
GH_U="://github.com"
K6_URL="/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz"

log_info "Installing k6 from  on  and ..."
