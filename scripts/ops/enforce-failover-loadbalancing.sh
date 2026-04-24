#!/usr/bin/env bash
# @file        scripts/ops/enforce-failover-loadbalancing.sh
# @module      infrastructure/high-availability
# @description Enforce failover configuration on the load balancer
# @owner       On-call ops
# @status      Active maintenance

set -euo pipefail

SCRIPT_DIR="./scripts/ops"
source "/../_common/init.sh"
init_repo

PRIMARY_HOST=""
REPLICA_HOST=""

log_info "Configuring loadbalancer failover between  and ..."

cat > /tmp/haproxy-failover.cfg << EOC
backend code_server
  server primary :8080 check inter 5s fall 3 rise 2
  server backup :8080 backup check inter 5s fall 3 rise 2
EOC

log_info "✓ Loadbalancer configuration updated"
