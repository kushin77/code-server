#!/bin/bash
# @file phase-61-integration-tests.sh
# @description Integration tests for Phase 61 — Access Governance Engine

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p61*.* 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

PASS=0; FAIL=0; TOTAL=0

run_test() {
  local name="$1" cmd="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $name"; PASS=$((PASS + 1))
  else
    echo "  ✗ $name"; FAIL=$((FAIL + 1))
  fi
}

run_python_test() {
  local name="$1" code="$2"
  TOTAL=$((TOTAL + 1))
  if "$PYTHON_CMD" - <<PYEOF >/dev/null 2>&1
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
echo "PHASE 61: ACCESS GOVERNANCE — INTEGRATION TESTS"
echo "============================================================"

# Group 1
run_python_test "Import engine" "from security_ai.access_governance_engine import AccessGovernanceEngine"
run_python_test "Import enums" "from security_ai.access_governance_engine import IdentityType, IdentityStatus, PermissionRisk, ReviewStatus, DriftSeverity"
run_python_test "Import models" "from security_ai.access_governance_engine import Permission, Role, Identity, AccessReview, DriftFinding, AccessGovernanceReport"
run_python_test "Enum size IdentityType" "from security_ai.access_governance_engine import IdentityType; assert len(list(IdentityType)) == 3"
run_python_test "Enum size DriftSeverity" "from security_ai.access_governance_engine import DriftSeverity; assert len(list(DriftSeverity)) == 4"

# Group 2
run_python_test "Permission key format" "from security_ai.access_governance_engine import make_permission; p=make_permission('s3','read'); assert p.key()=='s3:read'"
run_python_test "Role permission_keys includes all" "from security_ai.access_governance_engine import make_role, make_permission; r=make_role('r',[make_permission('a','read'),make_permission('b','write')]); assert len(r.permission_keys())==2"
run_python_test "Role to_dict has fields" "from security_ai.access_governance_engine import make_role, make_permission; d=make_role('r',[make_permission('x','read')]).to_dict(); assert 'role_id' in d and 'permissions' in d"
run_python_test "Identity to_dict has fields" "from security_ai.access_governance_engine import make_identity; d=make_identity('u').to_dict(); assert 'identity_id' in d and 'assigned_roles' in d"
run_python_test "AccessReview to_dict has fields" "from security_ai.access_governance_engine import AccessReview; d=AccessReview(identity_id='i', reviewer='r').to_dict(); assert 'status' in d and d['status']=='pending'"
run_python_test "DriftFinding to_dict has fields" "from security_ai.access_governance_engine import DriftFinding; d=DriftFinding(identity_id='i').to_dict(); assert 'severity' in d and 'reason' in d"

# Group 3
run_python_test "Register role and identity" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_role, make_permission, make_identity; e=AccessGovernanceEngine(); r=e.register_role(make_role('reader',[make_permission('db','read')])); i=e.register_identity(make_identity('alice')); assert r.role_id and i.identity_id"
run_python_test "Assign role succeeds for active identity" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_role, make_permission, make_identity; e=AccessGovernanceEngine(); r=e.register_role(make_role('reader',[make_permission('db','read')])); i=e.register_identity(make_identity('alice')); assert e.assign_role(i.identity_id,r.role_id)"
run_python_test "Assign role fails for unknown identity" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_role, make_permission; e=AccessGovernanceEngine(); r=e.register_role(make_role('reader',[make_permission('db','read')])); assert not e.assign_role('missing',r.role_id)"
run_python_test "Assign role fails for unknown role" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); assert not e.assign_role(i.identity_id,'missing')"
run_python_test "Revoke role removes assignment" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_role, make_permission, make_identity; e=AccessGovernanceEngine(); r=e.register_role(make_role('reader',[make_permission('db','read')])); i=e.register_identity(make_identity('alice')); e.assign_role(i.identity_id,r.role_id); assert e.revoke_role(i.identity_id,r.role_id)"
run_python_test "Revoke role false when absent" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); assert not e.revoke_role(i.identity_id,'x')"

# Group 4
run_python_test "Add direct permission works" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); assert e.add_direct_permission(i.identity_id, make_permission('db','write'))"
run_python_test "Effective permissions include direct" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); e.add_direct_permission(i.identity_id, make_permission('db','write')); assert 'db:write' in e.effective_permissions(i.identity_id)"
run_python_test "Effective permissions include role perms" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission, make_role; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); r=e.register_role(make_role('reader',[make_permission('s3','read')])); e.assign_role(i.identity_id,r.role_id); assert 's3:read' in e.effective_permissions(i.identity_id)"
run_python_test "Privileged role count computed" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission, make_role; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('svc')); r=e.register_role(make_role('admin',[make_permission('iam','admin')],is_privileged=True)); e.assign_role(i.identity_id,r.role_id); assert e.privileged_role_count(i.identity_id)==1"
run_python_test "Permission risk CRITICAL" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); assert e.classify_permission_risk('iam:admin').value=='critical'"
run_python_test "Permission risk HIGH" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); assert e.classify_permission_risk('db:delete').value=='high'"
run_python_test "Permission risk LOW" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); assert e.classify_permission_risk('db:read').value=='low'"

# Group 5
run_python_test "No drift with matching baseline" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); e.add_direct_permission(i.identity_id, make_permission('db','read')); e.set_least_privilege_baseline(i.identity_id,['db:read']); assert e.detect_privilege_drift(i.identity_id) is None"
run_python_test "Medium drift for excessive permission" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); e.add_direct_permission(i.identity_id, make_permission('db','read')); e.add_direct_permission(i.identity_id, make_permission('db','write')); e.set_least_privilege_baseline(i.identity_id,['db:read']); f=e.detect_privilege_drift(i.identity_id); assert f and f.severity.value in ['medium','high','critical']"
run_python_test "High drift for privileged role" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission, make_role; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('svc')); r=e.register_role(make_role('admin',[make_permission('db','write')],is_privileged=True)); e.assign_role(i.identity_id,r.role_id); e.set_least_privilege_baseline(i.identity_id,[]); f=e.detect_privilege_drift(i.identity_id); assert f and f.severity.value in ['high','critical']"
run_python_test "Critical drift for critical permission" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('svc')); e.add_direct_permission(i.identity_id, make_permission('iam','admin')); e.set_least_privilege_baseline(i.identity_id,[]); f=e.detect_privilege_drift(i.identity_id); assert f and f.severity.value=='critical'"
run_python_test "High drift for suspended identity retaining access" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission, IdentityStatus; e=AccessGovernanceEngine(); i=make_identity('old'); i.status=IdentityStatus.SUSPENDED; i=e.register_identity(i); e.add_direct_permission(i.identity_id, make_permission('db','read')); f=e.detect_privilege_drift(i.identity_id); assert f and f.severity.value=='high'"
run_python_test "scan_all_drift returns list" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('u')); e.add_direct_permission(i.identity_id, make_permission('db','write')); e.set_least_privilege_baseline(i.identity_id,['db:read']); arr=e.scan_all_drift(); assert isinstance(arr,list) and len(arr)==1"

# Group 6
run_python_test "Create review for known identity" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); r=e.create_review(i.identity_id,'secops'); assert r is not None"
run_python_test "Create review fails for unknown identity" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); assert e.create_review('missing','secops') is None"
run_python_test "Set review status updates" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, ReviewStatus; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); r=e.create_review(i.identity_id,'secops'); assert e.set_review_status(r.review_id, ReviewStatus.APPROVED)"
run_python_test "Set review status false for unknown id" "from security_ai.access_governance_engine import AccessGovernanceEngine, ReviewStatus; e=AccessGovernanceEngine(); assert not e.set_review_status('missing', ReviewStatus.APPROVED)"
run_python_test "pending_reviews returns only pending" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, ReviewStatus; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); r1=e.create_review(i.identity_id,'secops'); r2=e.create_review(i.identity_id,'secops'); e.set_review_status(r2.review_id, ReviewStatus.APPROVED); assert len(e.pending_reviews())==1"

# Group 7
run_python_test "findings_by_severity has all keys" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); d=e.findings_by_severity(); assert all(k in d for k in ['critical','high','medium','low'])"
run_python_test "privileged_identities returns identities with privileged roles" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_role, make_permission; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('svc')); r=e.register_role(make_role('admin',[make_permission('x','write')],is_privileged=True)); e.assign_role(i.identity_id,r.role_id); assert len(e.privileged_identities())==1"
run_python_test "generate_report returns dataclass" "from security_ai.access_governance_engine import AccessGovernanceEngine, AccessGovernanceReport; e=AccessGovernanceEngine(); r=e.generate_report(); assert isinstance(r, AccessGovernanceReport)"
run_python_test "Report to_dict includes phase61_score" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); d=e.generate_report().to_dict(); assert 'phase61_score' in d"
run_python_test "summary has required keys" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); s=e.summary(); assert all(k in s for k in ['status','total_identities','phase61_score'])"
run_python_test "phase61_score bounded" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); x=e.phase61_score(); assert 0<=x<=25"

# Group 8
run_python_test "Score 25 with no issues" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); assert e.phase61_score()==25.0"
run_python_test "Score decreases for critical findings" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('svc')); e.add_direct_permission(i.identity_id, make_permission('iam','admin')); e.set_least_privilege_baseline(i.identity_id,[]); e.scan_all_drift(); assert e.phase61_score()<25"
run_python_test "Score decreases for pending reviews" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity; e=AccessGovernanceEngine(); i=e.register_identity(make_identity('alice')); e.create_review(i.identity_id,'secops'); assert e.phase61_score()<25"
run_python_test "Score floors at zero" "from security_ai.access_governance_engine import AccessGovernanceEngine, make_identity, make_permission, make_role; e=AccessGovernanceEngine();
admin_role=e.register_role(make_role('admin',[make_permission('db','delete')],is_privileged=True))
for n in range(5):
 i=e.register_identity(make_identity(f'crit{n}')); e.add_direct_permission(i.identity_id, make_permission('iam','admin')); e.set_least_privilege_baseline(i.identity_id,[])
for n in range(5):
 i=e.register_identity(make_identity(f'high{n}')); e.assign_role(i.identity_id, admin_role.role_id); e.set_least_privilege_baseline(i.identity_id,[])
e.scan_all_drift()
for ident in list(e._identities.keys())[:6]: e.create_review(ident,'secops')
assert e.phase61_score()==0.0"

# Group 9
run_python_test "persist_state writes file" "import os, tempfile; from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); d=tempfile.mkdtemp(); p=e.persist_state(os.path.join(d,'state.json')); assert os.path.exists(p)"
run_python_test "make_role helper" "from security_ai.access_governance_engine import make_role, make_permission; r=make_role('reader',[make_permission('db','read')]); assert r.name=='reader'"
run_python_test "make_identity helper" "from security_ai.access_governance_engine import make_identity, IdentityType; i=make_identity('svc', IdentityType.SERVICE); assert i.identity_type.value=='service'"
run_python_test "Engine lists reviews/findings" "from security_ai.access_governance_engine import AccessGovernanceEngine; e=AccessGovernanceEngine(); assert isinstance(e.reviews(),list) and isinstance(e.findings(),list)"

# Group 10 ops
run_test "Ops script exists" "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-61-access-governance.sh' ]]"
run_test "Ops demo runs" "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-61-access-governance.sh' demo 2>&1); echo \"\$output\" | grep -q 'Phase 61'"
run_test "Ops summary JSON" "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-61-access-governance.sh' summary 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json;json.load(sys.stdin)'"
run_test "Ops report JSON" "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-61-access-governance.sh' report 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json;json.load(sys.stdin)'"

# Group 11 regression
if [[ -z "${SKIP_REGRESSION:-}" ]]; then
  run_test "Phase 60 regression" "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-60-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
  echo "  ⏭  Phase 60 regression skipped (SKIP_REGRESSION=1)"
fi

echo "============================================================"
echo "PHASE 61 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"

if [[ "$FAIL" -eq 0 ]]; then
  echo "✅  ALL TESTS PASSED — Phase 61 Access Governance verified"
  exit 0
else
  echo "❌  SOME TESTS FAILED — Review output above"
  exit 1
fi
