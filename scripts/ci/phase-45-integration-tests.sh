#!/bin/bash
# @file phase-45-integration-tests.sh
# @description Integration test suite for Phase 45 — Continuous Deployment & Release Management
# @since 2026-05-01
# @phase 45

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p45*.* /tmp/p44*.* 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

PY() { "$PYTHON_CMD" -c "import sys; sys.path.insert(0,'${PROJECT_ROOT}/apps'); $1"; }

echo "============================================================"
echo "PHASE 45: CONTINUOUS DEPLOYMENT ORCHESTRATOR — INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module imports
echo "GROUP 1: Module Import & API Surface"
run_test "Import DeploymentOrchestrator" \
    "PY 'from security_ai.deployment_orchestrator import DeploymentOrchestrator'"
run_test "Import DeploymentStage" \
    "PY 'from security_ai.deployment_orchestrator import DeploymentStage'"
run_test "Import DeploymentRecord" \
    "PY 'from security_ai.deployment_orchestrator import DeploymentRecord'"
run_test "Import PreflightGate" \
    "PY 'from security_ai.deployment_orchestrator import PreflightGate'"
run_test "Import CanaryMetrics" \
    "PY 'from security_ai.deployment_orchestrator import CanaryMetrics'"
run_test "Import GateResult" \
    "PY 'from security_ai.deployment_orchestrator import GateResult'"
run_test "Import deployment_score helper" \
    "PY 'from security_ai.deployment_orchestrator import deployment_score'"

echo ""
echo "GROUP 2: Preflight Gate Evaluation"
run_test "Gate evaluate PASS at high score" \
    "PY '
from security_ai.deployment_orchestrator import PreflightGate
g = PreflightGate(\"g1\", \"Test Gate\", \"phase_36\", threshold=80.0)
g.evaluate(95.0)
assert g.result.value == \"pass\", f\"Expected pass got {g.result}\"
'"
run_test "Gate evaluate WARN at moderate score" \
    "PY '
from security_ai.deployment_orchestrator import PreflightGate
g = PreflightGate(\"g2\", \"Test Gate\", \"phase_36\", threshold=80.0)
g.evaluate(63.0)  # 75% of 80 = 60; 63 > 60
assert g.result.value == \"warn\", f\"Expected warn got {g.result}\"
'"
run_test "Gate evaluate FAIL at low score" \
    "PY '
from security_ai.deployment_orchestrator import PreflightGate
g = PreflightGate(\"g3\", \"Test Gate\", \"phase_36\", threshold=80.0)
g.evaluate(40.0)
assert g.result.value == \"fail\", f\"Expected fail got {g.result}\"
'"
run_test "Gate message populated after evaluate" \
    "PY '
from security_ai.deployment_orchestrator import PreflightGate
g = PreflightGate(\"g4\", \"Test Gate\", \"phase_36\", threshold=80.0)
g.evaluate(90.0)
assert len(g.message) > 0
'"
run_test "Gate score clamped 0-100" \
    "PY '
from security_ai.deployment_orchestrator import PreflightGate
g = PreflightGate(\"g5\", \"Test Gate\", \"phase_36\", threshold=80.0)
g.evaluate(200.0)
assert g.score == 100.0
g.evaluate(-50.0)
assert g.score == 0.0
'"

echo ""
echo "GROUP 3: Canary Metrics Health"
run_test "Healthy canary metrics returns True" \
    "PY '
from security_ai.deployment_orchestrator import CanaryMetrics
m = CanaryMetrics(error_rate=0.1, p99_latency_ms=200.0, anomaly_score=0.05)
ok, issues = m.is_healthy()
assert ok, f\"Expected healthy: {issues}\"
'"
run_test "High error rate canary unhealthy" \
    "PY '
from security_ai.deployment_orchestrator import CanaryMetrics
m = CanaryMetrics(error_rate=5.0, p99_latency_ms=100.0)
ok, issues = m.is_healthy()
assert not ok and any(\"error\" in i for i in issues)
'"
run_test "High latency canary unhealthy" \
    "PY '
from security_ai.deployment_orchestrator import CanaryMetrics
m = CanaryMetrics(error_rate=0.1, p99_latency_ms=800.0)
ok, issues = m.is_healthy()
assert not ok and any(\"latency\" in i for i in issues)
'"
run_test "High anomaly score canary unhealthy" \
    "PY '
from security_ai.deployment_orchestrator import CanaryMetrics
m = CanaryMetrics(error_rate=0.1, p99_latency_ms=100.0, anomaly_score=0.8)
ok, issues = m.is_healthy()
assert not ok
'"

echo ""
echo "GROUP 4: Deployment Lifecycle"
run_test "Create deployment record" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
assert rec.service == \"svc\" and rec.version == \"v1\"
'"
run_test "Deployment has 7 standard gates" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
assert len(rec.gates) == 7, f\"Expected 7 gates got {len(rec.gates)}\"
'"
run_test "Preflight run_preflight returns bool" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
result = orch.run_preflight(rec)
assert isinstance(result, bool)
'"
run_test "High scores clear all gates" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
scores = {g.gate_id: 95.0 for g in rec.gates}
orch.run_preflight(rec, scores)
assert rec.is_gate_cleared()
'"
run_test "Low scores block gate" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
scores = {g.gate_id: 10.0 for g in rec.gates}
orch.run_preflight(rec, scores)
assert not rec.is_gate_cleared()
'"
run_test "Gate summary counts are consistent" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
orch.run_preflight(rec)
gs = rec.gate_summary()
total = sum(gs.values())
assert total == len(rec.gates)
'"

echo ""
echo "GROUP 5: Canary Integration"
run_test "deploy_canary with healthy metrics returns True" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage, CanaryMetrics
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.CANARY)
orch.run_preflight(rec)
m = CanaryMetrics(error_rate=0.1, p99_latency_ms=150.0, anomaly_score=0.02)
ok, issues = orch.deploy_canary(rec, m)
assert ok
'"
run_test "deploy_canary with bad metrics returns False" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage, CanaryMetrics
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.CANARY)
orch.run_preflight(rec)
m = CanaryMetrics(error_rate=10.0, p99_latency_ms=1500.0)
ok, issues = orch.deploy_canary(rec, m)
assert not ok and len(issues) > 0
'"

echo ""
echo "GROUP 6: Rollback & Promote"
run_test "should_rollback True when gate fails" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
orch.run_preflight(rec, {g.gate_id: 10.0 for g in rec.gates})
rb, reason = orch.should_rollback(rec)
assert rb and len(reason) > 0
'"
run_test "should_rollback False when all gates pass" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
orch.run_preflight(rec, {g.gate_id: 95.0 for g in rec.gates})
rb, _ = orch.should_rollback(rec)
assert not rb
'"
run_test "promote advances stage" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
orch.promote(rec)
assert rec.stage == DeploymentStage.CANARY
'"
run_test "rollback sets ROLLED_BACK status" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage, DeploymentStatus
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.CANARY)
orch.run_preflight(rec)
orch.rollback(rec, \"canary unhealthy\")
assert rec.status == DeploymentStatus.ROLLED_BACK
'"
run_test "finalize success sets SUCCEEDED status" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage, DeploymentStatus
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.PRODUCTION)
orch.run_preflight(rec)
orch.finalize(rec, success=True)
assert rec.status == DeploymentStatus.SUCCEEDED
'"

echo ""
echo "GROUP 7: Release Health Score"
run_test "Health score in range 0-25" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.PRODUCTION)
orch.run_preflight(rec, {g.gate_id: 90.0 for g in rec.gates})
orch.finalize(rec, success=True)
score = rec.release_health_score()
assert 0.0 <= score <= 25.0, f\"Score out of range: {score}\"
'"
run_test "Successful deployment has higher score than failed" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
ok_rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.PRODUCTION)
orch.run_preflight(ok_rec, {g.gate_id: 90.0 for g in ok_rec.gates})
orch.finalize(ok_rec, success=True)
fail_rec = orch.create_deployment(\"svc\", \"v2\", DeploymentStage.PRODUCTION)
orch.run_preflight(fail_rec, {g.gate_id: 90.0 for g in fail_rec.gates})
orch.finalize(fail_rec, success=False)
assert ok_rec.release_health_score() > fail_rec.release_health_score()
'"
run_test "deployment_score helper returns float" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage, deployment_score
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING)
orch.run_preflight(rec)
orch.finalize(rec, success=True)
s = deployment_score(orch)
assert isinstance(s, float) and 0 <= s <= 25
'"

echo ""
echo "GROUP 8: Summary & Phase Signals"
run_test "summary returns required keys" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator
orch = DeploymentOrchestrator()
s = orch.summary()
for key in [\"total_deployments\", \"succeeded\", \"rolled_back\", \"phase45_deployment_score\"]:
    assert key in s, f\"Missing key: {key}\"
'"
run_test "Phase signals propagate to gate synthesis" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.STAGING,
    phase_signals={\"phase36_score\": 98, \"phase30_score\": 97})
cleared = orch.run_preflight(rec)
assert cleared, \"High phase signals should clear all gates\"
'"
run_test "Low threat signals can block deployment" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
rec = orch.create_deployment(\"svc\", \"v1\", DeploymentStage.PRODUCTION,
    phase_signals={\"threat_level\": 1.0, \"anomaly_pct\": 9.9})
orch.run_preflight(rec)
gate_sum = rec.gate_summary()
# High threat/anomaly should result in at least one warn or fail
assert gate_sum[\"warn\"] + gate_sum[\"fail\"] > 0
'"
run_test "Multiple deployments tracked in summary" \
    "PY '
from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage
orch = DeploymentOrchestrator()
for i in range(3):
    rec = orch.create_deployment(f\"svc-{i}\", \"v1\", DeploymentStage.STAGING)
    orch.run_preflight(rec)
    orch.finalize(rec, success=True)
s = orch.summary()
assert s[\"total_deployments\"] == 3
assert s[\"succeeded\"] == 3
'"

echo ""
echo "GROUP 9: Ops Orchestrator"
OPS_SCRIPT="${PROJECT_ROOT}/scripts/ops/phase-45-deployment-orchestrator.sh"
run_test "Ops script exists" "test -f '$OPS_SCRIPT'"
run_test "Ops script syntax valid" "bash -n '$OPS_SCRIPT'"
run_test "Ops demo mode" "
timeout 30 bash '$OPS_SCRIPT' demo > /tmp/p45demo.out 2>&1 && grep -q 'PHASE 45' /tmp/p45demo.out
"
run_test "Ops summary mode" "
timeout 30 bash '$OPS_SCRIPT' summary > /tmp/p45sum.out 2>&1 && grep -q 'phase45_deployment_score' /tmp/p45sum.out
"
run_test "Ops deploy mode" "
timeout 30 bash '$OPS_SCRIPT' deploy api-gateway v2.4.1 staging > /tmp/p45dep.out 2>&1 && grep -q 'SUCCEEDED\|Release health' /tmp/p45dep.out
"

echo ""
echo "GROUP 10: Cross-Phase Integration"
run_test "Phase 44 platform orchestration still passing" "
timeout 90 bash ${PROJECT_ROOT}/scripts/ci/phase-44-integration-tests.sh > /tmp/p44.log 2>&1 && grep -q 'ALL TESTS PASSED' /tmp/p44.log
"

echo ""
echo "============================================================"
echo "TEST SUMMARY"
echo "============================================================"
printf "PASS: %d\nFAIL: %d\nTOTAL: %d\n" "$PASS" "$FAIL" "$TOTAL"
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "✓ ALL TESTS PASSED"
    exit 0
else
    echo "✗ SOME TESTS FAILED"
    exit 1
fi
