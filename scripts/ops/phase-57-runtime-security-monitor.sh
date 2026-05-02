#!/bin/bash
# @file phase-57-runtime-security-monitor.sh
# @description Phase 57 — Runtime Security Monitoring & Anomalous Process Detection
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..." >&2; rm -f /tmp/p57*.tmp 2>/dev/null || true' EXIT

MODE="${1:-demo}"

cmd_demo() {
    log_info "Phase 57 — Runtime Security Monitoring & Anomalous Process Detection"
    log_info "Running demo scan..."
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.runtime_security_monitor import (
    RuntimeSecurityMonitor, Baseline, make_process, make_connection,
    AnomalyType, AlertSeverity, RuntimeAlert, MonitoringScope
)

monitor = RuntimeSecurityMonitor()

# Define baseline for auth-service
bl = Baseline(
    name="auth-service",
    allowed_processes=["gunicorn", "python3", "nginx"],
    max_cpu_pct=70.0,
    max_mem_mb=512.0,
    allowed_remote_ports=[443, 5432, 6379],
    allow_privileged=False,
)
monitor.set_baseline(bl)

# Ingest processes
procs = [
    make_process(1001, "gunicorn",  user="appuser", cpu_pct=30.0, mem_mb=256.0),
    make_process(1002, "python3",   user="appuser", cpu_pct=10.0, mem_mb=128.0),
    make_process(1003, "nc",        user="appuser", cpu_pct=1.0,  mem_mb=4.0),   # suspicious
    make_process(1004, "gunicorn",  user="root",    cpu_pct=5.0,  mem_mb=64.0),  # priv escalation
    make_process(1005, "python3",   user="appuser", cpu_pct=95.0, mem_mb=128.0), # CPU abuse
]
alerts = monitor.scan_processes(procs, baseline_name="auth-service")

# Ingest connections
conn = make_connection(1003, "nc", "185.220.101.1", 9001, is_external=True)
monitor.ingest_connection(conn, baseline_name="auth-service")

score = monitor.phase57_score()
print(f"[Phase 57] Processes observed : {len(procs)}")
print(f"[Phase 57] Alerts raised      : {len(monitor.alerts())}")
print(f"[Phase 57] Active alerts      : {len(monitor.active_alerts())}")
print(f"[Phase 57] Critical alerts    : {len(monitor.critical_alerts())}")
print(f"[Phase 57] Gate score         : {score}/25")
print(f"[Phase 57] Status             : {'PASS' if score >= 10 else 'REVIEW'}")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process

monitor = RuntimeSecurityMonitor()
bl = Baseline(name="default", allowed_processes=["nginx", "python3"],
              max_cpu_pct=80.0, max_mem_mb=1024.0, allow_privileged=False)
monitor.set_baseline(bl)
monitor.ingest_process(make_process(1, "nginx",   user="www",  cpu_pct=10.0), "default")
monitor.ingest_process(make_process(2, "python3", user="app",  cpu_pct=20.0), "default")
monitor.ingest_process(make_process(3, "bash",    user="root", cpu_pct=1.0),  "default")
print(json.dumps(monitor.summary(), indent=2))
PYEOF
}

cmd_report() {
    "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process

monitor = RuntimeSecurityMonitor()
bl = Baseline(name="default", allowed_processes=["nginx"],
              max_cpu_pct=80.0, max_mem_mb=1024.0, allow_privileged=False)
monitor.set_baseline(bl)
monitor.ingest_process(make_process(1, "nginx",  user="www",  cpu_pct=10.0), "default")
monitor.ingest_process(make_process(2, "miner",  user="root", cpu_pct=99.0), "default")
print(json.dumps(monitor.generate_report(), indent=2))
PYEOF
}

cmd_persist() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, make_process

monitor = RuntimeSecurityMonitor()
monitor.ingest_process(make_process(1, "nginx", cpu_pct=5.0))
path = monitor.persist_state('${PROJECT_ROOT}/artifacts/phase57/runtime-monitor.json')
print(f"State persisted to: {path}")
PYEOF
}

case "$MODE" in
    demo)    cmd_demo    ;;
    summary) cmd_summary ;;
    report)  cmd_report  ;;
    persist) cmd_persist  ;;
    *)
        log_error "Unknown mode '$MODE'. Usage: $0 [demo|summary|report|persist]"
        exit 1
        ;;
esac
