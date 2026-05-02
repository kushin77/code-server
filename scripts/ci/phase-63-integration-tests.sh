#!/bin/bash
# @file phase-63-integration-tests.sh
# @description Integration tests for Phase 63 — Attack Surface Exposure Management

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p63*.* 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
  local name="$1" cmd="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $name"; PASS=$((PASS + 1))
  else
    echo "  ✗ $name"; FAIL=$((FAIL + 1))
  fi
}

run_python_test() {
  local name="$1" code="$2"
  TOTAL=$((TOTAL + 1))
  if "$PYTHON_CMD" - <<PYEOF >/dev/null 2>&1
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
$code
PYEOF
  then
    echo "  ✓ $name"; PASS=$((PASS + 1))
  else
    echo "  ✗ $name"; FAIL=$((FAIL + 1))
  fi
}

echo "============================================================"
echo "PHASE 63: ATTACK SURFACE MANAGEMENT — INTEGRATION TESTS"
echo "============================================================"

# Group 1: imports and enums
run_python_test "Import engine" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine"
run_python_test "Import dataclasses" "from security_ai.attack_surface_management import AttackSurfaceAsset, ExposureFinding, RemediationTask, ExposureReport"
run_python_test "Import helpers" "from security_ai.attack_surface_management import make_asset, make_exposure"
run_python_test "AssetType has 8 values" "from security_ai.attack_surface_management import AssetType; assert len(list(AssetType)) == 8"
run_python_test "ExposureSeverity has 4 values" "from security_ai.attack_surface_management import ExposureSeverity; assert len(list(ExposureSeverity)) == 4"
run_python_test "ExposureCategory has 7 values" "from security_ai.attack_surface_management import ExposureCategory; assert len(list(ExposureCategory)) == 7"
run_python_test "ExposureStatus has 4 values" "from security_ai.attack_surface_management import ExposureStatus; assert len(list(ExposureStatus)) == 4"
run_python_test "RemediationStatus has 4 values" "from security_ai.attack_surface_management import RemediationStatus; assert len(list(RemediationStatus)) == 4"

# Group 2: asset model
run_python_test "make_asset populates name" "from security_ai.attack_surface_management import make_asset; a=make_asset('api'); assert a.name=='api'"
run_python_test "Asset to_dict contains required keys" "from security_ai.attack_surface_management import make_asset; d=make_asset('a').to_dict(); assert 'asset_id' in d and 'internet_facing' in d"
run_python_test "internet_facing default is true" "from security_ai.attack_surface_management import make_asset; assert make_asset('a').internet_facing"
run_python_test "criticality preserved" "from security_ai.attack_surface_management import make_asset; assert make_asset('a', criticality=5).criticality==5"

# Group 3: finding model
run_python_test "make_exposure binds asset_id" "from security_ai.attack_surface_management import make_exposure; f=make_exposure('aid','title'); assert f.asset_id=='aid'"
run_python_test "Finding starts active" "from security_ai.attack_surface_management import make_exposure; assert make_exposure('aid','t').is_active()"
run_python_test "resolve() marks resolved" "from security_ai.attack_surface_management import make_exposure, ExposureStatus; f=make_exposure('aid','t'); f.resolve(); assert f.status==ExposureStatus.RESOLVED"
run_python_test "accept_risk() changes status" "from security_ai.attack_surface_management import make_exposure, ExposureStatus; f=make_exposure('aid','t'); f.accept_risk(); assert f.status==ExposureStatus.ACCEPTED_RISK"
run_python_test "start_remediation() changes status" "from security_ai.attack_surface_management import make_exposure, ExposureStatus; f=make_exposure('aid','t'); f.start_remediation(); assert f.status==ExposureStatus.IN_REMEDIATION"
run_python_test "to_dict includes severity and category" "from security_ai.attack_surface_management import make_exposure; d=make_exposure('a','t').to_dict(); assert 'severity' in d and 'category' in d"

# Group 4: registration and queries
run_python_test "register_asset stores asset" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('svc')); assert e.get_asset(a.asset_id) is not None"
run_python_test "assets() returns list" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert isinstance(e.assets(), list)"
run_python_test "internet_facing_assets() filters correctly" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset; e=AttackSurfaceManagementEngine(); e.register_asset(make_asset('a', internet_facing=True)); e.register_asset(make_asset('b', internet_facing=False)); assert len(e.internet_facing_assets())==1"
run_python_test "add_exposure rejects unknown asset" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_exposure; e=AttackSurfaceManagementEngine();
try: e.add_exposure(make_exposure('missing','x')); assert False
except KeyError: pass"
run_python_test "add_exposure stores finding" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('svc')); f=e.add_exposure(make_exposure(a.asset_id,'x')); assert e.get_finding(f.finding_id) is not None"
run_python_test "findings_for_asset filters" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure; e=AttackSurfaceManagementEngine(); a1=e.register_asset(make_asset('a1')); a2=e.register_asset(make_asset('a2')); e.add_exposure(make_exposure(a1.asset_id,'x')); e.add_exposure(make_exposure(a2.asset_id,'y')); assert len(e.findings_for_asset(a1.asset_id))==1"

# Group 5: severity and status queries
run_python_test "exposures_by_severity works" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure, ExposureSeverity; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); e.add_exposure(make_exposure(a.asset_id,'c',severity=ExposureSeverity.CRITICAL)); e.add_exposure(make_exposure(a.asset_id,'h',severity=ExposureSeverity.HIGH)); assert len(e.exposures_by_severity(ExposureSeverity.CRITICAL))==1"
run_python_test "critical_exposures proxies severity query" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure, ExposureSeverity; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); e.add_exposure(make_exposure(a.asset_id,'c',severity=ExposureSeverity.CRITICAL)); assert len(e.critical_exposures())==1"
run_python_test "unresolved_exposures only active" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); f1=e.add_exposure(make_exposure(a.asset_id,'x')); f2=e.add_exposure(make_exposure(a.asset_id,'y')); e.resolve_exposure(f1.finding_id); assert len(e.unresolved_exposures())==1"
run_python_test "resolve_exposure false on unknown" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert not e.resolve_exposure('missing')"
run_python_test "accept_risk false on unknown" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert not e.accept_risk('missing')"
run_python_test "start_remediation false on unknown" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert not e.start_remediation('missing')"

# Group 6: task workflow
run_python_test "assign_remediation creates task" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); f=e.add_exposure(make_exposure(a.asset_id,'x')); t=e.assign_remediation(f.finding_id,'secops'); assert t is not None"
run_python_test "assign_remediation sets finding in_remediation" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure, ExposureStatus; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); f=e.add_exposure(make_exposure(a.asset_id,'x')); e.assign_remediation(f.finding_id,'secops'); assert e.get_finding(f.finding_id).status==ExposureStatus.IN_REMEDIATION"
run_python_test "assign_remediation returns None on unknown finding" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert e.assign_remediation('missing','x') is None"
run_python_test "update_task_status false on missing task" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, RemediationStatus; e=AttackSurfaceManagementEngine(); assert not e.update_task_status('missing', RemediationStatus.DONE)"
run_python_test "update_task_status done resolves finding" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure, RemediationStatus, ExposureStatus; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); f=e.add_exposure(make_exposure(a.asset_id,'x')); t=e.assign_remediation(f.finding_id,'secops'); e.update_task_status(t.task_id, RemediationStatus.DONE); assert e.get_finding(f.finding_id).status==ExposureStatus.RESOLVED"
run_python_test "remediation_tasks returns list" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert isinstance(e.remediation_tasks(), list)"

# Group 7: coverage and reports
run_python_test "remediation_coverage 100 when no active findings" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert e.remediation_coverage_pct()==100.0"
run_python_test "remediation_coverage calculates correctly" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); f1=e.add_exposure(make_exposure(a.asset_id,'1')); f2=e.add_exposure(make_exposure(a.asset_id,'2')); e.assign_remediation(f1.finding_id,'secops'); assert e.remediation_coverage_pct()==50.0"
run_python_test "generate_report returns report dataclass" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, ExposureReport; e=AttackSurfaceManagementEngine(); r=e.generate_report(); assert isinstance(r, ExposureReport)"
run_python_test "report to_dict includes phase63_score" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); d=e.generate_report().to_dict(); assert 'phase63_score' in d"
run_python_test "phase63_score bounded" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); s=e.phase63_score(); assert 0.0 <= s <= 25.0"
run_python_test "summary has required keys" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); s=e.summary(); assert all(k in s for k in ['status','total_assets','active_findings','phase63_score'])"

# Group 8: scoring behavior
run_python_test "empty score is 25" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert e.phase63_score()==25.0"
run_python_test "critical finding reduces score" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure, ExposureSeverity; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); e.add_exposure(make_exposure(a.asset_id,'x',severity=ExposureSeverity.CRITICAL)); assert e.phase63_score() < 25.0"
run_python_test "high finding reduces score" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure, ExposureSeverity; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a')); e.add_exposure(make_exposure(a.asset_id,'x',severity=ExposureSeverity.HIGH)); assert e.phase63_score() < 25.0"
run_python_test "internet-facing active penalty applies" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure; e=AttackSurfaceManagementEngine(); a=e.register_asset(make_asset('a', internet_facing=True)); e.add_exposure(make_exposure(a.asset_id,'x')); assert e.phase63_score() <= 20.0"
run_python_test "score floors at zero under severe risk" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine, make_asset, make_exposure, ExposureSeverity; e=AttackSurfaceManagementEngine();
for i in range(10):
 a=e.register_asset(make_asset(f'a{i}', internet_facing=True)); e.add_exposure(make_exposure(a.asset_id,'x',severity=ExposureSeverity.CRITICAL))
assert e.phase63_score()==0.0"

# Group 9: persistence and helpers
run_python_test "persist_state writes file" "import os, tempfile; from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); d=tempfile.mkdtemp(); p=e.persist_state(os.path.join(d,'state.json')); assert os.path.exists(p)"
run_python_test "helper make_asset supports non-internet-facing" "from security_ai.attack_surface_management import make_asset; a=make_asset('x', internet_facing=False); assert not a.internet_facing"
run_python_test "helper make_exposure stores evidence" "from security_ai.attack_surface_management import make_exposure; f=make_exposure('a','x', evidence={'k':'v'}); assert f.evidence.get('k')=='v'"
run_python_test "findings() returns list" "from security_ai.attack_surface_management import AttackSurfaceManagementEngine; e=AttackSurfaceManagementEngine(); assert isinstance(e.findings(), list)"

# Group 10: ops script
run_test "Ops script exists and executable" "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-63-attack-surface-management.sh' ]]"
run_test "Ops demo prints PHASE 63" "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-63-attack-surface-management.sh' demo 2>&1 | grep -q 'PHASE 63'"
run_test "Ops summary outputs valid JSON" "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-63-attack-surface-management.sh' summary 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json;json.load(sys.stdin)'"
run_test "Ops report outputs valid JSON" "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-63-attack-surface-management.sh' report 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json;json.load(sys.stdin)'"
run_test "Ops persist writes artifact path" "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-63-attack-surface-management.sh' persist | grep -q 'State persisted to'"

# Group 11: regression guard
if [[ -z "${SKIP_REGRESSION:-}" ]]; then
  run_test "Phase 62 suite still passes" "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-62-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
  echo "  ⏭  Phase 62 regression skipped (SKIP_REGRESSION=1)"
fi

echo "============================================================"
echo "PHASE 63 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "✅  ALL TESTS PASSED — Phase 63 Attack Surface Management verified"
  exit 0
else
  echo "❌  SOME TESTS FAILED — Review output above"
  exit 1
fi
