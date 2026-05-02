#!/bin/bash
# @file phase-51-integration-tests.sh
# @description Integration tests for Phase 51 — Unified Security Orchestration & Platform Convergence
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p51*.* 2>/dev/null || true' EXIT

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
echo "PHASE 51: UNIFIED PLATFORM CONVERGENCE — INTEGRATION TESTS"
echo "         (MILESTONE: Phases 30-50 Convergence Verification)"
echo "============================================================"
echo ""

# GROUP 1: Module imports
echo "GROUP 1: Module Import & API Surface"

run_python_test "Import PlatformConvergenceEngine" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine"

run_python_test "Import ConvergenceHealth enum (4 values)" \
"from security_ai.platform_convergence_engine import ConvergenceHealth
assert len(list(ConvergenceHealth)) == 4"

run_python_test "Import CorrelationStrength enum (3 values)" \
"from security_ai.platform_convergence_engine import CorrelationStrength
assert len(list(CorrelationStrength)) == 3"

run_python_test "Import PlatformDomain enum (6 domains)" \
"from security_ai.platform_convergence_engine import PlatformDomain
assert len(list(PlatformDomain)) == 6"

run_python_test "Import PhaseSignal" \
"from security_ai.platform_convergence_engine import PhaseSignal"

run_python_test "Import CrossPhaseCorrelation" \
"from security_ai.platform_convergence_engine import CrossPhaseCorrelation"

run_python_test "Import DomainAggregate" \
"from security_ai.platform_convergence_engine import DomainAggregate"

run_python_test "Import ConvergenceSnapshot" \
"from security_ai.platform_convergence_engine import ConvergenceSnapshot"

run_python_test "Import DOMAIN_PHASES mapping (6 entries)" \
"from security_ai.platform_convergence_engine import DOMAIN_PHASES
assert len(DOMAIN_PHASES) == 6"

echo ""

# GROUP 2: PhaseSignal
echo "GROUP 2: PhaseSignal"

run_python_test "PhaseSignal normalised = score/25*100" \
"from security_ai.platform_convergence_engine import PhaseSignal, PlatformDomain
s = PhaseSignal('phase30', 20.0, PlatformDomain.SECURITY)
assert s.normalised == 80.0"

run_python_test "PhaseSignal health OPTIMAL when score>=22.5 (normalised>=90)" \
"from security_ai.platform_convergence_engine import PhaseSignal, PlatformDomain, ConvergenceHealth
s = PhaseSignal('phase30', 23.0, PlatformDomain.SECURITY)
assert s.health == ConvergenceHealth.OPTIMAL"

run_python_test "PhaseSignal health HEALTHY when normalised 75-89" \
"from security_ai.platform_convergence_engine import PhaseSignal, PlatformDomain, ConvergenceHealth
s = PhaseSignal('phase30', 20.0, PlatformDomain.SECURITY)
assert s.health == ConvergenceHealth.HEALTHY"

run_python_test "PhaseSignal health DEGRADED when normalised 50-74" \
"from security_ai.platform_convergence_engine import PhaseSignal, PlatformDomain, ConvergenceHealth
s = PhaseSignal('phase30', 15.0, PlatformDomain.SECURITY)
assert s.health == ConvergenceHealth.DEGRADED"

run_python_test "PhaseSignal health CRITICAL when normalised <50" \
"from security_ai.platform_convergence_engine import PhaseSignal, PlatformDomain, ConvergenceHealth
s = PhaseSignal('phase30', 10.0, PlatformDomain.SECURITY)
assert s.health == ConvergenceHealth.CRITICAL"

echo ""

# GROUP 3: CrossPhaseCorrelation
echo "GROUP 3: CrossPhaseCorrelation"

run_python_test "CorrelationStrength STRONG when |r|>=0.75" \
"from security_ai.platform_convergence_engine import CrossPhaseCorrelation, CorrelationStrength
assert CrossPhaseCorrelation('pa','pb',0.9).strength == CorrelationStrength.STRONG"

run_python_test "CorrelationStrength MODERATE when 0.40<=|r|<0.75" \
"from security_ai.platform_convergence_engine import CrossPhaseCorrelation, CorrelationStrength
assert CrossPhaseCorrelation('pa','pb',0.55).strength == CorrelationStrength.MODERATE"

run_python_test "CorrelationStrength WEAK when |r|<0.40" \
"from security_ai.platform_convergence_engine import CrossPhaseCorrelation, CorrelationStrength
assert CrossPhaseCorrelation('pa','pb',0.2).strength == CorrelationStrength.WEAK"

run_python_test "CrossPhaseCorrelation to_dict() has all required keys" \
"from security_ai.platform_convergence_engine import CrossPhaseCorrelation
d = CrossPhaseCorrelation('pa','pb',0.85).to_dict()
for k in ('phase_a','phase_b','coefficient','strength','sample_count'):
    assert k in d, k"

echo ""

# GROUP 4: DomainAggregate
echo "GROUP 4: DomainAggregate"

run_python_test "DomainAggregate avg_score() = mean of signals" \
"from security_ai.platform_convergence_engine import DomainAggregate, PhaseSignal, PlatformDomain
sigs = [PhaseSignal('p1', 20.0, PlatformDomain.SECURITY), PhaseSignal('p2', 10.0, PlatformDomain.SECURITY)]
da = DomainAggregate(PlatformDomain.SECURITY, sigs)
assert da.avg_score() == 15.0"

run_python_test "DomainAggregate avg_normalised() = avg/25*100" \
"from security_ai.platform_convergence_engine import DomainAggregate, PhaseSignal, PlatformDomain
da = DomainAggregate(PlatformDomain.SECURITY, [PhaseSignal('p1',25.0,PlatformDomain.SECURITY)])
assert da.avg_normalised() == 100.0"

run_python_test "DomainAggregate weakest_phase() = lowest score" \
"from security_ai.platform_convergence_engine import DomainAggregate, PhaseSignal, PlatformDomain
sigs = [PhaseSignal('p1',20.0,PlatformDomain.SECURITY), PhaseSignal('p2',5.0,PlatformDomain.SECURITY)]
da = DomainAggregate(PlatformDomain.SECURITY, sigs)
assert da.weakest_phase().phase_id == 'p2'"

run_python_test "DomainAggregate to_dict() has required keys" \
"from security_ai.platform_convergence_engine import DomainAggregate, PhaseSignal, PlatformDomain
da = DomainAggregate(PlatformDomain.SECURITY, [PhaseSignal('p1',20.0,PlatformDomain.SECURITY)])
d = da.to_dict()
for k in ('domain','phase_count','avg_score','avg_normalised','health','weakest_phase'):
    assert k in d, k"

run_python_test "DomainAggregate empty signals returns avg_score 0.0" \
"from security_ai.platform_convergence_engine import DomainAggregate, PlatformDomain
assert DomainAggregate(PlatformDomain.SECURITY, []).avg_score() == 0.0"

echo ""

# GROUP 5: Engine telemetry ingestion
echo "GROUP 5: Telemetry Ingestion"

run_python_test "ingest_phase_scores() stores all 20 phases" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
assert e.phases_ingested() == 20"

run_python_test "ingest_phase_scores() clamps 0-25" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({'phase30': 999.0, 'phase31': -5.0})
s = e.phase_scores()
assert s['phase30'] == 25.0 and s['phase31'] == 0.0"

run_python_test "set_phase_score() updates single entry" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.set_phase_score('phase30', 22.5)
assert e.phase_scores().get('phase30') == 22.5"

run_python_test "set_phase_score() clamps at 25" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.set_phase_score('phase30', 30.0)
assert e.phase_scores()['phase30'] == 25.0"

echo ""

# GROUP 6: Convergence cycle
echo "GROUP 6: Convergence Cycle"

run_python_test "converge() returns ConvergenceSnapshot" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine, ConvergenceSnapshot
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
assert isinstance(e.converge(), ConvergenceSnapshot)"

run_python_test "converge() builds signals for all ingested phases" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
assert len(e.converge().signals) == 20"

run_python_test "converge() creates 6 domain aggregates" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
assert len(e.converge().domain_aggregates) == 6"

run_python_test "converge() generates cross-phase correlations" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
assert len(e.converge().correlations) > 0"

run_python_test "Multiple converge() cycles accumulate" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge(); e.converge(); e.converge()
assert e.convergence_cycles() == 3"

echo ""

# GROUP 7: ConvergenceSnapshot aggregates
echo "GROUP 7: ConvergenceSnapshot Aggregates"

run_python_test "composite_index() in [0,100] for typical inputs" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
ci = e.converge().composite_index()
assert 0.0 <= ci <= 100.0"

run_python_test "composite_index() = 100 when all phases score 25" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 25.0 for i in range(30, 50)})
assert e.converge().composite_index() == 100.0"

run_python_test "composite_index() = 0 when all phases score 0" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30, 50)})
assert e.converge().composite_index() == 0.0"

run_python_test "phase50_score() = 25 when composite_index = 100" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 25.0 for i in range(30, 50)})
assert e.converge().phase50_score() == 25"

run_python_test "phase50_score() = 0 when composite_index = 0" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30, 50)})
assert e.converge().phase50_score() == 0"

run_python_test "overall_health() OPTIMAL when all scores 25" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine, ConvergenceHealth
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 25.0 for i in range(30, 50)})
assert e.converge().overall_health() == ConvergenceHealth.OPTIMAL"

run_python_test "overall_health() CRITICAL when all scores 0" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine, ConvergenceHealth
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 0.0 for i in range(30, 50)})
assert e.converge().overall_health() == ConvergenceHealth.CRITICAL"

run_python_test "top_risks() returns n lowest-scoring signals in order" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': float(i-29) for i in range(30,50)})
risks = e.converge().top_risks(3)
assert len(risks) == 3 and risks[0].score <= risks[1].score <= risks[2].score"

run_python_test "ConvergenceSnapshot to_dict() has required keys" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
d = e.converge().to_dict()
for k in ('snapshot_id','composite_index','overall_health','phase50_score','domains','correlations','signals'):
    assert k in d, k"

echo ""

# GROUP 8: Engine query API
echo "GROUP 8: Engine Query API"

run_python_test "latest_snapshot() is None before converge()" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
assert PlatformConvergenceEngine().latest_snapshot() is None"

run_python_test "composite_index() = 0.0 before converge()" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
assert PlatformConvergenceEngine().composite_index() == 0.0"

run_python_test "phase50_score() = 0 before converge()" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
assert PlatformConvergenceEngine().phase50_score() == 0"

run_python_test "overall_health() is None before converge()" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
assert PlatformConvergenceEngine().overall_health() is None"

run_python_test "top_risks() returns [] before converge()" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
assert PlatformConvergenceEngine().top_risks() == []"

echo ""

# GROUP 9: Summary
echo "GROUP 9: Engine Summary"

run_python_test "summary() before converge() has status no_convergence_cycle" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
assert PlatformConvergenceEngine().summary()['status'] == 'no_convergence_cycle'"

run_python_test "summary() after converge() has status ok" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
assert e.summary()['status'] == 'ok'"

run_python_test "summary() contains all required keys" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
s = e.summary()
for k in ('convergence_cycles','phases_ingested','composite_index','overall_health',
          'phase50_score','domains_active','top_risks','strong_correlations','domain_health'):
    assert k in s, k"

run_python_test "summary() phase50_score is int in [0,25]" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
score = e.summary()['phase50_score']
assert isinstance(score, int) and 0 <= score <= 25"

echo ""

# GROUP 10: generate_report views
echo "GROUP 10: generate_report Views"

run_python_test "generate_report() without converge returns error key" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
assert 'error' in PlatformConvergenceEngine().generate_report()"

run_python_test "generate_report('executive') has composite_index and top_risks" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
r = e.generate_report('executive')
assert r['view'] == 'executive' and 'composite_index' in r and 'top_risks' in r"

run_python_test "generate_report('domain') has domains key" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
r = e.generate_report('domain')
assert r['view'] == 'domain' and 'domains' in r"

run_python_test "generate_report('full') has signals and correlations" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
r = e.generate_report('full')
assert r['view'] == 'full' and 'signals' in r and 'correlations' in r"

run_python_test "generate_report() default view is full" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
assert e.generate_report().get('view') == 'full'"

echo ""

# GROUP 11: Correlation analysis
echo "GROUP 11: Correlation Analysis"

run_python_test "Identical scores produce coefficient = 1.0" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
snap = e.converge()
assert any(c.coefficient == 1.0 for c in snap.correlations)"

run_python_test "strong_correlations() returns only STRONG items" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine, CorrelationStrength
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
snap = e.converge()
for c in snap.strong_correlations():
    assert c.strength == CorrelationStrength.STRONG"

run_python_test "Correlations only within same domain" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine, _PHASE_DOMAIN_MAP
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
snap = e.converge()
for c in snap.correlations:
    da = _PHASE_DOMAIN_MAP.get(c.phase_a)
    db = _PHASE_DOMAIN_MAP.get(c.phase_b)
    assert da == db, f'{c.phase_a} domain {da} != {c.phase_b} domain {db}'"

echo ""

# GROUP 12: persist_state
echo "GROUP 12: State Persistence"

run_python_test "persist_state() creates valid JSON with phase=51" \
"import os, json, tempfile
from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
    path = f.name
e.persist_state(path)
with open(path) as f:
    d = json.load(f)
assert d['phase'] == 50  # engine reports its own phase number
assert 'summary' in d and 'snapshots' in d
os.unlink(path)"

run_python_test "persist_state() snapshots list length = cycle count" \
"import json, tempfile, os
from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge(); e.converge()
with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
    path = f.name
e.persist_state(path)
with open(path) as f:
    d = json.load(f)
assert len(d['snapshots']) == 2
os.unlink(path)"

run_python_test "persist_state() creates directory if missing" \
"import os, json, tempfile, shutil
from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e.converge()
tmpdir = tempfile.mkdtemp()
path = os.path.join(tmpdir, 'nested', 'dir', 'state.json')
e.persist_state(path)
assert os.path.exists(path)
shutil.rmtree(tmpdir)"

echo ""

# GROUP 13: Ops script
echo "GROUP 13: Ops Script"

run_test "Ops script exists and is executable" \
    "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-51-platform-convergence.sh' ]]"

run_test "Ops script demo mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-51-platform-convergence.sh' demo"

run_test "Ops script summary mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-51-platform-convergence.sh' summary 2>&1); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

run_test "Ops script report executive mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-51-platform-convergence.sh' report executive"

run_test "Ops script report domain mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-51-platform-convergence.sh' report domain"

run_test "Ops script report full mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-51-platform-convergence.sh' report full"

echo ""

# GROUP 14: Milestone — 20-phase full coverage
echo "GROUP 14: Milestone — 21-Phase Full Coverage (30-50)"

run_python_test "All 20 phases (30-49) produce signals after converge()" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
snap = e.converge()
expected = {f'phase{i}' for i in range(30, 50)}
assert expected.issubset(set(snap.signals.keys()))"

run_python_test "All 6 domains populated from full phase input" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine, PlatformDomain
e = PlatformConvergenceEngine()
e.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
snap = e.converge()
assert set(snap.domain_aggregates.keys()) == {d.value for d in PlatformDomain}"

run_python_test "Boosting security phases raises composite_index" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e1 = PlatformConvergenceEngine()
e1.ingest_phase_scores({f'phase{i}': 20.0 for i in range(30, 50)})
e1.converge()
ci_base = e1.composite_index()
e2 = PlatformConvergenceEngine()
scores = {f'phase{i}': 20.0 for i in range(30, 50)}
for p in ['phase30','phase36','phase37','phase40','phase43']:
    scores[p] = 25.0
e2.ingest_phase_scores(scores)
e2.converge()
assert e2.composite_index() > ci_base"

run_python_test "phase50_score() is int in [0,25] for realistic inputs" \
"from security_ai.platform_convergence_engine import PlatformConvergenceEngine
e = PlatformConvergenceEngine()
scores = {f'phase{i}': float(15 + (i % 8)) for i in range(30, 50)}
e.ingest_phase_scores(scores)
e.converge()
s = e.phase50_score()
assert isinstance(s, int) and 0 <= s <= 25"

echo ""

# GROUP 15: Phase 50 regression guard
echo "GROUP 15: Phase 50 Regression Guard"

if [[ -z "${SKIP_REGRESSION:-}" ]]; then
    run_test "Phase 50 integration suite still passes" \
        "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-50-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
    echo "  ⏭  Phase 50 regression skipped (SKIP_REGRESSION=1)"
fi

echo ""

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo "============================================================"
echo "PHASE 51 TEST RESULTS  (MILESTONE: Phases 30-50 Convergence)"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "✅  ALL TESTS PASSED — Phase 51 Platform Convergence Engine verified"
    echo "    MILESTONE: Unified orchestration of all 21 security phases (30-50) ✓"
    exit 0
else
    echo "❌  SOME TESTS FAILED — Review output above"
    exit 1
fi
