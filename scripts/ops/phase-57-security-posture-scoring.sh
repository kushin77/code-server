#!/bin/bash
# @file phase-57-security-posture-scoring.sh
# @description Phase 57 — Security Posture Scoring & Risk Benchmarking
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p57*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 57: Security Posture Scoring & Risk Benchmarking" >&2
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_posture_scoring import (
    SecurityPostureScoringEngine, RiskDomain, make_gate
)

engine = SecurityPostureScoringEngine()

print("=== PHASE 57: Security Posture Scoring Dashboard ===")
print()

# Simulate gate scores from Phase 52-56
gates = [
    make_gate("phase52", RiskDomain.THREAT_RESPONSE,   22.0, 1.3),
    make_gate("phase53", RiskDomain.ANOMALY_DETECTION, 20.0, 1.1),
    make_gate("phase54", RiskDomain.THREAT_INTEL,      18.5, 1.0),
    make_gate("phase55", RiskDomain.ZERO_TRUST,        21.0, 1.2),
    make_gate("phase56", RiskDomain.SUPPLY_CHAIN,      19.5, 1.0),
]
engine.record_scores(gates)
snap = engine.snapshot()

print(f"  Security Posture Index: {snap.spi:.1f}/100  [{snap.rating.value.upper()}]")
print()
print("  Domain Scores:")
for domain, score in snap.domain_scores.items():
    bar = "█" * int(score / 5)
    print(f"    {domain:22s}  {score:5.1f}  {bar}")
print()
print(f"  Weakest Domain:     {snap.weakest_domain}")
print(f"  Frameworks Passed:  {snap.frameworks_passed}/{len(snap.benchmark_results)}")
print()
for b in snap.benchmark_results:
    status = "✅ PASS" if b.passed else "❌ FAIL"
    print(f"  {status}  {b.framework.value:18s}  required={b.required_spi:.0f}  gap={b.gap:+.1f}")
print()
print(f"  Phase 57 Score:     {snap.phase57_score:.2f}/25")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_posture_scoring import (
    SecurityPostureScoringEngine, RiskDomain, make_gate
)
engine = SecurityPostureScoringEngine()
for phase, domain, score in [
    ("phase52", RiskDomain.THREAT_RESPONSE,   20.0),
    ("phase53", RiskDomain.ANOMALY_DETECTION, 18.0),
    ("phase54", RiskDomain.THREAT_INTEL,      15.0),
    ("phase55", RiskDomain.ZERO_TRUST,        19.0),
    ("phase56", RiskDomain.SUPPLY_CHAIN,      17.0),
]:
    engine.record_score(make_gate(phase, domain, score))
print(json.dumps(engine.summary(), indent=2))
PYEOF
}

cmd_benchmark() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.security_posture_scoring import (
    SecurityPostureScoringEngine, RiskDomain, make_gate
)
engine = SecurityPostureScoringEngine()
for phase, domain, score in [
    ("phase52", RiskDomain.THREAT_RESPONSE,   22.0),
    ("phase53", RiskDomain.ANOMALY_DETECTION, 21.0),
    ("phase54", RiskDomain.THREAT_INTEL,      20.0),
    ("phase55", RiskDomain.ZERO_TRUST,        23.0),
    ("phase56", RiskDomain.SUPPLY_CHAIN,      19.0),
]:
    engine.record_score(make_gate(phase, domain, score))
snap = engine.snapshot()
print(json.dumps(engine.generate_report(snap), indent=2))
PYEOF
}

case "$MODE" in
    demo)      cmd_demo ;;
    summary)   cmd_summary ;;
    benchmark) cmd_benchmark ;;
    *)
        echo "Usage: $0 [demo|summary|benchmark]"
        exit 1
        ;;
esac
