#!/bin/bash
# @file phase-45-deployment-orchestrator.sh
# @description Orchestrator for Phase 45 Continuous Deployment & Release Management
# @since 2026-05-01
# @phase 45

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

mkdir -p "${PROJECT_ROOT}/artifacts/phase45"

MODE="${1:-summary}"

case "$MODE" in
    demo)
        log_info "Running deployment orchestrator demo..."
        "$PYTHON_CMD" - <<'PYEOF'
import sys
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.deployment_orchestrator import (
    DeploymentOrchestrator,
    DeploymentStage,
    CanaryMetrics,
)

print("=" * 60)
print("PHASE 45: CONTINUOUS DEPLOYMENT ORCHESTRATOR DEMO")
print("=" * 60)

orch = DeploymentOrchestrator()

services = [
    ("api-gateway",       "v2.4.1", {"phase36_score": 92, "phase30_score": 88}),
    ("auth-service",      "v1.9.0", {"phase36_score": 85, "anomaly_pct": 2.0}),
    ("payment-processor", "v3.1.2", {"phase36_score": 95, "threat_level": 0.05}),
]

print("\n--- Pre-flight Gate Evaluation ---\n")
for svc, ver, signals in services:
    record = orch.create_deployment(svc, ver, DeploymentStage.STAGING, signals)
    cleared = orch.run_preflight(record)
    gate_sum = record.gate_summary()
    status_icon = "✓" if cleared else "✗"
    print(f"{status_icon} {svc} {ver}: gates pass={gate_sum['pass']} warn={gate_sum['warn']} fail={gate_sum['fail']}")

print("\n--- Canary Analysis ---\n")
# Promote first service to canary and test
canary_record = orch.create_deployment(
    "api-gateway", "v2.4.1", DeploymentStage.CANARY,
    {"phase36_score": 92, "phase30_score": 88}
)
orch.run_preflight(canary_record)

healthy_metrics = CanaryMetrics(
    error_rate=0.08, p99_latency_ms=145.0,
    throughput_rps=4200.0, anomaly_score=0.05,
)
canary_ok, issues = orch.deploy_canary(canary_record, healthy_metrics)
print(f"Canary health: {'✓ HEALTHY — promoting' if canary_ok else '✗ UNHEALTHY — rolling back'}")
if not canary_ok:
    print(f"  Issues: {'; '.join(issues)}")

if canary_ok:
    orch.promote(canary_record)
    orch.finalize(canary_record, success=True)

# Simulate a bad canary
bad_record = orch.create_deployment(
    "auth-service", "v1.9.0", DeploymentStage.CANARY,
    {"phase36_score": 85, "anomaly_pct": 2.0}
)
orch.run_preflight(bad_record)
bad_metrics = CanaryMetrics(error_rate=4.2, p99_latency_ms=820.0, anomaly_score=0.45)
bad_ok, bad_issues = orch.deploy_canary(bad_record, bad_metrics)
should_rb, rb_reason = orch.should_rollback(bad_record)
if should_rb:
    orch.rollback(bad_record, rb_reason)
    print(f"Rolled back auth-service: {rb_reason}")

# Summary
summary = orch.summary()
print("\n--- Deployment Summary ---\n")
print(f"Total deployments:    {summary['total_deployments']}")
print(f"Succeeded:            {summary['succeeded']}")
print(f"Rolled back:          {summary['rolled_back']}")
print(f"Avg release health:   {summary['avg_release_health']:.2f}/25")
print(f"Phase 45 score:       {summary['phase45_deployment_score']:.1f}/25.0")
PYEOF
        ;;
    summary)
        log_info "Generating deployment summary..."
        "$PYTHON_CMD" - <<'PYEOF'
import sys, json
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage

orch = DeploymentOrchestrator()
# Simulate a representative deployment for summary
rec = orch.create_deployment("platform", "v1.0.0", DeploymentStage.PRODUCTION)
orch.run_preflight(rec)
orch.finalize(rec, success=True)

summary = orch.summary()
print(json.dumps(summary, indent=2, default=str))
PYEOF
        ;;
    deploy)
        SERVICE="${2:-platform}"
        VERSION="${3:-v1.0.0}"
        STAGE="${4:-staging}"
        log_info "Deploying ${SERVICE} ${VERSION} to ${STAGE}..."
        "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.deployment_orchestrator import DeploymentOrchestrator, DeploymentStage

stage_map = {
    "dev": DeploymentStage.DEV,
    "staging": DeploymentStage.STAGING,
    "canary": DeploymentStage.CANARY,
    "production": DeploymentStage.PRODUCTION,
}
stage = stage_map.get("${STAGE}", DeploymentStage.STAGING)
orch = DeploymentOrchestrator()
rec = orch.create_deployment("${SERVICE}", "${VERSION}", stage)
cleared = orch.run_preflight(rec)

if cleared:
    orch.finalize(rec, success=True)
    gs = rec.gate_summary()
    print(f"Deployment {rec.deployment_id} SUCCEEDED")
    print(f"Gates: pass={gs['pass']} warn={gs['warn']} fail={gs['fail']}")
    print(f"Release health: {rec.release_health_score():.2f}/25")
else:
    failed = [g.name for g in rec.gates if g.result.value == 'fail']
    orch.finalize(rec, success=False)
    print(f"Deployment BLOCKED — failed gates: {', '.join(failed)}")
    sys.exit(1)
PYEOF
        ;;
    *)
        log_error "Unknown mode: $MODE"
        echo "Usage: $0 {demo|summary|deploy [service version stage]}"
        exit 1
        ;;
esac
