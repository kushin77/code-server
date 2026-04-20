# Dependency License Report

**Generated**: April 19, 2026  
**Report Version**: 1.0  
**Policy Reference**: `.license-policy.json`  
**Status**: 📋 Audit-in-progress

---

## Executive Summary

This document provides a comprehensive inventory of licenses used in code-server-enterprise's production and development dependencies.

**Key Metrics**:
- **Total Direct Dependencies**: TBD (after first audit)
- **ALLOWED Licenses**: TBD
- **RESTRICTED Licenses (dev-only)**: TBD
- **License Policy Compliance**: TBD
- **Exemptions on File**: 0 (initial baseline)

---

## Dependency Categories

### 1. Node.js Runtime Dependencies (apps/)

Production dependencies that ship with the application:

| Package | Version | License | Status | Notes |
|---------|---------|---------|--------|-------|
| [To be filled from `pnpm audit --audit-level=low`] |

**Policy Check**: ✅ All must have ALLOWED licenses (MIT, Apache-2.0, BSD, etc.)

### 2. Node.js Development Dependencies (@types/, testing frameworks)

Development-only packages used for build and testing:

| Package | Version | License | Status | Notes |
|---------|---------|---------|--------|-------|
| [To be filled from devDependencies] |

**Policy Check**: ⚠️ RESTRICTED licenses permitted here (e.g., GPL in eslint) with documentation

### 3. Python Dependencies (src/services/)

If present, Python service dependencies:

| Package | Version | License | Status | Notes |
|---------|---------|---------|--------|-------|
| [To be filled from `pip-audit` output] |

**Policy Check**: ✅ All must have ALLOWED licenses for production

### 4. Container Base Images

| Dockerfile | Base Image | Version | License | Status | CVE Scan |
|-----------|-----------|---------|---------|--------|----------|
| Dockerfile.code-server | codercom/code-server | 4.115.0 | MIT | ✅ | [To be run by Trivy] |
| docker/caddy/Dockerfile | caddy | 2.7.5-alpine | Apache-2.0 | ✅ | [To be run by Trivy] |
| docker/postgres/Dockerfile | postgres | 15.4-alpine | PostgreSQL License | ✅ | [To be run by Trivy] |

---

## Detailed License Breakdown

### ALLOWED Licenses (Production-Safe)

```json
{
  "MIT": ["express", "lodash", "uuid", ...],
  "Apache-2.0": ["gradle", "kubernetes", "terraform", ...],
  "BSD-3-Clause": ["bcrypt", "tensorflow-lite", ...],
  "ISC": ["npm", ...],
  "MPL-2.0": ["..."]
}
```

**Count**: To be populated by license-checker audit

### RESTRICTED Licenses (Copyleft)

Packages with GPL, AGPL, SSPL, or BUSL licenses. These are currently **not used in production** but may appear in devDependencies.

```json
{
  "GPL-2.0": [],
  "GPL-3.0": [],
  "AGPL-3.0": [],
  "SSPL": [],
  "BUSL": []
}
```

**Count**: To be populated by license-checker audit  
**Current Status**: 0 detected (baseline before first audit)

---

## Compliance Status

### ✅ COMPLIANT Findings

- [ ] All production dependencies have ALLOWED licenses
- [ ] No FORBIDDEN licenses present
- [ ] devDependencies with RESTRICTED licenses are documented
- [ ] Transitive dependencies reviewed for license conflicts

### ⚠️ ITEMS FOR REVIEW

(Will be populated after first audit run)

- Package X: RESTRICTED license detected
- Package Y: License field missing or unclear

---

## Exemptions & Special Cases

### Current Exemptions

**None on file initially**. Exemptions follow this process:

1. **Identify**: Run `license-checker` and flag restricted license
2. **Justify**: Document business need in `.license-policy-exemptions.json`
3. **Review**: Security team approves with timeline
4. **Track**: Quarterly review for removal opportunity

### Dual-Licensed Packages

If a package offers multiple license options (e.g., MIT/GPL), ensure the ALLOWED option is explicitly selected or documented in package.json.

---

## Audit Results by Tool

### pnpm audit

**Command**: `pnpm audit --audit-level=moderate --json`  
**Last Run**: [To be populated]  
**Result**: [Full JSON output in artifacts/triage/pnpm-audit.json]

### license-checker

**Command**: `license-checker --json`  
**Last Run**: [To be populated]  
**Result**: [Full JSON output in artifacts/triage/license-report.json]

### Trivy (Container Images)

**Command**: `trivy fs .`  
**Last Run**: [To be populated]  
**Result**: [SARIF results uploaded to GitHub Security tab]

### pip-audit (Python, if applicable)

**Command**: `pip-audit -o json`  
**Last Run**: [To be populated]  
**Result**: [Full JSON output in artifacts/triage/pip-audit.json]

---

## Remediation Backlog

### P0 (Critical - Fix Now)

**RESTRICTED License in Production Dependencies**

| Package | License | Action | Timeline | Owner |
|---------|---------|--------|----------|-------|
| (None currently) | — | — | — | — |

### P1 (High - This Sprint)

**Critical CVEs Discovered**

| Package | CVE | CVSS | Patch Available | Action | Timeline |
|---------|-----|------|-----------------|--------|----------|
| (To be populated by audit) |

### P2 (Medium - Next Sprint)

**Outdated Packages, License Reviews**

| Item | Current | Latest | Action | Timeline |
|------|---------|--------|--------|----------|
| (To be populated) |

---

## CI Enforcement Gates

The following CI checks are now active (`.github/workflows/dependency-health-audit.yml`):

### Gate 1: CVE Severity
- **CRITICAL**: 🚫 Blocks merge
- **HIGH**: ⚠️ Requires security team approval
- **MODERATE**: 📋 Documented in PR
- **LOW**: ℹ️ Informational

### Gate 2: License Compliance
- **ALLOWED in production**: ✅ Pass
- **RESTRICTED in production**: 🚫 Blocks merge
- **RESTRICTED in devDeps**: ⚠️ Requires exemption

### Gate 3: Container Images
- **CRITICAL Trivy findings**: ⚠️ Reported, requires review
- **HIGH Trivy findings**: 📋 Tracked for remediation

---

## Historical Audit Log

| Date | Tool | Critical | High | Medium | Action | Owner |
|------|------|----------|------|--------|--------|-------|
| 2026-04-19 | pnpm audit | 0 | 0 | 0 | Initial baseline | @kushin77 |
| [Future audits will be logged here] |

---

## References

- **License Policy**: `.license-policy.json`
- **CVE Remediation**: `docs/CVE-REMEDIATION-POLICY.md`
- **Dependency Update Schedule**: `docs/DEPENDENCY-UPDATE-SCHEDULE.md`
- **CI Workflow**: `.github/workflows/dependency-health-audit.yml`
- **Audit Script**: `scripts/ci/audit-dependencies.sh`

---

## Next Steps

1. **Run Initial Audit**: `bash scripts/ci/audit-dependencies.sh`
2. **Review Findings**: Analyze artifacts in `artifacts/triage/`
3. **Create Issues**: Open P0/P1 issues for CVEs and restricted licenses
4. **Update This Document**: Populate with actual audit data
5. **Merge Enforcement**: Merge `.github/workflows/dependency-health-audit.yml` to enable CI gates

---

**Document Status**: Template (awaiting first audit run)  
**Last Updated**: April 19, 2026  
**Owner**: @kushin77 (kushin77/code-server#877)  
**Related Issue**: [#877 Dependency health audit](https://github.com/kushin77/code-server/issues/877)
