#!/bin/bash
# @file phase-58-integration-tests.sh
# @description Integration tests for Phase 58 — Secrets Management & Credential Rotation Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p58*.* 2>/dev/null || true' EXIT

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
echo "PHASE 58: SECRETS MANAGEMENT & CREDENTIAL ROTATION ENGINE"
echo "          INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Imports
echo "GROUP 1: Module Import & API Surface"

run_python_test "Import SecretsManager" \
"from security_ai.secrets_manager import SecretsManager"

run_python_test "Import Secret" \
"from security_ai.secrets_manager import Secret"

run_python_test "Import AccessEvent" \
"from security_ai.secrets_manager import AccessEvent"

run_python_test "Import RotationRecord" \
"from security_ai.secrets_manager import RotationRecord"

run_python_test "Import SecretsReport" \
"from security_ai.secrets_manager import SecretsReport"

run_python_test "Import SecretType enum (7 types)" \
"from security_ai.secrets_manager import SecretType
assert len(list(SecretType)) == 7"

run_python_test "Import SecretStatus enum (5 statuses)" \
"from security_ai.secrets_manager import SecretStatus
assert len(list(SecretStatus)) == 5"

run_python_test "Import RotationPolicy enum (6 policies)" \
"from security_ai.secrets_manager import RotationPolicy
assert len(list(RotationPolicy)) == 6"

run_python_test "Import AccessOutcome enum (3 outcomes)" \
"from security_ai.secrets_manager import AccessOutcome
assert len(list(AccessOutcome)) == 3"

run_python_test "Import RiskLevel enum (5 levels)" \
"from security_ai.secrets_manager import RiskLevel
assert len(list(RiskLevel)) == 5"

run_python_test "Import helpers make_secret() and make_access_event()" \
"from security_ai.secrets_manager import make_secret, make_access_event
s = make_secret('test-secret')
assert s.name == 'test-secret'"

echo ""

# GROUP 2: Secret properties
echo "GROUP 2: Secret Properties & Status"

run_python_test "status = ACTIVE for fresh secret" \
"from security_ai.secrets_manager import make_secret, SecretStatus, RotationPolicy
s = make_secret('fresh', rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=5)
assert s.status == SecretStatus.ACTIVE"

run_python_test "status = EXPIRED for overdue secret" \
"from security_ai.secrets_manager import make_secret, SecretStatus, RotationPolicy
s = make_secret('stale', rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=35)
assert s.status == SecretStatus.EXPIRED"

run_python_test "status = EXPIRING within warning window" \
"from security_ai.secrets_manager import make_secret, SecretStatus, RotationPolicy
s = make_secret('soon', rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=25)
assert s.status == SecretStatus.EXPIRING"

run_python_test "status = ACTIVE for MANUAL policy regardless of age" \
"from security_ai.secrets_manager import make_secret, SecretStatus, RotationPolicy
s = make_secret('manual', rotation_policy=RotationPolicy.MANUAL, days_since_rotation=9999)
assert s.status == SecretStatus.ACTIVE"

run_python_test "status = REVOKED after revoke()" \
"from security_ai.secrets_manager import make_secret, SecretStatus
s = make_secret('revokeme')
s.revoke()
assert s.status == SecretStatus.REVOKED"

run_python_test "risk_level = CRITICAL for expired secret" \
"from security_ai.secrets_manager import make_secret, RiskLevel, RotationPolicy
s = make_secret('expired', rotation_policy=RotationPolicy.WEEKLY, days_since_rotation=10)
assert s.risk_level == RiskLevel.CRITICAL"

run_python_test "risk_level = HIGH for unencrypted secret" \
"from security_ai.secrets_manager import make_secret, RiskLevel
s = make_secret('cleartext', is_encrypted_at_rest=False)
assert s.risk_level == RiskLevel.HIGH"

run_python_test "risk_level = MEDIUM for expiring secret" \
"from security_ai.secrets_manager import make_secret, RiskLevel, RotationPolicy
s = make_secret('expiring', rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=25)
assert s.risk_level == RiskLevel.MEDIUM"

run_python_test "risk_level = LOW for healthy encrypted active secret" \
"from security_ai.secrets_manager import make_secret, RiskLevel, RotationPolicy
s = make_secret('healthy', rotation_policy=RotationPolicy.MONTHLY,
                is_encrypted_at_rest=True, days_since_rotation=5)
assert s.risk_level == RiskLevel.LOW"

run_python_test "rotate() increments rotated_count" \
"from security_ai.secrets_manager import make_secret
s = make_secret('rotate-me')
assert s.rotated_count == 0
s.rotate()
assert s.rotated_count == 1
s.rotate()
assert s.rotated_count == 2"

run_python_test "rotate() resets expiry" \
"from security_ai.secrets_manager import make_secret, SecretStatus, RotationPolicy
s = make_secret('rotate-me', rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=35)
assert s.status == SecretStatus.EXPIRED
s.rotate()
assert s.status == SecretStatus.ACTIVE"

run_python_test "to_dict() contains all required fields" \
"from security_ai.secrets_manager import make_secret
d = make_secret('check').to_dict()
for k in ('secret_id','name','secret_type','rotation_policy','owner_service','environment',
          'is_encrypted_at_rest','status','risk_level','rotated_count',
          'created_at','last_rotated_at','expires_at','days_until_expiry','tags'):
    assert k in d, k"

run_python_test "expires_at = None for MANUAL policy" \
"from security_ai.secrets_manager import make_secret, RotationPolicy
s = make_secret('manual', rotation_policy=RotationPolicy.MANUAL)
assert s.expires_at is None
assert s.days_until_expiry is None"

echo ""

# GROUP 3: AccessEvent & RotationRecord
echo "GROUP 3: AccessEvent & RotationRecord"

run_python_test "AccessEvent to_dict() has all fields" \
"from security_ai.secrets_manager import make_access_event, AccessOutcome
e = make_access_event('sid-001', 'svc-a', AccessOutcome.GRANTED)
d = e.to_dict()
for k in ('event_id','secret_id','accessor','outcome','reason','accessed_at'):
    assert k in d, k"

run_python_test "RotationRecord to_dict() has all fields" \
"from security_ai.secrets_manager import RotationRecord
r = RotationRecord(secret_id='sid-001', triggered_by='policy')
d = r.to_dict()
for k in ('record_id','secret_id','triggered_by','rotated_at','success','notes'):
    assert k in d, k"

echo ""

# GROUP 4: SecretsManager registration
echo "GROUP 4: SecretsManager Registration & Retrieval"

run_python_test "register_secret() stores and retrieves secret" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
s = make_secret('my-secret')
m.register_secret(s)
assert m.get_secret(s.secret_id) is s"

run_python_test "get_secret() returns None for unknown ID" \
"from security_ai.secrets_manager import SecretsManager
m = SecretsManager()
assert m.get_secret('no-such-id') is None"

run_python_test "secrets() returns all registered secrets" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
for i in range(4):
    m.register_secret(make_secret(f'secret-{i}'))
assert len(m.secrets()) == 4"

run_python_test "secrets_for_service() filters by owner" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
m.register_secret(make_secret('a', owner_service='auth'))
m.register_secret(make_secret('b', owner_service='auth'))
m.register_secret(make_secret('c', owner_service='billing'))
assert len(m.secrets_for_service('auth')) == 2"

echo ""

# GROUP 5: Rotation
echo "GROUP 5: Rotation Engine"

run_python_test "rotate_secret() returns RotationRecord" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
s = m.register_secret(make_secret('rot'))
rec = m.rotate_secret(s.secret_id)
assert rec is not None"

run_python_test "rotate_secret() increments secret rotated_count" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
s = m.register_secret(make_secret('rot'))
m.rotate_secret(s.secret_id)
assert s.rotated_count == 1"

run_python_test "rotate_secret() logs into rotation_history()" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
s = m.register_secret(make_secret('rot'))
m.rotate_secret(s.secret_id, triggered_by='manual', notes='security incident')
assert len(m.rotation_history()) == 1
assert m.rotation_history()[0].triggered_by == 'manual'"

run_python_test "rotate_secret() returns None for unknown ID" \
"from security_ai.secrets_manager import SecretsManager
m = SecretsManager()
assert m.rotate_secret('no-such-id') is None"

run_python_test "rotate_secret() returns None for revoked secret" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
s = m.register_secret(make_secret('rev'))
m.revoke_secret(s.secret_id)
assert m.rotate_secret(s.secret_id) is None"

run_python_test "rotate_all_expired() rotates all expired secrets" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
for i in range(3):
    m.register_secret(make_secret(f'exp-{i}', rotation_policy=RotationPolicy.WEEKLY,
                                   days_since_rotation=10))
records = m.rotate_all_expired()
assert len(records) == 3
assert len(m.expired_secrets()) == 0"

run_python_test "rotate_all_expired() skips revoked secrets" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
s = m.register_secret(make_secret('exp', rotation_policy=RotationPolicy.WEEKLY,
                                   days_since_rotation=10))
m.revoke_secret(s.secret_id)
records = m.rotate_all_expired()
assert len(records) == 0"

echo ""

# GROUP 6: Revocation
echo "GROUP 6: Revocation"

run_python_test "revoke_secret() returns True" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
s = m.register_secret(make_secret('rev'))
assert m.revoke_secret(s.secret_id)"

run_python_test "revoke_secret() returns False for unknown ID" \
"from security_ai.secrets_manager import SecretsManager
m = SecretsManager()
assert not m.revoke_secret('no-such-id')"

run_python_test "revoked_secrets() returns only revoked" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
s1 = m.register_secret(make_secret('a'))
s2 = m.register_secret(make_secret('b'))
m.revoke_secret(s1.secret_id)
revoked = m.revoked_secrets()
assert len(revoked) == 1
assert revoked[0].secret_id == s1.secret_id"

echo ""

# GROUP 7: Access logging
echo "GROUP 7: Access Logging"

run_python_test "record_access() stores event" \
"from security_ai.secrets_manager import SecretsManager, make_access_event, AccessOutcome
m = SecretsManager()
e = make_access_event('sid-1', 'svc-a', AccessOutcome.GRANTED)
m.record_access(e)
assert len(m.access_log()) == 1"

run_python_test "access_denied_events() filters DENIED outcomes" \
"from security_ai.secrets_manager import SecretsManager, make_access_event, AccessOutcome
m = SecretsManager()
m.record_access(make_access_event('s1', 'a', AccessOutcome.GRANTED))
m.record_access(make_access_event('s2', 'b', AccessOutcome.DENIED))
m.record_access(make_access_event('s3', 'c', AccessOutcome.DENIED))
assert len(m.access_denied_events()) == 2"

echo ""

# GROUP 8: Queries
echo "GROUP 8: Query Methods"

run_python_test "expired_secrets() returns only expired" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
m.register_secret(make_secret('ok',  rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=5))
m.register_secret(make_secret('exp', rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=35))
assert len(m.expired_secrets()) == 1"

run_python_test "expiring_secrets() returns within warning window" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
m.register_secret(make_secret('ok',   rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=5))
m.register_secret(make_secret('soon', rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=25))
assert len(m.expiring_secrets()) == 1"

run_python_test "unencrypted_secrets() returns cleartext secrets" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
m.register_secret(make_secret('enc',   is_encrypted_at_rest=True))
m.register_secret(make_secret('clear', is_encrypted_at_rest=False))
assert len(m.unencrypted_secrets()) == 1"

run_python_test "secrets_by_status() groups all statuses" \
"from security_ai.secrets_manager import SecretsManager, SecretStatus
m = SecretsManager()
by_status = m.secrets_by_status()
for s in SecretStatus:
    assert s.value in by_status"

run_python_test "secrets_by_risk() groups all risk levels" \
"from security_ai.secrets_manager import SecretsManager, RiskLevel
m = SecretsManager()
by_risk = m.secrets_by_risk()
for r in RiskLevel:
    assert r.value in by_risk"

run_python_test "scan_secrets() returns (secret, risk_level) tuples" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
m.register_secret(make_secret('a'))
m.register_secret(make_secret('b'))
results = m.scan_secrets()
assert len(results) == 2
assert all(len(t) == 2 for t in results)"

echo ""

# GROUP 9: Scoring
echo "GROUP 9: Scoring"

run_python_test "phase58_score() = 25 for all-healthy secrets" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
for i in range(3):
    m.register_secret(make_secret(f's{i}', rotation_policy=RotationPolicy.MONTHLY,
                                   is_encrypted_at_rest=True, days_since_rotation=5))
assert m.phase58_score() == 25.0"

run_python_test "phase58_score() decreases with expired secret" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
m.register_secret(make_secret('expired', rotation_policy=RotationPolicy.MONTHLY,
                               days_since_rotation=35))
assert m.phase58_score() < 25.0"

run_python_test "one expired deducts 5 pts" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
m.register_secret(make_secret('exp', rotation_policy=RotationPolicy.MONTHLY, days_since_rotation=35))
assert m.phase58_score() == 20.0"

run_python_test "one unencrypted deducts 4 pts" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
m.register_secret(make_secret('cleartext', is_encrypted_at_rest=False))
assert m.phase58_score() == 21.0"

run_python_test "phase58_score() floors at 0" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
for i in range(10):
    m.register_secret(make_secret(f'exp-{i}', rotation_policy=RotationPolicy.DAILY,
                                   is_encrypted_at_rest=False, days_since_rotation=5))
assert m.phase58_score() == 0.0"

run_python_test "phase58_score() in range [0, 25]" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
for i in range(5):
    m.register_secret(make_secret(f's{i}', rotation_policy=RotationPolicy.MONTHLY,
                                   days_since_rotation=i*8))
score = m.phase58_score()
assert 0.0 <= score <= 25.0"

run_python_test "SecretsReport.phase58_score() max 15 deduction for expired" \
"from security_ai.secrets_manager import SecretsReport
r = SecretsReport(expired_count=10)
assert r.phase58_score() == 25.0 - 15"

echo ""

# GROUP 10: Summary & reporting
echo "GROUP 10: Summary & Reporting"

run_python_test "summary() has all required keys" \
"from security_ai.secrets_manager import SecretsManager
m = SecretsManager()
s = m.summary()
for k in ('status','total_secrets','active','expiring','expired','revoked',
          'unencrypted','rotation_rate','access_events','denied_events',
          'rotation_records','phase58_score'):
    assert k in s, k"

run_python_test "summary() status='ok' for all-healthy vault" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
m.register_secret(make_secret('healthy', rotation_policy=RotationPolicy.MONTHLY,
                               is_encrypted_at_rest=True, days_since_rotation=5))
assert m.summary()['status'] == 'ok'"

run_python_test "summary() status='attention_required' with expired secret" \
"from security_ai.secrets_manager import SecretsManager, RotationPolicy, make_secret
m = SecretsManager()
m.register_secret(make_secret('expired', rotation_policy=RotationPolicy.MONTHLY,
                               days_since_rotation=35))
assert m.summary()['status'] == 'attention_required'"

run_python_test "generate_report() returns SecretsReport" \
"from security_ai.secrets_manager import SecretsManager, SecretsReport
m = SecretsManager()
r = m.generate_report()
assert isinstance(r, SecretsReport)"

run_python_test "generate_report().to_dict() includes phase58_score" \
"from security_ai.secrets_manager import SecretsManager
m = SecretsManager()
d = m.generate_report().to_dict()
assert 'phase58_score' in d"

run_python_test "rotation_rate reported in summary" \
"from security_ai.secrets_manager import SecretsManager, make_secret
m = SecretsManager()
s = m.register_secret(make_secret('rot'))
m.rotate_secret(s.secret_id)
m.rotate_secret(s.secret_id)
summary = m.summary()
assert summary['rotation_records'] == 2"

echo ""

# GROUP 11: Ops script
echo "GROUP 11: Ops Script"

run_test "Ops script exists and is executable" \
    "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-58-secrets-manager.sh' ]]"

run_test "Ops script demo mode exits 0" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-58-secrets-manager.sh' demo"

run_test "Ops script summary mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-58-secrets-manager.sh' summary 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

run_test "Ops script report mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-58-secrets-manager.sh' report 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

run_test "Ops script report output has phase58_score field" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-58-secrets-manager.sh' report 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); assert \"phase58_score\" in d'"

echo ""

# GROUP 12: Phase 57 regression guard
echo "GROUP 12: Phase 57 Regression Guard"

if [[ -z "${SKIP_REGRESSION:-}" ]]; then
    run_test "Phase 57 integration suite still passes" \
        "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-57-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
    echo "  ⏭  Phase 57 regression skipped (SKIP_REGRESSION=1)"
fi

echo ""

echo "============================================================"
echo "PHASE 58 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "✅  ALL TESTS PASSED — Phase 58 Secrets Manager verified"
    exit 0
else
    echo "❌  SOME TESTS FAILED — Review output above"
    exit 1
fi
