#!/bin/bash
# @file phase-56-integration-tests.sh
# @description Integration tests for Phase 56 — Supply Chain Security & Dependency Risk Engine
# @since 2026-05-01

set -o pipefail

log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/p56*.* 2>/dev/null || true' EXIT

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
echo "PHASE 56: SUPPLY CHAIN SECURITY &"
echo "          DEPENDENCY RISK ENGINE — INTEGRATION TESTS"
echo "============================================================"
echo ""

# GROUP 1: Imports
echo "GROUP 1: Module Import & API Surface"

run_python_test "Import SupplyChainSecurityEngine" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine"

run_python_test "Import Dependency" \
"from security_ai.supply_chain_security import Dependency"

run_python_test "Import CVE" \
"from security_ai.supply_chain_security import CVE"

run_python_test "Import SBOMEntry" \
"from security_ai.supply_chain_security import SBOMEntry"

run_python_test "Import SupplyChainReport" \
"from security_ai.supply_chain_security import SupplyChainReport"

run_python_test "Import DependencyType enum (4 types)" \
"from security_ai.supply_chain_security import DependencyType
assert len(list(DependencyType)) == 4"

run_python_test "Import Ecosystem enum (7 ecosystems)" \
"from security_ai.supply_chain_security import Ecosystem
assert len(list(Ecosystem)) == 7"

run_python_test "Import VulnerabilitySeverity enum (5 levels)" \
"from security_ai.supply_chain_security import VulnerabilitySeverity
assert len(list(VulnerabilitySeverity)) == 5"

run_python_test "Import LicenseRisk enum (4 categories)" \
"from security_ai.supply_chain_security import LicenseRisk
assert len(list(LicenseRisk)) == 4"

run_python_test "Import ProvenanceStatus enum (4 statuses)" \
"from security_ai.supply_chain_security import ProvenanceStatus
assert len(list(ProvenanceStatus)) == 4"

run_python_test "Import DependencyRisk enum (5 levels)" \
"from security_ai.supply_chain_security import DependencyRisk
assert len(list(DependencyRisk)) == 5"

run_python_test "Import helpers make_dependency() and make_cve()" \
"from security_ai.supply_chain_security import make_dependency, make_cve, Ecosystem
d = make_dependency('requests', '2.31.0', Ecosystem.PYPI)
assert d.name == 'requests'"

echo ""

# GROUP 2: License classification
echo "GROUP 2: License Classification"

run_python_test "classify_license MIT → ALLOWED" \
"from security_ai.supply_chain_security import classify_license, LicenseRisk
assert classify_license('MIT') == LicenseRisk.ALLOWED"

run_python_test "classify_license Apache-2.0 → ALLOWED" \
"from security_ai.supply_chain_security import classify_license, LicenseRisk
assert classify_license('Apache-2.0') == LicenseRisk.ALLOWED"

run_python_test "classify_license GPL-3.0 → BLOCKED" \
"from security_ai.supply_chain_security import classify_license, LicenseRisk
assert classify_license('GPL-3.0') == LicenseRisk.BLOCKED"

run_python_test "classify_license AGPL-3.0 → BLOCKED" \
"from security_ai.supply_chain_security import classify_license, LicenseRisk
assert classify_license('AGPL-3.0') == LicenseRisk.BLOCKED"

run_python_test "classify_license MPL-2.0 → RESTRICTED" \
"from security_ai.supply_chain_security import classify_license, LicenseRisk
assert classify_license('MPL-2.0') == LicenseRisk.RESTRICTED"

run_python_test "classify_license unknown string → UNKNOWN" \
"from security_ai.supply_chain_security import classify_license, LicenseRisk
assert classify_license('Proprietary-XYZ') == LicenseRisk.UNKNOWN"

run_python_test "classify_license empty string → UNKNOWN" \
"from security_ai.supply_chain_security import classify_license, LicenseRisk
assert classify_license('') == LicenseRisk.UNKNOWN"

echo ""

# GROUP 3: Dependency risk classification
echo "GROUP 3: Dependency Risk Classification"

run_python_test "CRITICAL CVE → CRITICAL dep risk" \
"from security_ai.supply_chain_security import make_dependency, make_cve, Ecosystem, DependencyRisk, VulnerabilitySeverity
d = make_dependency('log4j', '2.14.1', Ecosystem.MAVEN)
d.cves.append(make_cve('CVE-2021-44228', VulnerabilitySeverity.CRITICAL, 10.0))
assert d.risk == DependencyRisk.CRITICAL"

run_python_test "HIGH CVE → HIGH dep risk" \
"from security_ai.supply_chain_security import make_dependency, make_cve, Ecosystem, DependencyRisk, VulnerabilitySeverity
d = make_dependency('vuln-pkg', '1.0.0', Ecosystem.NPM)
d.cves.append(make_cve('CVE-2024-1234', VulnerabilitySeverity.HIGH, 8.5))
assert d.risk == DependencyRisk.HIGH"

run_python_test "GPL-3.0 license → HIGH dep risk" \
"from security_ai.supply_chain_security import make_dependency, Ecosystem, DependencyRisk
d = make_dependency('gpl-lib', '1.0.0', Ecosystem.PYPI, license_spdx='GPL-3.0')
assert d.risk == DependencyRisk.HIGH"

run_python_test "TAMPERED provenance → CRITICAL dep risk" \
"from security_ai.supply_chain_security import make_dependency, Ecosystem, DependencyRisk, ProvenanceStatus
d = make_dependency('bad-pkg', '1.0.0', Ecosystem.NPM, provenance=ProvenanceStatus.TAMPERED)
assert d.risk == DependencyRisk.CRITICAL"

run_python_test "MEDIUM CVE → MEDIUM dep risk" \
"from security_ai.supply_chain_security import make_dependency, make_cve, Ecosystem, DependencyRisk, VulnerabilitySeverity
d = make_dependency('med-pkg', '1.0.0', Ecosystem.PYPI)
d.cves.append(make_cve('CVE-2024-9999', VulnerabilitySeverity.MEDIUM, 5.0))
assert d.risk == DependencyRisk.MEDIUM"

run_python_test "Healthy dep (MIT, verified, pinned) → NONE risk" \
"from security_ai.supply_chain_security import make_dependency, Ecosystem, DependencyRisk, ProvenanceStatus
d = make_dependency('requests', '2.31.0', Ecosystem.PYPI, license_spdx='MIT',
                    provenance=ProvenanceStatus.VERIFIED, is_pinned=True,
                    maintainer_count=5, last_updated_days_ago=30)
assert d.risk == DependencyRisk.NONE"

run_python_test "worst_cve_severity with multiple CVEs picks highest" \
"from security_ai.supply_chain_security import make_dependency, make_cve, Ecosystem, VulnerabilitySeverity
d = make_dependency('multi-cve', '1.0.0', Ecosystem.PYPI)
d.cves.append(make_cve('CVE-A', VulnerabilitySeverity.LOW, 2.0))
d.cves.append(make_cve('CVE-B', VulnerabilitySeverity.HIGH, 8.0))
assert d.worst_cve_severity == VulnerabilitySeverity.HIGH"

run_python_test "worst_cve_severity with no CVEs → NONE" \
"from security_ai.supply_chain_security import make_dependency, Ecosystem, VulnerabilitySeverity
d = make_dependency('clean', '1.0.0', Ecosystem.PYPI)
assert d.worst_cve_severity == VulnerabilitySeverity.NONE"

echo ""

# GROUP 4: Engine — dependency management
echo "GROUP 4: Engine — Dependency Management"

run_python_test "add_dependency() stores dependency" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
d = make_dependency('requests', '2.31.0', Ecosystem.PYPI)
e.add_dependency(d)
assert e.dependency_count() == 1"

run_python_test "get_dependency() retrieves by ID" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
d = make_dependency('requests', '2.31.0', Ecosystem.PYPI)
e.add_dependency(d)
assert e.get_dependency(d.dep_id) is d"

run_python_test "get_dependency() returns None for unknown ID" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine
e = SupplyChainSecurityEngine()
assert e.get_dependency('nonexistent') is None"

run_python_test "add_cve() attaches CVE to dependency" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, make_cve, Ecosystem, VulnerabilitySeverity
e = SupplyChainSecurityEngine()
d = make_dependency('vuln-lib', '1.0.0', Ecosystem.PYPI)
e.add_dependency(d)
ok = e.add_cve(d.dep_id, make_cve('CVE-2024-1', VulnerabilitySeverity.HIGH, 8.0))
assert ok
assert len(d.cves) == 1"

run_python_test "add_cve() returns False for unknown dep_id" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_cve, VulnerabilitySeverity
e = SupplyChainSecurityEngine()
assert not e.add_cve('no-such', make_cve('CVE-X', VulnerabilitySeverity.LOW))"

run_python_test "vulnerable_deps() returns only CVE-affected deps" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, make_cve, Ecosystem, VulnerabilitySeverity
e = SupplyChainSecurityEngine()
d1 = make_dependency('clean', '1.0.0', Ecosystem.PYPI)
d2 = make_dependency('vuln',  '1.0.0', Ecosystem.PYPI)
e.add_dependency(d1); e.add_dependency(d2)
e.add_cve(d2.dep_id, make_cve('CVE-Z', VulnerabilitySeverity.MEDIUM))
assert len(e.vulnerable_deps()) == 1"

run_python_test "unpinned_deps() returns floating deps" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
e.add_dependency(make_dependency('pinned',   '1.0.0', Ecosystem.NPM, is_pinned=True))
e.add_dependency(make_dependency('unpinned', '^1.0.0', Ecosystem.NPM, is_pinned=False))
assert len(e.unpinned_deps()) == 1"

run_python_test "blocked_license_deps() returns GPL-family deps" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
e.add_dependency(make_dependency('ok',  '1.0', Ecosystem.PYPI, license_spdx='MIT'))
e.add_dependency(make_dependency('bad', '1.0', Ecosystem.PYPI, license_spdx='GPL-3.0'))
assert len(e.blocked_license_deps()) == 1"

run_python_test "tampered_deps() returns provenance-tampered deps" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem, ProvenanceStatus
e = SupplyChainSecurityEngine()
e.add_dependency(make_dependency('ok',  '1.0', Ecosystem.NPM))
e.add_dependency(make_dependency('bad', '1.0', Ecosystem.NPM, provenance=ProvenanceStatus.TAMPERED))
assert len(e.tampered_deps()) == 1"

run_python_test "critical_deps() returns only CRITICAL risk deps" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, make_cve, Ecosystem, VulnerabilitySeverity
e = SupplyChainSecurityEngine()
d = make_dependency('log4j', '2.14', Ecosystem.MAVEN)
d.cves.append(make_cve('CVE-2021-44228', VulnerabilitySeverity.CRITICAL, 10.0))
e.add_dependency(d)
e.add_dependency(make_dependency('safe', '1.0', Ecosystem.PYPI))
crits = e.critical_deps()
assert len(crits) == 1
assert crits[0].name == 'log4j'"

echo ""

# GROUP 5: SBOM
echo "GROUP 5: SBOM Management"

run_python_test "add_sbom_entry() creates entry" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem, SBOMEntry
e = SupplyChainSecurityEngine()
d = make_dependency('requests', '2.31.0', Ecosystem.PYPI)
e.add_dependency(d)
entry = e.add_sbom_entry('auth-service', d)
assert isinstance(entry, SBOMEntry)
assert len(e.sbom()) == 1"

run_python_test "components() returns unique component names" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
d1 = make_dependency('a', '1.0', Ecosystem.PYPI); e.add_dependency(d1)
d2 = make_dependency('b', '1.0', Ecosystem.PYPI); e.add_dependency(d2)
e.add_sbom_entry('svc-a', d1)
e.add_sbom_entry('svc-b', d2)
e.add_sbom_entry('svc-a', d2)
comps = e.components()
assert len(comps) == 2
assert 'svc-a' in comps"

run_python_test "deps_for_component() filters by component" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
d1 = make_dependency('a', '1.0', Ecosystem.PYPI); e.add_dependency(d1)
d2 = make_dependency('b', '1.0', Ecosystem.PYPI); e.add_dependency(d2)
e.add_sbom_entry('svc-a', d1)
e.add_sbom_entry('svc-b', d2)
deps = e.deps_for_component('svc-a')
assert len(deps) == 1
assert deps[0].name == 'a'"

echo ""

# GROUP 6: Scan
echo "GROUP 6: Scan"

run_python_test "scan() returns dict with all DependencyRisk levels" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine
e = SupplyChainSecurityEngine()
s = e.scan()
for lvl in ('critical','high','medium','low','none'):
    assert lvl in s, lvl"

run_python_test "scan() counts correctly for mixed inventory" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, make_cve, Ecosystem, VulnerabilitySeverity, ProvenanceStatus
e = SupplyChainSecurityEngine()
# CRITICAL: tampered
d1 = make_dependency('tampered', '1.0', Ecosystem.NPM, provenance=ProvenanceStatus.TAMPERED)
# HIGH: GPL
d2 = make_dependency('gpl-lib', '1.0', Ecosystem.PYPI, license_spdx='GPL-3.0')
# NONE: clean
d3 = make_dependency('clean', '1.0', Ecosystem.PYPI, license_spdx='MIT')
for d in [d1, d2, d3]:
    e.add_dependency(d)
s = e.scan()
assert s['critical'] == 1, s
assert s['high'] == 1, s
assert s['none'] == 1, s"

run_python_test "deps_by_risk() groups deps by risk level" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
e.add_dependency(make_dependency('clean', '1.0', Ecosystem.PYPI, license_spdx='MIT'))
by_risk = e.deps_by_risk()
assert isinstance(by_risk, dict)
assert any(e.dependency_count() == sum(len(v) for v in by_risk.values()) for _ in [1])"

echo ""

# GROUP 7: Scoring
echo "GROUP 7: Scoring"

run_python_test "phase56_score() = 25 with no dependencies" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine
e = SupplyChainSecurityEngine()
assert e.phase56_score() == 25.0"

run_python_test "phase56_score() = 25 with all healthy deps" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
for i in range(5):
    e.add_dependency(make_dependency(f'pkg-{i}', '1.0', Ecosystem.PYPI, license_spdx='MIT'))
assert e.phase56_score() == 25.0"

run_python_test "phase56_score() decreases with CRITICAL dep" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, make_cve, Ecosystem, VulnerabilitySeverity
e = SupplyChainSecurityEngine()
d = make_dependency('crit-pkg', '1.0', Ecosystem.PYPI)
d.cves.append(make_cve('CVE-X', VulnerabilitySeverity.CRITICAL, 10.0))
e.add_dependency(d)
assert e.phase56_score() < 25.0"

run_python_test "SupplyChainReport.phase56_score() deducts 5 per CRITICAL" \
"from security_ai.supply_chain_security import SupplyChainReport
r = SupplyChainReport(total_dependencies=5, risk_breakdown={'critical': 2, 'none': 3})
assert r.phase56_score() == 25.0 - 10"

run_python_test "SupplyChainReport.phase56_score() deducts 3 per HIGH" \
"from security_ai.supply_chain_security import SupplyChainReport
r = SupplyChainReport(total_dependencies=5, risk_breakdown={'high': 3, 'none': 2})
assert r.phase56_score() == 25.0 - 9"

run_python_test "SupplyChainReport.phase56_score() deducts 5 per tampered" \
"from security_ai.supply_chain_security import SupplyChainReport
r = SupplyChainReport(total_dependencies=5, tampered_provenance=2, risk_breakdown={'none': 5})
assert r.phase56_score() == 25.0 - 10"

run_python_test "SupplyChainReport.phase56_score() floors at 0" \
"from security_ai.supply_chain_security import SupplyChainReport
r = SupplyChainReport(total_dependencies=20, risk_breakdown={'critical': 10},
                      tampered_provenance=5, blocked_licenses=5)
assert r.phase56_score() == 0.0"

run_python_test "phase56_score() in range [0, 25]" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem, ProvenanceStatus
e = SupplyChainSecurityEngine()
for i in range(8):
    e.add_dependency(make_dependency(f'p{i}', '1.0', Ecosystem.PYPI,
                                     license_spdx='GPL-3.0',
                                     provenance=ProvenanceStatus.TAMPERED))
score = e.phase56_score()
assert 0.0 <= score <= 25.0, score"

echo ""

# GROUP 8: Summary & reporting
echo "GROUP 8: Summary & Reporting"

run_python_test "summary() has all required keys" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine
e = SupplyChainSecurityEngine()
s = e.summary()
for k in ('status','total_dependencies','risk_breakdown','cve_count','blocked_licenses',
          'unverified_provenance','tampered_provenance','unpinned','deprecated',
          'sbom_entries','phase56_score'):
    assert k in s, k"

run_python_test "summary() status='no_dependencies' when empty" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine
e = SupplyChainSecurityEngine()
assert e.summary()['status'] == 'no_dependencies'"

run_python_test "summary() status='ok' with deps" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
e.add_dependency(make_dependency('x', '1.0', Ecosystem.PYPI))
assert e.summary()['status'] == 'ok'"

run_python_test "generate_report() returns SupplyChainReport instance" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, SupplyChainReport, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
e.add_dependency(make_dependency('x', '1.0', Ecosystem.PYPI))
r = e.generate_report()
assert isinstance(r, SupplyChainReport)"

run_python_test "generate_report().to_dict() has all required keys" \
"from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
e = SupplyChainSecurityEngine()
e.add_dependency(make_dependency('x', '1.0', Ecosystem.PYPI))
d = e.generate_report().to_dict()
for k in ('report_id','generated_at','total_dependencies','risk_breakdown','cve_count',
          'blocked_licenses','unverified_provenance','tampered_provenance','unpinned',
          'deprecated','phase56_score','entries'):
    assert k in d, k"

run_python_test "CVE.to_dict() contains all fields" \
"from security_ai.supply_chain_security import make_cve, VulnerabilitySeverity
c = make_cve('CVE-2024-1', VulnerabilitySeverity.HIGH, 8.5, fixed_in='1.2.3')
d = c.to_dict()
for k in ('cve_id','severity','cvss_score','description','fixed_in'):
    assert k in d, k"

run_python_test "Dependency.to_dict() contains all required fields" \
"from security_ai.supply_chain_security import make_dependency, Ecosystem
d = make_dependency('requests', '2.31.0', Ecosystem.PYPI, license_spdx='Apache-2.0').to_dict()
for k in ('dep_id','name','version','ecosystem','dep_type','license_spdx','license_risk',
          'provenance','is_pinned','is_deprecated','cve_count','worst_cve_severity','risk'):
    assert k in d, k"

run_python_test "SBOMEntry.to_dict() contains component field" \
"from security_ai.supply_chain_security import SBOMEntry, make_dependency, Ecosystem
d = make_dependency('x', '1.0', Ecosystem.PYPI)
e = SBOMEntry(component='auth-svc', dependency=d)
assert 'component' in e.to_dict()"

echo ""

# GROUP 9: Ops script
echo "GROUP 9: Ops Script"

run_test "Ops script exists and is executable" \
    "[[ -x '${PROJECT_ROOT}/scripts/ops/phase-56-supply-chain-security.sh' ]]"

run_test "Ops script demo mode mentions Phase 56" \
    "timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-56-supply-chain-security.sh' demo 2>&1 | grep -i 'Phase 56'"

run_test "Ops script summary mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-56-supply-chain-security.sh' summary 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

run_test "Ops script report mode outputs valid JSON" \
    "output=\$(timeout 30 bash '${PROJECT_ROOT}/scripts/ops/phase-56-supply-chain-security.sh' report 2>/dev/null); echo \"\$output\" | python3 -c 'import sys,json; json.load(sys.stdin)'"

echo ""

# GROUP 10: Phase 55 regression guard
echo "GROUP 10: Phase 55 Regression Guard"

if [[ -z "${SKIP_REGRESSION:-}" ]]; then
    run_test "Phase 55 integration suite still passes" \
        "SKIP_REGRESSION=1 timeout 120 bash '${PROJECT_ROOT}/scripts/ci/phase-55-integration-tests.sh' 2>&1 | grep -E 'FAIL:\s+0'"
else
    echo "  ⏭  Phase 55 regression skipped (SKIP_REGRESSION=1)"
fi

echo ""

echo "============================================================"
echo "PHASE 56 TEST RESULTS"
echo "============================================================"
printf "PASS:  %d\n" "$PASS"
printf "FAIL:  %d\n" "$FAIL"
printf "TOTAL: %d\n" "$TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "✅  ALL TESTS PASSED — Phase 56 Supply Chain Security verified"
    exit 0
else
    echo "❌  SOME TESTS FAILED — Review output above"
    exit 1
fi
