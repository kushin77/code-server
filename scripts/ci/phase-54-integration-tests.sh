#!/bin/bash
# @file phase-54-integration-tests.sh
# @description Integration tests for Phase 54 — Threat Intelligence Correlation Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p54*.* /tmp/p54_reg53.log 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
    local name="$1" cmd="$2"
    ((TOTAL++)) || true
    if eval "$cmd" > /tmp/p54_last.out 2>&1; then
        echo "  ✓ $name"; ((PASS++)) || true
    else
        echo "  ✗ $name"; ((FAIL++)) || true
        [[ -s /tmp/p54_last.out ]] && head -5 /tmp/p54_last.out | sed 's/^/    /'
    fi
}

py() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
$1
PYEOF
}

echo ""
echo "============================================================"
echo "  PHASE 54 — THREAT INTELLIGENCE CORRELATION ENGINE"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------
# GROUP 1: Module imports
# -----------------------------------------------------------------------
echo "GROUP 1: Module imports"

run_test "ThreatIntelligenceCorrelationEngine importable" \
    "py 'from security_ai.threat_intelligence_correlation import ThreatIntelligenceCorrelationEngine; print(\"ok\")' | grep -q ok"

run_test "IOCRecord importable" \
    "py 'from security_ai.threat_intelligence_correlation import IOCRecord; print(\"ok\")' | grep -q ok"

run_test "CorrelatedThreat importable" \
    "py 'from security_ai.threat_intelligence_correlation import CorrelatedThreat; print(\"ok\")' | grep -q ok"

run_test "ThreatFeedSnapshot importable" \
    "py 'from security_ai.threat_intelligence_correlation import ThreatFeedSnapshot; print(\"ok\")' | grep -q ok"

run_test "FeedSource importable" \
    "py 'from security_ai.threat_intelligence_correlation import FeedSource; print(\"ok\")' | grep -q ok"

run_test "IOCType has 7 values" \
    "py '
from security_ai.threat_intelligence_correlation import IOCType
assert len(list(IOCType)) == 7
print(\"ok\")
' | grep -q ok"

run_test "FeedConfidence has 3 values" \
    "py '
from security_ai.threat_intelligence_correlation import FeedConfidence
assert len(list(FeedConfidence)) == 3
print(\"ok\")
' | grep -q ok"

run_test "ThreatCategory has 8 values" \
    "py '
from security_ai.threat_intelligence_correlation import ThreatCategory
assert len(list(ThreatCategory)) == 8
print(\"ok\")
' | grep -q ok"

run_test "CorrelationStrength has 3 values" \
    "py '
from security_ai.threat_intelligence_correlation import CorrelationStrength
assert len(list(CorrelationStrength)) == 3
print(\"ok\")
' | grep -q ok"

run_test "make_ioc helper importable" \
    "py 'from security_ai.threat_intelligence_correlation import make_ioc; print(\"ok\")' | grep -q ok"

run_test "intel_score helper importable" \
    "py 'from security_ai.threat_intelligence_correlation import intel_score; print(\"ok\")' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 2: IOCRecord properties
# -----------------------------------------------------------------------
echo ""
echo "GROUP 2: IOCRecord properties"

run_test "confidence ≥0.80 → HIGH" \
    "py '
from security_ai.threat_intelligence_correlation import make_ioc, IOCType, FeedConfidence
r = make_ioc(IOCType.IP, \"1.2.3.4\", \"feed\", 0.85)
assert r.feed_confidence == FeedConfidence.HIGH
print(\"ok\")
' | grep -q ok"

run_test "confidence 0.65 → MEDIUM" \
    "py '
from security_ai.threat_intelligence_correlation import make_ioc, IOCType, FeedConfidence
r = make_ioc(IOCType.IP, \"1.2.3.4\", \"feed\", 0.65)
assert r.feed_confidence == FeedConfidence.MEDIUM
print(\"ok\")
' | grep -q ok"

run_test "confidence 0.30 → LOW" \
    "py '
from security_ai.threat_intelligence_correlation import make_ioc, IOCType, FeedConfidence
r = make_ioc(IOCType.IP, \"1.2.3.4\", \"feed\", 0.30)
assert r.feed_confidence == FeedConfidence.LOW
print(\"ok\")
' | grep -q ok"

run_test "normalized_key lowercases domain" \
    "py '
from security_ai.threat_intelligence_correlation import make_ioc, IOCType
r = make_ioc(IOCType.DOMAIN, \"Evil.Example.COM\", \"feed\")
assert r.normalized_key == \"domain:evil.example.com\", r.normalized_key
print(\"ok\")
' | grep -q ok"

run_test "normalized_key format: type:value" \
    "py '
from security_ai.threat_intelligence_correlation import make_ioc, IOCType
r = make_ioc(IOCType.IP, \"10.0.0.1\", \"feed\")
assert r.normalized_key == \"ip:10.0.0.1\"
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 3: Ingestion
# -----------------------------------------------------------------------
echo ""
echo "GROUP 3: IOC ingestion"

run_test "ingest() adds to ioc_store" \
    "py '
from security_ai.threat_intelligence_correlation import ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_a\"))
assert len(e.ioc_store) == 1
print(\"ok\")
' | grep -q ok"

run_test "ingest_batch() returns count" \
    "py '
from security_ai.threat_intelligence_correlation import ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
e = ThreatIntelligenceCorrelationEngine()
records = [make_ioc(IOCType.IP, f\"1.2.3.{i}\", \"feed_a\") for i in range(5)]
n = e.ingest_batch(records)
assert n == 5
print(\"ok\")
' | grep -q ok"

run_test "duplicate IOC across feeds adds two ioc_store entries" \
    "py '
from security_ai.threat_intelligence_correlation import ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_a\"))
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_b\"))
assert len(e.ioc_store) == 2
print(\"ok\")
' | grep -q ok"

run_test "load_feed() with None loader returns 0" \
    "py '
from security_ai.threat_intelligence_correlation import ThreatIntelligenceCorrelationEngine, FeedSource
e = ThreatIntelligenceCorrelationEngine()
e.register_feed(FeedSource(name=\"f\", base_confidence=0.8))
assert e.load_feed(\"f\") == 0
print(\"ok\")
' | grep -q ok"

run_test "load_feed() with loader ingests records" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, FeedSource, make_ioc, IOCType
)
records = [make_ioc(IOCType.IP, f\"10.0.0.{i}\", \"feed_x\") for i in range(3)]
e = ThreatIntelligenceCorrelationEngine()
e.register_feed(FeedSource(name=\"feed_x\", base_confidence=0.9, loader=lambda: records))
n = e.load_feed(\"feed_x\")
assert n == 3 and len(e.ioc_store) == 3
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 4: Correlation strength
# -----------------------------------------------------------------------
echo ""
echo "GROUP 4: Correlation strength"

run_test "Single feed → CANDIDATE" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType, CorrelationStrength
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_a\"))
threats = e.correlate()
assert threats[0].strength == CorrelationStrength.CANDIDATE, threats[0].strength
print(\"ok\")
' | grep -q ok"

run_test "Two feeds → PROBABLE" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType, CorrelationStrength
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_a\"))
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_b\"))
threats = e.correlate()
assert threats[0].strength == CorrelationStrength.PROBABLE, threats[0].strength
print(\"ok\")
' | grep -q ok"

run_test "Three feeds → CONFIRMED" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType, CorrelationStrength
)
e = ThreatIntelligenceCorrelationEngine()
for f in [\"feed_a\",\"feed_b\",\"feed_c\"]:
    e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", f))
threats = e.correlate()
assert threats[0].strength == CorrelationStrength.CONFIRMED
print(\"ok\")
' | grep -q ok"

run_test "Distinct IOCs remain separate threats" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_a\"))
e.ingest(make_ioc(IOCType.IP, \"5.6.7.8\", \"feed_a\"))
threats = e.correlate()
assert len(threats) == 2
print(\"ok\")
' | grep -q ok"

run_test "Threats sorted by priority_score descending" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
# High-priority: confirmed by 3 feeds
for f in [\"a\",\"b\",\"c\"]:
    e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", f, 0.95))
# Low-priority: single feed
e.ingest(make_ioc(IOCType.IP, \"9.9.9.9\", \"a\", 0.30))
threats = e.correlate()
scores = [t.priority_score for t in threats]
assert scores == sorted(scores, reverse=True), scores
print(\"ok\")
' | grep -q ok"

run_test "max_confidence picks highest across feeds" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_a\", 0.70))
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_b\", 0.95))
threats = e.correlate()
assert threats[0].max_confidence == 0.95
print(\"ok\")
' | grep -q ok"

run_test "Tags aggregated across records without duplicates" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"a\", tags=[\"apt29\",\"russia\"]))
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"b\", tags=[\"apt29\",\"c2\"]))
threats = e.correlate()
tags = threats[0].tags
assert len(tags) == len(set(tags)), f\"duplicates in {tags}\"
assert \"apt29\" in tags and \"russia\" in tags and \"c2\" in tags
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 5: priority_score and phase54_contribution
# -----------------------------------------------------------------------
echo ""
echo "GROUP 5: priority_score and phase54_contribution"

run_test "priority_score in [0, 25]" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
for f in [\"a\",\"b\",\"c\"]:
    e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", f, 0.99))
for t in e.correlate():
    assert 0.0 <= t.priority_score <= 25.0, t.priority_score
print(\"ok\")
' | grep -q ok"

run_test "phase54_contribution = 25 - priority_score" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
for f in [\"a\",\"b\"]:
    e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", f, 0.80))
t = e.correlate()[0]
assert abs((t.phase54_contribution + t.priority_score) - 25.0) < 0.01
print(\"ok\")
' | grep -q ok"

run_test "CONFIRMED high-confidence threat has highest priority" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
for f in [\"a\",\"b\",\"c\"]:
    e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", f, 0.99))
e.ingest(make_ioc(IOCType.IP, \"9.9.9.9\", \"a\", 0.30))
threats = e.correlate()
assert threats[0].priority_score > threats[-1].priority_score
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 6: phase54_score
# -----------------------------------------------------------------------
echo ""
echo "GROUP 6: phase54_score()"

run_test "No IOCs → score=25.0" \
    "py '
from security_ai.threat_intelligence_correlation import ThreatIntelligenceCorrelationEngine, intel_score
e = ThreatIntelligenceCorrelationEngine()
assert intel_score(e) == 25.0
print(\"ok\")
' | grep -q ok"

run_test "Only low-priority threats → score near 25.0" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType, intel_score
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"9.9.9.9\", \"a\", 0.10))
sc = intel_score(e)
assert sc >= 20.0, sc
print(\"ok\")
' | grep -q ok"

run_test "All confirmed high-confidence → score reduced" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType, intel_score
)
e = ThreatIntelligenceCorrelationEngine()
for i in range(5):
    for f in [\"a\",\"b\",\"c\"]:
        e.ingest(make_ioc(IOCType.IP, f\"1.2.3.{i}\", f, 0.99))
sc = intel_score(e)
assert sc < 25.0, sc
print(\"ok\")
' | grep -q ok"

run_test "score is in [0.0, 25.0]" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType, intel_score
)
e = ThreatIntelligenceCorrelationEngine()
for i in range(10):
    for f in [\"a\",\"b\",\"c\"]:
        e.ingest(make_ioc(IOCType.IP, f\"10.0.0.{i}\", f, 0.99))
sc = intel_score(e)
assert 0.0 <= sc <= 25.0, sc
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 7: snapshot()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 7: snapshot()"

run_test "snapshot() returns ThreatFeedSnapshot" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, ThreatFeedSnapshot, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"a\"))
snap = e.snapshot()
assert isinstance(snap, ThreatFeedSnapshot)
print(\"ok\")
' | grep -q ok"

run_test "snapshot.total_iocs matches store count" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
for i in range(4):
    e.ingest(make_ioc(IOCType.IP, f\"1.2.3.{i}\", \"a\"))
snap = e.snapshot()
assert snap.total_iocs == 4
print(\"ok\")
' | grep -q ok"

run_test "snapshot.confirmed_count counts CONFIRMED threats" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
for f in [\"a\",\"b\",\"c\"]:
    e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", f))
snap = e.snapshot()
assert snap.confirmed_count == 1
print(\"ok\")
' | grep -q ok"

run_test "snapshot.phase54_score consistent with engine.phase54_score" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"a\"))
snap = e.snapshot()
assert snap.phase54_score == e.phase54_score()
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 8: lookup()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 8: lookup()"

run_test "lookup() returns None for unknown IOC" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
assert e.lookup(IOCType.IP, \"9.9.9.9\") is None
print(\"ok\")
' | grep -q ok"

run_test "lookup() returns CorrelatedThreat for known IOC" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, CorrelatedThreat, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", \"feed_a\"))
t = e.lookup(IOCType.IP, \"1.2.3.4\")
assert isinstance(t, CorrelatedThreat)
print(\"ok\")
' | grep -q ok"

run_test "lookup() case-insensitive on domain" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
e.ingest(make_ioc(IOCType.DOMAIN, \"Evil.Example.COM\", \"feed_a\"))
t = e.lookup(IOCType.DOMAIN, \"evil.example.com\")
assert t is not None
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 9: summary()
# -----------------------------------------------------------------------
echo ""
echo "GROUP 9: summary()"

run_test "summary() contains all required keys" \
    "py '
from security_ai.threat_intelligence_correlation import ThreatIntelligenceCorrelationEngine
e = ThreatIntelligenceCorrelationEngine()
s = e.summary()
for k in [\"total_iocs\",\"registered_feeds\",\"unique_threats\",\"confirmed\",
          \"probable\",\"candidate\",\"high_priority\",\"phase54_score\"]:
    assert k in s, f\"missing {k}\"
print(\"ok\")
' | grep -q ok"

run_test "summary confirmed/probable/candidate tally is correct" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, make_ioc, IOCType
)
e = ThreatIntelligenceCorrelationEngine()
# Confirmed: 3 feeds for IP A
for f in [\"a\",\"b\",\"c\"]:
    e.ingest(make_ioc(IOCType.IP, \"1.2.3.4\", f))
# Probable: 2 feeds for IP B
for f in [\"a\",\"b\"]:
    e.ingest(make_ioc(IOCType.IP, \"5.6.7.8\", f))
# Candidate: 1 feed for domain
e.ingest(make_ioc(IOCType.DOMAIN, \"bad.example.com\", \"a\"))
s = e.summary()
assert s[\"confirmed\"] == 1, s
assert s[\"probable\"] == 1, s
assert s[\"candidate\"] == 1, s
print(\"ok\")
' | grep -q ok"

run_test "Feed registration tracked in summary" \
    "py '
from security_ai.threat_intelligence_correlation import (
    ThreatIntelligenceCorrelationEngine, FeedSource
)
e = ThreatIntelligenceCorrelationEngine()
e.register_feed(FeedSource(\"f1\", 0.9))
e.register_feed(FeedSource(\"f2\", 0.7))
s = e.summary()
assert s[\"registered_feeds\"] == 2
print(\"ok\")
' | grep -q ok"

# -----------------------------------------------------------------------
# GROUP 10: Ops script integration
# -----------------------------------------------------------------------
echo ""
echo "GROUP 10: Ops script integration"

OPS="${PROJECT_ROOT}/scripts/ops/phase-54-threat-intelligence-correlation.sh"
[[ -x "$OPS" ]] || chmod +x "$OPS"

run_test "Ops script exists" "[[ -f '$OPS' ]]"

run_test "demo mode exits 0" \
    "bash '$OPS' demo > /tmp/p54demo.out 2>&1"

run_test "demo outputs PHASE 54" \
    "grep -q 'PHASE 54' /tmp/p54demo.out"

run_test "demo shows Phase 54 Score" \
    "grep -q 'Phase 54 Score' /tmp/p54demo.out"

run_test "summary mode outputs valid JSON" \
    "bash '$OPS' summary > /tmp/p54sum.out 2>&1 && python3 -c 'import json; json.load(open(\"/tmp/p54sum.out\"))'"

run_test "summary contains phase54_score" \
    "python3 -c 'import json; d=json.load(open(\"/tmp/p54sum.out\")); assert \"phase54_score\" in d'"

run_test "lookup mode exits 0" \
    "bash '$OPS' lookup 10.0.0.1 > /tmp/p54look.out 2>&1"

run_test "lookup outputs valid JSON" \
    "python3 -c 'import json; json.load(open(\"/tmp/p54look.out\"))'"

# -----------------------------------------------------------------------
# GROUP 11: Phase 53 regression guard
# -----------------------------------------------------------------------
echo ""
echo "GROUP 11: Phase 53 regression guard"

run_test "Phase 53 integration suite still passes" \
    "timeout 150 bash '${PROJECT_ROOT}/scripts/ci/phase-53-integration-tests.sh' > /tmp/p54_reg53.log 2>&1"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================================================"
echo "PHASE 54 TEST RESULTS"
echo "============================================================"
echo "PASS:  $PASS"
echo "FAIL:  $FAIL"
echo "TOTAL: $TOTAL"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "✅  ALL TESTS PASSED — Phase 54 Threat Intelligence Correlation verified"
    exit 0
else
    echo ""
    echo "❌  SOME TESTS FAILED"
    exit 1
fi
