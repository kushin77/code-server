#!/bin/bash
# @file phase-56-supply-chain-security.sh
# @description Phase 56 — Supply Chain Security & Dependency Risk Engine
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..." >&2; rm -f /tmp/p56*.tmp 2>/dev/null || true' EXIT

MODE="${1:-demo}"

cmd_demo() {
    log_info "Phase 56 — Supply Chain Security & Dependency Risk Engine"
    log_info "Scanning demo dependency inventory..."
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.supply_chain_security import (
    SupplyChainSecurityEngine, make_dependency, make_cve,
    Ecosystem, DependencyType, ProvenanceStatus, VulnerabilitySeverity
)

engine = SupplyChainSecurityEngine()

deps = [
    make_dependency("requests",       "2.31.0", Ecosystem.PYPI,   license_spdx="Apache-2.0"),
    make_dependency("cryptography",   "41.0.0", Ecosystem.PYPI,   license_spdx="Apache-2.0"),
    make_dependency("lodash",         "4.17.21", Ecosystem.NPM,   license_spdx="MIT"),
    make_dependency("log4j",          "2.14.1", Ecosystem.MAVEN,  license_spdx="Apache-2.0",
                    provenance=ProvenanceStatus.UNVERIFIED),
    make_dependency("left-pad",       "1.3.0",  Ecosystem.NPM,    license_spdx="MIT",
                    maintainer_count=1, last_updated_days_ago=1200, is_deprecated=True),
    make_dependency("openssl",        "3.0.7",  Ecosystem.SYSTEM, license_spdx="Apache-2.0"),
    make_dependency("gpl-component",  "2.0.0",  Ecosystem.PYPI,   license_spdx="GPL-3.0"),
    make_dependency("tampered-pkg",   "1.0.0",  Ecosystem.NPM,    license_spdx="MIT",
                    provenance=ProvenanceStatus.TAMPERED),
]

for d in deps:
    engine.add_dependency(d)

# Attach CVEs
vuln_dep = [d for d in engine.dependencies() if d.name == "log4j"][0]
engine.add_cve(vuln_dep.dep_id, make_cve("CVE-2021-44228", VulnerabilitySeverity.CRITICAL, 10.0))

engine.add_sbom_entry("auth-service",    deps[0])
engine.add_sbom_entry("auth-service",    deps[1])
engine.add_sbom_entry("frontend",        deps[2])
engine.add_sbom_entry("logging-service", deps[3])

scan = engine.scan()
score = engine.phase56_score()
print(f"[Phase 56] Dependencies  : {engine.dependency_count()}")
print(f"[Phase 56] CRITICAL risk : {scan.get('critical', 0)}")
print(f"[Phase 56] HIGH risk     : {scan.get('high', 0)}")
print(f"[Phase 56] MEDIUM risk   : {scan.get('medium', 0)}")
print(f"[Phase 56] CVEs found    : {sum(len(d.cves) for d in engine.dependencies())}")
print(f"[Phase 56] Gate score    : {score}/25")
print(f"[Phase 56] Status        : {'PASS' if score >= 15 else 'REVIEW'}")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.supply_chain_security import (
    SupplyChainSecurityEngine, make_dependency, Ecosystem, ProvenanceStatus
)
engine = SupplyChainSecurityEngine()
engine.add_dependency(make_dependency("requests",     "2.31.0", Ecosystem.PYPI,   license_spdx="Apache-2.0"))
engine.add_dependency(make_dependency("lodash",       "4.17.21", Ecosystem.NPM,   license_spdx="MIT"))
engine.add_dependency(make_dependency("gpl-lib",      "1.0.0",  Ecosystem.PYPI,   license_spdx="GPL-3.0"))
print(json.dumps(engine.summary(), indent=2))
PYEOF
}

cmd_report() {
    "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.supply_chain_security import (
    SupplyChainSecurityEngine, make_dependency, Ecosystem
)
engine = SupplyChainSecurityEngine()
engine.add_dependency(make_dependency("requests", "2.31.0", Ecosystem.PYPI, license_spdx="Apache-2.0"))
engine.add_dependency(make_dependency("lodash",   "4.17.21", Ecosystem.NPM, license_spdx="MIT"))
print(json.dumps(engine.generate_report().to_dict(), indent=2))
PYEOF
}

cmd_persist() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.supply_chain_security import SupplyChainSecurityEngine, make_dependency, Ecosystem
engine = SupplyChainSecurityEngine()
engine.add_dependency(make_dependency("demo-dep", "1.0.0", Ecosystem.PYPI, license_spdx="MIT"))
path = engine.persist_state('${PROJECT_ROOT}/artifacts/phase56/supply-chain-report.json')
print(f"State persisted to: {path}")
PYEOF
}

case "$MODE" in
    demo)    cmd_demo    ;;
    summary) cmd_summary ;;
    report)  cmd_report  ;;
    persist) cmd_persist  ;;
    *)
        log_error "Unknown mode '$MODE'. Usage: $0 [demo|summary|report|persist]"
        exit 1
        ;;
esac
