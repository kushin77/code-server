# Audit Findings: GitHub Issues Reference

**Generated:** 2026-04-28
**Total Issues:** 15 (P1: 5, P2: 10)

This document lists all audit findings formatted for GitHub issue creation. Use either:
1. **Python Script** (Automated): `python3 scripts/ops/create-comprehensive-audit-issues.py`
2. **Manual Creation**: Copy issue details below and create in GitHub UI

---

## 🔴 Critical Issues (P1)

### 1. [INFRA] Replica Host (192.168.168.32) Connection Timeout
- **Labels:** P1, audit-finding, infrastructure, automated
- **Severity:** Connection down
- **Brief:** Replica host unreachable via SSH, preventing failover validation
- **Key Evidence:** CLUSTER-SHUTDOWN-REPORT-2026-04-27.md shows replica "not accessible"

### 2. [OPS] Missing Runtime Tooling: Docker and Kubectl
- **Labels:** P1, audit-finding, operations, automated
- **Severity:** Development environment incomplete
- **Brief:** `docker` and `kubectl` commands missing, blocking troubleshooting and K8s operations
- **Key Evidence:** Commands exit with code 127 (not found)

### 3. [SEC] NPM Dependency Vulnerabilities: Ongoing Remediation
- **Labels:** P1, audit-finding, security, automated
- **Severity:** Security exposure
- **Brief:** 6+ npm vulnerabilities identified; remediation incomplete
- **Key Evidence:** Commits bf54fc59 and 768b058d; pnpm-lock.yaml overrides

### 4. [INFRA] Primary-Replica Cluster Parity Validation Missing
- **Labels:** P1, audit-finding, infrastructure, automated
- **Severity:** Infrastructure risk
- **Brief:** No automated validation for config consistency between primary/replica
- **Key Evidence:** COMPREHENSIVE-GAP-ANALYSIS.md notes stale documentation causing errors

### 5. [OPS] Service Readiness Timeouts During E2E Testing
- **Labels:** P1, audit-finding, operations, automated
- **Severity:** Testing blocked
- **Brief:** Intermittent service readiness failures preventing E2E/load test execution
- **Key Evidence:** test-e2e-load.sh line 111; "Failed to start services" errors

---

## 🟡 High-Priority Issues (P2) - 10 Items

### 6. [DEBT] Engineering Hardening: 74+ Scripts Missing Trap Handlers
- **Labels:** P2, audit-finding, engineering, automated
- **Type:** Technical Debt
- **Coverage:** 10/65+ scripts (14% compliance)

### 7. [CI] Error Handling Lint Check Failures in Strict Mode
- **Labels:** P2, audit-finding, ci-cd, automated
- **Type:** CI/CD Infrastructure
- **Impact:** Cannot enforce consistency across codebase

### 8. [IAC] Terraform Version Outdated (v1.8.0 vs v1.14.9)
- **Labels:** P2, audit-finding, iac, automated
- **Type:** Infrastructure as Code
- **Recommendation:** Upgrade to v1.14.9

### 9. [IaC] Terraform Configuration Missing Root Context
- **Labels:** P2, audit-finding, iac, automated
- **Type:** Developer Experience
- **Problem:** Must manually switch directories for terraform operations

### 10. [CONFIG] Environment Variable SSOT Consolidation Incomplete
- **Labels:** P2, audit-finding, configuration, automated
- **Type:** Configuration Management
- **Status:** Phase 1 partial (60+ vars); Phases 2-3 pending

### 11. [IaC] Docker Compose File Consolidation Strategy
- **Labels:** P2, audit-finding, iac, automated
- **Type:** Infrastructure as Code
- **Problem:** ~20+ files without clear consolidation strategy

### 12. [DOCS] Missing Service Health Monitoring & Init Container Documentation
- **Labels:** P2, audit-finding, documentation, automated
- **Type:** Operational Knowledge
- **Missing:** Health monitoring runbook, init container strategy

### 13. [K8S] Kubernetes Migration Phase 14: Runtime Validation Blocked
- **Labels:** P2, audit-finding, kubernetes, automated
- **Type:** Migration Blocker
- **Impact:** kubectl missing; Phase 14 completion unverifiable

### 14. [APP] Activity Feed & Agent Runtime: Recurring WebSocket/Ingest Errors
- **Labels:** P2, audit-finding, application, automated
- **Type:** Application Reliability
- **Pattern:** Error recovery not implemented

### 15. [DEBT] Historical Code Duplication: App Directory Consolidation
- **Labels:** P2, audit-finding, engineering, automated
- **Type:** Technical Debt
- **Recent Fix:** Commit e9c9236e; other directories need audit

---

## 📊 Summary

| Priority | Count | Status |
| --- | --- | --- |
| P1 (Critical) | 5 | Requires immediate attention |
| P2 (High) | 10 | Schedule for next phase |
| **Total** | **15** | **Ready for GitHub** |

## 🚀 Creation Instructions

### Automated (Recommended)

Requires: `GITHUB_TOKEN` environment variable

```bash
export GITHUB_TOKEN='ghp_your_token_here'
export GITHUB_REPO='kushin77/code-server'
python3 scripts/ops/create-comprehensive-audit-issues.py
```

Dry run (preview without creating):
```bash
export DRY_RUN=true
python3 scripts/ops/create-comprehensive-audit-issues.py
```

### Manual Creation

1. Copy each issue title and body from below
2. In GitHub repo: Issues → New Issue
3. Paste title and body
4. Add labels from "Labels:" field
5. Save

---

## 📝 Full Issue Details

[See `scripts/ops/create-comprehensive-audit-issues.py` for complete issue text]
