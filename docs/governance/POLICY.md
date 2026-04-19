# Code Quality Governance Policy

**Version**: 1.0  
**Effective**: April 22, 2026  
**Owner**: Infrastructure Team  
**Last Updated**: April 22, 2026

---

## Executive Summary

This document establishes the unified quality standards for the kushin77/code-server repository. All code contributions—regardless of file type (shell, Terraform, Python, YAML, workflows)—must comply with this policy.

Non-compliance blocks merge unless:
1. **Explicit Waiver**: Documented and approved per section 5
2. **Technical Impossibility**: Approved by infrastructure lead with justification

---

## 1. Core Standards

### 1.1 Script Entry Point Standard

**Scope**: All `.sh` files (shell scripts, including provisioning, deployment, CI/CD scripts)  
**Priority**: P0 (blocking)

#### Required Header
Every shell script MUST contain:
```bash
#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════════════════════
# SCRIPT_TITLE: [Purpose in 1 line]
#
# DESCRIPTION: [Functionality overview, 2-3 sentences]
# USAGE: ./<script-name>.sh [options] [args]
#
# AUTHOR: [Team/User]
# DATE: [YYYY-MM-DD]
# VERSION: [X.Y]
#
# DEPENDENCIES: bash >= 4.0, [list tools]
# ENVIRONMENT: [Required env vars: VAR1, VAR2]
#
# CHANGES:
#   YYYY-MM-DD | vX.Y | [Change description]
#   YYYY-MM-DD | vX.Y | [Change description]
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail
```

#### Code Quality Requirements
- **Error handling**: `set -euo pipefail` on line 3 (after shebang + header)
- **Logging**: All functions must use consistent logging (log_info, log_error, log_warn, log_debug)
- **No hardcoded paths**: Use `${SCRIPT_DIR}`, `${PROJECT_ROOT}` variables
- **No hardcoded secrets**: All credentials via env vars or config files
- **Comments**: Minimum 20% of code is explanatory comments
- **Shellcheck compliance**: Zero warnings on shellcheck -x
- **Exit codes**: Functions return explicit 0 (success) or 1+ (failure)
- **Idempotency**: Script safe to run multiple times without side effects (unless --force flag)

#### Naming Convention
```
{action}-{target}-{phase}.sh

Examples:
  provision-workload-identity.sh
  deploy-container-hardening.sh
  scan-secrets-pre-commit.sh
  verify-governance-framework.sh
```

---

### 1.2 Terraform Configuration Standard

**Scope**: All `.tf` and `.tfvars` files  
**Priority**: P0 (blocking)

#### Required Structure
Every module/configuration MUST contain:

```hcl
# ════════════════════════════════════════════════════════════════════════════════════════════
# MODULE: [module_name]
# DESCRIPTION: [What this module provisions, 1-2 sentences]
# DEPENDENCIES: [List other modules, data sources]
# OUTPUTS: [What values are exported]
# ════════════════════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "= 3.0.2"  # PINNED VERSION (not ~=, not >=)
    }
  }
}

# Version-specific locals for deployment
locals {
  # SSOT: Keep all values here, avoid repetition in resource blocks
  service_name = "example-service"
  image_tag    = "4.2.1"  # Pinned, immutable
  labels = {
    "io.kushnir.managed"  = "true"
    "io.kushnir.version"  = "1.0"
    "io.kushnir.owner"    = "infrastructure"
  }
}
```

#### Code Quality Requirements
- **Version pinning**: ALL provider versions pinned with `=` (not `~=`, not `>=`)
- **Immutability**: No optional defaults that vary; if not specified, must fail validation
- **Comments**: Explain "why" for non-obvious configurations (30% of code)
- **No code duplication**: Use `locals{}`, `for_each`, `for` loops instead of repeating blocks
- **Sensitive values**: Mark all credentials with `sensitive = true`
- **Data source validation**: All external data sources validated with `plan` before `apply`
- **Resource naming**: Use `{service}-{function}-{version}` convention
- **Outputs**: All resource outputs documented with descriptions

#### Naming Convention
```
{category}-{purpose}.tf

Examples:
  iam.tf (identity & access management)
  rbac.tf (role-based access control)
  audit.tf (audit logging & compliance)
  monitoring.tf (observability infrastructure)
  networking.tf (network policies, service discovery)
```

#### Validation
```bash
terraform fmt -check     # Formatting
terraform validate       # Syntax & dependency validation
terraform plan -json     # Plan validation
```

---

### 1.3 GitHub Workflow Standard

**Scope**: All `.github/workflows/*.yml` files  
**Priority**: P0 (blocking)

#### Required Metadata
```yaml
name: [Workflow Name]
on:
  push:
    branches: [main, feature/**]
    paths:
      - "src/**"
      - ".github/workflows/this-workflow.yml"
  pull_request:
    types: [opened, synchronize]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
  # EXPLICIT: No secrets-write, no repo-write unless required
  # REASON: [Why this permission is needed, 1 line]

env:
  REGISTRY: ghcr.io
  # SSOT: Versions pinned here
  TERRAFORM_VERSION: "1.3.0"
```

#### Code Quality Requirements
- **Action versions**: Pinned to commit SHA (not `@v1`, not `@main`)
  ```yaml
  - uses: actions/checkout@b4ffde65f69c9871e6c2a34aeadc886367a37751  # v4.1.0
  ```
- **No secrets in logs**: Redact all sensitive output
- **Artifact cleanup**: Delete after 7 days maximum
- **No shell injections**: Use `run:` input, not `${{ secrets.* }}` in script
- **Timeout enforcement**: All jobs have explicit timeout: 60m max
- **Retry logic**: Network flaky operations have 2x retry
- **Status checks**: All jobs report status to GitHub (via `if: always()`)

#### Naming Convention
```
{trigger}-{action}-{target}.yml

Examples:
  pr-validate-terraform.yml
  push-scan-secrets.yml
  schedule-governance-check.yml
```

---

### 1.4 Configuration File Standard

**Scope**: `.yml`, `.yaml`, `.toml`, `.json` (except generated files)  
**Priority**: P0 (blocking)

#### Required Headers
```yaml
# ════════════════════════════════════════════════════════════════════════════════════════════
# FILE: [config/path/filename.yml]
# PURPOSE: [What this config file does, 1-2 sentences]
# OWNER: [Team responsible]
# GENERATED_BY: [Script that generates this, if auto-generated]
# ════════════════════════════════════════════════════════════════════════════════════════════

# SSOT: Single source of truth
# Do NOT duplicate values - reference with ${VAR} or anchors (&)
```

#### Code Quality Requirements
- **No secrets**: All credentials external (env vars, Secret Manager)
- **Comments**: Explain non-obvious configuration choices (30% of content)
- **Validation**: Config syntax validated in CI before merge
- **SSOT**: No value appears twice; use anchors (`&ref`) or substitution
- **Paths**: Use relative paths with `${CONFIG_ROOT}` base
- **Immutability**: All version strings pinned to specific version, not ranges

---

### 1.5 Duplicate Detection Standard

**Scope**: All files (shell, Terraform, config, Python, etc.)  
**Priority**: P0 (blocking)

#### Rules
- **Minimum 5 lines**: Code blocks < 5 lines can be duplicated
- **Threshold**: jscpd default (90% match, 3+ occurrences = duplicate)
- **Exceptions**: 
  - Generated files (e.g., Caddyfile from .tpl)
  - Test data (fixtures, mocks)
  - Documentation examples (marked with `<!-- language: example -->`)

#### Remediation
- **Extract to function/module**: Move duplicated code to shared function
- **Template**: Use templates (Terraform `.tpl`, shell `.sh.tpl`) and generate
- **Loop/Iteration**: Use `for_each`, `for` loops instead of repeating resource blocks
- **Waiver**: Document why duplication is acceptable (with expiration date)

---

### 1.6 Secrets Detection Standard

**Scope**: All files in git (scripts, config, Terraform, workflows)  
**Priority**: P0 (blocking) — Merge rejected if ANY secret detected

#### Tools & Configuration
- **TruffleHog v3.76.3**: Entropy + verified secrets detection (fail-closed)
- **gitleaks**: Pattern matching with allowlist support (fail-closed)
- **Detection scope**:
  - AWS keys, GCP service accounts, GitHub tokens, API keys
  - Passwords, private keys, OAuth secrets
  - Database connection strings with credentials
  - Slack/Discord webhooks

#### Allowed Exceptions
- **Test values**: Marked with `# EXAMPLE:` comment and non-functional (e.g., `example@example.com`)
- **Public data**: Non-sensitive configuration values
- **Placeholders**: Template variables like `${APEX_DOMAIN}`, `{{ variable }}`

#### Response Protocol
If secret found in commit:
1. Immediate notification to committer
2. 15 minutes to force-push fix OR revert
3. If expired: automatic PR rejection
4. Post-commit: rotate compromised credential immediately

---

### 1.7 Code Duplication Detection Standard

**Scope**: Shell scripts, Terraform, Python, configuration files  
**Priority**: P0 (blocking)

#### Tool: jscpd
```bash
jscpd --min-lines 5 --min-tokens 30 --threshold 0.9
```

#### Rules
- **5+ identical lines** = duplication
- **90% match** = duplication
- **Multiple occurrences** = violation

#### Resolution
1. **Extract function**: Create reusable function with parameters
2. **Use variables/locals**: Reduce repetition via dynamic values
3. **Template generation**: Use `.tpl` + render pipeline (Terraform, Make)
4. **Waiver**: Documented if duplication unavoidable

---

### 1.8 Dependency & License Standard

**Scope**: All dependencies (npm, Python pip, Terraform providers, Docker images)  
**Priority**: P1 (warning on first occurrence, blocking on policy repeat)

#### Requirements
- **Pinned versions**: All dependencies pinned to exact version (not ranges: `~`, `^`, `>=`)
- **License compliance**: All dependencies must have OSI-approved licenses (Apache 2.0, MIT, GPL-compatible)
- **Vulnerability scanning**: Trivy scans all dependencies; critical CVEs block merge
- **Deprecation tracking**: Version pinned = responsible for tracking deprecations

#### Images & Artifacts
- **Docker images**: Scan with Trivy, tag with date + git SHA
- **Binaries**: Sign with cosign, verify on every deployment
- **Terraform modules**: Pin source version (not `main` branch reference)

---

### 1.9 Documentation Standard

**Scope**: All code-adjacent documentation (READMEs, runbooks, ADRs)  
**Priority**: P1

#### Required Elements
Every code delivery MUST include:

1. **Architecture Decision Record (ADR)**: If structural decision made
   - Template: `docs/architecture/ADR-XXX-[title].md`
   - Content: Problem → Solution → Consequences → Alternatives

2. **Runbook**: For operational procedures
   - Template: `docs/runbooks/[service]-[procedure].md`
   - Content: Prerequisites → Steps → Verification → Rollback

3. **README**: Updated with new features/commands
   - Include: What changed, why, how to use, where docs are

---

## 2. Enforcement Mechanism

### 2.1 CI/CD Governance Workflow

Every PR runs:
```
1. shellcheck         → Shell scripts (P0)
2. terraform fmt      → Terraform formatting (P0)
3. terraform validate → Terraform validation (P0)
4. yamllint          → YAML syntax (P0)
5. jscpd             → Duplication detection (P0)
6. gitleaks          → Secrets scanning (P0)
7. TruffleHog        → Entropy + verified secrets (P0)
8. Trivy             → Vulnerability scanning (P1)
9. SAST (Semgrep)    → Security code analysis (P1)
10. checkov          → IaC security (P1)
```

**Default**: FAIL on violation  
**Exception**: Waiver (section 5)

### 2.2 Quality Gate Status

PRs require:
- ✅ All P0 checks PASS
- ✅ All P1 checks PASS (or waivered)
- ✅ Code review approval (1+ maintainer)

### 2.3 Merge Blocking

PR blocked if:
- Any P0 check fails AND no waiver
- Security check detects new vulnerability
- Duplicate code > threshold without justification

---

## 3. Metrics & Reporting

### 3.1 Governance Debt Dashboard

Published monthly to Prometheus + Grafana:

```
governance_violations_total          # By category (script, terraform, workflow, config)
governance_violations_by_severity    # (info, warn, error, critical)
governance_debt_aging_days           # Time since violation detected
governance_waivers_active            # Active exceptions with expiration dates
governance_remediation_sla_days      # SLA timer for fixing violations
```

### 3.2 Reporting

**Weekly**: Governance violation summary (team Slack digest)  
**Monthly**: Full governance debt report (email + dashboard)

### 3.3 Governance Score

GitHub Project `Governance Debt Tracker` and the governance enforcement workflow track a composite governance score from **0–100**.

Formula:

```text
score = max(0, 100
  - (jscpd_violations * 5)
  - (missing_headers * 2)
  - (hardcoded_ips * 10)
  - (active_shims_with_fallback * 8))
```

Inputs are derived from canonical repository checks only:
- `jscpd_violations`: duplicate clusters detected by `jscpd`
- `missing_headers`: active `scripts/MANIFEST.toml` entries missing `@file/@module/@description`
- `hardcoded_ips`: active top-level scripts with raw `192.168.168.x` references
- `active_shims_with_fallback`: compatibility shims still retaining fallback implementations

Usage:
- PR workflow posts the current score as a comment and step summary.
- Monthly governance report exports the score as Prometheus metrics.
- GitHub Project field `Governance Score` stores the current debt posture for governance issues.

---

## 4. Toolchain Configuration

### Central Manifest
All tools configured in single file: `config/governance-manifest.yml`

#### Example Structure
```yaml
governance:
  version: "1.0"
  tools:
    shellcheck:
      enabled: true
      rules: "all"
      exclude: "SC1091,SC2086"
      
    terraform:
      enabled: true
      fmt_check: true
      validate: true
      version_pinning: "required"
      
    jscpd:
      enabled: true
      min_lines: 5
      min_tokens: 30
      threshold: 0.9
      
    secrets:
      trufflehog:
        enabled: true
        fail_closed: true
        verified_only: true
      gitleaks:
        enabled: true
        fail_closed: true
        
    sast:
      semgrep:
        enabled: true
        rules: "rulesets/owasp-top-10"
        
  waivers:
    enabled: true
    approval_required: true
    expiration_days: 90
```

---

## 5. Waiver Request & Approval Process

### 5.1 When to Request Waiver

Examples:
- "This shell script < 100 lines, doesn't need full error handling framework"
- "Test fixture intentionally duplicates data (5 copies for test coverage)"
- "Configuration file auto-generated by vendor tool (can't modify)"

### 5.2 Waiver Request Format

**File**: `docs/governance/WAIVERS.md` (append to existing)

```markdown
### Waiver #[AUTO_INCREMENT]

**Date Requested**: YYYY-MM-DD  
**Requested By**: @github_username  
**Issue**: [Link to issue or PR]  
**Policy Violated**: [Which policy, e.g., "Script Entry Point Standard"]  
**Violation**: [Specific violation found]  
**Justification**: [Why waiver necessary, 2-3 sentences]  
**Expiration**: [Date or version when waiver expires]  
**Approved By**: @maintainer  
**Approval Date**: YYYY-MM-DD  

---
```

### 5.3 Approval Criteria

Waiver approved if:
- **Technical impossibility**: Legitimate reason preventing compliance
- **Risk acceptable**: Violation does not introduce security risk
- **Temporary**: Waiver has explicit expiration date
- **Documented**: Justification clear and traceable

### 5.4 Audit Trail

All waivers logged in:
1. `docs/governance/WAIVERS.md` (permanent record)
2. GitHub PR comments (with approval justification)
3. Metrics dashboard (tracks active/expired waivers)

---

## 6. Team Training & Rollout

### 6.1 Required Training

All developers MUST complete:
- [ ] Read this policy document (15 min)
- [ ] Watch governance framework demo (20 min)
- [ ] Complete waiver request on sample PR (30 min)
- [ ] Review governance dashboard (10 min)

### 6.2 Rollout Timeline

- **Week 1**: Governance framework deployed, warnings mode (advisory)
- **Week 2**: Security checks (P0) enforced, fail-closed
- **Week 3**: All checks enforced (P0+P1), waivers active
- **Week 4+**: Governance debt tracking, monthly reporting

---

## 7. Escalation & Exception Process

### 7.1 Policy Exception (Rare)

**Process**: 
1. Request via GitHub issue (tag #380)
2. Infrastructure lead reviews
3. Security team approval (if security-related)
4. Documented in this policy (permanent record)

**Criteria**: 
- Exception affects < 5 files
- Clear technical justification
- No security risk introduced
- Owner assigned for future compliance

---

## 8. Policy Updates

**Versioning**: Semantic (MAJOR.MINOR.PATCH)  
**Review Cadence**: Quarterly  
**Change Process**: Issue → Discussion → Team approval → Merge to main

---

## Appendix A: Tool Configuration Files

- `.shellcheckrc` — Shell script rules
- `terraform.tfvars` — Terraform defaults
- `.yamllint` — YAML validation rules
- `.jscpdrc` — Duplication detection threshold
- `.gitleaks.toml` — Secrets patterns
- `.trivyignore` — Accepted vulnerabilities
- `semgrep.yml` — SAST rules

---

## Appendix B: Glossary

- **SSOT**: Single Source of Truth (one place to define each value)
- **Idempotent**: Running twice = same result (safe to re-run)
- **Fail-closed**: Violation blocks merge (default: yes)
- **Waiver**: Exception to policy with approval + expiration
- **Governance debt**: Accumulated violations not yet remediated

---

**Document Status**: APPROVED ✅  
**Next Review**: Q3 2026 (July 1)  
**Owner**: @kushnir (Infrastructure Lead)
