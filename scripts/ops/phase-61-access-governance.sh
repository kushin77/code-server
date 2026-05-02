#!/bin/bash
# @file phase-61-access-governance.sh
# @description Phase 61 — Identity Access Governance & Privilege Drift Engine

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..." >&2; rm -f /tmp/p61*.tmp 2>/dev/null || true' EXIT

MODE="${1:-demo}"

cmd_demo() {
  log_info "Phase 61 — Identity Access Governance & Privilege Drift"
  "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.access_governance_engine import (
    AccessGovernanceEngine, IdentityType, ReviewStatus,
    make_permission, make_role, make_identity
)

eng = AccessGovernanceEngine()

reader = eng.register_role(make_role(
    "reader",
    [make_permission("s3:bucketA", "read"), make_permission("db:users", "list")],
    is_privileged=False,
))
admin = eng.register_role(make_role(
    "admin",
    [make_permission("iam", "admin"), make_permission("kms", "decrypt")],
    is_privileged=True,
))

alice = eng.register_identity(make_identity("alice", IdentityType.HUMAN, owner="security"))
svc = eng.register_identity(make_identity("svc-payments", IdentityType.SERVICE, owner="platform"))

eng.assign_role(alice.identity_id, reader.role_id)
eng.assign_role(svc.identity_id, reader.role_id)
eng.assign_role(svc.identity_id, admin.role_id)
eng.add_direct_permission(svc.identity_id, make_permission("prod-db", "delete"))

eng.set_least_privilege_baseline(alice.identity_id, ["s3:bucketA:read", "db:users:list"])
eng.set_least_privilege_baseline(svc.identity_id, ["s3:bucketA:read"])

eng.scan_all_drift()
review = eng.create_review(svc.identity_id, "secops", ["admin role not justified"])
if review:
    eng.set_review_status(review.review_id, ReviewStatus.PENDING)

summary = eng.summary()
print(f"[Phase 61] Total identities     : {summary['total_identities']}")
print(f"[Phase 61] Drift findings       : {summary['drift_findings']}")
print(f"[Phase 61] Critical findings    : {summary['critical_findings']}")
print(f"[Phase 61] Pending reviews      : {summary['pending_reviews']}")
print(f"[Phase 61] Review coverage      : {summary['review_coverage_pct']:.2f}%")
print(f"[Phase 61] Gate score           : {summary['phase61_score']}/25")
PYEOF
}

cmd_summary() {
  "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity

eng = AccessGovernanceEngine()
eng.register_identity(make_identity("user-a"))
print(json.dumps(eng.summary(), indent=2))
PYEOF
}

cmd_report() {
  "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.access_governance_engine import (
    AccessGovernanceEngine, make_permission, make_role, make_identity
)

eng = AccessGovernanceEngine()
admin = eng.register_role(make_role("admin", [make_permission("iam", "admin")], is_privileged=True))
id1 = eng.register_identity(make_identity("svc-a"))
eng.assign_role(id1.identity_id, admin.role_id)
eng.set_least_privilege_baseline(id1.identity_id, [])
eng.scan_all_drift()
print(json.dumps(eng.generate_report().to_dict(), indent=2))
PYEOF
}

cmd_persist() {
  "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity

eng = AccessGovernanceEngine()
eng.register_identity(make_identity("persist-user"))
path = eng.persist_state('${PROJECT_ROOT}/artifacts/phase61/access-governance.json')
print(f"State persisted to: {path}")
PYEOF
}

case "$MODE" in
  demo) cmd_demo ;;
  summary) cmd_summary ;;
  report) cmd_report ;;
  persist) cmd_persist ;;
  *)
    log_error "Unknown mode '$MODE'. Usage: $0 [demo|summary|report|persist]"
    exit 1
    ;;
esac
