#!/bin/bash
# @file phase-54-threat-intelligence-correlation.sh
# @description Phase 54 — Threat Intelligence Correlation Engine
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'rm -f /tmp/p54*.tmp 2>/dev/null || true' EXIT
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

MODE="${1:-demo}"

cmd_demo() {
    log_info "PHASE 54: Threat Intelligence Correlation Engine" >&2
    "$PYTHON_CMD" <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, IOCType, ThreatCategory, make_ioc
)

engine = ThreatIntelligenceCorrelationEngine()

print("=== PHASE 54: Threat Intelligence Correlation Dashboard ===")
print()

# Feed A — high-confidence APT indicators
for val, ioc_type, conf in [
    ("192.168.1.100", IOCType.IP, 0.95),
    ("evil.example.com", IOCType.DOMAIN, 0.90),
    ("abc123deadbeef", IOCType.HASH_MD5, 0.85),
]:
    engine.ingest(make_ioc(ioc_type, val, "feed_apt_alpha", conf, ThreatCategory.APT, ["apt29"]))

# Feed B — corroborates some of the same IOCs
for val, ioc_type, conf in [
    ("192.168.1.100", IOCType.IP, 0.88),
    ("evil.example.com", IOCType.DOMAIN, 0.75),
    ("phish.example.net", IOCType.DOMAIN, 0.60),
]:
    engine.ingest(make_ioc(ioc_type, val, "feed_osint_beta", conf, ThreatCategory.PHISHING))

# Feed C — adds third confirmation for the IP
engine.ingest(make_ioc(IOCType.IP, "192.168.1.100", "feed_gov_cert", 0.99, ThreatCategory.APT))

snap = engine.snapshot()

for thr in snap.correlated_threats[:6]:
    print(f"  [{thr.strength.value.upper():9s}] {thr.value:30s} "
          f"priority={thr.priority_score:.1f}/25 "
          f"sources={len(thr.sources)}")

print()
s = engine.summary()
print(f"  Total IOCs:         {s['total_iocs']}")
print(f"  Unique Threats:     {s['unique_threats']}")
print(f"  Confirmed:          {s['confirmed']}")
print(f"  Probable:           {s['probable']}")
print(f"  High Priority:      {s['high_priority']}")
print(f"  Phase 54 Score:     {s['phase54_score']:.2f}/25")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, IOCType, ThreatCategory, make_ioc
)
engine = ThreatIntelligenceCorrelationEngine()
for v, t, c, f in [
    ("1.2.3.4", IOCType.IP, 0.9, "feed_a"),
    ("1.2.3.4", IOCType.IP, 0.8, "feed_b"),
    ("bad.example.com", IOCType.DOMAIN, 0.7, "feed_a"),
]:
    engine.ingest(make_ioc(t, v, f, c, ThreatCategory.MALWARE))
print(json.dumps(engine.summary(), indent=2))
PYEOF
}

cmd_lookup() {
    local ioc_val="${2:-192.168.1.100}"
    "$PYTHON_CMD" <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, IOCType, ThreatCategory, make_ioc
)
engine = ThreatIntelligenceCorrelationEngine()
engine.ingest(make_ioc(IOCType.IP, "${ioc_val}", "feed_a", 0.95, ThreatCategory.APT))
engine.ingest(make_ioc(IOCType.IP, "${ioc_val}", "feed_b", 0.80, ThreatCategory.APT))
t = engine.lookup(IOCType.IP, "${ioc_val}")
if t:
    print(json.dumps({
        "value": t.value, "strength": t.strength.value,
        "priority_score": t.priority_score,
        "sources": t.sources,
    }, indent=2))
else:
    print(json.dumps({"result": "not_found"}))
PYEOF
}

case "$MODE" in
    demo)   cmd_demo ;;
    summary) cmd_summary ;;
    lookup)  cmd_lookup "$@" ;;
    *)
        echo "Usage: $0 [demo|summary|lookup [ioc_value]]"
        exit 1
        ;;
esac
