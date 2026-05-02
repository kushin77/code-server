#!/bin/bash
# @file phase-54-integration-tests.sh
# @description Integration tests for Phase 54 — Cryptographic Asset Inventory & Key Lifecycle Management
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p54*.* 2>/dev/null || true' EXIT

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
echo "PHASE 54: CRYPTOGRAPHIC ASSET INVENTORY &"
echo "          KEY LIFECYCLE MANAGEMENT — INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Module imports
echo "GROUP 1: Module Import & API Surface"

run_python_test "Import CryptoAssetInventoryEngine" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine"

run_python_test "Import CryptoAsset" \
"from security_ai.crypto_asset_inventory import CryptoAsset"

run_python_test "Import InventoryReport" \
"from security_ai.crypto_asset_inventory import InventoryReport"

run_python_test "Import RotationEvent" \
"from security_ai.crypto_asset_inventory import RotationEvent"

run_python_test "Import AssetType enum (8 types)" \
"from security_ai.crypto_asset_inventory import AssetType
assert len(list(AssetType)) == 8"

run_python_test "Import AssetStatus enum (6 statuses)" \
"from security_ai.crypto_asset_inventory import AssetStatus
assert len(list(AssetStatus)) == 6"

run_python_test "Import RiskLevel enum (5 levels)" \
"from security_ai.crypto_asset_inventory import RiskLevel
assert len(list(RiskLevel)) == 5"

run_python_test "Import RotationPolicy enum (6 policies)" \
"from security_ai.crypto_asset_inventory import RotationPolicy
assert len(list(RotationPolicy)) == 6"

run_python_test "Import helper make_asset()" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType
a = make_asset('test', AssetType.SECRET)
assert a.name == 'test'"

echo ""

# GROUP 2: CryptoAsset status classification
echo "GROUP 2: CryptoAsset Status Classification"

run_python_test "Expired asset (negative days_until_expiry) → EXPIRED status" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, AssetStatus
a = make_asset('x', AssetType.SECRET, expires_in_days=-1)
assert a.compute_status() == AssetStatus.EXPIRED"

run_python_test "Asset expiring within warning window → EXPIRING status" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, AssetStatus
a = make_asset('x', AssetType.SECRET, expires_in_days=3, rotation_warning_days=7)
assert a.compute_status() == AssetStatus.EXPIRING"

run_python_test "Asset expiring far future → ACTIVE status" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, AssetStatus
a = make_asset('x', AssetType.SECRET, expires_in_days=120, rotation_warning_days=7)
assert a.compute_status() == AssetStatus.ACTIVE"

run_python_test "Revoked asset stays REVOKED regardless of expiry" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, AssetStatus
a = make_asset('x', AssetType.SECRET, expires_in_days=120)
a.revoke()
assert a.compute_status() == AssetStatus.REVOKED"

run_python_test "days_until_expiry() returns correct positive value" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType
a = make_asset('x', AssetType.SECRET, expires_in_days=10)
due = a.days_until_expiry()
assert due is not None and 9 <= due <= 10, due"

run_python_test "days_until_expiry() returns None when no expiry set" \
"from security_ai.crypto_asset_inventory import CryptoAsset
a = CryptoAsset(name='x')
assert a.days_until_expiry() is None"

echo ""

# GROUP 3: Risk level classification
echo "GROUP 3: Risk Level Classification"

run_python_test "EXPIRED → CRITICAL risk" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RiskLevel
a = make_asset('x', AssetType.SECRET, expires_in_days=-1)
assert a.risk_level() == RiskLevel.CRITICAL"

run_python_test "REVOKED → CRITICAL risk" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RiskLevel
a = make_asset('x', AssetType.SECRET, expires_in_days=30)
a.revoke()
assert a.risk_level() == RiskLevel.CRITICAL"

run_python_test "Expiring in 3 days → HIGH risk" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RiskLevel
a = make_asset('x', AssetType.SECRET, expires_in_days=3, rotation_warning_days=30)
assert a.risk_level() == RiskLevel.HIGH"

run_python_test "Expiring in 20 days → MEDIUM risk" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RiskLevel
a = make_asset('x', AssetType.SECRET, expires_in_days=20, rotation_warning_days=30)
assert a.risk_level() == RiskLevel.MEDIUM"

run_python_test "Active asset far from expiry → LOW risk" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RiskLevel
a = make_asset('x', AssetType.SECRET, expires_in_days=200, rotation_warning_days=30)
assert a.risk_level() == RiskLevel.LOW"

echo ""

# GROUP 4: Rotation policy & overdue detection
echo "GROUP 4: Rotation Policy & Overdue Detection"

run_python_test "is_overdue_for_rotation() False when last rotated recently" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RotationPolicy
a = make_asset('x', AssetType.SECRET, rotation_policy=RotationPolicy.MONTHLY,
               expires_in_days=30, last_rotated_days_ago=5)
assert not a.is_overdue_for_rotation()"

run_python_test "is_overdue_for_rotation() True when overdue" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RotationPolicy
a = make_asset('x', AssetType.SECRET, rotation_policy=RotationPolicy.WEEKLY,
               expires_in_days=30, last_rotated_days_ago=10)
assert a.is_overdue_for_rotation()"

run_python_test "RotationPolicy.NEVER → never overdue" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RotationPolicy
a = make_asset('x', AssetType.ASYMMETRIC_KEY, rotation_policy=RotationPolicy.NEVER,
               expires_in_days=None, last_rotated_days_ago=3650)
assert not a.is_overdue_for_rotation()"

run_python_test "rotate() updates last_rotated and expires_at" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, RotationPolicy
a = make_asset('x', AssetType.SECRET, rotation_policy=RotationPolicy.MONTHLY,
               expires_in_days=2)
a.rotate()
assert a.last_rotated is not None
assert a.expires_at is not None
assert a.days_until_expiry() > 25"

run_python_test "rotate() sets status ACTIVE" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, AssetStatus, RotationPolicy
a = make_asset('x', AssetType.SECRET, rotation_policy=RotationPolicy.MONTHLY, expires_in_days=2)
a.rotate()
assert a.status == AssetStatus.ACTIVE"

run_python_test "revoke() sets status REVOKED" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType, AssetStatus
a = make_asset('x', AssetType.SECRET, expires_in_days=100)
a.revoke()
assert a.status == AssetStatus.REVOKED"

echo ""

# GROUP 5: Engine asset registration
echo "GROUP 5: Engine — Asset Registration"

run_python_test "register_asset() stores asset" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
a = make_asset('test', AssetType.SECRET)
e.register_asset(a)
assert e.asset_count() == 1"

run_python_test "get_asset() retrieves by ID" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
a = make_asset('test', AssetType.SECRET)
e.register_asset(a)
assert e.get_asset(a.asset_id) is a"

run_python_test "get_asset() returns None for unknown ID" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine
e = CryptoAssetInventoryEngine()
assert e.get_asset('nonexistent') is None"

run_python_test "register_asset() logs creation event" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('test', AssetType.SECRET))
assert any(ev.event_type == 'creation' for ev in e.events())"

run_python_test "Multiple assets can be registered" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
for i in range(5):
    e.register_asset(make_asset(f'key-{i}', AssetType.API_TOKEN))
assert e.asset_count() == 5"

echo ""

# GROUP 6: Engine lifecycle actions
echo "GROUP 6: Engine — Lifecycle Actions"

run_python_test "rotate_asset() updates last_rotated on asset" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy
e = CryptoAssetInventoryEngine()
a = make_asset('test', AssetType.SECRET, rotation_policy=RotationPolicy.MONTHLY, expires_in_days=2)
e.register_asset(a)
ok = e.rotate_asset(a.asset_id)
assert ok
assert a.last_rotated is not None"

run_python_test "rotate_asset() logs rotation event" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy
e = CryptoAssetInventoryEngine()
a = make_asset('test', AssetType.SECRET, rotation_policy=RotationPolicy.MONTHLY, expires_in_days=2)
e.register_asset(a)
e.rotate_asset(a.asset_id)
assert any(ev.event_type == 'rotation' for ev in e.events())"

run_python_test "rotate_asset() returns False for unknown ID" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine
e = CryptoAssetInventoryEngine()
assert not e.rotate_asset('no-such-id')"

run_python_test "rotate_asset() returns False for revoked asset" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy
e = CryptoAssetInventoryEngine()
a = make_asset('test', AssetType.SECRET, rotation_policy=RotationPolicy.MONTHLY, expires_in_days=30)
e.register_asset(a)
e.revoke_asset(a.asset_id)
assert not e.rotate_asset(a.asset_id)"

run_python_test "revoke_asset() sets REVOKED status" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, AssetStatus
e = CryptoAssetInventoryEngine()
a = make_asset('test', AssetType.API_TOKEN, expires_in_days=100)
e.register_asset(a)
ok = e.revoke_asset(a.asset_id)
assert ok
assert a.status == AssetStatus.REVOKED"

run_python_test "revoke_asset() logs revocation event" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
a = make_asset('test', AssetType.API_TOKEN, expires_in_days=100)
e.register_asset(a)
e.revoke_asset(a.asset_id)
assert any(ev.event_type == 'revocation' for ev in e.events())"

run_python_test "rotate_overdue_assets() rotates all overdue" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy
e = CryptoAssetInventoryEngine()
for i in range(3):
    e.register_asset(make_asset(f'k{i}', AssetType.SECRET,
                                rotation_policy=RotationPolicy.WEEKLY,
                                expires_in_days=30, last_rotated_days_ago=10))
count = e.rotate_overdue_assets()
assert count == 3, count"

echo ""

# GROUP 7: Scan & analysis
echo "GROUP 7: Scan & Analysis"

run_python_test "scan() returns dict with required keys" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine
e = CryptoAssetInventoryEngine()
s = e.scan()
for k in ('active','expiring','expired','revoked','pending','rotated','overdue'):
    assert k in s, k"

run_python_test "scan() counts expired assets correctly" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('x', AssetType.SECRET, expires_in_days=-5))
e.register_asset(make_asset('y', AssetType.SECRET, expires_in_days=100))
s = e.scan()
assert s['expired'] == 1, s"

run_python_test "expiring_soon() returns assets within window" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('soon', AssetType.TLS_CERT, expires_in_days=5, rotation_warning_days=30))
e.register_asset(make_asset('far',  AssetType.TLS_CERT, expires_in_days=200, rotation_warning_days=30))
result = e.expiring_soon(days=30)
assert len(result) == 1
assert result[0].name == 'soon'"

run_python_test "expired_assets() returns only expired" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('a', AssetType.SECRET, expires_in_days=-1))
e.register_asset(make_asset('b', AssetType.SECRET, expires_in_days=50))
expired = e.expired_assets()
assert len(expired) == 1
assert expired[0].name == 'a'"

run_python_test "assets_by_risk() returns dict with risk levels" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('x', AssetType.SECRET, expires_in_days=100, rotation_warning_days=7))
by_risk = e.assets_by_risk()
assert isinstance(by_risk, dict)"

run_python_test "overdue_assets() returns only overdue" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('overdue', AssetType.SECRET,
                             rotation_policy=RotationPolicy.WEEKLY,
                             expires_in_days=30, last_rotated_days_ago=15))
e.register_asset(make_asset('fresh', AssetType.SECRET,
                             rotation_policy=RotationPolicy.MONTHLY,
                             expires_in_days=30, last_rotated_days_ago=2))
ods = e.overdue_assets()
assert len(ods) == 1
assert ods[0].name == 'overdue'"

echo ""

# GROUP 8: Scoring
echo "GROUP 8: Scoring"

run_python_test "phase54_score() = 25 with no assets" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine
e = CryptoAssetInventoryEngine()
assert e.phase54_score() == 25.0"

run_python_test "phase54_score() = 25 with only healthy assets" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
for i in range(5):
    e.register_asset(make_asset(f'k{i}', AssetType.SSH_KEY,
                                expires_in_days=200, rotation_warning_days=7))
assert e.phase54_score() == 25.0"

run_python_test "phase54_score() decreases with expired assets" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('ok',      AssetType.SECRET, expires_in_days=100, rotation_warning_days=7))
e.register_asset(make_asset('expired', AssetType.SECRET, expires_in_days=-1))
score = e.phase54_score()
assert score < 25.0, score"

run_python_test "phase54_score() is in range [0, 25]" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
for i in range(5):
    e.register_asset(make_asset(f'x{i}', AssetType.SECRET, expires_in_days=-i))
score = e.phase54_score()
assert 0.0 <= score <= 25.0, score"

run_python_test "InventoryReport.phase54_score() deducts 4 per CRITICAL" \
"from security_ai.crypto_asset_inventory import InventoryReport
r = InventoryReport(total_assets=5, risk_breakdown={'critical': 2, 'low': 3})
assert r.phase54_score() == 25.0 - 8"

run_python_test "InventoryReport.phase54_score() deducts 2 per HIGH" \
"from security_ai.crypto_asset_inventory import InventoryReport
r = InventoryReport(total_assets=5, risk_breakdown={'high': 3, 'low': 2})
assert r.phase54_score() == 25.0 - 6"

run_python_test "InventoryReport.phase54_score() floors at 0" \
"from security_ai.crypto_asset_inventory import InventoryReport
r = InventoryReport(total_assets=20, risk_breakdown={'critical': 10, 'high': 10})
assert r.phase54_score() == 0.0"

echo ""

# GROUP 9: Summary & reporting
echo "GROUP 9: Summary & Reporting"

run_python_test "summary() has required keys" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine
e = CryptoAssetInventoryEngine()
s = e.summary()
for k in ('status','total_assets','active','expiring','expired','revoked',
          'overdue_for_rotation','risk_breakdown','total_events','phase54_score'):
    assert k in s, k"

run_python_test "summary() status='no_assets' when empty" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine
e = CryptoAssetInventoryEngine()
assert e.summary()['status'] == 'no_assets'"

run_python_test "summary() status='ok' when assets exist" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('x', AssetType.SECRET, expires_in_days=30))
assert e.summary()['status'] == 'ok'"

run_python_test "generate_report() returns InventoryReport instance" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, InventoryReport, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('x', AssetType.SECRET, expires_in_days=30))
r = e.generate_report()
assert isinstance(r, InventoryReport)"

run_python_test "generate_report().to_dict() has all required keys" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType
e = CryptoAssetInventoryEngine()
e.register_asset(make_asset('x', AssetType.SECRET, expires_in_days=30))
d = e.generate_report().to_dict()
for k in ('report_id','generated_at','total_assets','active','expiring','expired',
          'revoked','risk_breakdown','phase54_score','assets','events'):
    assert k in d, k"

run_python_test "events() grows with each lifecycle action" \
"from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy
e = CryptoAssetInventoryEngine()
a = make_asset('x', AssetType.SECRET, rotation_policy=RotationPolicy.MONTHLY, expires_in_days=30)
e.register_asset(a)  # +1 creation event
e.rotate_asset(a.asset_id)  # +1 rotation event
e.revoke_asset(a.asset_id)  # +1 revocation event
assert len(e.events()) == 3"

echo ""

# GROUP 10: CryptoAsset serialisation
echo "GROUP 10: CryptoAsset Serialisation"

run_python_test "to_dict() has all required fields" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType
a = make_asset('mykey', AssetType.TLS_CERT, 'ops-team', expires_in_days=90)
d = a.to_dict()
for k in ('asset_id','name','asset_type','owner','rotation_policy','status',
          'live_status','risk_level','days_until_expiry','is_overdue_for_rotation',
          'created_at','expires_at','last_rotated','tags'):
    assert k in d, k"

run_python_test "to_dict() asset_type is string value" \
"from security_ai.crypto_asset_inventory import make_asset, AssetType
a = make_asset('x', AssetType.TLS_CERT)
assert isinstance(a.to_dict()['asset_type'], str)"

run_python_test "RotationEvent.to_dict() serialises correctly" \
"from security_ai.crypto_asset_inventory import RotationEvent
ev = RotationEvent(asset_id='aid', asset_name='test', event_type='rotation')
d = ev.to_dict()
for k in ('event_id','asset_id','asset_name','event_type','triggered_by','occurred_at','notes'):
    assert k in d, k"

echo ""

# GROUP 11: Ops script
echo "GROUP 11: Ops Script"

run_test "Ops script exists and is executable" \
    "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-54-crypto-asset-inventory.sh' ]]"

run_test "Ops script demo mode exits 0 and mentions Phase 54" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-54-crypto-asset-inventory.sh' demo 2>&1 | grep -i 'Phase 54'"

run_test "Ops script summary mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-54-crypto-asset-inventory.sh' summary 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

run_test "Ops script report mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-54-crypto-asset-inventory.sh' report 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

echo ""

# GROUP 12: Phase 53 regression guard
echo "GROUP 12: Phase 53 Regression Guard"

if [[ -z "${SKIP_REGRESSION:-}" ]]; then
    run_test "Phase 53 integration suite still passes" \
        "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-53-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
    echo "  ⏭  Phase 53 regression skipped (SKIP_REGRESSION=1)"
fi

echo ""

echo "============================================================"
echo "PHASE 54 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "✅  ALL TESTS PASSED — Phase 54 Cryptographic Asset Inventory verified"
    exit 0
else
    echo "❌  SOME TESTS FAILED — Review output above"
    exit 1
fi
