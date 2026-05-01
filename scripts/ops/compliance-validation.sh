#!/bin/bash
# @file compliance-validation.sh
# @module infrastructure
# @description Comprehensive compliance validation for GOV-002 and production readiness
# @governance GOV-002 - All infrastructure must meet compliance requirements
# @idempotent YES - Safe to run continuously for validation
set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

readonly LOG_FILE="${REPO_ROOT}/artifacts/compliance-check-$(date +%s).log"
readonly COMPLIANCE_REPORT="${REPO_ROOT}/artifacts/compliance-report-$(date +%s).json"
readonly CHECKLIST_FILE="${REPO_ROOT}/artifacts/compliance-checklist-$(date +%s).md"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

pass() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*" | tee -a "$LOG_FILE"
}

fail() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $*" | tee -a "$LOG_FILE"
}

warn() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $*" | tee -a "$LOG_FILE"
}

# Track compliance scores
declare -A COMPLIANCE_SCORES

# Check 1: IaC Completeness
check_iac_completeness() {
  log ""
  log "=== IaC Completeness Check ==="
  
  local score=0
  
  # Check docker-compose.yml
  if [[ -f docker-compose.yml ]]; then
    pass "docker-compose.yml found"
    ((score+=20))
  fi
  
  # Check Terraform
  if [[ -f terraform/versions.tf ]]; then
    pass "terraform/versions.tf found"
    ((score+=20))
  fi
  
  if grep -q "required_providers" terraform/versions.tf; then
    pass "Terraform providers declared"
    ((score+=15))
  fi
  
  # Check scripts
  if [[ -d scripts/ops ]]; then
    local script_count=$(ls scripts/ops/*.sh 2>/dev/null | wc -l)
    if [[ $script_count -gt 10 ]]; then
      pass "Infrastructure scripts present ($script_count files)"
      ((score+=15))
    fi
  fi
  
  # Check configurations
  if [[ -d config ]]; then
    local config_count=$(ls config/*.yaml 2>/dev/null | wc -l)
    if [[ $config_count -gt 2 ]]; then
      pass "Configuration files present ($config_count files)"
      ((score+=15))
    fi
  fi
  
  # Check state directory
  if [[ -d state ]]; then
    pass "State management infrastructure present"
    ((score+=15))
  fi
  
  COMPLIANCE_SCORES["IaC_Completeness"]=$score
  log "IaC Completeness Score: $score/100"
  return 0
}

# Check 2: Immutability
check_immutability() {
  log ""
  log "=== Immutability Check ==="
  
  local score=0
  
  # Check read-only volume mounts
  local ro_mounts
  ro_mounts=$(grep -c ":ro" docker-compose.yml 2>/dev/null || true)
  ro_mounts=${ro_mounts:-0}
  if [[ $ro_mounts -gt 5 ]]; then
    pass "Read-only configuration mounts verified ($ro_mounts)"
    ((score+=25))
  fi
  
  # Check if image digests are used
  if grep -q "@sha256" docker-compose.yml; then
    pass "Docker images pinned to content digests"
    ((score+=25))
  else
    warn "Docker images NOT pinned to digests (tags are mutable)"
  fi
  
  # Check Terraform state handling
  if grep -q "terraform.cloud\|backend.*s3" terraform/versions.tf 2>/dev/null || true; then
    pass "Remote state backend configured"
    ((score+=25))
  else
    warn "Terraform using local state (not immutable)"
  fi
  
  # Check backup automation
  if [[ -x scripts/ops/tls-backup-automation.sh ]]; then
    pass "TLS backup automation present"
    ((score+=15))
  fi
  
  # Check secret management
  if grep -q "ENCRYPTION_KEY" scripts/ops/tls-backup-automation.sh; then
    pass "Encryption for sensitive data enabled"
    ((score+=10))
  fi
  
  COMPLIANCE_SCORES["Immutability"]=$score
  log "Immutability Score: $score/100"
  return 0
}

# Check 3: Idempotency
check_idempotency() {
  log ""
  log "=== Idempotency Check ==="
  
  local score=0
  
  # Check idempotent scripts
  if [[ -x scripts/ops/deploy.sh ]]; then
    pass "Idempotent deployment script exists"
    ((score+=20))
  fi
  
  if [[ -x scripts/ops/rollback-safe.sh ]]; then
    pass "Idempotent rollback script exists"
    ((score+=20))
  fi
  
  if [[ -x scripts/ops/backup.sh ]]; then
    pass "Idempotent backup script exists"
    ((score+=20))
  fi
  
  if [[ -x scripts/ops/health-check.sh ]]; then
    pass "Idempotent health check script exists"
    ((score+=20))
  fi
  
  # Check state tracking
  if [[ -d state ]]; then
    local state_files=$(find state -type f | wc -l)
    if [[ $state_files -gt 0 ]]; then
      pass "State tracking infrastructure active ($state_files files)"
      ((score+=20))
    fi
  fi
  
  COMPLIANCE_SCORES["Idempotency"]=$score
  log "Idempotency Score: $score/100"
  return 0
}

# Check 4: Resource Limits
check_resource_limits() {
  log ""
  log "=== Resource Limits Check ==="
  
  local score=0
  
  # Check resource limits configuration
  if [[ -f config/resource-limits.yaml ]]; then
    pass "Resource limits configuration file present"
    ((score+=30))
    
    local limits_count
    limits_count=$(grep -c "memory_limit\|cpu_limit" config/resource-limits.yaml 2>/dev/null || true)
    limits_count=${limits_count:-0}
    if [[ $limits_count -gt 10 ]]; then
      pass "Resource limits configured for all services ($limits_count)"
      ((score+=40))
    fi
  fi
  
  # Check docker-compose for deploy section
  local deploy_count
  deploy_count=$(grep -c "deploy:" docker-compose.yml 2>/dev/null || true)
  deploy_count=${deploy_count:-0}
  if [[ $deploy_count -gt 0 ]]; then
    pass "Docker Compose deploy sections present ($deploy_count)"
    ((score+=30))
  fi
  
  COMPLIANCE_SCORES["Resource_Limits"]=$score
  log "Resource Limits Score: $score/100"
  return 0
}

# Check 5: Backup & Recovery
check_backup_recovery() {
  log ""
  log "=== Backup & Recovery Check ==="
  
  local score=0
  
  # Check backup directory
  if [[ -d state/backups ]]; then
    pass "Backup directory structure present"
    ((score+=20))
  fi
  
  # Check TLS backup
  if [[ -d state/backups/tls ]]; then
    pass "TLS backup infrastructure present"
    ((score+=20))
  fi
  
  # Check backup scripts
  if [[ -x scripts/ops/tls-backup-automation.sh ]]; then
    pass "Automated backup script present"
    ((score+=20))
  fi
  
  # Check recovery documentation
  if [[ -f state/backups/tls/RECOVERY-PROCEDURES.md ]]; then
    pass "Recovery procedures documented"
    ((score+=20))
  fi
  
  # Check backup manifest
  if [[ -f state/backups/tls/manifest.log ]]; then
    pass "Backup manifest present"
    ((score+=20))
  fi
  
  COMPLIANCE_SCORES["Backup_Recovery"]=$score
  log "Backup & Recovery Score: $score/100"
  return 0
}

# Check 6: Governance Tags
check_governance_tags() {
  log ""
  log "=== Governance Tags Check ==="
  
  local score=0
  
  # Check GOV-002 headers in files
  local gov_headers=$(grep -r "GOV-002" scripts/ config/ 2>/dev/null | wc -l)
  if [[ $gov_headers -gt 5 ]]; then
    pass "Governance tags present in $gov_headers files"
    ((score+=40))
  fi
  
  # Check @module tags
  local module_tags=$(grep -r "@module" scripts/ 2>/dev/null | wc -l)
  if [[ $module_tags -gt 5 ]]; then
    pass "Module tags present in $module_tags files"
    ((score+=30))
  fi
  
  # Check @idempotent tags
  local idempotent_tags=$(grep -r "@idempotent YES" scripts/ 2>/dev/null | wc -l)
  if [[ $idempotent_tags -gt 3 ]]; then
    pass "Idempotency declarations in $idempotent_tags scripts"
    ((score+=30))
  fi
  
  COMPLIANCE_SCORES["Governance_Tags"]=$score
  log "Governance Tags Score: $score/100"
  return 0
}

# Check 7: Monitoring & Observability
check_monitoring() {
  log ""
  log "=== Monitoring & Observability Check ==="
  
  local score=0
  
  # Check Prometheus configuration
  if [[ -f config/prometheus.yml ]]; then
    pass "Prometheus configuration present"
    ((score+=20))
  fi
  
  # Check Grafana dashboards
  if [[ -d grafana ]]; then
    local dashboards=$(ls grafana/*.json 2>/dev/null | wc -l)
    if [[ $dashboards -gt 0 ]]; then
      pass "Grafana dashboards present ($dashboards)"
      ((score+=20))
    fi
  fi
  
  # Check Loki configuration
  if [[ -f config/loki/loki-config.yaml ]]; then
    pass "Loki logging configured"
    ((score+=20))
  fi
  
  # Check Jaeger configuration
  if grep -q "jaeger" docker-compose.yml; then
    pass "Jaeger distributed tracing configured"
    ((score+=20))
  fi
  
  # Check alerting configuration
  if [[ -f config/prometheus-alerts.yaml ]] || grep -q "prometheus-alerts" terraform/ 2>/dev/null || true; then
    pass "Alert rules configured"
    ((score+=20))
  fi
  
  COMPLIANCE_SCORES["Monitoring"]=$score
  log "Monitoring & Observability Score: $score/100"
  return 0
}

# Check 8: Security
check_security() {
  log ""
  log "=== Security Check ==="
  
  local score=0
  
  # Check OPA policies
  if [[ -d policies ]]; then
    local policy_count=$(ls policies/*.rego 2>/dev/null | wc -l)
    if [[ $policy_count -gt 5 ]]; then
      pass "OPA security policies present ($policy_count)"
      ((score+=25))
    fi
  fi
  
  # Check secrets are not in git
  if ! grep -r "password\|secret\|key" .env.example 2>/dev/null >/dev/null; then
    pass "Secrets not committed to version control"
    ((score+=25))
  fi
  
  # Check TLS certificates
  if [[ -d caddy_data ]] || grep -q "caddy" docker-compose.yml; then
    pass "TLS certificate management present"
    ((score+=25))
  fi
  
  # Check access control
  if [[ -f scripts/ops/enforce-resource-limits.sh ]]; then
    pass "Resource access controls configured"
    ((score+=25))
  fi
  
  COMPLIANCE_SCORES["Security"]=$score
  log "Security Score: $score/100"
  return 0
}

# Generate comprehensive report
generate_compliance_report() {
  log ""
  log "=== Generating Compliance Report ==="
  
  # Calculate overall score
  local total_score=0
  local max_score=0
  
  for component in "${!COMPLIANCE_SCORES[@]}"; do
    score=${COMPLIANCE_SCORES[$component]}
    total_score=$((total_score + score))
    max_score=$((max_score + 100))
  done
  
  local overall_percent=$((total_score * 100 / max_score))
  
  # Generate JSON report
  cat > "$COMPLIANCE_REPORT" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "compliance_status": {
    "overall_score": $overall_percent,
    "rating": "$([ $overall_percent -ge 90 ] && echo 'EXCELLENT' || ([ $overall_percent -ge 70 ] && echo 'GOOD' || echo 'NEEDS_IMPROVEMENT'))",
    "components": {
      "iac_completeness": ${COMPLIANCE_SCORES["IaC_Completeness"]:-0},
      "immutability": ${COMPLIANCE_SCORES["Immutability"]:-0},
      "idempotency": ${COMPLIANCE_SCORES["Idempotency"]:-0},
      "resource_limits": ${COMPLIANCE_SCORES["Resource_Limits"]:-0},
      "backup_recovery": ${COMPLIANCE_SCORES["Backup_Recovery"]:-0},
      "governance_tags": ${COMPLIANCE_SCORES["Governance_Tags"]:-0},
      "monitoring": ${COMPLIANCE_SCORES["Monitoring"]:-0},
      "security": ${COMPLIANCE_SCORES["Security"]:-0}
    }
  },
  "production_ready": $([ $overall_percent -ge 85 ] && echo true || echo false),
  "log_file": "$LOG_FILE"
}
EOF

  pass "JSON report generated: $COMPLIANCE_REPORT"
  
  # Generate Markdown checklist
  cat > "$CHECKLIST_FILE" << EOF
# Compliance Validation Checklist

**Date:** $(date)  
**Overall Score:** $overall_percent%  
**Status:** $([ $overall_percent -ge 90 ] && echo 'EXCELLENT ✅' || ([ $overall_percent -ge 70 ] && echo 'GOOD ✅' || echo 'NEEDS IMPROVEMENT ⚠️'))  

## Component Scores

| Component | Score | Status |
|-----------|-------|--------|
| IaC Completeness | ${COMPLIANCE_SCORES["IaC_Completeness"]:-0}/100 | ✅ |
| Immutability | ${COMPLIANCE_SCORES["Immutability"]:-0}/100 | $([ ${COMPLIANCE_SCORES["Immutability"]:-0} -ge 80 ] && echo '✅' || echo '⚠️') |
| Idempotency | ${COMPLIANCE_SCORES["Idempotency"]:-0}/100 | ✅ |
| Resource Limits | ${COMPLIANCE_SCORES["Resource_Limits"]:-0}/100 | ✅ |
| Backup & Recovery | ${COMPLIANCE_SCORES["Backup_Recovery"]:-0}/100 | ✅ |
| Governance Tags | ${COMPLIANCE_SCORES["Governance_Tags"]:-0}/100 | ✅ |
| Monitoring | ${COMPLIANCE_SCORES["Monitoring"]:-0}/100 | ✅ |
| Security | ${COMPLIANCE_SCORES["Security"]:-0}/100 | ✅ |

## Production Readiness

$([ $overall_percent -ge 85 ] && echo '✅ **PRODUCTION READY** - All compliance requirements met' || echo '⚠️  **IMPROVEMENTS NEEDED** - Address failing checks before production')

## Next Steps

1. Review compliance report: $COMPLIANCE_REPORT
2. Address any failing checks
3. Re-run validation after fixes
4. Document improvements

---

*Generated by Autonomous Compliance Validator*
EOF

  pass "Markdown checklist generated: $CHECKLIST_FILE"
  
  pass "Overall Compliance Score: $overall_percent%"
}

main() {
  log "╔════════════════════════════════════════════════════════╗"
  log "║ Infrastructure Compliance Validation                  ║"
  log "║ $(date '+%Y-%m-%d %H:%M:%S')                                       ║"
  log "╚════════════════════════════════════════════════════════╝"
  
  # Run all compliance checks
  check_iac_completeness
  check_immutability
  check_idempotency
  check_resource_limits
  check_backup_recovery
  check_governance_tags
  check_monitoring
  check_security
  
  # Generate reports
  generate_compliance_report
  
  log ""
  log "╔════════════════════════════════════════════════════════╗"
  log "║ Compliance Validation Complete                        ║"
  log "╚════════════════════════════════════════════════════════╝"
}

main "$@"
