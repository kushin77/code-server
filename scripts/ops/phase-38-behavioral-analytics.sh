#!/bin/bash
# @file phase-38-behavioral-analytics.sh
# @description Orchestrator for Phase 38 ML-driven behavioral analytics
# @since 2026-05-01
# @phase 38

set -o pipefail

# Error handling
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${PROJECT_ROOT}/artifacts/phase38"
PYTHON_CMD="python3"
if [[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]]; then
    PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"
fi

# Ensure state directory
mkdir -p "$STATE_DIR"

# Mode: analyze, summary, demo
MODE="${1:-summary}"

case "$MODE" in
    analyze)
        log_info "Starting behavioral analytics analysis..."
        "$PYTHON_CMD" - <<'PYEOF'
import sys
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.behavioral_analytics import (
    BehavioralAnalyticsEngine,
    BehaviorMetric,
)
from datetime import datetime, timedelta
import random

# Initialize engine
engine = BehavioralAnalyticsEngine()

# Simulate metric ingestion
metrics = []
entities = [
    ("user_001", "user"),
    ("service_auth", "service"),
    ("container_api", "container"),
]

for entity_id, entity_type in entities:
    # Generate baseline metrics
    baseline_values = [random.uniform(50, 100) for _ in range(100)]
    baseline = engine.build_baseline(
        entity_id=entity_id,
        entity_type=entity_type,
        metric_type="api_calls_per_hour",
        values=baseline_values
    )
    entity_key = f"{entity_type}:{entity_id}"
    engine.baselines[entity_key]["api_calls_per_hour"] = baseline

# Simulate anomalies
test_metrics = [
    ("user_001", "user", [("api_calls_per_hour", 350.0)]),  # Anomaly
    ("service_auth", "service", [("cpu_usage_percent", 95.0)]),  # Anomaly
    ("container_api", "container", [("network_connections", 5000)]),  # Anomaly
]

for entity_id, entity_type, metrics_data in test_metrics:
    anomalies = engine.detect_anomalies_ml(
        entity_id, entity_type, metrics_data
    )
    entity_key = f"{entity_type}:{entity_id}"
    if entity_key in engine.profiles:
        engine.profiles[entity_key].anomalies.extend(anomalies)

# Persist and summary
engine.persist_state()
summary = engine.summary()

print(f"Phase 38 Behavioral Analytics Analysis:")
print(f"  Entities monitored: {summary['total_entities_monitored']}")
print(f"  Anomalies detected: {summary['total_anomalies_detected']}")
print(f"  Critical anomalies: {summary['critical_anomalies']}")
print(f"  Avg confidence: {summary['average_confidence']}")
print(f"  Phase 38 score: {summary['phase38_behavioral_score']}/25.0")
PYEOF
        ;;
    summary)
        log_info "Generating behavioral analytics summary..."
        "$PYTHON_CMD" - <<'PYEOF'
import sys
import json
import os
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.behavioral_analytics import BehavioralAnalyticsEngine

# Load existing state if available
engine = BehavioralAnalyticsEngine()
try:
    engine.load_state()
except:
    pass

summary = engine.summary()
print(json.dumps(summary, indent=2, default=str))
PYEOF
        ;;
    demo)
        log_info "Running behavioral analytics demo..."
        "$PYTHON_CMD" - <<'PYEOF'
import sys
sys.path.insert(0, "/home/akushnir/code-server/apps")

from security_ai.behavioral_analytics import (
    BehavioralAnalyticsEngine,
    BehaviorMetric,
    BehavioralAnomaly,
    BehaviorAnomaloType,
)
import random

print("=" * 60)
print("PHASE 38: ML-DRIVEN BEHAVIORAL ANALYTICS DEMO")
print("=" * 60)

# Initialize engine
engine = BehavioralAnalyticsEngine()

# Demo: Detect anomalies for different entity types
demo_cases = [
    ("admin_user_001", "user", [
        ("sudo_command_count", 42.0),  # Normally 1-2 per day
        ("failed_login_attempts", 8.0),  # Normally 0-1
    ]),
    ("payment_service", "service", [
        ("cpu_usage_percent", 98.0),  # Normally 20-40%
        ("memory_usage_mb", 9800.0),  # Normally 512-1024 MB
    ]),
    ("api_gateway_container", "container", [
        ("network_connections_count", 12000),  # Normally 100-500
        ("bytes_transferred_hour", 50000000),  # Normally < 1GB/hour
    ]),
]

print("\n--- Detecting Anomalies ---\n")
for entity_id, entity_type, metrics_data in demo_cases:
    print(f"{entity_type.upper()}: {entity_id}")
    
    anomalies = engine.detect_anomalies_ml(
        entity_id, entity_type, metrics_data
    )
    
    entity_key = f"{entity_type}:{entity_id}"
    if entity_key not in engine.profiles:
        from security_ai.behavioral_analytics import BehavioralProfile
        engine.profiles[entity_key] = BehavioralProfile(
            entity_id=entity_id,
            entity_type=entity_type
        )
    
    engine.profiles[entity_key].anomalies.extend(anomalies)
    
    for anomaly in anomalies:
        print(f"  ✗ Anomaly: {anomaly.anomaly_type.value}")
        print(f"    Severity: {anomaly.severity}/5")
        print(f"    Confidence: {anomaly.confidence:.2%}")
        print(f"    Description: {anomaly.description}")
        print(f"    Recommended: {', '.join(anomaly.recommended_actions[:2])}")
        print()

# Calculate behavioral scores
print("\n--- Behavioral Risk Scores ---\n")
for entity_id, entity_type, _ in demo_cases:
    score = engine.behavioral_score(entity_id, entity_type)
    status = "✓ GOOD" if score >= 20 else "⚠ WARNING" if score >= 10 else "✗ CRITICAL"
    print(f"{entity_type}:{entity_id}: {score:.1f}/25.0 {status}")

# Summary
engine.persist_state()
summary = engine.summary()
print("\n--- Analytics Summary ---\n")
print(f"Total entities monitored: {summary['total_entities_monitored']}")
print(f"Total anomalies detected: {summary['total_anomalies_detected']}")
print(f"Critical anomalies: {summary['critical_anomalies']}")
print(f"Avg anomaly confidence: {summary['average_confidence']:.2%}")
print(f"Phase 38 behavioral score: {summary['phase38_behavioral_score']:.1f}/25.0")
print()
PYEOF
        ;;
    *)
        log_error "Unknown mode: $MODE"
        echo "Usage: $0 {analyze|summary|demo}"
        exit 1
        ;;
esac
