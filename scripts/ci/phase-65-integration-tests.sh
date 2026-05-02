#!/bin/bash
# @file phase-65-integration-tests.sh
# @description Integration tests for Phase 65 — Insider Threat Detection Engine

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p65*.* 2>/dev/null || true' EXIT

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
echo "PHASE 65: INSIDER THREAT DETECTION — INTEGRATION TESTS"
echo "============================================================"

# Group 1: imports
echo "GROUP 1: Imports"
run_python_test "Import engine" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine"
run_python_test "Import models" "from security_ai.insider_threat_detection_engine import BehaviorEvent, BaselineProfile, InsiderAlert, InsiderThreatReport"
run_python_test "ActorType size" "from security_ai.insider_threat_detection_engine import ActorType; assert len(list(ActorType))==3"
run_python_test "EventType size" "from security_ai.insider_threat_detection_engine import EventType; assert len(list(EventType))==5"
run_python_test "RiskLevel size" "from security_ai.insider_threat_detection_engine import RiskLevel; assert len(list(RiskLevel))==5"
run_python_test "AlertStatus size" "from security_ai.insider_threat_detection_engine import AlertStatus; assert len(list(AlertStatus))==4"
run_python_test "Helpers import" "from security_ai.insider_threat_detection_engine import make_event, make_baseline"

# Group 2: model behavior
echo "GROUP 2: Models"
run_python_test "BehaviorEvent to_dict keys" "from security_ai.insider_threat_detection_engine import make_event, EventType; d=make_event('u1', EventType.LOGIN).to_dict(); assert 'event_id' in d and 'event_type' in d"
run_python_test "Baseline to_dict keys" "from security_ai.insider_threat_detection_engine import make_baseline; d=make_baseline('u1').to_dict(); assert 'actor_id' in d and 'allowed_resources' in d"
run_python_test "Alert active when open" "from security_ai.insider_threat_detection_engine import InsiderAlert; a=InsiderAlert(); assert a.is_active()"
run_python_test "Alert inactive when resolved" "from security_ai.insider_threat_detection_engine import InsiderAlert, AlertStatus; a=InsiderAlert(status=AlertStatus.RESOLVED); assert not a.is_active()"
run_python_test "Report score bounded" "from security_ai.insider_threat_detection_engine import InsiderThreatReport; r=InsiderThreatReport(active_alerts=1, critical_alerts=2, high_alerts=1); s=r.phase65_score(); assert 0<=s<=25"

# Group 3: baseline + ingest
echo "GROUP 3: Baseline and Ingest"
run_python_test "Set/get baseline" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline; e=InsiderThreatDetectionEngine(); b=make_baseline('alice'); e.set_baseline(b); assert e.get_baseline('alice').actor_id=='alice'"
run_python_test "No baseline triggers medium alert" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_event, EventType, RiskLevel; e=InsiderThreatDetectionEngine(); a=e.ingest_event(make_event('x', EventType.LOGIN)); assert a and a.risk==RiskLevel.MEDIUM"
run_python_test "Large export triggers critical" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline, make_event, EventType, RiskLevel; e=InsiderThreatDetectionEngine(); e.set_baseline(make_baseline('alice', max_daily_exports_gb=1.0)); a=e.ingest_event(make_event('alice', EventType.DATA_EXPORT, metadata={'export_gb':3.2})); assert a and a.risk==RiskLevel.CRITICAL"
run_python_test "Excess privilege changes triggers high" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline, make_event, EventType, RiskLevel; e=InsiderThreatDetectionEngine(); e.set_baseline(make_baseline('alice', max_privilege_changes_per_day=1)); e.ingest_event(make_event('alice', EventType.PRIVILEGE_CHANGE)); a=e.ingest_event(make_event('alice', EventType.PRIVILEGE_CHANGE)); assert a and a.risk==RiskLevel.HIGH"
run_python_test "Unexpected resource triggers high" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline, make_event, EventType, RiskLevel; e=InsiderThreatDetectionEngine(); e.set_baseline(make_baseline('alice', allowed_resources=['safe'])); a=e.ingest_event(make_event('alice', EventType.FILE_ACCESS, resource='secret')); assert a and a.risk==RiskLevel.HIGH"
run_python_test "Unexpected region triggers medium" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline, make_event, EventType, RiskLevel; e=InsiderThreatDetectionEngine(); e.set_baseline(make_baseline('alice', expected_regions=['us-east-1'])); a=e.ingest_event(make_event('alice', EventType.LOGIN, metadata={'region':'eu-west-1'})); assert a and a.risk==RiskLevel.MEDIUM"
run_python_test "Normal event returns no alert" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline, make_event, EventType; e=InsiderThreatDetectionEngine(); e.set_baseline(make_baseline('alice', expected_regions=['us-east-1'], allowed_resources=['safe'])); a=e.ingest_event(make_event('alice', EventType.FILE_ACCESS, resource='safe', metadata={'region':'us-east-1'})); assert a is None"

# Group 4: alert management
echo "GROUP 4: Alert Management"
run_python_test "alerts() returns list" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine; e=InsiderThreatDetectionEngine(); assert isinstance(e.alerts(), list)"
run_python_test "active_alerts filters by status" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_event, EventType; e=InsiderThreatDetectionEngine(); a=e.ingest_event(make_event('x', EventType.LOGIN)); e.resolve_alert(a.alert_id); assert len(e.active_alerts())==0"
run_python_test "resolve_alert true when found" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_event, EventType; e=InsiderThreatDetectionEngine(); a=e.ingest_event(make_event('x', EventType.LOGIN)); assert e.resolve_alert(a.alert_id)"
run_python_test "resolve_alert false when missing" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine; e=InsiderThreatDetectionEngine(); assert not e.resolve_alert('missing')"
run_python_test "suppress_alert true when found" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_event, EventType; e=InsiderThreatDetectionEngine(); a=e.ingest_event(make_event('x', EventType.LOGIN)); assert e.suppress_alert(a.alert_id)"
run_python_test "alerts_by_risk works" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline, make_event, EventType, RiskLevel; e=InsiderThreatDetectionEngine(); e.set_baseline(make_baseline('a', max_daily_exports_gb=1.0)); e.ingest_event(make_event('a', EventType.DATA_EXPORT, metadata={'export_gb':5})); assert len(e.alerts_by_risk(RiskLevel.CRITICAL))==1"

# Group 5: report + score
echo "GROUP 5: Report and Score"
run_python_test "generate_report returns dataclass" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, InsiderThreatReport; e=InsiderThreatDetectionEngine(); r=e.generate_report(); assert isinstance(r, InsiderThreatReport)"
run_python_test "phase65_score 25 when empty" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine; e=InsiderThreatDetectionEngine(); assert e.phase65_score()==25.0"
run_python_test "phase65_score decreases with critical" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline, make_event, EventType; e=InsiderThreatDetectionEngine(); e.set_baseline(make_baseline('a', max_daily_exports_gb=1.0)); e.ingest_event(make_event('a', EventType.DATA_EXPORT, metadata={'export_gb':5})); assert e.phase65_score()<25"
run_python_test "phase65_score floors at zero" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_baseline, make_event, EventType; e=InsiderThreatDetectionEngine(); e.set_baseline(make_baseline('a', max_daily_exports_gb=1.0, allowed_resources=['safe']));
for i in range(5): e.ingest_event(make_event('a', EventType.DATA_EXPORT, metadata={'export_gb':10+i}))
for i in range(5): e.ingest_event(make_event('a', EventType.FILE_ACCESS, resource='secret'))
assert e.phase65_score()==0.0"
run_python_test "summary has required keys" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine; e=InsiderThreatDetectionEngine(); s=e.summary(); assert all(k in s for k in ['status','total_events','total_alerts','phase65_score'])"
run_python_test "report to_dict includes phase65_score" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine; e=InsiderThreatDetectionEngine(); d=e.generate_report().to_dict(); assert 'phase65_score' in d"
run_python_test "events list populated" "from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine, make_event, EventType; e=InsiderThreatDetectionEngine(); e.ingest_event(make_event('x', EventType.LOGIN)); assert len(e.events())==1"

# Group 6: persist + ops
echo "GROUP 6: Persist and Ops"
run_python_test "persist_state writes file" "import os, tempfile; from security_ai.insider_threat_detection_engine import InsiderThreatDetectionEngine; e=InsiderThreatDetectionEngine(); d=tempfile.mkdtemp(); p=e.persist_state(os.path.join(d,'state.json')); assert os.path.exists(p)"
run_test "Ops script exists and executable" "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-65-insider-threat-detection.sh' ]]"
run_test "Ops demo contains PHASE 65" "out=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-65-insider-threat-detection.sh' demo 2>&1); echo \"\$out\" | grep -q 'PHASE 65'"
run_test "Ops summary outputs JSON" "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-65-insider-threat-detection.sh' summary 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json;json.load(sys.stdin)'"
run_test "Ops report outputs JSON" "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-65-insider-threat-detection.sh' report 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json;json.load(sys.stdin)'"
run_test "Ops persist writes output" "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-65-insider-threat-detection.sh' persist | grep -q 'State persisted to'"

# Group 7: regression guard
if [[ -z "${SKIP_REGRESSION:-}" ]]; then
  run_test "Phase 64 suite still passes" "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-64-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
  echo "  ⏭  Phase 64 regression skipped (SKIP_REGRESSION=1)"
fi

echo "============================================================"
echo "PHASE 65 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "✅  ALL TESTS PASSED — Phase 65 Insider Threat Detection verified"
  exit 0
else
  echo "❌  SOME TESTS FAILED — Review output above"
  exit 1
fi
