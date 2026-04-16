# Unified Code Governance Framework

**Effective Date**: April 2026  
**Status**: ACTIVE / PRODUCTION-ENFORCED  
**Owner**: Architecture + DevOps Team  
**Review Cycle**: Quarterly  

---

## 1. GOVERNANCE PHILOSOPHY

This framework establishes production-first, globally-enforceable standards that prevent the same governance issues from re-appearing in new code.

### Core Principles
- **Global-first**: Standards apply universally; one-off exemptions require documented waivers
- **Single source of truth**: One canonical rule per capability (config, script, workflow)
- **Fail-closed**: Default action is to block violations; waivers are explicit exceptions
- **Audit trail**: All granted waivers and policy changes logged with justification
- **Measurable**: Metrics track compliance trends over time; SLA for remediation

---

## 2. GOVERNANCE STANDARDS

### 2.1 Shell Scripts (`.sh` files)

**Scope**: All executable shell scripts in `scripts/`, `_common/`, and root

#### Required Standard Pattern
```bash
#!/usr/bin/env bash
# @file: <BRIEF DESCRIPTION>
# @module: <logical-namespace/script-name>
# @description: <2-3 sentence purpose>
# @author: <TEAM>
# @updated: <YYYY-MM-DD>

set -euo pipefail
IFS=$'\n\t'

# Source common utilities (if needed)
source "${SCRIPT_DIR}/_common/env.sh"
source "${SCRIPT_DIR}/_common/logging.sh"

# Parameterize all values - NO HARDCODED IPs, passwords, ports
# Use environment variables from _common/env.sh or .env files
```

#### Rules
1. **Shebang**: Must be `#!/usr/bin/env bash` (portable across systems)
2. **Headers**: Must include `@file`, `@description` metadata (machine-parseable)
3. **Strict mode**: Must include `set -euo pipefail` at the top after header
4. **No hardcoded values**:
   - IPs: Use `${PROD_HOST}` from env.sh
   - Ports: Use `${SERVICE_PORT}` from env.sh  
   - Credentials: Use `${SECRET_NAME}` from .env / Vault
   - Filenames: Use `${SCRIPT_DIR}` for paths
5. **Error handling**: All commands that can fail must have error handlers or `set -e` protection
6. **Logging**: Use `log_info`, `log_error`, `log_warn` from `_common/logging.sh` (NOT raw `echo`)
7. **Exit codes**: Return non-zero on any error; document expected codes in comment block

#### Violations Trigger
- Pre-commit hook: WARN (non-blocking)
- CI: FAIL if new script added without headers
- Governance check: FAIL if parameterization missing

#### Examples

✅ CORRECT:
```bash
#!/usr/bin/env bash
# @file: health-check.sh
# @module: health/check
# @description: Validates all core services are responsive. Exits 0 if healthy, 1+ if issues.

set -euo pipefail

source "${SCRIPT_DIR}/_common/env.sh"
source "${SCRIPT_DIR}/_common/logging.sh"

HEALTH_ENDPOINT="${HEALTH_CHECK_URL:-http://localhost:8080/health}"
TIMEOUT_SEC="${HEALTH_TIMEOUT:-10}"

log_info "Checking health endpoint: $HEALTH_ENDPOINT"

if curl -sf --max-time "$TIMEOUT_SEC" "$HEALTH_ENDPOINT" > /dev/null; then
  log_info "Health check passed"
  exit 0
else
  log_error "Health check failed"
  exit 1
fi
```

❌ WRONG:
```bash
#!/bin/bash
# Health check script

curl -s http://192.168.168.31:8080/health > /dev/null && echo "OK" || echo "FAILED"
exit 0  # Always exits 0 (wrong!)
```

---

### 2.2 Configuration Files (YAML, TOML, JSON)

**Scope**: All `*.yml`, `*.yaml`, `*.toml`, `*.json` files in `config/`, `.github/`, `docker-compose.tpl`, etc.

#### Rules
1. **No hardcoded secrets**: Scan with gitleaks
2. **Parameterized**: Use `${VAR}` syntax for all environment-specific values
3. **Documented defaults**: Config files must include comment explaining each variable
4. **Schema validation**: YAML must pass `yamllint`; JSON must pass schema validation
5. **Immutable versions**: Docker image tags and dependency versions must be explicit (no `latest`)

#### Violations Trigger
- Gitleaks: FAIL if secret pattern detected
- YAMLLint: FAIL if style violations found
- Governance check: FAIL if variables not parameterized

---

### 2.3 Docker Builds

**Scope**: All `Dockerfile*` files

#### Rules
1. **Build args parameterized**: All runtime values via `ARG` or `ENV` (from .env during build)
2. **Immutable base images**: Use pinned versions (`ubuntu:22.04`, not `ubuntu:latest`)
3. **Multi-stage builds**: Use `FROM ... AS builder` pattern to reduce final image size
4. **No secrets in layers**: Never `RUN echo $SECRET` or similar
5. **Scanned for vulnerabilities**: Trivy must find 0 HIGH/CRITICAL CVEs

#### Violations Trigger
- Dockerfile lint: WARN
- Trivy scanning: FAIL if HIGH/CRITICAL CVEs found
- Governance check: FAIL if base image is `latest` or has unresolved CVEs

---

### 2.4 GitHub Workflows (`.github/workflows/*.yml`)

**Scope**: All CI/CD workflow files

#### Rules
1. **No hardcoded secrets**: Use GitHub Secrets or OIDC federation
2. **Reusable workflows**: Extract common patterns to `.github/workflows/_shared/`
3. **Idempotent**: Workflows must be safe to re-run multiple times
4. **Timeout boundaries**: Each job must specify `timeout-minutes`
5. **Clear success criteria**: Each workflow must document "done when..."
6. **Audit trail**: Sensitive operations logged to `$GITHUB_OUTPUT`

#### Violations Trigger
- Gitleaks: FAIL if secret patterns found
- Governance check: FAIL if dependencies not vendored or pinned
- Lint: FAIL if workflow syntax invalid

---

### 2.5 Terraform Configuration

**Scope**: All `.tf` files in `terraform/`

#### Rules
1. **Provider pinning**: Must specify version constraints (e.g., `>= 4.0, < 5.0`)
2. **Input validation**: All `variable` blocks must have `validation` rules
3. **Locals parameterized**: No hardcoded values in locals; use `var.` references
4. **Sensitive outputs**: Marked with `sensitive = true` (passwords, tokens)
5. **Fmt standard**: Code formatted with `terraform fmt` before commit

#### Violations Trigger
- TFSec: FAIL if security issues found
- Terraform fmt: FAIL if code not formatted
- Governance check: FAIL if provider versions not pinned

---

### 2.6 Code Duplication & Dead Code

**Scope**: All code files (shell, Terraform, config)

#### Rules (Enforced by jscpd and knip)
1. **Duplicate blocks**: jscpd fails if > 5% of codebase is duplicated
2. **Dead code**: knip fails if  functions/variables are unused
3. **Cross-file duplication**: Extract to shared module/function
4. **Waiver process**: Can request exception with justification

#### Violations Trigger
- jscpd: FAIL if duplication > threshold
- knip: FAIL if unused code found
- Manual review: Required to approve waiver

---

## 3. ENFORCEMENT MECHANISM

### 3.1 CI Governance Workflow

**File**: `.github/workflows/iac-governance.yml` (global orchestrator)

**Execution**: Runs on every push and PR

**Gates** (Sequential, all must pass to merge):
1. **Gitleaks** — Scan for secrets (0 matches required)
2. **TFSec** — Terraform security scan (0 HIGH/CRITICAL)
3. **Checkov** — IaC policy enforcement (0 policy violations)
4. **Shellcheck** — Shell script linting (only non-library issues)
5. **YAMLLint** — Configuration validation
6. **jscpd** — Duplicate detection (< 5%)
7. **knip** — Dead code detection (optional warnings)
8. **Docker Lint** — Dockerfile best practices
9. **Trivy** — Container image scanning
10. **Cosign** — Artifact signing verification

### 3.2 Pre-Commit Hooks

**File**: `.pre-commit-config.yaml`

**Execution**: Before every local commit (can be bypassed with `--no-verify`, logged)

**Hooks**:
- shellcheck
- yamllint
- terraform fmt
- gitleaks (warning only locally)
- detect-secrets
- prettier (formatting)

### 3.3 Manual Code Review

**Process**:
- All PRs must have 1+ review from senior engineer
- Reviewers explicitly check governance checklist (parameterization, duplication, headers)
- Checklist embedded in PR template

---

## 4. WAIVER & EXCEPTION PROCESS

### 4.1 When to Request a Waiver

Situations where a waiver is justified:
- **Technical necessity**: Code cannot be refactored without major rewrite
- **Maintenance burden**: Over-parameterization creates maintenance debt
- **Performance**: Standards would cause unacceptable latency

### 4.2 Waiver Request Template

```markdown
## Governance Waiver Request

**Standard Violated**: [e.g., "Shell script without @file header"]  
**Why**: [2-3 sentence business justification]  
**Duration**: [e.g., "90 days" or "permanent with maintenance waiver"]  
**Risk**: [What could go wrong if this waiver is granted?]  
**Owner**: [@username - person responsible for remediation]  

**Approval**: [Requires signature from architecture + security]
```

### 4.3 Audit Trail

All waivers logged in `docs/GOVERNANCE-WAIVERS.md`:
- Date granted
- Standard violated
- Justification
- Approval signature
- Expiration date
- Actual remediation status

---

## 5. METRICS & COMPLIANCE REPORTING

### 5.1 Weekly Governance Report

**Auto-generated**, posted in `#eng-infrastructure` Slack channel:

```
### Code Governance Compliance (Week of YYYY-MM-DD)

| Standard | Violations | Trend | Waivers | Active Debt |
|----------|-----------|-------|---------|-------------|
| Hardcoded Secrets | 0 | ↓ | 0 | 0 lines |
| Parameterization | 2 | → | 0 | 45 lines |
| Shell Headers | 12 | ↑ | 3 | 500+ files |
| Duplicate Code | 3.2% | ↓ | 1 | jscpd report |
| Dead Code | 150 funcs | → | 2 | knip report |
| Dockerfile CVEs | 0 | ↓ | 0 | N/A |

**P0 Blockers**: None  
**Remediation SLA**: All P1 violations resolved within 2 weeks  
**Coverage**: 100% (all code files scanned)
```

### 5.2 Metrics Dashboard

**Tool**: Prometheus + Grafana  
**Queries**:
- Governance violations over time (by type)
- Waiver approval-to-remediation cycle time
- False-positive rate for jscpd/knip
- CI success rate for governance checks
- Mean time to governance fix (P0/P1/P2)

### 5.3 Governance Debt Tracking

**Tracked in**: `docs/GOVERNANCE-DEBT.md`

**Entries**:
- Issue number
- Standard violated
- Date discovered
- Target remediation date
- Owner
- Status (open/closed)
- Waiver (if applicable)

---

## 6. EXCEPTIONS & SPECIAL RULES

### 6.1 Generated Files

**Exempt from governance** if:
- Explicitly marked `@generated` in header
- Produced by code-generation tool with version pin
- Vendored third-party code (in `vendor/` or `third-party/` folder)

**Still required**:
- Secret scanning (gitleaks)
- Vulnerability scanning (Trivy)

### 6.2 Documentation Files

**Exempt from** shell/code style rules  
**Still required**:
- No secrets (gitleaks)
- Spelling/grammar (if applicable)
- Link validation (CI check)

### 6.3 Legacy Phase-Based Scripts

**Transition period**: 90 days from framework adoption  
**Status**: DEPRECATED (marked in header)  
**Actions**:
- Replaced by canonical script equivalents
- Moved to `scripts/archive/` after EOL
- Linked from `DEPRECATED-SCRIPTS.md`

---

## 7. ONBOARDING & TRAINING

### 7.1 For Engineers

1. **Initial**: Read this framework document (15 min)
2. **Setup**: Install pre-commit hooks locally (`pre-commit install`)
3. **Practice**: Submit a test PR following all standards, get peer review feedback
4. **Reference**: Bookmark `/docs/GOVERNANCE-CHECKLIST.md` for quick reference

### 7.2 For Code Review

All reviewers must verify (checklist in PR template):
- [ ] Shell scripts have `@file`, `@description` headers
- [ ] No hardcoded IPs/ports/credentials
- [ ] Configuration is parameterized
- [ ] Duplicated code extracted to shared functions
- [ ] Error handling complete (not silent failures)
- [ ] Docker images are scanned (Trivy) and use pinned versions
- [ ] Terraform uses version constraints and input validation

---

## 8. POLICY VERSIONING & CHANGES

### 8.1 Change Control

Changes to this framework require:
1. RFC (Request for Comments) issue in GitHub with `governance` label
2. Minimum 1-week discussion window
3. Approval from: architecture owner + security + 2 engineers from different teams
4. Updated version in this document
5. Announcement in `#eng-infrastructure` and team meeting

### 8.2 Backwards Compatibility

New standards must include a transition period:
- **Announce** (day 1): "New standard effective in 30 days"
- **Grace period** (days 1-30): Warnings in CI, not failures
- **Enforce** (day 31+): Failures block merge

---

## 9. ESCALATION & FEEDBACK

### 9.1 If Governance Blocks Valid Work

1. **First**: Verify the violation is real (not a false positive)
2. **Second**: Request temporary waiver (see section 4.2)
3. **Third**: If standard seems misaligned, open RFC to change framework
4. **Contact**: @architecture-owner or DM in Slack

### 9.2 False Positives

Report in GitHub issue with `governance-feedback` label:
- Tool name (jscpd, knip, etc.)
- File path
- Why this should not be a violation
- Suggested fix

---

## 10. QUICK REFERENCE CHECKLISTS

### 10.1 Shell Script Checklist

Before committing a shell script:
- [ ] Header with `@file`, `@description`, `@module`
- [ ] `set -euo pipefail` on line 4
- [ ] No hardcoded IPs (use `${PROD_HOST}`)
- [ ] No hardcoded ports (use `${SERVICE_PORT}`)
- [ ] Error handling for all external commands
- [ ] Uses `log_info`/`log_error` from `_common/logging.sh`
- [ ] Exit code documented (0=success, non-zero=failure)
- [ ] Passes shellcheck locally (`shellcheck myscript.sh`)

### 10.2 Configuration File Checklist

Before committing a YAML/JSON/TOML config:
- [ ] No secrets (gitleaks passes)
- [ ] Variables parameterized (no hardcoded IPs/ports)
- [ ] Defaults documented in comments
- [ ] Schema valid (yamllint passes)
- [ ] Docker image tags pinned (not `latest`)
- [ ] Terraform versions pinned (`>= 1.0, < 2.0`)

### 10.3 PR Review Checklist

Before approving a PR:
- [ ] Code matches governance framework
- [ ] No duplicate code introduced
- [ ] Parameterization complete
- [ ] Error handling non-silent
- [ ] No hardcoded values
- [ ] Tests added for new functionality
- [ ] Runbooks/docs updated if needed

---

## APPENDIX: TOOL VERSIONS

| Tool | Version | Link |
|------|---------|------|
| gitleaks | 8.20+ | https://gitleaks.io |
| TFSec | 1.28+ | https://aquasecurity.github.io/tfsec |
| Checkov | 3.2+ | https://www.checkov.io |
| ShellCheck | 0.9+ | https://www.shellcheck.net |
| YAMLLint | 1.33+ | https://yamllint.readthedocs.io |
| jscpd | 4.0+ | https://github.com/kucherenko/jscpd |
| Knip | 5.0+ | https://knip.dev |
| Trivy | 0.52+ | https://aquasecurity.github.io/trivy |
| Cosign | 2.2+ | https://sigstore.dev |
| Pre-commit | 4.0+ | https://pre-commit.com |

---

**Document Version**: 1.0  
**Effective Date**: April 15, 2026  
**Next Review**: July 15, 2026  
**Owner**: @architecture-team
