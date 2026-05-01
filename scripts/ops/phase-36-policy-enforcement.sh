#!/usr/bin/env bash
################################################################################
# @file scripts/ops/phase-36-policy-enforcement.sh
# @description Phase 36 — Zero-Trust Policy Enforcement Orchestrator
#
# Modes:
#   --mode audit      Evaluate all policies against current platform state
#   --mode enforce    Evaluate + execute remediations for violations
#   --mode score      Print policy score and violation summary
#   --mode demo       Synthetic round-trip: violating context → remediation
#
# Usage:
#   bash scripts/ops/phase-36-policy-enforcement.sh --mode audit [--dry-run]
#   bash scripts/ops/phase-36-policy-enforcement.sh --mode score
#   DRY_RUN=true bash scripts/ops/phase-36-policy-enforcement.sh --mode demo
#
# @since 2026-05-01
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

trap 'log_error "Phase 36 script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Phase 36 policy enforcement script exiting"' EXIT

MODE="${MODE:-audit}"
DRY_RUN="${DRY_RUN:-true}"
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/phase36"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)       MODE="$2";     shift 2 ;;
    --dry-run)    DRY_RUN=true;  shift   ;;
    --no-dry-run) DRY_RUN=false; shift   ;;
    --help|-h)
      echo "Usage: $0 [--mode audit|enforce|score|demo] [--dry-run]"
      echo ""
      echo "Modes:"
      echo "  audit    — evaluate all policies (default)"
      echo "  enforce  — evaluate + auto-remediate violations"
      echo "  score    — show policy score summary"
      echo "  demo     — synthetic demo with intentional violations"
      exit 0
      ;;
    *) log_error "Unknown argument: $1"; exit 1 ;;
  esac
done

mkdir -p "${ARTIFACTS_DIR}"
_p36_log() { log_info "[phase-36] $*"; }

# ---------------------------------------------------------------------------
# Mode: score
# ---------------------------------------------------------------------------
run_score() {
  _p36_log "Phase 36 — policy score"
  python3 - <<'PYEOF'
import sys
sys.path.insert(0, '.')
from apps.security_ai.policy_engine import summary, get_policies

s = summary()
print(f"Phase 36 Policy Score: {s['policy_score']}/20")
print(f"Total policies: {s['total_policies']}")
print(f"Total violations: {s['total_violations']}")
print(f"Open violations: {s['open_violations']}")
print(f"Remediations executed: {s['total_remediations']}")
by_sev = s.get('violations_by_severity', {})
if by_sev:
    print("Open violations by severity:")
    for sev, count in sorted(by_sev.items()):
        print(f"  {sev}: {count}")
PYEOF
}

# ---------------------------------------------------------------------------
# Mode: audit
# ---------------------------------------------------------------------------
run_audit() {
  _p36_log "Phase 36 — policy audit (dry_run=${DRY_RUN})"

  python3 - <<PYEOF
import sys, json
sys.path.insert(0, '.')
from apps.security_ai.policy_engine import evaluate_policies, get_policies

# Representative platform context (code-server defaults)
contexts = [
    {
        "container_id": "code-server-primary-1",
        "container_name": "code-server-primary",
        "user_uid": 1000,
        "privileged": False,
        "env_vars": {"APP_NAME": "code-server", "LOG_LEVEL": "info"},
        "port_bindings": ["127.0.0.1:8080:8080"],
        "read_only_rootfs": False,
        "capabilities": [],
        "secret_age_days": 45,
    },
    {
        "container_id": "code-server-replica-1",
        "container_name": "code-server-replica",
        "user_uid": 1000,
        "privileged": False,
        "env_vars": {"APP_NAME": "code-server"},
        "port_bindings": ["127.0.0.1:8080:8080"],
        "read_only_rootfs": True,
        "capabilities": [],
        "secret_age_days": 30,
    },
]

total_violations = 0
for ctx in contexts:
    violations = evaluate_policies(ctx, dry_run=True)
    total_violations += len(violations)
    if violations:
        print(f"Container {ctx['container_id']}: {len(violations)} violation(s)")
        for v in violations:
            print(f"  [{v.severity.value.upper()}] {v.policy_name}: {v.description}")
    else:
        print(f"Container {ctx['container_id']}: PASS (no violations)")

print(f"\nAudit complete. Total violations: {total_violations}")
PYEOF
}

# ---------------------------------------------------------------------------
# Mode: enforce
# ---------------------------------------------------------------------------
run_enforce() {
  _p36_log "Phase 36 — enforce (dry_run=${DRY_RUN})"

  python3 - <<PYEOF
import sys
sys.path.insert(0, '.')
from apps.security_ai.policy_engine import (
    evaluate_policies, remediate_violation, summary
)

ctx = {
    "container_id": "code-server-enforced-1",
    "container_name": "code-server-enforced",
    "user_uid": 1000,
    "privileged": False,
    "env_vars": {"DATABASE_PASSWORD": "s3cr3t", "APP_NAME": "code-server"},
    "port_bindings": ["127.0.0.1:8080:8080"],
    "read_only_rootfs": True,
    "capabilities": [],
    "secret_age_days": 100,
}

violations = evaluate_policies(ctx, dry_run=True)
print(f"Violations found: {len(violations)}")

remediated = 0
for v in violations:
    rec = remediate_violation(v.violation_id, dry_run=${DRY_RUN})
    if rec:
        remediated += 1
        print(f"  Remediated [{rec.action.value}]: {v.policy_name} → {rec.status}")

s = summary()
print(f"\nPolicy score after enforcement: {s['policy_score']}/20")
print(f"Open violations remaining: {s['open_violations']}")
PYEOF
}

# ---------------------------------------------------------------------------
# Mode: demo
# ---------------------------------------------------------------------------
run_demo() {
  _p36_log "Phase 36 demo — synthetic zero-trust violation round-trip"

  python3 - <<'PYEOF'
import sys
sys.path.insert(0, '.')
from apps.security_ai.policy_engine import (
    evaluate_policies, remediate_violation, policy_score, summary
)

print("=== Phase 36 Zero-Trust Policy Demo ===")
print()

# Step 1: intentionally violating context
ctx = {
    "container_id": "demo-container-001",
    "container_name": "code-server-demo",
    "user_uid": 0,            # root → p001 violation
    "privileged": True,       # → p002 violation
    "env_vars": {
        "DATABASE_PASSWORD": "hunter2",  # → p003 violation
        "APP_NAME": "code-server",
    },
    "port_bindings": ["0.0.0.0:8080:8080"],  # → p004 violation
    "read_only_rootfs": True,
    "capabilities": [],
    "secret_age_days": 120,   # → p007 violation
}

print("Step 1: Evaluating policies against violating context...")
violations = evaluate_policies(ctx, dry_run=True)
print(f"  Found {len(violations)} violation(s):")
for v in violations:
    print(f"    [{v.severity.value.upper()}] {v.policy_name}: {v.description}")

print()
print("Step 2: Executing remediations (dry-run)...")
remediated = 0
for v in violations:
    rec = remediate_violation(v.violation_id, dry_run=True)
    if rec:
        remediated += 1
        print(f"  ✓ [{rec.action.value.upper()}] {v.policy_name} → {rec.status}")

print()
s = summary()
print(f"Step 3: Final state")
print(f"  Policy score: {s['policy_score']}/20")
print(f"  Open violations: {s['open_violations']}")
print(f"  Remediations: {s['total_remediations']}")
print()
print("Phase 36 demo complete.")
PYEOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${MODE}" in
  score)   run_score   ;;
  audit)   run_audit   ;;
  enforce) run_enforce ;;
  demo)    run_demo    ;;
  *)
    log_error "Unknown mode '${MODE}'. Use: audit, enforce, score, demo"
    exit 1
    ;;
esac
