"""
runtime_security_monitor.py — Phase 57: Runtime Security Monitoring & Anomalous Process Detection
Collects runtime process/syscall/network telemetry, detects anomalous behaviour using
baseline deviation rules, raises RuntimeAlerts, and produces a gate score.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class ProcessState(Enum):
    RUNNING   = "running"
    SLEEPING  = "sleeping"
    STOPPED   = "stopped"
    ZOMBIE    = "zombie"
    UNKNOWN   = "unknown"


class AnomalyType(Enum):
    UNEXPECTED_PROCESS     = "unexpected_process"
    PRIVILEGE_ESCALATION   = "privilege_escalation"
    SUSPICIOUS_SYSCALL     = "suspicious_syscall"
    UNUSUAL_NETWORK_CONN   = "unusual_network_connection"
    FILE_INTEGRITY_BREACH  = "file_integrity_breach"
    RESOURCE_ABUSE         = "resource_abuse"
    CONTAINER_ESCAPE       = "container_escape"
    LATERAL_MOVEMENT       = "lateral_movement"


class AlertSeverity(Enum):
    CRITICAL = "critical"
    HIGH     = "high"
    MEDIUM   = "medium"
    LOW      = "low"


class AlertStatus(Enum):
    OPEN         = "open"
    INVESTIGATING = "investigating"
    SUPPRESSED   = "suppressed"
    RESOLVED     = "resolved"


class MonitoringScope(Enum):
    HOST       = "host"
    CONTAINER  = "container"
    KUBERNETES = "kubernetes"
    NETWORK    = "network"


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class ProcessSnapshot:
    """Point-in-time snapshot of a running process."""
    pid: int
    name: str
    user: str = "root"
    state: ProcessState = ProcessState.RUNNING
    cpu_pct: float = 0.0        # 0-100
    mem_mb: float = 0.0
    parent_pid: Optional[int] = None
    cmdline: str = ""
    container_id: Optional[str] = None
    namespace: str = "default"
    observed_at: datetime = field(default_factory=datetime.utcnow)

    def is_privileged(self) -> bool:
        return self.user in ("root", "0")

    def to_dict(self) -> dict:
        return {
            "pid": self.pid,
            "name": self.name,
            "user": self.user,
            "state": self.state.value,
            "cpu_pct": self.cpu_pct,
            "mem_mb": self.mem_mb,
            "parent_pid": self.parent_pid,
            "cmdline": self.cmdline,
            "container_id": self.container_id,
            "namespace": self.namespace,
            "is_privileged": self.is_privileged(),
            "observed_at": self.observed_at.isoformat(),
        }


@dataclass
class NetworkConnection:
    """An observed network connection from a process."""
    conn_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    pid: int = 0
    process_name: str = ""
    local_addr: str = ""
    remote_addr: str = ""
    remote_port: int = 0
    protocol: str = "tcp"
    is_external: bool = False
    observed_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "conn_id": self.conn_id,
            "pid": self.pid,
            "process_name": self.process_name,
            "local_addr": self.local_addr,
            "remote_addr": self.remote_addr,
            "remote_port": self.remote_port,
            "protocol": self.protocol,
            "is_external": self.is_external,
            "observed_at": self.observed_at.isoformat(),
        }


@dataclass
class RuntimeAlert:
    """An anomaly detection alert raised by the monitoring engine."""
    alert_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    anomaly_type: AnomalyType = AnomalyType.UNEXPECTED_PROCESS
    severity: AlertSeverity = AlertSeverity.MEDIUM
    status: AlertStatus = AlertStatus.OPEN
    source_pid: Optional[int] = None
    source_process: str = ""
    scope: MonitoringScope = MonitoringScope.CONTAINER
    description: str = ""
    evidence: Dict = field(default_factory=dict)
    raised_at: datetime = field(default_factory=datetime.utcnow)
    resolved_at: Optional[datetime] = None

    def resolve(self) -> None:
        self.status = AlertStatus.RESOLVED
        self.resolved_at = datetime.utcnow()

    def suppress(self) -> None:
        self.status = AlertStatus.SUPPRESSED

    def investigate(self) -> None:
        self.status = AlertStatus.INVESTIGATING

    def is_active(self) -> bool:
        return self.status in (AlertStatus.OPEN, AlertStatus.INVESTIGATING)

    def to_dict(self) -> dict:
        return {
            "alert_id": self.alert_id,
            "anomaly_type": self.anomaly_type.value,
            "severity": self.severity.value,
            "status": self.status.value,
            "source_pid": self.source_pid,
            "source_process": self.source_process,
            "scope": self.scope.value,
            "description": self.description,
            "evidence": self.evidence,
            "raised_at": self.raised_at.isoformat(),
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
        }


@dataclass
class Baseline:
    """
    Expected behaviour profile for a workload.
    Defines allowed processes, max resource thresholds, and trusted network ranges.
    """
    name: str
    allowed_processes: List[str] = field(default_factory=list)
    max_cpu_pct: float = 80.0
    max_mem_mb: float = 2048.0
    allowed_remote_ports: List[int] = field(default_factory=list)
    allowed_namespaces: List[str] = field(default_factory=lambda: ["default"])
    allow_privileged: bool = False

    def process_allowed(self, proc: ProcessSnapshot) -> bool:
        if self.allowed_processes and proc.name not in self.allowed_processes:
            return False
        return True

    def cpu_ok(self, proc: ProcessSnapshot) -> bool:
        return proc.cpu_pct <= self.max_cpu_pct

    def mem_ok(self, proc: ProcessSnapshot) -> bool:
        return proc.mem_mb <= self.max_mem_mb

    def port_allowed(self, conn: NetworkConnection) -> bool:
        if not self.allowed_remote_ports:
            return True
        return conn.remote_port in self.allowed_remote_ports

    def namespace_ok(self, proc: ProcessSnapshot) -> bool:
        return proc.namespace in self.allowed_namespaces


# ---------------------------------------------------------------------------
# Core engine
# ---------------------------------------------------------------------------

# Severity weights for gate scoring
_SEVERITY_DEDUCTIONS: Dict[str, int] = {
    AlertSeverity.CRITICAL.value: 6,
    AlertSeverity.HIGH.value:     3,
    AlertSeverity.MEDIUM.value:   1,
    AlertSeverity.LOW.value:      0,
}


class RuntimeSecurityMonitor:
    """
    Phase 57 — Runtime Security Monitoring & Anomalous Process Detection.

    Workflow:
      1. set_baseline()            — define expected behaviour for a workload
      2. ingest_process()          — snapshot a running process; auto-detects anomalies
      3. ingest_connection()       — observe a network connection; checks baseline
      4. raise_alert()             — manually inject an alert
      5. resolve_alert()           — mark alert resolved
      6. scan_processes()          — batch-ingest and analyse process list
      7. phase57_score()           — gate contribution 0-25
      8. summary() / persist_state()
    """

    def __init__(self) -> None:
        self._baselines: Dict[str, Baseline] = {}
        self._processes: List[ProcessSnapshot] = []
        self._connections: List[NetworkConnection] = []
        self._alerts: Dict[str, RuntimeAlert] = {}

    # ---- Baselines -------------------------------------------------------

    def set_baseline(self, baseline: Baseline) -> None:
        self._baselines[baseline.name] = baseline

    def get_baseline(self, name: str) -> Optional[Baseline]:
        return self._baselines.get(name)

    def baselines(self) -> List[Baseline]:
        return list(self._baselines.values())

    # ---- Process ingestion -----------------------------------------------

    def ingest_process(
        self,
        proc: ProcessSnapshot,
        baseline_name: Optional[str] = None,
    ) -> List[RuntimeAlert]:
        self._processes.append(proc)
        alerts: List[RuntimeAlert] = []
        baseline = self._baselines.get(baseline_name or "default")

        if baseline:
            if not baseline.process_allowed(proc):
                alerts.append(self._raise(
                    AnomalyType.UNEXPECTED_PROCESS,
                    AlertSeverity.HIGH,
                    proc,
                    description=f"Process '{proc.name}' not in allowed list for baseline '{baseline.name}'",
                    evidence={"allowed": baseline.allowed_processes},
                ))
            if not baseline.cpu_ok(proc):
                alerts.append(self._raise(
                    AnomalyType.RESOURCE_ABUSE,
                    AlertSeverity.MEDIUM,
                    proc,
                    description=f"Process '{proc.name}' CPU {proc.cpu_pct}% exceeds threshold {baseline.max_cpu_pct}%",
                ))
            if not baseline.mem_ok(proc):
                alerts.append(self._raise(
                    AnomalyType.RESOURCE_ABUSE,
                    AlertSeverity.MEDIUM,
                    proc,
                    description=f"Process '{proc.name}' MEM {proc.mem_mb}MB exceeds threshold {baseline.max_mem_mb}MB",
                ))
            if not baseline.allow_privileged and proc.is_privileged():
                alerts.append(self._raise(
                    AnomalyType.PRIVILEGE_ESCALATION,
                    AlertSeverity.CRITICAL,
                    proc,
                    description=f"Privileged process '{proc.name}' (user={proc.user}) detected",
                ))
            if not baseline.namespace_ok(proc):
                alerts.append(self._raise(
                    AnomalyType.CONTAINER_ESCAPE,
                    AlertSeverity.HIGH,
                    proc,
                    description=f"Process '{proc.name}' in unexpected namespace '{proc.namespace}'",
                ))
        return alerts

    def scan_processes(
        self,
        processes: List[ProcessSnapshot],
        baseline_name: Optional[str] = None,
    ) -> List[RuntimeAlert]:
        all_alerts: List[RuntimeAlert] = []
        for proc in processes:
            all_alerts.extend(self.ingest_process(proc, baseline_name))
        return all_alerts

    # ---- Network ingestion -----------------------------------------------

    def ingest_connection(
        self,
        conn: NetworkConnection,
        baseline_name: Optional[str] = None,
    ) -> Optional[RuntimeAlert]:
        self._connections.append(conn)
        baseline = self._baselines.get(baseline_name or "default")
        if baseline and not baseline.port_allowed(conn):
            proc_snap = ProcessSnapshot(pid=conn.pid, name=conn.process_name)
            return self._raise(
                AnomalyType.UNUSUAL_NETWORK_CONN,
                AlertSeverity.HIGH,
                proc_snap,
                description=(
                    f"Connection from '{conn.process_name}' to port {conn.remote_port} "
                    f"({conn.remote_addr}) not in allowed ports"
                ),
                evidence={"remote_addr": conn.remote_addr, "remote_port": conn.remote_port},
            )
        return None

    # ---- Manual alert management ----------------------------------------

    def raise_alert(self, alert: RuntimeAlert) -> RuntimeAlert:
        self._alerts[alert.alert_id] = alert
        return alert

    def resolve_alert(self, alert_id: str) -> bool:
        alert = self._alerts.get(alert_id)
        if not alert:
            return False
        alert.resolve()
        return True

    def suppress_alert(self, alert_id: str) -> bool:
        alert = self._alerts.get(alert_id)
        if not alert:
            return False
        alert.suppress()
        return True

    def alerts(self) -> List[RuntimeAlert]:
        return list(self._alerts.values())

    def active_alerts(self) -> List[RuntimeAlert]:
        return [a for a in self._alerts.values() if a.is_active()]

    def alerts_by_severity(self) -> Dict[str, List[RuntimeAlert]]:
        result: Dict[str, List[RuntimeAlert]] = {s.value: [] for s in AlertSeverity}
        for a in self._alerts.values():
            result[a.severity.value].append(a)
        return result

    def critical_alerts(self) -> List[RuntimeAlert]:
        return [a for a in self._alerts.values() if a.severity == AlertSeverity.CRITICAL]

    # ---- Scoring --------------------------------------------------------

    def phase57_score(self) -> float:
        """
        Gate contribution 0-25.
        Starts at 25; deducts per active (unresolved/unsuppressed) alert:
          CRITICAL: 6 pts, HIGH: 3 pts, MEDIUM: 1 pt, LOW: 0 pts.
        Floor at 0.
        """
        deductions = sum(
            _SEVERITY_DEDUCTIONS.get(a.severity.value, 0)
            for a in self._alerts.values()
            if a.is_active()
        )
        return max(0.0, round(25.0 - deductions, 2))

    # ---- Reporting -------------------------------------------------------

    def summary(self) -> dict:
        by_sev = self.alerts_by_severity()
        return {
            "status": "ok" if not self.active_alerts() else "alerts_active",
            "total_alerts": len(self._alerts),
            "active_alerts": len(self.active_alerts()),
            "resolved_alerts": sum(1 for a in self._alerts.values() if a.status == AlertStatus.RESOLVED),
            "suppressed_alerts": sum(1 for a in self._alerts.values() if a.status == AlertStatus.SUPPRESSED),
            "severity_breakdown": {k: len(v) for k, v in by_sev.items() if v},
            "processes_observed": len(self._processes),
            "connections_observed": len(self._connections),
            "baselines_configured": len(self._baselines),
            "phase57_score": self.phase57_score(),
        }

    def generate_report(self) -> dict:
        return {
            **self.summary(),
            "alerts": [a.to_dict() for a in self._alerts.values()],
            "processes": [p.to_dict() for p in self._processes[-20:]],
            "connections": [c.to_dict() for c in self._connections[-20:]],
        }

    def persist_state(
        self, output_path: str = "artifacts/phase57/runtime-monitor.json"
    ) -> str:
        import os
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        state = {
            "phase": 57,
            "engine": "RuntimeSecurityMonitor",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "alerts": [a.to_dict() for a in self._alerts.values()],
        }
        with open(output_path, "w") as f:
            json.dump(state, f, indent=2)
        return output_path

    # ---- Internal --------------------------------------------------------

    def _raise(
        self,
        anomaly_type: AnomalyType,
        severity: AlertSeverity,
        proc: ProcessSnapshot,
        description: str = "",
        evidence: Optional[Dict] = None,
    ) -> RuntimeAlert:
        alert = RuntimeAlert(
            anomaly_type=anomaly_type,
            severity=severity,
            source_pid=proc.pid,
            source_process=proc.name,
            scope=MonitoringScope.CONTAINER if proc.container_id else MonitoringScope.HOST,
            description=description,
            evidence=evidence or {},
        )
        self._alerts[alert.alert_id] = alert
        return alert


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_process(
    pid: int,
    name: str,
    user: str = "appuser",
    cpu_pct: float = 5.0,
    mem_mb: float = 128.0,
    state: ProcessState = ProcessState.RUNNING,
    container_id: Optional[str] = "ctr-default",
    namespace: str = "default",
    cmdline: str = "",
) -> ProcessSnapshot:
    return ProcessSnapshot(
        pid=pid,
        name=name,
        user=user,
        state=state,
        cpu_pct=cpu_pct,
        mem_mb=mem_mb,
        container_id=container_id,
        namespace=namespace,
        cmdline=cmdline,
    )


def make_connection(
    pid: int,
    process_name: str,
    remote_addr: str,
    remote_port: int,
    is_external: bool = False,
) -> NetworkConnection:
    return NetworkConnection(
        pid=pid,
        process_name=process_name,
        remote_addr=remote_addr,
        remote_port=remote_port,
        is_external=is_external,
    )
