#!/bin/bash
# @file phase-57-integration-tests.sh
# @description Integration tests for Phase 57 — Runtime Security Monitoring & Anomalous Process Detection
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p57*.* 2>/dev/null || true' EXIT

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
echo "PHASE 57: RUNTIME SECURITY MONITORING &"
echo "          ANOMALOUS PROCESS DETECTION — INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Imports
echo "GROUP 1: Module Import & API Surface"

run_python_test "Import RuntimeSecurityMonitor" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor"

run_python_test "Import ProcessSnapshot" \
"from security_ai.runtime_security_monitor import ProcessSnapshot"

run_python_test "Import NetworkConnection" \
"from security_ai.runtime_security_monitor import NetworkConnection"

run_python_test "Import RuntimeAlert" \
"from security_ai.runtime_security_monitor import RuntimeAlert"

run_python_test "Import Baseline" \
"from security_ai.runtime_security_monitor import Baseline"

run_python_test "Import ProcessState enum (5 states)" \
"from security_ai.runtime_security_monitor import ProcessState
assert len(list(ProcessState)) == 5"

run_python_test "Import AnomalyType enum (8 types)" \
"from security_ai.runtime_security_monitor import AnomalyType
assert len(list(AnomalyType)) == 8"

run_python_test "Import AlertSeverity enum (4 levels)" \
"from security_ai.runtime_security_monitor import AlertSeverity
assert len(list(AlertSeverity)) == 4"

run_python_test "Import AlertStatus enum (4 statuses)" \
"from security_ai.runtime_security_monitor import AlertStatus
assert len(list(AlertStatus)) == 4"

run_python_test "Import MonitoringScope enum (4 scopes)" \
"from security_ai.runtime_security_monitor import MonitoringScope
assert len(list(MonitoringScope)) == 4"

run_python_test "Import helpers make_process() and make_connection()" \
"from security_ai.runtime_security_monitor import make_process, make_connection
p = make_process(1, 'nginx')
assert p.name == 'nginx'"

echo ""

# GROUP 2: ProcessSnapshot
echo "GROUP 2: ProcessSnapshot"

run_python_test "is_privileged() True for root user" \
"from security_ai.runtime_security_monitor import make_process
p = make_process(1, 'bash', user='root')
assert p.is_privileged()"

run_python_test "is_privileged() True for user '0'" \
"from security_ai.runtime_security_monitor import make_process
p = make_process(1, 'bash', user='0')
assert p.is_privileged()"

run_python_test "is_privileged() False for non-root user" \
"from security_ai.runtime_security_monitor import make_process
p = make_process(1, 'nginx', user='www-data')
assert not p.is_privileged()"

run_python_test "to_dict() contains all required fields" \
"from security_ai.runtime_security_monitor import make_process
d = make_process(1001, 'gunicorn', user='app', cpu_pct=30.0).to_dict()
for k in ('pid','name','user','state','cpu_pct','mem_mb','is_privileged','observed_at'):
    assert k in d, k"

echo ""

# GROUP 3: Baseline
echo "GROUP 3: Baseline"

run_python_test "process_allowed() True when in allowed list" \
"from security_ai.runtime_security_monitor import Baseline, make_process
bl = Baseline(name='test', allowed_processes=['nginx', 'python3'])
p = make_process(1, 'nginx')
assert bl.process_allowed(p)"

run_python_test "process_allowed() False when not in allowed list" \
"from security_ai.runtime_security_monitor import Baseline, make_process
bl = Baseline(name='test', allowed_processes=['nginx'])
p = make_process(1, 'bash')
assert not bl.process_allowed(p)"

run_python_test "process_allowed() True when allowed_processes is empty (no restriction)" \
"from security_ai.runtime_security_monitor import Baseline, make_process
bl = Baseline(name='test', allowed_processes=[])
p = make_process(1, 'anything')
assert bl.process_allowed(p)"

run_python_test "cpu_ok() True below threshold" \
"from security_ai.runtime_security_monitor import Baseline, make_process
bl = Baseline(name='test', max_cpu_pct=80.0)
p = make_process(1, 'nginx', cpu_pct=50.0)
assert bl.cpu_ok(p)"

run_python_test "cpu_ok() False above threshold" \
"from security_ai.runtime_security_monitor import Baseline, make_process
bl = Baseline(name='test', max_cpu_pct=80.0)
p = make_process(1, 'miner', cpu_pct=95.0)
assert not bl.cpu_ok(p)"

run_python_test "mem_ok() False above threshold" \
"from security_ai.runtime_security_monitor import Baseline, make_process
bl = Baseline(name='test', max_mem_mb=512.0)
p = make_process(1, 'bloat', mem_mb=1024.0)
assert not bl.mem_ok(p)"

run_python_test "port_allowed() True when port in allowed list" \
"from security_ai.runtime_security_monitor import Baseline, make_connection
bl = Baseline(name='test', allowed_remote_ports=[443, 5432])
c = make_connection(1, 'nginx', '10.0.0.1', 443)
assert bl.port_allowed(c)"

run_python_test "port_allowed() False when port not in allowed list" \
"from security_ai.runtime_security_monitor import Baseline, make_connection
bl = Baseline(name='test', allowed_remote_ports=[443, 5432])
c = make_connection(1, 'nc', '10.0.0.1', 9001)
assert not bl.port_allowed(c)"

run_python_test "namespace_ok() False for unknown namespace" \
"from security_ai.runtime_security_monitor import Baseline, make_process
bl = Baseline(name='test', allowed_namespaces=['default'])
p = make_process(1, 'nginx', namespace='kube-system')
assert not bl.namespace_ok(p)"

echo ""

# GROUP 4: RuntimeAlert lifecycle
echo "GROUP 4: RuntimeAlert Lifecycle"

run_python_test "is_active() True for OPEN alert" \
"from security_ai.runtime_security_monitor import RuntimeAlert, AlertStatus, AnomalyType, AlertSeverity, MonitoringScope
a = RuntimeAlert(anomaly_type=AnomalyType.UNEXPECTED_PROCESS, severity=AlertSeverity.HIGH,
                 scope=MonitoringScope.CONTAINER)
assert a.is_active()"

run_python_test "is_active() True for INVESTIGATING alert" \
"from security_ai.runtime_security_monitor import RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
a = RuntimeAlert(anomaly_type=AnomalyType.UNEXPECTED_PROCESS, severity=AlertSeverity.HIGH,
                 scope=MonitoringScope.HOST)
a.investigate()
assert a.is_active()"

run_python_test "is_active() False after resolve()" \
"from security_ai.runtime_security_monitor import RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
a = RuntimeAlert(anomaly_type=AnomalyType.RESOURCE_ABUSE, severity=AlertSeverity.MEDIUM,
                 scope=MonitoringScope.CONTAINER)
a.resolve()
assert not a.is_active()"

run_python_test "is_active() False after suppress()" \
"from security_ai.runtime_security_monitor import RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
a = RuntimeAlert(anomaly_type=AnomalyType.RESOURCE_ABUSE, severity=AlertSeverity.LOW,
                 scope=MonitoringScope.HOST)
a.suppress()
assert not a.is_active()"

run_python_test "resolve() sets resolved_at timestamp" \
"from security_ai.runtime_security_monitor import RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
a = RuntimeAlert(anomaly_type=AnomalyType.PRIVILEGE_ESCALATION, severity=AlertSeverity.CRITICAL,
                 scope=MonitoringScope.CONTAINER)
a.resolve()
assert a.resolved_at is not None"

run_python_test "to_dict() has all required fields" \
"from security_ai.runtime_security_monitor import RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
a = RuntimeAlert(anomaly_type=AnomalyType.LATERAL_MOVEMENT, severity=AlertSeverity.HIGH,
                 scope=MonitoringScope.KUBERNETES, source_pid=1001)
d = a.to_dict()
for k in ('alert_id','anomaly_type','severity','status','source_pid','scope','description','raised_at'):
    assert k in d, k"

echo ""

# GROUP 5: Engine — process ingestion
echo "GROUP 5: Engine — Process Ingestion"

run_python_test "ingest_process() stores process" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, make_process
m = RuntimeSecurityMonitor()
m.ingest_process(make_process(1, 'nginx'))
assert m.summary()['processes_observed'] == 1"

run_python_test "ingest_process() raises alert for unexpected process" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_processes=['nginx']))
alerts = m.ingest_process(make_process(1, 'bash'), 'default')
assert len(alerts) >= 1"

run_python_test "ingest_process() no alerts for allowed process" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_processes=['nginx'],
                        max_cpu_pct=80.0, max_mem_mb=1024.0, allow_privileged=False))
alerts = m.ingest_process(make_process(1, 'nginx', user='www', cpu_pct=10.0, mem_mb=64.0), 'default')
assert len(alerts) == 0"

run_python_test "ingest_process() raises PRIVILEGE_ESCALATION for root process" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process, AnomalyType
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_processes=['nginx'], allow_privileged=False))
m.ingest_process(make_process(1, 'nginx', user='root', cpu_pct=5.0, mem_mb=64.0), 'default')
assert any(a.anomaly_type == AnomalyType.PRIVILEGE_ESCALATION for a in m.alerts())"

run_python_test "ingest_process() raises RESOURCE_ABUSE for CPU spike" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process, AnomalyType
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_processes=['miner'], max_cpu_pct=50.0))
m.ingest_process(make_process(1, 'miner', user='app', cpu_pct=99.0), 'default')
assert any(a.anomaly_type == AnomalyType.RESOURCE_ABUSE for a in m.alerts())"

run_python_test "ingest_process() raises CONTAINER_ESCAPE for unexpected namespace" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process, AnomalyType
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_processes=['nginx'],
                        allowed_namespaces=['app-ns']))
p = make_process(1, 'nginx', namespace='kube-system')
m.ingest_process(p, 'default')
assert any(a.anomaly_type == AnomalyType.CONTAINER_ESCAPE for a in m.alerts())"

run_python_test "scan_processes() returns all raised alerts" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_processes=['nginx']))
procs = [make_process(i, 'bash' if i > 1 else 'nginx') for i in range(1, 5)]
alerts = m.scan_processes(procs, 'default')
assert len(alerts) >= 3"

echo ""

# GROUP 6: Engine — connection ingestion
echo "GROUP 6: Engine — Connection Ingestion"

run_python_test "ingest_connection() stores connection" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, make_connection
m = RuntimeSecurityMonitor()
m.ingest_connection(make_connection(1, 'nginx', '10.0.0.1', 443))
assert m.summary()['connections_observed'] == 1"

run_python_test "ingest_connection() raises alert for disallowed port" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_connection
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_remote_ports=[443]))
alert = m.ingest_connection(make_connection(1, 'nc', '1.2.3.4', 9001), 'default')
assert alert is not None"

run_python_test "ingest_connection() returns None for allowed port" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_connection
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_remote_ports=[443, 5432]))
alert = m.ingest_connection(make_connection(1, 'nginx', '10.0.0.1', 443), 'default')
assert alert is None"

run_python_test "ingest_connection() UNUSUAL_NETWORK_CONN anomaly type" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_connection, AnomalyType
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_remote_ports=[443]))
m.ingest_connection(make_connection(1, 'nc', '1.2.3.4', 6666), 'default')
assert any(a.anomaly_type == AnomalyType.UNUSUAL_NETWORK_CONN for a in m.alerts())"

echo ""

# GROUP 7: Alert management
echo "GROUP 7: Alert Management"

run_python_test "raise_alert() stores alert" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
a = RuntimeAlert(anomaly_type=AnomalyType.LATERAL_MOVEMENT, severity=AlertSeverity.HIGH,
                 scope=MonitoringScope.NETWORK)
m.raise_alert(a)
assert len(m.alerts()) == 1"

run_python_test "resolve_alert() returns True and resolves" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, AlertStatus, MonitoringScope
m = RuntimeSecurityMonitor()
a = RuntimeAlert(anomaly_type=AnomalyType.RESOURCE_ABUSE, severity=AlertSeverity.MEDIUM,
                 scope=MonitoringScope.HOST)
m.raise_alert(a)
ok = m.resolve_alert(a.alert_id)
assert ok
assert a.status == AlertStatus.RESOLVED"

run_python_test "resolve_alert() returns False for unknown ID" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor
m = RuntimeSecurityMonitor()
assert not m.resolve_alert('no-such-id')"

run_python_test "suppress_alert() marks alert SUPPRESSED" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, AlertStatus, MonitoringScope
m = RuntimeSecurityMonitor()
a = RuntimeAlert(anomaly_type=AnomalyType.UNEXPECTED_PROCESS, severity=AlertSeverity.LOW,
                 scope=MonitoringScope.CONTAINER)
m.raise_alert(a)
m.suppress_alert(a.alert_id)
assert a.status == AlertStatus.SUPPRESSED"

run_python_test "active_alerts() excludes resolved and suppressed" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
a1 = RuntimeAlert(anomaly_type=AnomalyType.RESOURCE_ABUSE, severity=AlertSeverity.LOW, scope=MonitoringScope.HOST)
a2 = RuntimeAlert(anomaly_type=AnomalyType.PRIVILEGE_ESCALATION, severity=AlertSeverity.CRITICAL, scope=MonitoringScope.CONTAINER)
m.raise_alert(a1); m.raise_alert(a2)
m.resolve_alert(a1.alert_id)
assert len(m.active_alerts()) == 1"

run_python_test "critical_alerts() returns only CRITICAL severity" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
m.raise_alert(RuntimeAlert(anomaly_type=AnomalyType.CONTAINER_ESCAPE,
                            severity=AlertSeverity.CRITICAL, scope=MonitoringScope.CONTAINER))
m.raise_alert(RuntimeAlert(anomaly_type=AnomalyType.RESOURCE_ABUSE,
                            severity=AlertSeverity.LOW, scope=MonitoringScope.HOST))
assert len(m.critical_alerts()) == 1"

run_python_test "alerts_by_severity() groups by all severity levels" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor
m = RuntimeSecurityMonitor()
by_sev = m.alerts_by_severity()
for lvl in ('critical','high','medium','low'):
    assert lvl in by_sev, lvl"

echo ""

# GROUP 8: Scoring
echo "GROUP 8: Scoring"

run_python_test "phase57_score() = 25 with no alerts" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor
m = RuntimeSecurityMonitor()
assert m.phase57_score() == 25.0"

run_python_test "phase57_score() decreases with active CRITICAL alert" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
m.raise_alert(RuntimeAlert(anomaly_type=AnomalyType.PRIVILEGE_ESCALATION,
                            severity=AlertSeverity.CRITICAL, scope=MonitoringScope.CONTAINER))
assert m.phase57_score() < 25.0"

run_python_test "CRITICAL alert deducts 6 pts" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
m.raise_alert(RuntimeAlert(anomaly_type=AnomalyType.CONTAINER_ESCAPE,
                            severity=AlertSeverity.CRITICAL, scope=MonitoringScope.CONTAINER))
assert m.phase57_score() == 25.0 - 6"

run_python_test "HIGH alert deducts 3 pts" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
m.raise_alert(RuntimeAlert(anomaly_type=AnomalyType.UNEXPECTED_PROCESS,
                            severity=AlertSeverity.HIGH, scope=MonitoringScope.HOST))
assert m.phase57_score() == 25.0 - 3"

run_python_test "Resolved alert not counted in score deduction" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
a = RuntimeAlert(anomaly_type=AnomalyType.RESOURCE_ABUSE,
                 severity=AlertSeverity.CRITICAL, scope=MonitoringScope.CONTAINER)
m.raise_alert(a)
m.resolve_alert(a.alert_id)
assert m.phase57_score() == 25.0"

run_python_test "phase57_score() floors at 0 with many critical alerts" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
for i in range(10):
    m.raise_alert(RuntimeAlert(anomaly_type=AnomalyType.CONTAINER_ESCAPE,
                                severity=AlertSeverity.CRITICAL, scope=MonitoringScope.CONTAINER))
assert m.phase57_score() == 0.0"

run_python_test "phase57_score() in range [0, 25]" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, Baseline, make_process
m = RuntimeSecurityMonitor()
m.set_baseline(Baseline(name='default', allowed_processes=['nginx'], allow_privileged=False))
for i in range(5):
    m.ingest_process(make_process(i, 'bash', user='root', cpu_pct=99.0), 'default')
score = m.phase57_score()
assert 0.0 <= score <= 25.0"

echo ""

# GROUP 9: Summary & reporting
echo "GROUP 9: Summary & Reporting"

run_python_test "summary() has all required keys" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor
m = RuntimeSecurityMonitor()
s = m.summary()
for k in ('status','total_alerts','active_alerts','resolved_alerts','suppressed_alerts',
          'severity_breakdown','processes_observed','connections_observed',
          'baselines_configured','phase57_score'):
    assert k in s, k"

run_python_test "summary() status='ok' when no active alerts" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor
m = RuntimeSecurityMonitor()
assert m.summary()['status'] == 'ok'"

run_python_test "summary() status='alerts_active' when active alerts exist" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor, RuntimeAlert, AnomalyType, AlertSeverity, MonitoringScope
m = RuntimeSecurityMonitor()
m.raise_alert(RuntimeAlert(anomaly_type=AnomalyType.LATERAL_MOVEMENT,
                            severity=AlertSeverity.HIGH, scope=MonitoringScope.NETWORK))
assert m.summary()['status'] == 'alerts_active'"

run_python_test "generate_report() includes alerts and processes keys" \
"from security_ai.runtime_security_monitor import RuntimeSecurityMonitor
m = RuntimeSecurityMonitor()
r = m.generate_report()
for k in ('alerts','processes','connections'):
    assert k in r, k"

run_python_test "NetworkConnection.to_dict() has all required fields" \
"from security_ai.runtime_security_monitor import make_connection
c = make_connection(1001, 'nginx', '10.0.0.1', 443, is_external=False)
d = c.to_dict()
for k in ('conn_id','pid','process_name','remote_addr','remote_port','protocol','is_external','observed_at'):
    assert k in d, k"

echo ""

# GROUP 10: Ops script
echo "GROUP 10: Ops Script"

run_test "Ops script exists and is executable" \
    "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-57-runtime-security-monitor.sh' ]]"

run_test "Ops script demo mode mentions Phase 57" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-57-runtime-security-monitor.sh' demo 2>&1 | grep -i 'Phase 57'"

run_test "Ops script summary mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-57-runtime-security-monitor.sh' summary 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

run_test "Ops script report mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-57-runtime-security-monitor.sh' report 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

echo ""

# GROUP 11: Phase 56 regression guard
echo "GROUP 11: Phase 56 Regression Guard"

if [[ -z "${SKIP_REGRESSION:-}" ]]; then
    run_test "Phase 56 integration suite still passes" \
        "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-56-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
    echo "  ⏭  Phase 56 regression skipped (SKIP_REGRESSION=1)"
fi

echo ""

echo "============================================================"
echo "PHASE 57 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "✅  ALL TESTS PASSED — Phase 57 Runtime Security Monitor verified"
    exit 0
else
    echo "❌  SOME TESTS FAILED — Review output above"
    exit 1
fi
