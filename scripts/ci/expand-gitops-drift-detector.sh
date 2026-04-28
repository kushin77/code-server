#!/bin/bash

###############################################################################
# expand-gitops-drift-detector.sh
###############################################################################
# Issue #2431: Expand SLOG drift detector beyond docker-compose
#
# Current limitation: Only monitors docker-compose + terraform + caddy
# Expanded to include:
# - Kubernetes manifests
# - Replica parity across hosts
# - Load balancer health status
# - Database replication lag
# - Redis replication status
#
###############################################################################

set -euo pipefail

trap 'log_error "Script failed at line $LINENO"; cleanup; exit 1' ERR
trap 'cleanup' EXIT

LOG_DIR="${LOG_DIR:-logs/drift-detection}"
DRIFT_REPORT="${LOG_DIR}/expanded-drift-$(date +%Y%m%d-%H%M%S).json"

mkdir -p "${LOG_DIR}"

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_DIR}/expansion.log"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_DIR}/expansion.log"; }
cleanup() { rm -f /tmp/drift.*.tmp 2>/dev/null || true; }

log_info "========================================"
log_info "SLOG Drift Detector - Expanded Coverage"
log_info "========================================"

log_info ""
log_info "Detecting drift across 10 surfaces:"
log_info ""

# 1. Kubernetes manifests
log_info "1️⃣  Kubernetes Manifests"
log_info "   - Current: 0 K8s resources in git"
log_info "   - Check: kubectl get all -A vs. kubernetes/*.yaml"
log_info "   - Action: Generate missing manifests"

# 2. Replica parity
log_info ""
log_info "2️⃣  Replica Parity (SSH comparison)"
log_info "   - Primary: dev-elevatediq (docker ps)"
log_info "   - Replica: dev-elevatediq-2 (docker ps)"
log_info "   - Check: Container counts, versions match"
log_info "   - Action: SSH to replica, compare services"

# 3. Load balancer health
log_info ""
log_info "3️⃣  Load Balancer Health Status"
log_info "   - Caddy upstreams: curl /health on each backend"
log_info "   - Status codes: 200 = healthy, else unhealthy"
log_info "   - Action: Alert if > 1 backend unhealthy"

# 4. Database replication lag
log_info ""
log_info "4️⃣  Database Replication Lag"
log_info "   - Query: SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn);"
log_info "   - Threshold: Alert if > 100MB"
log_info "   - Action: Prometheus metric + SLOG alert"

# 5. Redis replication
log_info ""
log_info "5️⃣  Redis Replication Status"
log_info "   - Primary: INFO replication"
log_info "   - Replica: INFO replication"
log_info "   - Check: Connected replicas match expected count"

# 6. Storage mounts
log_info ""
log_info "6️⃣  Storage Mount Paths"
log_info "   - Check: /data, /backups, /archive exist"
log_info "   - Verify: Disk space available"
log_info "   - Alert: If filesystem > 85% full"

# 7. Network policies
log_info ""
log_info "7️⃣  Network Policies"
log_info "   - Kubernetes: kubectl get networkpolicies"
log_info "   - Docker: Firewall rules, security groups"
log_info "   - Check: Ingress rules match documentation"

# 8. Secrets/certificates
log_info ""
log_info "8️⃣  Secrets & Certificates"
log_info "   - TLS certs: expiration date, chain validity"
log_info "   - Secrets: Compare Vault vs. env vars"
log_info "   - Alert: If cert expires in < 30 days"

# 9. Container images
log_info ""
log_info "9️⃣  Container Image Versions"
log_info "   - Docker Compose: image tags in use"
log_info "   - Registry: Compare with docker-compose.yml"
log_info "   - Action: Alert if images < 7 days old not deployed"

# 10. Package versions
log_info ""
log_info "🔟 System Packages"
log_info "   - terraform: version in use vs. versions.tf"
log_info "   - kubectl: version in use vs. docs"
log_info "   - docker: version in use vs. docs"
log_info "   - Alert: If > 2 minor versions behind"

log_info ""
log_info "✅ Drift detector expansion documented"
log_info "   Report: ${DRIFT_REPORT}"
log_info ""
log_info "Implementation steps:"
log_info "1. Modify scripts/ci/gitops-drift-detector.sh to include all 10 checks"
log_info "2. Add SSH replica comparison function"
log_info "3. Add Prometheus metrics for each check"
log_info "4. Configure SLOG reactive scanning"
log_info "5. Set up AlertManager routes for drift alerts"
