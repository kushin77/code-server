#!/bin/bash
# @file phase-59-forensic-investigation.sh
# @description Phase 59 — Forensic Investigation & Chain of Custody Engine
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p59*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 59: Forensic Investigation & Chain of Custody Engine" >&2
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.forensic_investigation_engine import (
    ForensicInvestigationEngine, EvidenceType, FindingSeverity
)

engine = ForensicInvestigationEngine()

print("=== PHASE 59: Forensic Investigation Dashboard ===")
print()

# Open a case
case = engine.open_case("Malware Incident on Host-31")
print(f"  Case opened: [{case.case_id}] {case.title}")
print()

# Collect evidence
ev1 = engine.collect_evidence(
    case.case_id, EvidenceType.DISK_IMAGE, "Full disk image from host-31",
    "/mnt/forensics/host31.img", "analyst@corp.io",
    sha256_hash="abc123def456" * 5 + "abc1",
)
ev2 = engine.collect_evidence(
    case.case_id, EvidenceType.LOG_FILE, "Application logs",
    "/var/log/app.log", "analyst@corp.io",
    sha256_hash="xyz789uvw012" * 5 + "xyz7",
)
print(f"  Evidence collected: {case.total_evidence}")
print(f"    • {ev1.item_type.value}: {ev1.description}")
print(f"    • {ev2.item_type.value}: {ev2.description}")
print()

# Verify hashes
engine.verify_evidence_hash(case.case_id, ev1.evidence_id, ev1.sha256_hash, "analyst@corp.io")
print(f"  Verification: {case.verified_evidence}/{case.total_evidence} verified")
print()

# Add findings
finding = engine.add_finding(
    case.case_id, FindingSeverity.HIGH, "Malware Execution",
    "Evidence of WinRAR exploitation chain detected",
    evidence_ids=[ev1.evidence_id, ev2.evidence_id],
)
print(f"  Findings: {case.critical_findings} critical, {case.high_findings} high")
print()

print(f"  Phase 59 Score: {engine.phase59_score():.2f}/25")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.forensic_investigation_engine import (
    ForensicInvestigationEngine, EvidenceType, FindingSeverity
)
engine = ForensicInvestigationEngine()
case1 = engine.open_case("Incident A")
engine.collect_evidence(case1.case_id, EvidenceType.DISK_IMAGE, "disk", "/path/a", "analyst")
engine.collect_evidence(case1.case_id, EvidenceType.LOG_FILE, "logs", "/path/b", "analyst")
case2 = engine.open_case("Incident B")
engine.collect_evidence(case2.case_id, EvidenceType.MEMORY_DUMP, "mem", "/path/c", "analyst")
engine.close_case(case1.case_id)
print(json.dumps(engine.summary(), indent=2))
PYEOF
}

cmd_report() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.forensic_investigation_engine import (
    ForensicInvestigationEngine, EvidenceType, FindingSeverity
)
engine = ForensicInvestigationEngine()
case = engine.open_case("Forensic Investigation - Supply Chain Attack")
ev = engine.collect_evidence(
    case.case_id, EvidenceType.EXECUTABLE, "Compromised binary",
    "/opt/service/app", "security@corp.io",
    sha256_hash="d" * 64, size_bytes=2048576
)
engine.verify_evidence_hash(case.case_id, ev.evidence_id, ev.sha256_hash, "analyst")
finding = engine.add_finding(case.case_id, FindingSeverity.CRITICAL,
    "Supply Chain Compromise", "External package execution detected")
print(json.dumps(engine.case_report(case.case_id), indent=2))
PYEOF
}

case "$MODE" in
    demo)      cmd_demo ;;
    summary)   cmd_summary ;;
    report)    cmd_report ;;
    *)
        echo "Usage: $0 [demo|summary|report]"
        exit 1
        ;;
esac
