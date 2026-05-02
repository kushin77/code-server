#!/bin/bash
# @file phase-63-attack-surface-management.sh
# @description Phase 63 — Attack Surface Exposure Management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..." >&2; rm -f /tmp/p63*.tmp 2>/dev/null || true' EXIT

MODE="${1:-demo}"

cmd_demo() {
  log_info "Running Phase 63 Attack Surface Management demo"
  "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.attack_surface_management import (
    AttackSurfaceManagementEngine,
    AssetType,
    ExposureCategory,
    ExposureSeverity,
    RemediationStatus,
    make_asset,
    make_exposure,
)

eng = AttackSurfaceManagementEngine()

api = eng.register_asset(make_asset("public-api", AssetType.API, internet_facing=True, owner_team="platform", criticality=5))
admin = eng.register_asset(make_asset("admin-panel", AssetType.WEB_APP, internet_facing=True, owner_team="security", criticality=5))
redis = eng.register_asset(make_asset("cache-internal", AssetType.DATABASE, internet_facing=False, owner_team="data", criticality=3))

f1 = eng.add_exposure(make_exposure(api.asset_id, "Unauthenticated endpoint", ExposureCategory.WEAK_AUTH, ExposureSeverity.CRITICAL))
f2 = eng.add_exposure(make_exposure(admin.asset_id, "Admin panel open to internet", ExposureCategory.EXPOSED_ADMIN_INTERFACE, ExposureSeverity.HIGH))
f3 = eng.add_exposure(make_exposure(redis.asset_id, "Missing TLS", ExposureCategory.MISSING_ENCRYPTION, ExposureSeverity.MEDIUM))

eng.assign_remediation(f1.finding_id, "secops", "2026-05-07")
eng.assign_remediation(f2.finding_id, "platform", "2026-05-05")
eng.update_task_status(eng.remediation_tasks()[0].task_id, RemediationStatus.DONE, "WAF auth policy enabled")
eng.accept_risk(f3.finding_id)

summary = eng.summary()
print("============================================================")
print("PHASE 63 — ATTACK SURFACE MANAGEMENT")
print("============================================================")
print(f"Assets tracked: {summary['total_assets']}")
print(f"Internet-facing assets: {summary['internet_facing_assets']}")
print(f"Total findings: {summary['total_findings']}")
print(f"Active findings: {summary['active_findings']}")
print(f"Critical findings: {summary['critical_findings']}")
print(f"Remediation coverage: {summary['remediation_coverage_pct']}%")
print(f"Phase 63 score: {summary['phase63_score']}/25")
PYEOF
}

cmd_summary() {
  "$PYTHON_CMD" - <<PYEOF
import json
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.attack_surface_management import AttackSurfaceManagementEngine

eng = AttackSurfaceManagementEngine()
print(json.dumps(eng.summary(), indent=2))
PYEOF
}

cmd_report() {
  "$PYTHON_CMD" - <<PYEOF
import json
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.attack_surface_management import (
    AttackSurfaceManagementEngine,
    AssetType,
    ExposureCategory,
    ExposureSeverity,
    make_asset,
    make_exposure,
)

eng = AttackSurfaceManagementEngine()
asset = eng.register_asset(make_asset("prod-api", AssetType.API, internet_facing=True))
eng.add_exposure(make_exposure(asset.asset_id, "Open admin endpoint", ExposureCategory.EXPOSED_ADMIN_INTERFACE, ExposureSeverity.HIGH))
print(json.dumps(eng.generate_report().to_dict(), indent=2))
PYEOF
}

cmd_persist() {
  "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset

eng = AttackSurfaceManagementEngine()
eng.register_asset(make_asset("persist-asset"))
out = eng.persist_state('${PROJECT_ROOT}/artifacts/phase63/attack-surface-report.json')
print(f"State persisted to: {out}")
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
