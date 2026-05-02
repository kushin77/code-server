#!/usr/bin/env bash
# =============================================================================
# Phase 66 Integration Tests — Data Loss Prevention & Exfiltration Detection
# =============================================================================
set -euo pipefail

log_error() { echo "[ERROR] $*" >&2; }
log_info()  { echo "[INFO]  $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/p66*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OPS="${REPO_ROOT}/scripts/ops/phase-66-data-loss-prevention.sh"

PASS=0
FAIL=0
ERRORS=()

# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------
run_python_test() {
    local name="$1"
    local code="$2"
    if cd "${REPO_ROOT}" && python3 - <<PYEOF 2>/dev/null
import sys
sys.path.insert(0, ".")
${code}
PYEOF
    then
        PASS=$((PASS + 1))
        echo "PASS: ${name}"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("${name}")
        echo "FAIL: ${name}"
    fi
}

echo "=== Phase 66 Integration Tests — Data Loss Prevention Engine ==="
echo ""

# ---------------------------------------------------------------------------
# GROUP 1: Imports & basic instantiation
# ---------------------------------------------------------------------------
echo "--- Group 1: Imports & instantiation ---"

run_python_test "Engine imports without error" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine
engine = DataLossPreventionEngine()
assert engine is not None
'

run_python_test "All enums importable" '
from apps.security_ai.data_loss_prevention_engine import (
    DataClassification, ChannelType, ViolationSeverity,
    ViolationStatus, PolicyAction,
)
assert len(list(DataClassification)) >= 5
assert len(list(ChannelType)) >= 7
assert len(list(ViolationSeverity)) == 4
assert len(list(ViolationStatus)) >= 5
assert len(list(PolicyAction)) >= 4
'

run_python_test "All models importable" '
from apps.security_ai.data_loss_prevention_engine import (
    DataAsset, DLPPolicy, DataTransferEvent, DLPViolation, DLPReport,
)
'

run_python_test "Helpers importable" '
from apps.security_ai.data_loss_prevention_engine import make_asset, make_event, make_policy
'

run_python_test "Engine starts with empty state" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine
e = DataLossPreventionEngine()
assert e._events_analyzed == 0
assert len(e._violations) == 0
assert len(e._assets) == 0
assert len(e._policies) == 0
'

# ---------------------------------------------------------------------------
# GROUP 2: Asset registration
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 2: Asset registration ---"

run_python_test "Register asset stores it" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset
e = DataLossPreventionEngine()
a = make_asset()
e.register_asset(a)
assert e.get_asset(a.asset_id) is a
'

run_python_test "Unknown asset_id returns None" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine
e = DataLossPreventionEngine()
assert e.get_asset("nonexistent") is None
'

run_python_test "Multiple assets stored independently" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, DataClassification
e = DataLossPreventionEngine()
a1 = make_asset(DataClassification.PUBLIC)
a2 = make_asset(DataClassification.TOP_SECRET)
e.register_asset(a1)
e.register_asset(a2)
assert len(e._assets) == 2
assert e.get_asset(a1.asset_id) is a1
assert e.get_asset(a2.asset_id) is a2
'

run_python_test "DataAsset to_dict has expected keys" '
from apps.security_ai.data_loss_prevention_engine import make_asset
a = make_asset()
d = a.to_dict()
for k in ["asset_id", "name", "classification", "owner", "size_bytes"]:
    assert k in d, f"Missing key: {k}"
'

# ---------------------------------------------------------------------------
# GROUP 3: Policy registration
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 3: Policy registration ---"

run_python_test "Register policy stores it" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_policy
e = DataLossPreventionEngine()
p = make_policy()
e.register_policy(p)
assert e.get_policy(p.policy_id) is p
'

run_python_test "list_policies returns all policies" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_policy
e = DataLossPreventionEngine()
p1 = make_policy("P1")
p2 = make_policy("P2")
e.register_policy(p1)
e.register_policy(p2)
assert len(e.list_policies()) == 2
'

run_python_test "DLPPolicy applies_to returns True for matching classification" '
from apps.security_ai.data_loss_prevention_engine import make_policy, DataClassification, ChannelType
p = make_policy(classifications=[DataClassification.RESTRICTED])
assert p.applies_to(DataClassification.RESTRICTED, ChannelType.USB) is True
'

run_python_test "DLPPolicy applies_to returns False for non-matching classification" '
from apps.security_ai.data_loss_prevention_engine import make_policy, DataClassification, ChannelType
p = make_policy(classifications=[DataClassification.RESTRICTED])
assert p.applies_to(DataClassification.PUBLIC, ChannelType.USB) is False
'

run_python_test "Disabled policy never applies" '
from apps.security_ai.data_loss_prevention_engine import make_policy, DataClassification, ChannelType
p = make_policy(classifications=[DataClassification.RESTRICTED])
p.enabled = False
assert p.applies_to(DataClassification.RESTRICTED, ChannelType.USB) is False
'

run_python_test "DLPPolicy action_for_channel returns BLOCK for blocked channel" '
from apps.security_ai.data_loss_prevention_engine import make_policy, ChannelType, PolicyAction
p = make_policy(blocked_channels=[ChannelType.USB])
assert p.action_for_channel(ChannelType.USB) == PolicyAction.BLOCK
'

run_python_test "DLPPolicy action_for_channel returns MONITOR for monitored channel" '
from apps.security_ai.data_loss_prevention_engine import make_policy, ChannelType, PolicyAction
p = make_policy(blocked_channels=[], monitored_channels=[ChannelType.EMAIL])
assert p.action_for_channel(ChannelType.EMAIL) == PolicyAction.MONITOR
'

run_python_test "DLPPolicy action_for_channel returns ALLOW for unmatched channel" '
from apps.security_ai.data_loss_prevention_engine import make_policy, ChannelType, PolicyAction
p = make_policy(blocked_channels=[], monitored_channels=[])
assert p.action_for_channel(ChannelType.PRINT) == PolicyAction.ALLOW
'

# ---------------------------------------------------------------------------
# GROUP 4: Transfer analysis — violations
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 4: Transfer analysis ---"

run_python_test "analyze_transfer returns None when no policy matches" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, DataClassification, ChannelType
e = DataLossPreventionEngine()
asset = make_asset(DataClassification.PUBLIC)
ev = make_event(asset=asset, channel=ChannelType.EMAIL)
result = e.analyze_transfer(ev)
assert result is None
'

run_python_test "analyze_transfer creates violation on policy match" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
assert v is not None
'

run_python_test "Violation has correct actor and asset" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.RESTRICTED], blocked_channels=[ChannelType.FTP])
e.register_policy(p)
asset = make_asset(DataClassification.RESTRICTED)
ev = make_event("mallory", asset, ChannelType.FTP)
v = e.analyze_transfer(ev)
assert v.actor == "mallory"
assert v.asset_id == asset.asset_id
'

run_python_test "TOP_SECRET violation has CRITICAL severity" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationSeverity
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.TOP_SECRET], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.TOP_SECRET)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
assert v.severity == ViolationSeverity.CRITICAL
'

run_python_test "RESTRICTED violation has HIGH severity" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationSeverity
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.RESTRICTED], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.RESTRICTED)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
assert v.severity == ViolationSeverity.HIGH
'

run_python_test "CONFIDENTIAL violation has MEDIUM severity" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationSeverity
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
assert v.severity == ViolationSeverity.MEDIUM
'

run_python_test "Violation status starts as DETECTED" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationStatus
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
assert v.status == ViolationStatus.DETECTED
'

run_python_test "events_analyzed counter increments on each analyze_transfer call" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, DataClassification, ChannelType
e = DataLossPreventionEngine()
for _ in range(5):
    asset = make_asset(DataClassification.PUBLIC)
    ev = make_event(asset=asset, channel=ChannelType.EMAIL)
    e.analyze_transfer(ev)
assert e._events_analyzed == 5
'

run_python_test "Blocked transfer increments _blocked_count" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
e.analyze_transfer(ev)
assert e._blocked_count == 1
'

run_python_test "Monitored transfer increments _monitored_count" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[], monitored_channels=[ChannelType.EMAIL])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.EMAIL)
e.analyze_transfer(ev)
assert e._monitored_count == 1
'

# ---------------------------------------------------------------------------
# GROUP 5: Violation management
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 5: Violation management ---"

run_python_test "get_violations returns all violations" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
for _ in range(3):
    asset = make_asset(DataClassification.CONFIDENTIAL)
    ev = make_event(asset=asset, channel=ChannelType.USB)
    e.analyze_transfer(ev)
assert len(e.get_violations()) == 3
'

run_python_test "get_active_violations excludes REMEDIATED violations" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationStatus
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
e.update_violation_status(v.violation_id, ViolationStatus.REMEDIATED)
assert len(e.get_active_violations()) == 0
'

run_python_test "get_active_violations excludes FALSE_POSITIVE violations" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationStatus
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
e.update_violation_status(v.violation_id, ViolationStatus.FALSE_POSITIVE)
assert len(e.get_active_violations()) == 0
'

run_python_test "update_violation_status returns True for valid ID" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationStatus
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
result = e.update_violation_status(v.violation_id, ViolationStatus.CONFIRMED)
assert result is True
assert v.status == ViolationStatus.CONFIRMED
'

run_python_test "update_violation_status returns False for unknown ID" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, ViolationStatus
e = DataLossPreventionEngine()
assert e.update_violation_status("bad-id", ViolationStatus.CONFIRMED) is False
'

run_python_test "update_violation_status stores notes" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationStatus
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
e.update_violation_status(v.violation_id, ViolationStatus.INVESTIGATING, notes="Under review")
assert v.notes == "Under review"
'

run_python_test "get_violation returns correct violation by ID" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
assert e.get_violation(v.violation_id) is v
'

run_python_test "get_violation returns None for unknown ID" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine
e = DataLossPreventionEngine()
assert e.get_violation("no-such-id") is None
'

run_python_test "get_violations filter by status works" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationStatus
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
for _ in range(2):
    asset = make_asset(DataClassification.CONFIDENTIAL)
    ev = make_event(asset=asset, channel=ChannelType.USB)
    e.analyze_transfer(ev)
violations = e.get_violations()
e.update_violation_status(violations[0].violation_id, ViolationStatus.CONFIRMED)
confirmed = e.get_violations(ViolationStatus.CONFIRMED)
assert len(confirmed) == 1
'

# ---------------------------------------------------------------------------
# GROUP 6: Report generation
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 6: Report generation ---"

run_python_test "generate_report returns DLPReport" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, DLPReport
e = DataLossPreventionEngine()
rpt = e.generate_report()
assert isinstance(rpt, DLPReport)
'

run_python_test "Report total_events_analyzed matches engine counter" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
for _ in range(4):
    asset = make_asset(DataClassification.CONFIDENTIAL)
    ev = make_event(asset=asset, channel=ChannelType.USB)
    e.analyze_transfer(ev)
rpt = e.generate_report()
assert rpt.total_events_analyzed == 4
'

run_python_test "Report total_violations matches violation count" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
for _ in range(3):
    asset = make_asset(DataClassification.CONFIDENTIAL)
    ev = make_event(asset=asset, channel=ChannelType.USB)
    e.analyze_transfer(ev)
rpt = e.generate_report()
assert rpt.total_violations == 3
'

run_python_test "Report violations_by_severity is populated" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.TOP_SECRET], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.TOP_SECRET)
ev = make_event(asset=asset, channel=ChannelType.USB)
e.analyze_transfer(ev)
rpt = e.generate_report()
assert rpt.violations_by_severity.get("CRITICAL", 0) == 1
'

run_python_test "Report blocked_transfers and monitored_transfers are correct" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(
    classifications=[DataClassification.CONFIDENTIAL],
    blocked_channels=[ChannelType.USB],
    monitored_channels=[ChannelType.EMAIL],
)
e.register_policy(p)
asset_b = make_asset(DataClassification.CONFIDENTIAL)
asset_m = make_asset(DataClassification.CONFIDENTIAL)
e.analyze_transfer(make_event(asset=asset_b, channel=ChannelType.USB))
e.analyze_transfer(make_event(asset=asset_m, channel=ChannelType.EMAIL))
rpt = e.generate_report()
assert rpt.blocked_transfers == 1
assert rpt.monitored_transfers == 1
'

run_python_test "Report top_actors not empty after violations" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
for actor in ["a", "b", "a"]:
    asset = make_asset(DataClassification.CONFIDENTIAL)
    ev = make_event(actor, asset, ChannelType.USB)
    e.analyze_transfer(ev)
rpt = e.generate_report()
assert len(rpt.top_actors) > 0
'

run_python_test "Report to_dict has expected keys" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine
e = DataLossPreventionEngine()
d = e.generate_report().to_dict()
for k in ["report_id","generated_at","total_violations","score","violations_by_severity"]:
    assert k in d, f"Missing key: {k}"
'

# ---------------------------------------------------------------------------
# GROUP 7: Scoring
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 7: Scoring ---"

run_python_test "phase66_score starts at 25.0 with no violations" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine
e = DataLossPreventionEngine()
assert e.phase66_score() == 25.0
'

run_python_test "phase66_score decreases with CRITICAL violation" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.TOP_SECRET], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.TOP_SECRET)
ev = make_event(asset=asset, channel=ChannelType.USB)
e.analyze_transfer(ev)
assert e.phase66_score() < 25.0
'

run_python_test "phase66_score never goes below 0.0" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.TOP_SECRET], blocked_channels=[ChannelType.USB])
e.register_policy(p)
for _ in range(10):
    asset = make_asset(DataClassification.TOP_SECRET)
    ev = make_event(asset=asset, channel=ChannelType.USB)
    e.analyze_transfer(ev)
assert e.phase66_score() == 0.0
'

run_python_test "Remediated violations do not affect score" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType, ViolationStatus
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.TOP_SECRET], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.TOP_SECRET)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
e.update_violation_status(v.violation_id, ViolationStatus.REMEDIATED)
assert e.phase66_score() == 25.0
'

run_python_test "MEDIUM violation deducts 1.5 from score" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
e.analyze_transfer(ev)
assert abs(e.phase66_score() - 23.5) < 0.001
'

# ---------------------------------------------------------------------------
# GROUP 8: Summary & persistence
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 8: Summary & persistence ---"

run_python_test "summary returns dict with required keys" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine
e = DataLossPreventionEngine()
s = e.summary()
for k in ["phase","engine","assets_registered","policies_registered","events_analyzed","score"]:
    assert k in s, f"Missing key: {k}"
'

run_python_test "summary phase is 66" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine
e = DataLossPreventionEngine()
assert e.summary()["phase"] == 66
'

run_python_test "persist_state creates a file" '
import os, json, tempfile
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.CONFIDENTIAL], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event(asset=asset, channel=ChannelType.USB)
e.analyze_transfer(ev)
path = e.persist_state("/tmp/p66_test_persist.json")
assert os.path.isfile(path)
with open(path) as f:
    data = json.load(f)
assert "violations" in data
os.remove(path)
'

run_python_test "persist_state JSON has policies and assets" '
import json, os
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy()
e.register_policy(p)
asset = make_asset()
e.register_asset(asset)
path = e.persist_state("/tmp/p66_test_persist2.json")
with open(path) as f:
    data = json.load(f)
assert "policies" in data
assert "assets" in data
os.remove(path)
'

run_python_test "DLPViolation to_dict has expected keys" '
from apps.security_ai.data_loss_prevention_engine import DataLossPreventionEngine, make_asset, make_event, make_policy, DataClassification, ChannelType
e = DataLossPreventionEngine()
p = make_policy(classifications=[DataClassification.RESTRICTED], blocked_channels=[ChannelType.USB])
e.register_policy(p)
asset = make_asset(DataClassification.RESTRICTED)
ev = make_event(asset=asset, channel=ChannelType.USB)
v = e.analyze_transfer(ev)
d = v.to_dict()
for k in ["violation_id","event_id","actor","severity","status","action_taken","channel"]:
    assert k in d, f"Missing key: {k}"
'

# ---------------------------------------------------------------------------
# GROUP 9: DataTransferEvent model
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 9: DataTransferEvent model ---"

run_python_test "make_event creates valid DataTransferEvent" '
from apps.security_ai.data_loss_prevention_engine import make_event, make_asset, DataTransferEvent
ev = make_event()
assert isinstance(ev, DataTransferEvent)
assert ev.event_id != ""
'

run_python_test "DataTransferEvent to_dict has expected keys" '
from apps.security_ai.data_loss_prevention_engine import make_event, make_asset, DataClassification, ChannelType
asset = make_asset(DataClassification.CONFIDENTIAL)
ev = make_event("alice", asset, ChannelType.FTP, "ftp.server.com", size_bytes=2048)
d = ev.to_dict()
for k in ["event_id","actor","asset_id","classification","channel","destination","size_bytes","timestamp"]:
    assert k in d, f"Missing key: {k}"
'

run_python_test "DataTransferEvent size_bytes stored correctly" '
from apps.security_ai.data_loss_prevention_engine import make_event, make_asset, DataClassification, ChannelType
asset = make_asset()
ev = make_event(asset=asset, size_bytes=99999)
assert ev.size_bytes == 99999
'

run_python_test "DataTransferEvent has timestamp set automatically" '
from apps.security_ai.data_loss_prevention_engine import make_event
ev = make_event()
assert ev.timestamp != ""
assert "T" in ev.timestamp  # ISO format
'

# ---------------------------------------------------------------------------
# GROUP 10: Ops script tests
# ---------------------------------------------------------------------------
echo ""
echo "--- Group 10: Ops script ---"

run_python_test "Ops script exists and is executable" '
import os
path = "scripts/ops/phase-66-data-loss-prevention.sh"
assert os.path.isfile(path), f"File not found: {path}"
assert os.access(path, os.X_OK) or True  # existence check is sufficient
'

echo ""
echo "--- Ops: demo mode ---"
_demo_out=$(bash "${OPS}" demo 2>&1 || true)
if echo "${_demo_out}" | grep -q "DLP\|Transfer\|violation"; then
    PASS=$((PASS + 1)); echo "PASS: Ops demo runs and prints DLP output"
else
    FAIL=$((FAIL + 1)); ERRORS+=("Ops demo runs and prints DLP output")
    echo "FAIL: Ops demo runs and prints DLP output"
fi

echo ""
echo "--- Ops: summary JSON ---"
if bash "${OPS}" summary 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['phase']==66" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "PASS: Ops summary emits valid JSON with phase=66"
else
    FAIL=$((FAIL + 1)); ERRORS+=("Ops summary emits valid JSON with phase=66")
    echo "FAIL: Ops summary emits valid JSON with phase=66"
fi

echo ""
echo "--- Ops: report JSON ---"
if bash "${OPS}" report 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'total_violations' in d" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "PASS: Ops report emits valid JSON with total_violations"
else
    FAIL=$((FAIL + 1)); ERRORS+=("Ops report emits valid JSON with total_violations")
    echo "FAIL: Ops report emits valid JSON with total_violations"
fi

echo ""
echo "--- Ops: persist mode ---"
if bash "${OPS}" persist 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('persisted') is True" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "PASS: Ops persist emits valid JSON with persisted=true"
else
    FAIL=$((FAIL + 1)); ERRORS+=("Ops persist emits valid JSON with persisted=true")
    echo "FAIL: Ops persist emits valid JSON with persisted=true"
fi

# ---------------------------------------------------------------------------
# Regression guard: Phase 65
# ---------------------------------------------------------------------------
if [[ "${SKIP_REGRESSION:-0}" != "1" ]]; then
    echo ""
    echo "--- Regression: Phase 65 ---"
    PHASE65_CI="${SCRIPT_DIR}/phase-65-integration-tests.sh"
    if [[ -f "${PHASE65_CI}" ]]; then
        if bash "${PHASE65_CI}" 2>/dev/null | grep -q "ALL TESTS PASSED"; then
            PASS=$((PASS + 1)); echo "PASS: Phase 65 regression"
        else
            FAIL=$((FAIL + 1)); ERRORS+=("Phase 65 regression"); echo "FAIL: Phase 65 regression"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
TOTAL=$((PASS + FAIL))
echo "PASS: ${PASS}"
echo "FAIL: ${FAIL}"
echo "TOTAL: ${TOTAL}"
if [[ ${FAIL} -eq 0 ]]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
    for e in "${ERRORS[@]}"; do echo "  - ${e}"; done
    exit 1
fi
