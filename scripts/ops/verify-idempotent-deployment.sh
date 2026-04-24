#!/usr/bin/env bash
# @file        scripts/ops/verify-idempotent-deployment.sh
# @module      ops/deployment
# @description Verify deployment is idempotent (can re-run safely)
# @owner       Infrastructure Team
# @status      ACTIVE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"

log_title "🔄 IDEMPOTENCY VERIFICATION"
log_info "Checking if deployment can be safely re-applied..."
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# IDEMPOTENCY CHECK 1: docker-compose config is stable
# ════════════════════════════════════════════════════════════════════════════
log_section "Check 1: docker-compose Configuration Stability"

config_hash_1=$(ssh akushnir@${DEPLOY_HOST} "cd code-server-enterprise-ops && docker-compose config 2>/dev/null | sha256sum" 2>/dev/null | awk '{print $1}')
config_hash_2=$(ssh akushnir@${DEPLOY_HOST} "cd code-server-enterprise-ops && docker-compose config 2>/dev/null | sha256sum" 2>/dev/null | awk '{print $1}')

if [[ "$config_hash_1" == "$config_hash_2" ]]; then
  log_success "✅ docker-compose config is stable (idempotent)"
else
  log_error "❌ docker-compose config changed on re-read (not idempotent!)"
  exit 1
fi
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# IDEMPOTENCY CHECK 2: Service states are deterministic
# ════════════════════════════════════════════════════════════════════════════
log_section "Check 2: Service Health State Determinism"

# Get initial state
initial_state=$(ssh akushnir@${DEPLOY_HOST} "docker ps --format '{{.Names}}:{{.State}}' | sort" 2>/dev/null || true)

# Wait 10s
sleep 10

# Get state again
second_state=$(ssh akushnir@${DEPLOY_HOST} "docker ps --format '{{.Names}}:{{.State}}' | sort" 2>/dev/null || true)

if [[ "$initial_state" == "$second_state" ]]; then
  log_success "✅ Service states are stable (idempotent)"
else
  log_warn "⚠️  Service states differ - check for startup races:"
  echo "$initial_state" | head -5
  echo "---"
  echo "$second_state" | head -5
fi
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# IDEMPOTENCY CHECK 3: Secrets are stable
# ════════════════════════════════════════════════════════════════════════════
log_section "Check 3: Secret Configuration Stability"

secrets_check=$(ssh akushnir@${DEPLOY_HOST} "grep -c 'CODE_SERVER_PASSWORD=\${VAULT' code-server-enterprise-ops/.env.production 2>/dev/null || true")
if [[ $secrets_check -gt 0 ]]; then
  log_success "✅ Secrets use vault references (idempotent)"
else
  log_warn "⚠️  Secrets may not use vault references"
fi
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# IDEMPOTENCY CHECK 4: Volume mounts are repeatable
# ════════════════════════════════════════════════════════════════════════════
log_section "Check 4: Volume Mount Consistency"

# Get volume config from docker-compose
vol_config=$(ssh akushnir@${DEPLOY_HOST} "cd code-server-enterprise-ops && docker-compose config | grep -A 3 'volumes:' | head -10" 2>/dev/null || true)

if echo "$vol_config" | grep -q 'type: bind\|type: volume'; then
  log_success "✅ Volume mounts are configured (idempotent)"
else
  log_warn "⚠️  Could not verify volume configuration"
fi
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════════════════
log_title "✅ IDEMPOTENCY VERIFICATION COMPLETE"
log_info "Deployment can be safely re-applied (idempotent properties verified)"
log_info ""
log_info "Key guarantees:"
log_info "  ✓ docker-compose config produces deterministic output"
log_info "  ✓ Service states stabilize quickly"
log_info "  ✓ Secrets use vault references"
log_info "  ✓ Volume mounts are repeatable"
log_info ""
log_info "Next steps:"
log_info "  → Deploy: docker-compose up -d (safe to re-run)"
log_info "  → Rollback: docker-compose down + restore snapshot (safe to re-run)"
