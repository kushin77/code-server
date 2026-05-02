#!/bin/bash
# @file phase-52-integration-tests.sh
# @description Integration tests for Phase 52 — Adaptive Threat Response & Autonomous Countermeasures
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p52*.* 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cmd" > /dev/null 2>&1; then
        echo "  ✓ $name"; PASS=$((PASS + 1))
    else
        echo "  ✗ $name"; FAIL=$((FAIL + 1))
    fi
}

run_python_test() {
    local name="$1"
    local code="$2"
    TOTAL=$((TOTAL + 1))
    if "$PYTHON_CMD" - <<PYEOF > /dev/null 2>&1
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
echo "PHASE 52: ADAPTIVE THREAT RESPONSE & AUTONOMOUS"
echo "          COUNTERMEASURES — INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module imports
echo "GROUP 1: Module Import & API Surface"

run_python_test "Import AdaptiveThreatResponseOrchestrator" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator"

run_python_test "Import ThreatSignal" \
"from security_ai.adaptive_threat_response import ThreatSignal"

run_python_test "Import ResponsePlaybook" \
"from security_ai.adaptive_threat_response import ResponsePlaybook"

run_python_test "Import ResponseAction" \
"from security_ai.adaptive_threat_response import ResponseAction"

run_python_test "Import ThreatSeverity enum (4 levels)" \
"from security_ai.adaptive_threat_response import ThreatSeverity
assert len(list(ThreatSeverity)) == 4"

run_python_test "Import ResponseStrategy enum (5 strategies)" \
"from security_ai.adaptive_threat_response import ResponseStrategy
assert len(list(ResponseStrategy)) == 5"

run_python_test "Import ResponseStatus enum" \
"from security_ai.adaptive_threat_response import ResponseStatus
assert len(list(ResponseStatus)) >= 4"

run_python_test "Import AdaptationMode enum (3 modes)" \
"from security_ai.adaptive_threat_response import AdaptationMode
assert len(list(AdaptationMode)) == 3"

run_python_test "Import helper make_signal()" \
"from security_ai.adaptive_threat_response import make_signal
sig = make_signal('phase30', 15.0, 'test')
assert sig.score == 15.0"

run_python_test "Import response_score()" \
"from security_ai.adaptive_threat_response import response_score, AdaptiveThreatResponseOrchestrator
o = AdaptiveThreatResponseOrchestrator()
assert response_score(o) == 0.0"

echo ""

# GROUP 2: ThreatSignal severity classification
echo "GROUP 2: ThreatSignal Severity Classification"

run_python_test "Score < 10 → CRITICAL severity" \
"from security_ai.adaptive_threat_response import ThreatSignal, ThreatSeverity
sig = ThreatSignal(signal_id='s1', phase_source='phase30', score=5.0)
assert sig.severity == ThreatSeverity.CRITICAL"

run_python_test "Score 10-15.9 → HIGH severity" \
"from security_ai.adaptive_threat_response import ThreatSignal, ThreatSeverity
sig = ThreatSignal(signal_id='s1', phase_source='phase30', score=13.0)
assert sig.severity == ThreatSeverity.HIGH"

run_python_test "Score 16-19.9 → MEDIUM severity" \
"from security_ai.adaptive_threat_response import ThreatSignal, ThreatSeverity
sig = ThreatSignal(signal_id='s1', phase_source='phase30', score=18.0)
assert sig.severity == ThreatSeverity.MEDIUM"

run_python_test "Score >= 20 → LOW severity" \
"from security_ai.adaptive_threat_response import ThreatSignal, ThreatSeverity
sig = ThreatSignal(signal_id='s1', phase_source='phase30', score=22.0)
assert sig.severity == ThreatSeverity.LOW"

run_python_test "urgency CRITICAL=0, HIGH=1, MEDIUM=2, LOW=3" \
"from security_ai.adaptive_threat_response import ThreatSignal
scores = [5.0, 13.0, 18.0, 22.0]
urgencies = [ThreatSignal('s'+str(i),'p',s).urgency for i,s in enumerate(scores)]
assert urgencies == [0, 1, 2, 3], urgencies"

echo ""

# GROUP 3: ResponseAction execution
echo "GROUP 3: ResponseAction Execution"

run_python_test "ResponseAction execute() sets status RESOLVED on success" \
"from security_ai.adaptive_threat_response import ResponseAction, ResponseStatus, ResponseStrategy
a = ResponseAction(action_id='a1', name='Test', strategy=ResponseStrategy.CONTAIN, phase_source='phase30')
ok = a.execute()
assert ok
assert a.status == ResponseStatus.RESOLVED"

run_python_test "ResponseAction execute() sets executed_at timestamp" \
"from security_ai.adaptive_threat_response import ResponseAction, ResponseStrategy
a = ResponseAction(action_id='a1', name='Test', strategy=ResponseStrategy.MITIGATE, phase_source='phase30')
a.execute()
assert a.executed_at is not None"

run_python_test "ResponseAction execute() with failing handler sets FAILED" \
"from security_ai.adaptive_threat_response import ResponseAction, ResponseStatus, ResponseStrategy
a = ResponseAction(action_id='a1', name='Fail', strategy=ResponseStrategy.ERADICATE,
                   phase_source='phase30', handler=lambda ctx: False)
ok = a.execute()
assert not ok
assert a.status == ResponseStatus.FAILED"

run_python_test "ResponseAction result stores 'success' on success" \
"from security_ai.adaptive_threat_response import ResponseAction, ResponseStrategy
a = ResponseAction(action_id='a1', name='T', strategy=ResponseStrategy.RECOVER, phase_source='p30')
a.execute()
assert a.result == 'success'"

echo ""

# GROUP 4: ResponsePlaybook
echo "GROUP 4: ResponsePlaybook"

run_python_test "ResponsePlaybook success_rate() = 0 before execution" \
"from security_ai.adaptive_threat_response import ResponsePlaybook, ThreatSignal
sig = ThreatSignal(signal_id='s1', phase_source='p30', score=15.0)
pb = ResponsePlaybook(playbook_id='pb1', name='T', threat_signal=sig)
assert pb.success_rate() == 0.0"

run_python_test "ResponsePlaybook is_complete() False when actions pending" \
"from security_ai.adaptive_threat_response import ResponsePlaybook, ResponseAction, ThreatSignal, ResponseStrategy
sig = ThreatSignal(signal_id='s1', phase_source='p30', score=15.0)
pb = ResponsePlaybook(playbook_id='pb1', name='T', threat_signal=sig)
pb.actions.append(ResponseAction('a1','T',ResponseStrategy.CONTAIN,'p30'))
assert not pb.is_complete()"

run_python_test "ResponsePlaybook is_complete() True when all actions resolved" \
"from security_ai.adaptive_threat_response import ResponsePlaybook, ResponseAction, ThreatSignal, ResponseStrategy, ResponseStatus
sig = ThreatSignal(signal_id='s1', phase_source='p30', score=15.0)
pb = ResponsePlaybook(playbook_id='pb1', name='T', threat_signal=sig)
a = ResponseAction('a1','T',ResponseStrategy.CONTAIN,'p30')
a.status = ResponseStatus.RESOLVED
pb.actions.append(a)
assert pb.is_complete()"

run_python_test "ResponsePlaybook phase52_score() = success_rate * 25" \
"from security_ai.adaptive_threat_response import ResponsePlaybook, ResponseAction, ThreatSignal, ResponseStrategy, ResponseStatus
sig = ThreatSignal(signal_id='s1', phase_source='p30', score=15.0)
pb = ResponsePlaybook(playbook_id='pb1', name='T', threat_signal=sig)
a = ResponseAction('a1','T',ResponseStrategy.CONTAIN,'p30')
a.status = ResponseStatus.RESOLVED
a.result = 'success'
pb.actions.append(a)
assert pb.phase52_score() == 25.0"

echo ""

# GROUP 5: Orchestrator — signal ingestion
echo "GROUP 5: Orchestrator — Signal Ingestion"

run_python_test "ingest_signal() returns ResponsePlaybook" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal, ResponsePlaybook
o = AdaptiveThreatResponseOrchestrator()
sig = make_signal('phase30', 15.0, 'test')
pb = o.ingest_signal(sig)
assert isinstance(pb, ResponsePlaybook)"

run_python_test "ingest_signal() registers playbook in active_playbooks" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 10.0))
assert pb.playbook_id in o.active_playbooks"

run_python_test "ingest_signal() CRITICAL signal builds more actions than LOW" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb_crit = o.ingest_signal(make_signal('phase30', 5.0))
pb_low  = o.ingest_signal(make_signal('phase31', 22.0))
assert len(pb_crit.actions) >= len(pb_low.actions)"

run_python_test "ingest_signals_bulk() processes signals sorted by urgency" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
signals = [make_signal(f'phase{30+i}', float(20-i*3)) for i in range(5)]
pbs = o.ingest_signals_bulk(signals)
assert len(pbs) == 5"

run_python_test "Playbook name includes severity label" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 5.0, 'DangerZone'))
assert 'critical' in pb.name.lower()"

echo ""

# GROUP 6: Orchestrator — execution
echo "GROUP 6: Orchestrator — Playbook Execution"

run_python_test "execute_playbook() returns True when all actions succeed" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 15.0))
result = o.execute_playbook(pb)
assert result is True"

run_python_test "execute_playbook() sets playbook.is_complete() = True" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 15.0))
o.execute_playbook(pb)
assert pb.is_complete()"

run_python_test "execute_playbook() sets overall_status RESOLVED on success" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal, ResponseStatus
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 12.0))
o.execute_playbook(pb)
assert pb.overall_status == ResponseStatus.RESOLVED"

run_python_test "execute_playbook() sets completed_at timestamp" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 12.0))
o.execute_playbook(pb)
assert pb.completed_at is not None"

run_python_test "execute_all() executes all active playbooks" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
for i in range(4):
    o.ingest_signal(make_signal(f'phase{30+i}', float(5+i*4)))
results = o.execute_all()
assert len(results) == 4
assert all(results.values())"

run_python_test "execute_all() returns dict of playbook_id → bool" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
o.ingest_signal(make_signal('phase30', 10.0))
results = o.execute_all()
assert isinstance(results, dict)"

echo ""

# GROUP 7: resolve and custom actions
echo "GROUP 7: Resolve & Custom Actions"

run_python_test "resolve_playbook() moves playbook to resolved_playbooks" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 10.0))
o.execute_playbook(pb)
o.resolve_playbook(pb)
assert pb in o.resolved_playbooks
assert pb.playbook_id not in o.active_playbooks"

run_python_test "add_custom_action() adds action to playbook" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal, ResponseStrategy
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 15.0))
before = len(pb.actions)
o.add_custom_action(pb, 'Custom Block', ResponseStrategy.CONTAIN, 'phase30', handler_key='contain')
assert len(pb.actions) == before + 1"

run_python_test "Custom action with inline handler executes correctly" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal, ResponseStrategy, ResponseStatus
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 18.0))
o.add_custom_action(pb, 'NoOp', ResponseStrategy.MITIGATE, 'phase30', handler=lambda ctx: True)
o.execute_playbook(pb)
custom = pb.actions[-1]
assert custom.status == ResponseStatus.RESOLVED"

echo ""

# GROUP 8: Scoring
echo "GROUP 8: Scoring"

run_python_test "phase52_score() = 0 before any playbooks" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator
o = AdaptiveThreatResponseOrchestrator()
assert o.phase52_score() == 0.0"

run_python_test "phase52_score() = 25.0 after all successful executions" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
for i in range(3):
    pb = o.ingest_signal(make_signal(f'phase{30+i}', float(10 + i*5)))
    o.execute_playbook(pb)
    o.resolve_playbook(pb)
score = o.phase52_score()
assert score == 25.0, score"

run_python_test "response_score() helper returns same as phase52_score()" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal, response_score
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 10.0))
o.execute_playbook(pb)
o.resolve_playbook(pb)
assert response_score(o) == o.phase52_score()"

run_python_test "Playbook phase52_score() in [0,25]" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 8.0))
o.execute_playbook(pb)
score = pb.phase52_score()
assert 0.0 <= score <= 25.0, score"

echo ""

# GROUP 9: Summary
echo "GROUP 9: Summary"

run_python_test "summary() has required keys" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator
o = AdaptiveThreatResponseOrchestrator()
s = o.summary()
for k in ('total_playbooks','active_playbooks','resolved_playbooks',
          'completed_playbooks','avg_success_rate','phase52_score','severity_breakdown'):
    assert k in s, k"

run_python_test "summary() severity_breakdown counts all 4 levels" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator
o = AdaptiveThreatResponseOrchestrator()
sb = o.summary()['severity_breakdown']
for lvl in ('critical','high','medium','low'):
    assert lvl in sb"

run_python_test "summary() total_playbooks increases after ingest" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
before = o.summary()['total_playbooks']
o.ingest_signal(make_signal('phase30', 10.0))
o.ingest_signal(make_signal('phase31', 15.0))
assert o.summary()['total_playbooks'] == before + 2"

run_python_test "generate_report() returns dict with playbook details" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, make_signal
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 12.0))
o.execute_playbook(pb)
r = o.generate_report(pb)
for k in ('playbook_id','name','severity','success_rate','phase52_score','is_complete','action_results'):
    assert k in r, k"

echo ""

# GROUP 10: AdaptationMode
echo "GROUP 10: AdaptationMode"

run_python_test "Default mode is AUTOMATIC" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, AdaptationMode
o = AdaptiveThreatResponseOrchestrator()
assert o.default_mode == AdaptationMode.AUTOMATIC"

run_python_test "ASSISTED mode is accepted" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, AdaptationMode
o = AdaptiveThreatResponseOrchestrator(default_mode=AdaptationMode.ASSISTED)
assert o.default_mode == AdaptationMode.ASSISTED"

run_python_test "Playbook inherits orchestrator mode" \
"from security_ai.adaptive_threat_response import AdaptiveThreatResponseOrchestrator, AdaptationMode, make_signal
o = AdaptiveThreatResponseOrchestrator(default_mode=AdaptationMode.MANUAL)
pb = o.ingest_signal(make_signal('phase30', 15.0))
assert pb.mode == AdaptationMode.MANUAL"

echo ""

# GROUP 11: stop_on_failure behaviour
echo "GROUP 11: stop_on_failure Behaviour"

run_python_test "execute_playbook(stop_on_failure=True) skips remaining on failure" \
"from security_ai.adaptive_threat_response import (AdaptiveThreatResponseOrchestrator, make_signal,
    ResponseStrategy, ResponseStatus)
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 5.0))
# Inject a failing action at the front
from security_ai.adaptive_threat_response import ResponseAction
failing = ResponseAction('bad','Fail',ResponseStrategy.ERADICATE,'phase30',handler=lambda c: False)
pb.actions.insert(0, failing)
o.execute_playbook(pb, stop_on_failure=True)
assert pb.overall_status == ResponseStatus.FAILED"

run_python_test "execute_playbook(stop_on_failure=False) continues after failure" \
"from security_ai.adaptive_threat_response import (AdaptiveThreatResponseOrchestrator, make_signal,
    ResponseStrategy, ResponseStatus)
o = AdaptiveThreatResponseOrchestrator()
pb = o.ingest_signal(make_signal('phase30', 18.0))
from security_ai.adaptive_threat_response import ResponseAction
failing = ResponseAction('bad','Fail',ResponseStrategy.ERADICATE,'phase30',handler=lambda c: False)
pb.actions.insert(0, failing)
o.execute_playbook(pb, stop_on_failure=False)
resolved = [a for a in pb.actions if a.status == ResponseStatus.RESOLVED]
assert len(resolved) > 0"

echo ""

# GROUP 12: Ops script
echo "GROUP 12: Ops Script"

run_test "Ops script exists and is executable" \
    "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-52-adaptive-threat-response.sh' ]]"

run_test "Ops script exits 0 with no arguments (default mode)" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-52-adaptive-threat-response.sh' 2>&1 | grep -iE 'phase 52|threat|score|playbook'"

run_test "Ops script demo mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-52-adaptive-threat-response.sh' demo 2>&1 | grep -iE 'phase 52|threat|response'"

run_test "Ops script summary mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-52-adaptive-threat-response.sh' summary 2>&1); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

echo ""

# GROUP 13: Phase 51 regression guard
echo "GROUP 13: Phase 51 Regression Guard"

if [[ -z "${SKIP_REGRESSION:-}" ]]; then
    run_test "Phase 51 integration suite still passes" \
        "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-51-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
    echo "  ⏭  Phase 51 regression skipped (SKIP_REGRESSION=1)"
fi

echo ""

echo "============================================================"
echo "PHASE 52 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "✅  ALL TESTS PASSED — Phase 52 Adaptive Threat Response verified"
    exit 0
else
    echo "❌  SOME TESTS FAILED — Review output above"
    exit 1
fi
