"""
supply_chain_security.py — Phase 56: Supply Chain Security & Dependency Risk Engine
Tracks software dependencies, detects vulnerabilities (CVEs), license violations,
provenance gaps, and produces a supply-chain risk score for the Phase 31 gate.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class DependencyType(Enum):
    DIRECT      = "direct"
    TRANSITIVE  = "transitive"
    DEV         = "dev"
    OPTIONAL    = "optional"


class Ecosystem(Enum):
    PYPI    = "pypi"
    NPM     = "npm"
    MAVEN   = "maven"
    CARGO   = "cargo"
    GO      = "go"
    DOCKER  = "docker"
    SYSTEM  = "system"


class VulnerabilitySeverity(Enum):
    CRITICAL = "critical"
    HIGH     = "high"
    MEDIUM   = "medium"
    LOW      = "low"
    NONE     = "none"


class LicenseRisk(Enum):
    BLOCKED    = "blocked"    # GPL-family incompatible with proprietary use
    RESTRICTED = "restricted" # requires attribution / disclosure
    ALLOWED    = "allowed"    # permissive (MIT, Apache, BSD)
    UNKNOWN    = "unknown"    # no SPDX identifier found


class ProvenanceStatus(Enum):
    VERIFIED   = "verified"    # signed + hash-matched
    UNVERIFIED = "unverified"  # no signature
    TAMPERED   = "tampered"    # hash mismatch
    UNKNOWN    = "unknown"     # no provenance data


class DependencyRisk(Enum):
    CRITICAL = "critical"
    HIGH     = "high"
    MEDIUM   = "medium"
    LOW      = "low"
    NONE     = "none"


# ---------------------------------------------------------------------------
# License classification helpers
# ---------------------------------------------------------------------------

_BLOCKED_LICENSES    = {"GPL-2.0", "GPL-3.0", "AGPL-3.0", "LGPL-2.1", "LGPL-3.0"}
_RESTRICTED_LICENSES = {"MPL-2.0", "EUPL-1.2", "CDDL-1.0", "EPL-2.0"}
_ALLOWED_LICENSES    = {"MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause",
                        "ISC", "0BSD", "Unlicense", "CC0-1.0", "PSF-2.0"}


def classify_license(spdx_id: str) -> LicenseRisk:
    if not spdx_id:
        return LicenseRisk.UNKNOWN
    if spdx_id in _BLOCKED_LICENSES:
        return LicenseRisk.BLOCKED
    if spdx_id in _RESTRICTED_LICENSES:
        return LicenseRisk.RESTRICTED
    if spdx_id in _ALLOWED_LICENSES:
        return LicenseRisk.ALLOWED
    return LicenseRisk.UNKNOWN


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class CVE:
    """A known vulnerability record."""
    cve_id: str                                      # e.g. "CVE-2024-12345"
    severity: VulnerabilitySeverity = VulnerabilitySeverity.MEDIUM
    cvss_score: float = 0.0                          # 0-10
    description: str = ""
    fixed_in: Optional[str] = None                  # version that patches it

    def to_dict(self) -> dict:
        return {
            "cve_id": self.cve_id,
            "severity": self.severity.value,
            "cvss_score": self.cvss_score,
            "description": self.description,
            "fixed_in": self.fixed_in,
        }


@dataclass
class Dependency:
    """A software dependency in the inventory."""
    dep_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    name: str = ""
    version: str = ""
    ecosystem: Ecosystem = Ecosystem.PYPI
    dep_type: DependencyType = DependencyType.DIRECT
    license_spdx: str = ""
    provenance: ProvenanceStatus = ProvenanceStatus.UNKNOWN
    cves: List[CVE] = field(default_factory=list)
    is_pinned: bool = True          # version pinned vs floating range
    is_deprecated: bool = False
    maintainer_count: int = 1       # number of active maintainers
    last_updated_days_ago: int = 0  # days since last upstream release

    # ------------------------------------------------------------------ #

    @property
    def license_risk(self) -> LicenseRisk:
        return classify_license(self.license_spdx)

    @property
    def worst_cve_severity(self) -> VulnerabilitySeverity:
        if not self.cves:
            return VulnerabilitySeverity.NONE
        order = [
            VulnerabilitySeverity.CRITICAL,
            VulnerabilitySeverity.HIGH,
            VulnerabilitySeverity.MEDIUM,
            VulnerabilitySeverity.LOW,
            VulnerabilitySeverity.NONE,
        ]
        for sev in order:
            if any(c.severity == sev for c in self.cves):
                return sev
        return VulnerabilitySeverity.NONE

    @property
    def risk(self) -> DependencyRisk:
        """Aggregate risk level for this dependency."""
        # CVE severity drives the base risk
        cve_sev = self.worst_cve_severity
        if cve_sev == VulnerabilitySeverity.CRITICAL:
            return DependencyRisk.CRITICAL
        if cve_sev == VulnerabilitySeverity.HIGH:
            return DependencyRisk.HIGH

        # Blocked license → HIGH
        if self.license_risk == LicenseRisk.BLOCKED:
            return DependencyRisk.HIGH

        # Tampered provenance → CRITICAL
        if self.provenance == ProvenanceStatus.TAMPERED:
            return DependencyRisk.CRITICAL

        # Medium CVE or unverified provenance + deprecated → MEDIUM
        if cve_sev == VulnerabilitySeverity.MEDIUM:
            return DependencyRisk.MEDIUM
        if self.is_deprecated and self.provenance == ProvenanceStatus.UNVERIFIED:
            return DependencyRisk.MEDIUM

        # Unpinned + unknown license → MEDIUM
        if not self.is_pinned and self.license_risk == LicenseRisk.UNKNOWN:
            return DependencyRisk.MEDIUM

        # Low CVE or single maintainer or old package
        if cve_sev == VulnerabilitySeverity.LOW:
            return DependencyRisk.LOW
        if self.maintainer_count <= 1 or self.last_updated_days_ago > 365:
            return DependencyRisk.LOW

        return DependencyRisk.NONE

    def to_dict(self) -> dict:
        return {
            "dep_id": self.dep_id,
            "name": self.name,
            "version": self.version,
            "ecosystem": self.ecosystem.value,
            "dep_type": self.dep_type.value,
            "license_spdx": self.license_spdx,
            "license_risk": self.license_risk.value,
            "provenance": self.provenance.value,
            "is_pinned": self.is_pinned,
            "is_deprecated": self.is_deprecated,
            "maintainer_count": self.maintainer_count,
            "last_updated_days_ago": self.last_updated_days_ago,
            "cve_count": len(self.cves),
            "worst_cve_severity": self.worst_cve_severity.value,
            "risk": self.risk.value,
            "cves": [c.to_dict() for c in self.cves],
        }


@dataclass
class SBOMEntry:
    """Software Bill of Materials entry — links a component to a dependency."""
    component: str       # service / app name
    dependency: Dependency
    introduced_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "component": self.component,
            "introduced_at": self.introduced_at.isoformat(),
            **self.dependency.to_dict(),
        }


@dataclass
class SupplyChainReport:
    """Full supply-chain risk report snapshot."""
    report_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    generated_at: datetime = field(default_factory=datetime.utcnow)
    total_dependencies: int = 0
    risk_breakdown: Dict[str, int] = field(default_factory=dict)
    cve_count: int = 0
    blocked_licenses: int = 0
    unverified_provenance: int = 0
    tampered_provenance: int = 0
    unpinned: int = 0
    deprecated: int = 0
    entries: List[dict] = field(default_factory=list)

    def phase56_score(self) -> float:
        """
        Gate contribution 0-25.
        Deductions:
          CRITICAL risk dep: 5 pts each
          HIGH risk dep:     3 pts each
          MEDIUM risk dep:   1 pt  each
          tampered:          5 pts each (additive)
          blocked license:   2 pts each
        Floor at 0.
        """
        if self.total_dependencies == 0:
            return 25.0
        deductions = (
            self.risk_breakdown.get("critical", 0) * 5
            + self.risk_breakdown.get("high", 0) * 3
            + self.risk_breakdown.get("medium", 0) * 1
            + self.tampered_provenance * 5
            + self.blocked_licenses * 2
        )
        return max(0.0, round(25.0 - deductions, 2))

    def to_dict(self) -> dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_dependencies": self.total_dependencies,
            "risk_breakdown": self.risk_breakdown,
            "cve_count": self.cve_count,
            "blocked_licenses": self.blocked_licenses,
            "unverified_provenance": self.unverified_provenance,
            "tampered_provenance": self.tampered_provenance,
            "unpinned": self.unpinned,
            "deprecated": self.deprecated,
            "phase56_score": self.phase56_score(),
            "entries": self.entries,
        }


# ---------------------------------------------------------------------------
# Core engine
# ---------------------------------------------------------------------------


class SupplyChainSecurityEngine:
    """
    Phase 56 — Supply Chain Security & Dependency Risk Engine.

    Workflow:
      1. add_dependency()          — register a dependency (with optional CVEs)
      2. add_cve()                 — attach a CVE to an existing dependency
      3. add_sbom_entry()          — link component → dependency in the SBOM
      4. scan()                    — produce risk breakdown across all deps
      5. generate_report()         — full SupplyChainReport
      6. phase56_score()           — gate contribution 0-25
      7. summary() / persist_state()
    """

    def __init__(self) -> None:
        self._deps: Dict[str, Dependency] = {}
        self._sbom: List[SBOMEntry] = []

    # ---- Dependency management -------------------------------------------

    def add_dependency(self, dep: Dependency) -> Dependency:
        self._deps[dep.dep_id] = dep
        return dep

    def get_dependency(self, dep_id: str) -> Optional[Dependency]:
        return self._deps.get(dep_id)

    def dependencies(self) -> List[Dependency]:
        return list(self._deps.values())

    def dependency_count(self) -> int:
        return len(self._deps)

    def add_cve(self, dep_id: str, cve: CVE) -> bool:
        dep = self._deps.get(dep_id)
        if not dep:
            return False
        dep.cves.append(cve)
        return True

    # ---- SBOM -----------------------------------------------------------

    def add_sbom_entry(self, component: str, dep: Dependency) -> SBOMEntry:
        entry = SBOMEntry(component=component, dependency=dep)
        self._sbom.append(entry)
        return entry

    def sbom(self) -> List[SBOMEntry]:
        return list(self._sbom)

    def components(self) -> List[str]:
        return sorted({e.component for e in self._sbom})

    def deps_for_component(self, component: str) -> List[Dependency]:
        return [e.dependency for e in self._sbom if e.component == component]

    # ---- Scanning -------------------------------------------------------

    def scan(self) -> Dict[str, int]:
        """Return risk-level counts across all registered dependencies."""
        counts: Dict[str, int] = {lvl.value: 0 for lvl in DependencyRisk}
        for dep in self._deps.values():
            counts[dep.risk.value] += 1
        return counts

    def deps_by_risk(self) -> Dict[str, List[Dependency]]:
        result: Dict[str, List[Dependency]] = {lvl.value: [] for lvl in DependencyRisk}
        for dep in self._deps.values():
            result[dep.risk.value].append(dep)
        return result

    def critical_deps(self) -> List[Dependency]:
        return [d for d in self._deps.values() if d.risk == DependencyRisk.CRITICAL]

    def vulnerable_deps(self) -> List[Dependency]:
        return [d for d in self._deps.values() if d.cves]

    def unpinned_deps(self) -> List[Dependency]:
        return [d for d in self._deps.values() if not d.is_pinned]

    def blocked_license_deps(self) -> List[Dependency]:
        return [d for d in self._deps.values() if d.license_risk == LicenseRisk.BLOCKED]

    def tampered_deps(self) -> List[Dependency]:
        return [d for d in self._deps.values() if d.provenance == ProvenanceStatus.TAMPERED]

    # ---- Scoring --------------------------------------------------------

    def phase56_score(self) -> float:
        return self.generate_report().phase56_score()

    # ---- Reporting ------------------------------------------------------

    def generate_report(self) -> SupplyChainReport:
        by_risk = self.deps_by_risk()
        all_cves = sum(len(d.cves) for d in self._deps.values())
        return SupplyChainReport(
            total_dependencies=len(self._deps),
            risk_breakdown={k: len(v) for k, v in by_risk.items() if v},
            cve_count=all_cves,
            blocked_licenses=len(self.blocked_license_deps()),
            unverified_provenance=sum(
                1 for d in self._deps.values()
                if d.provenance == ProvenanceStatus.UNVERIFIED
            ),
            tampered_provenance=len(self.tampered_deps()),
            unpinned=len(self.unpinned_deps()),
            deprecated=sum(1 for d in self._deps.values() if d.is_deprecated),
            entries=[e.to_dict() for e in self._sbom],
        )

    def summary(self) -> dict:
        r = self.generate_report()
        return {
            "status": "ok" if self._deps else "no_dependencies",
            "total_dependencies": r.total_dependencies,
            "risk_breakdown": r.risk_breakdown,
            "cve_count": r.cve_count,
            "blocked_licenses": r.blocked_licenses,
            "unverified_provenance": r.unverified_provenance,
            "tampered_provenance": r.tampered_provenance,
            "unpinned": r.unpinned,
            "deprecated": r.deprecated,
            "sbom_entries": len(self._sbom),
            "phase56_score": r.phase56_score(),
        }

    def persist_state(
        self, output_path: str = "artifacts/phase56/supply-chain-report.json"
    ) -> str:
        import os
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        state = {
            "phase": 56,
            "engine": "SupplyChainSecurityEngine",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "dependencies": [d.to_dict() for d in self._deps.values()],
            "sbom": [e.to_dict() for e in self._sbom],
        }
        with open(output_path, "w") as f:
            json.dump(state, f, indent=2)
        return output_path


# ---------------------------------------------------------------------------
# Helper factories
# ---------------------------------------------------------------------------


def make_dependency(
    name: str,
    version: str = "1.0.0",
    ecosystem: Ecosystem = Ecosystem.PYPI,
    dep_type: DependencyType = DependencyType.DIRECT,
    license_spdx: str = "MIT",
    provenance: ProvenanceStatus = ProvenanceStatus.VERIFIED,
    is_pinned: bool = True,
    is_deprecated: bool = False,
    maintainer_count: int = 3,
    last_updated_days_ago: int = 30,
) -> Dependency:
    return Dependency(
        name=name,
        version=version,
        ecosystem=ecosystem,
        dep_type=dep_type,
        license_spdx=license_spdx,
        provenance=provenance,
        is_pinned=is_pinned,
        is_deprecated=is_deprecated,
        maintainer_count=maintainer_count,
        last_updated_days_ago=last_updated_days_ago,
    )


def make_cve(
    cve_id: str,
    severity: VulnerabilitySeverity = VulnerabilitySeverity.HIGH,
    cvss_score: float = 7.5,
    fixed_in: Optional[str] = None,
) -> CVE:
    return CVE(
        cve_id=cve_id,
        severity=severity,
        cvss_score=cvss_score,
        fixed_in=fixed_in,
    )
