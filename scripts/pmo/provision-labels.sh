#!/usr/bin/env bash
# @file        scripts/pmo/provision-labels.sh
# @module      pmo/labels
# @description Provision canonical 5-dimension label taxonomy for PMO-driven issue management
# @owner       PMO Framework
# @status      active
#
# Idempotent provisioning of 33+ labels across 5 dimensions:
#   - Priority: P0 (critical), P1 (high), P2 (medium), P3 (low)
#   - Type: epic, feature, bug, task, chore, refactor, security, docs, infra, test
#   - Status: backlog, ready, in-progress, blocked, review, done
#   - Epic: pmo-excellence, oidc-auth, resilience, observability, security-hardening, kushnir-cloud
#   - Agent/Gate: copilot, human, pair, gate:committed, gate:merged, gate:deployed, gate:cleaned

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${1:-kushin77/code-server}"
DRY_RUN="${DRY_RUN:-0}"

# Source common logging (if available; fallback to echo)
if [[ -f "$SCRIPT_DIR/scripts/_common/logging.sh" ]]; then
    source "$SCRIPT_DIR/scripts/_common/logging.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_fatal() { echo "[FATAL] $*"; exit 1; }
fi

log_info "Starting label provisioning for repository: $REPO"
[[ "$DRY_RUN" == "1" ]] && log_warn "DRY_RUN mode enabled — no labels will be created"

# Define label taxonomy as array of tuples: name|color|description
declare -a LABELS=(
    # PRIORITY DIMENSION (4 labels)
    "P0|d73a4a|Critical — immediate action required (outage, security)"
    "P1|f97316|High — major feature/degradation this sprint"
    "P2|eab308|Medium — enhancement or non-critical fix"
    "P3|84cc16|Low — nice-to-have, documentation, tech debt"
    
    # TYPE DIMENSION (10 labels)
    "epic|4f46e5|Type: Epic — strategic initiative rolling up sub-issues"
    "feature|a78bfa|Type: Feature — new capability or enhancement"
    "bug|dc2626|Type: Bug — defect or broken functionality"
    "task|0891b2|Type: Task — implementation or investigation work"
    "chore|6b7280|Type: Chore — maintenance, tooling, process"
    "refactor|7c3aed|Type: Refactor — code quality, structure, performance"
    "security|dc2626|Type: Security — vulnerability, auth, encryption"
    "docs|059669|Type: Documentation — guides, API docs, runbooks"
    "infra|1f2937|Type: Infrastructure — IaC, deployment, ops"
    "test|7c2d12|Type: Test — test suite, CI/CD, quality automation"
    
    # STATUS DIMENSION (6 labels)
    "status:backlog|e5e7eb|Status: Backlog — not yet started or prioritized"
    "status:ready|bfdbfe|Status: Ready — approved and ready to work"
    "status:in-progress|93c5fd|Status: In Progress — actively being worked on"
    "status:blocked|fca5a5|Status: Blocked — waiting on external dependency"
    "status:review|fed7aa|Status: Under Review — PR open, awaiting approval"
    "status:done|bbf7d0|Status: Done — completed, merged, deployed"
    
    # EPIC DIMENSION (6 labels)
    "epic:pmo-excellence|6366f1|Epic: PMO Process Excellence Framework"
    "epic:oidc-auth|8b5cf6|Epic: OIDC Authentication & Identity"
    "epic:resilience|10b981|Epic: Infrastructure Resilience & Failover"
    "epic:observability|f59e0b|Epic: Observability, Monitoring, Alerting"
    "epic:security-hardening|dc2626|Epic: Security Hardening & Compliance"
    "epic:kushnir-cloud|3b82f6|Epic: Kushnir.cloud (KC) DevOS Platform"
    
    # AGENT/GATE DIMENSION (7 labels)
    "agent:copilot|7e22ce|Agent: Copilot — AI-driven automation"
    "agent:human|6366f1|Agent: Human — manual review or execution"
    "agent:pair|8b5cf6|Agent: Pair — human+Copilot collaboration"
    "gate:committed|22c55e|Gate: Committed — code committed to branch"
    "gate:merged|16a34a|Gate: Merged — PR merged to main branch"
    "gate:deployed|059669|Gate: Deployed — production deployment complete (192.168.168.31)"
    "gate:cleaned|0f766e|Gate: Cleaned — branches deleted, repo clean"
)

provision_count=0
skip_count=0
error_count=0

# Provision each label
for label_spec in "${LABELS[@]}"; do
    IFS='|' read -r name color description <<< "$label_spec"
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] gh label create \"$name\" --color \"$color\" --repo \"$REPO\" --description \"$description\""
        ((provision_count++))
    else
        # Check if label already exists (idempotent)
        if gh label list --repo "$REPO" --limit 100 | grep -q "^$name\s"; then
            log_info "✓ Label already exists: $name"
            ((skip_count++))
        else
            if gh label create "$name" --color "$color" --repo "$REPO" --description "$description" 2>/dev/null; then
                log_info "✓ Created label: $name ($color) — $description"
                ((provision_count++))
            else
                log_error "✗ Failed to create label: $name"
                ((error_count++))
            fi
        fi
    fi
done

echo ""
log_info "Label provisioning complete:"
log_info "  Created: $provision_count"
log_info "  Skipped (already exist): $skip_count"
log_info "  Errors: $error_count"

if [[ $error_count -gt 0 ]]; then
    log_fatal "Label provisioning failed with $error_count errors"
fi

log_info "✅ All labels provisioned successfully for $REPO"
