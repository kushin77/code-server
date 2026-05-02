#!/bin/bash
# @file phase-40-predictive-threat-intelligence.sh
# @description Ops orchestrator for Phase 40 Predictive Threat Intelligence Engine
# @since 2026-05-01
# @phase 40

set -o pipefail

# Error handling
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase40"
PYTHON_CMD="python3"
if [[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]]; then
    PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
fi

mkdir -p "$STATE_DIR"

# Show help
show_help() {
    cat <<'EOF'
PHASE 40: PREDICTIVE THREAT INTELLIGENCE ENGINE

Usage: phase-40-predictive-threat-intelligence.sh <mode>

Modes:
  analyze       Generate threat forecasts from historical metrics
  verify        Verify forecasts against actual values
  summary       Display predictive intelligence summary
  demo          Run full demo with sample metrics

Options:
  -h, --help    Show this help message
EOF
}

# Demo mode
run_demo() {
    log_info "Running predictive threat intelligence demo..."
    
    cat <<'EOF'
============================================================
PHASE 40: PREDICTIVE THREAT INTELLIGENCE DEMO
============================================================

--- Ingesting Threat Metrics from Upstream Phases ---

EOF

    "$PYTHON_CMD" - <<'PYTHON_EOF'
import sys
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence
from datetime import datetime, timedelta

# Initialize engine
engine = PredictiveThreatIntelligence()

# Simulate metrics from upstream phases
print("Phase 34 (Resilience): Ingesting latency metrics...")
for i in range(10):
    engine.ingest_threat_metrics(34, {
        "degradation_latency_ms": 80 + (i * 5),
        "recovery_time_s": 2.0 + (i * 0.2)
    })
print(f"  Ingested 2 metrics × 10 observations = 20 data points")

print("Phase 35 (Forensics): Ingesting trace metrics...")
for i in range(10):
    engine.ingest_threat_metrics(35, {
        "trace_latency_ms": 100 + (i * 8),
        "event_correlation_score": 0.7 + (i * 0.02)
    })
print(f"  Ingested 2 metrics × 10 observations = 20 data points")

print("Phase 36 (Policy): Ingesting policy metrics...")
for i in range(8):
    engine.ingest_threat_metrics(36, {
        "policy_violation_count": max(0, i - 2),
        "compliance_percentage": 95.0 - (i * 1.5)
    })
print(f"  Ingested 2 metrics × 8 observations = 16 data points")

print("Phase 38 (Behavioral): Ingesting anomaly metrics...")
for i in range(10):
    engine.ingest_threat_metrics(38, {
        "anomaly_latency_ms": 90 + (i * 6),
        "anomaly_detection_rate": 0.05 + (i * 0.01)
    })
print(f"  Ingested 2 metrics × 10 observations = 20 data points")

print("Phase 39 (Optimizer): Ingesting optimization metrics...")
for i in range(8):
    engine.ingest_threat_metrics(39, {
        "optimization_success_rate": 0.8 + (i * 0.02),
        "recommendation_confidence": 0.75 + (i * 0.015)
    })
print(f"  Ingested 2 metrics × 8 observations = 16 data points")

print(f"\nTotal metrics ingested: {len(engine.metrics_history)}")

# Generate forecasts
print("\n--- Generating Threat Forecasts ---\n")
forecasts = engine.generate_forecasts(lookback_hours=24)

for i, forecast in enumerate(forecasts[:5], 1):
    print(f"Forecast {i}:")
    print(f"  Threat Type: {forecast.threat_type}")
    print(f"  Horizon: {forecast.horizon}")
    print(f"  Predicted Value: {forecast.predicted_value:.2f}")
    print(f"  Confidence: {forecast.confidence:.1%}")
    print(f"  Range: [{forecast.lower_bound:.2f}, {forecast.upper_bound:.2f}]")
    print(f"  Method: {forecast.methodology}")
    if forecast.recommended_actions:
        print(f"  Recommended Actions:")
        for action in forecast.recommended_actions[:2]:
            print(f"    • {action}")
    print()

# Persist state
engine.persist_state()
print("State persisted to disk")

# Summary
print("\n--- Predictive Intelligence Summary ---\n")
summary = engine.summary()
print(f"Metrics Ingested: {summary['metrics_ingested']}")
print(f"Forecasts Generated: {summary['forecasts_generated']}")
print(f"Threat Types: {', '.join(summary['threat_types_detected'])}")
print(f"Average Confidence: {summary['average_confidence']:.1%}")
print(f"Accuracy Score: {summary['accuracy_score']:.1f}/25.0 pts")
print(f"Source Phases: {', '.join(str(p) for p in summary['source_phases'])}")
print(f"Forecast Methodologies: {', '.join(summary['forecast_methodologies'])}")

if summary['recommended_actions']:
    print(f"\nPreemptive Actions ({len(summary['recommended_actions'])} total):")
    for i, action in enumerate(summary['recommended_actions'][:5], 1):
        print(f"  {i}. {action}")

PYTHON_EOF
}

# Analyze mode
run_analyze() {
    log_info "Running forecast analysis..."
    
    "$PYTHON_CMD" - <<'PYTHON_EOF'
import sys
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence

engine = PredictiveThreatIntelligence()

# Ingest from phases
for phase in [34, 35, 36, 38, 39]:
    metrics_map = {
        34: {"latency": 100},
        35: {"trace_latency": 120},
        36: {"violation_count": 1},
        38: {"anomaly_score": 0.08},
        39: {"optimization_score": 18.5}
    }
    if phase in metrics_map:
        engine.ingest_threat_metrics(phase, metrics_map[phase])

forecasts = engine.generate_forecasts()
summary = engine.summary()

print(f"Threat Forecasts Generated: {len(forecasts)}")
print(f"Average Forecast Confidence: {summary['average_confidence']:.1%}")
print(f"Accuracy Score: {summary['accuracy_score']:.1f}/25.0 pts")

PYTHON_EOF
}

# Summary mode
run_summary() {
    log_info "Generating predictive intelligence summary..."
    
    "$PYTHON_CMD" - <<'PYTHON_EOF'
import sys
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.predictive_threat_intelligence import PredictiveThreatIntelligence

engine = PredictiveThreatIntelligence()
summary = engine.summary()

echo "=========================================="
echo "PREDICTIVE THREAT INTELLIGENCE SUMMARY"
echo "=========================================="
echo ""
echo "Metrics Ingested: ${summary['metrics_ingested']}"
echo "Forecasts Generated: ${summary['forecasts_generated']}"
echo "Accuracy Score: ${summary['accuracy_score']:.1f}/25.0"

PYTHON_EOF
}

# Main
case "${1:-demo}" in
    demo)
        run_demo
        ;;
    analyze)
        run_analyze
        ;;
    summary)
        run_summary
        ;;
    -h|--help)
        show_help
        ;;
    *)
        log_error "Unknown mode: $1"
        show_help
        exit 1
        ;;
esac
