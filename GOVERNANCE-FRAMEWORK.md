# Unified Global Code-Quality Governance Framework

**Version**: 1.0  
**Effective**: April 16, 2026  
**Owner**: Architecture + DevOps  
**Status**: DRAFT - Awaiting team approval

---

## I. EXECUTIVE SUMMARY

This framework defines non-negotiable code standards and enforcement rules across shell scripts, Terraform configurations, GitHub workflows, and infrastructure-as-code. It replaces ad-hoc governance with a coordinated, measurable, and reversible policy engine.

**Key Principles**:
- **Global-first**: No one-off exemptions without reusable framework
- **Single Source of Truth**: One canonical policy for each capability category
- **Fail-Closed**: All violations block merge; waivers are documented and audited
- **Measurable**: Every policy has clear acceptance criteria and metrics

---

## II. POLICY FRAMEWORK

### A. Script Standards (Shell Scripts)

**Policy P1: Script Header & Metadata**
- All production scripts must include header block with:
  - Purpose and usage documentation
  - Author/owner for escalation
  - Version/last-modified date
  - Idempotency statement (safe to re-run without side effects)

**Enforcement**:
- ✅ Shellcheck must pass (no warnings)
- ✅ Header validation in CI (automated grep check)
- ✅ Blocks merge if missing or non-standard format

---

**Policy P2: Credential & Secret Handling**
- All secrets must be parameterized via environment variables
- No hardcoded passwords, API keys, or tokens
- Defaults must be non-functional (changeme, replace-me, example.com patterns)

**Enforcement**:
- ✅ Gitleaks blocks any commit with secret patterns
- ✅ .gitleaks.toml allowlist for false positives
- ✅ Pre-commit hook (no-hardcoded-credentials)

---

**Policy P3: Error Handling & Exit Codes**
- All scripts must use `set -euo pipefail` (fail on error, undefined vars, pipe failures)
- All conditional blocks must have error handling
- Script must exit with non-zero code on failure

**Enforcement**:
- ✅ Shellcheck validates error handling patterns
- ✅ CI test: verify script exits 1 when command fails
- ✅ Blocks merge if unhandled error paths detected

---

**Policy P4: Idempotency & State Management**
- All production scripts must be safe to re-run without side effects
- Script must check current state before making changes
- Script must report changes made (for audit trail)

**Enforcement**:
- ✅ Scripts must include idempotency statement in header
- ✅ CI test: verify script produces same state on 2nd run
- ✅ Runbook must verify idempotency before production use

---

### B. Terraform/IaC Standards

**Policy T1: Variable Definition & Parameterization**
- All values must be parameterized (no hardcoded values in resource definitions)
- Variables must have descriptions, types, and sensible defaults
- Sensitive values must be marked as `sensitive = true`

**Enforcement**:
- ✅ `terraform validate` must pass
- ✅ `terraform fmt` enforces consistent formatting
- ✅ Checkov scans for hardcoded secrets
- ✅ Blocks merge if sensitive values hardcoded

---

**Policy T2: Resource Naming Convention**
- Resources must follow pattern: `<type>_<environment>_<capability>`
- Example: `docker_container_prod_code_server`

**Enforcement**:
- ✅ Regex validation in CI (pattern matching)
- ✅ Blocks merge if non-standard naming detected

---

**Policy T3: Immutability & Versioning**
- All external resources must pin to specific versions
- Example: Docker images, Terraform providers, package versions

**Enforcement**:
- ✅ Checkov warns on unpinned versions
- ✅ Tfsec validates Terraform security practices
- ✅ Blocks merge if using `latest` tags

---

### C. GitHub Workflows Standards

**Policy W1: Workflow Naming & Triggers**
- Workflow file name must reflect purpose
- Triggers must be explicit (no implicit default branches)
- Workflow must have clear description in comments

**Enforcement**:
- ✅ Yamllint validates YAML syntax
- ✅ Workflow registry check (all workflows documented)
- ✅ Blocks merge if missing documentation

---

**Policy W2: Secrets & Credentials in Workflows**
- All sensitive values must use GitHub Secrets
- No environment variables hardcoded in workflow steps
- Secrets must be passed explicitly to steps needing them

**Enforcement**:
- ✅ Gitleaks scans workflow files
- ✅ CI warns if secrets appear in logs
- ✅ Blocks merge if hardcoded credentials detected

---

### D. Configuration File Standards

**Policy C1: Configuration Duplication**
- No configuration should appear in multiple files
- Shared configs must use single source of truth (template or shared base)
- Variants must be minimal (only values that differ)

**Enforcement**:
- ✅ jscpd detects duplicate blocks (threshold: <5% duplication)
- ✅ knip detects unused config variants
- ✅ Blocks merge if duplication exceeds threshold

---

**Policy C2: Configuration Validation**
- All config files must pass syntax validation
- Docker Compose files must pass `docker-compose config`
- YAML files must pass yamllint
- JSON files must pass `jq empty`

**Enforcement**:
- ✅ CI runs syntax validation for all config formats
- ✅ Blocks merge if any config has syntax errors
- ✅ Automated fix suggestions for formatting issues

---

### E. Documentation Standards

**Policy D1: File Naming & Hierarchy**
- Documentation must follow 5-level hierarchy (see #376)
- Root directory: Max 10 files (only critical entrypoints)
- Each file must have clear purpose and owner

**Enforcement**:
- ✅ CI checks file count at each level
- ✅ Blocks merge if root sprawl detected
- ✅ Automated suggest for file reorganization

---

**Policy D2: Link Integrity**
- All internal links must be valid
- All cross-references must be bidirectional (A→B implies B→A where appropriate)
- Deprecated links must have redirect rules

**Enforcement**:
- ✅ Link checker runs on every merge (validates 404s)
- ✅ Blocks merge if broken links detected
- ✅ Redirect rules documented in .github/REDIRECT_MAP.md

---

## III. ENFORCEMENT TOOLCHAIN

| Tool | Purpose | Config File |
|------|---------|-------------|
| **gitleaks** | Secret scanning | `.gitleaks.toml` |
| **checkov** | IaC misconfigurations | `.checkov.yaml` |
| **tfsec** | Terraform security | `.tfsec.yaml` |
| **shellcheck** | Shell script linting | `.shellcheckrc` |
| **yamllint** | YAML validation | `.yamllint.yaml` |
| **jscpd** | Duplicate detection | `.jscpdrc.json` |
| **knip** | Unused code detection | `knip.json` |
| **Link Checker** | Documentation links | None |
| **Docker Compose** | Syntax validation | None |

---

## IV. WAIVER & EXCEPTION PROCESS

### A. Waiver Request Template

When a policy exception is needed:

1. **Create a GitHub issue** titled: `waiver(policy-code): Reason for exception`
2. **Include**:
   - Policy code (e.g., P2, T1, W1)
   - Specific violation
   - Business justification
   - Proposed remediation timeline
   - Expiration date (max 30 days)

3. **Approval Required**:
   - Security team (for security/credential waivers)
   - Architecture team (for IaC/structure waivers)
   - DevOps team (for operational waivers)

4. **Enforcement**:
   - Waiver added to `WAIVERS.md` with expiration date
   - CI re-runs after waiver approval
   - Automatic escalation on expiration date

---

### B. Waiver Audit Trail

**File**: `WAIVERS.md`

Tracks all granted exceptions:

| Policy | Violation | Reason | Approved By | Expires | Status |
|--------|-----------|--------|-------------|---------|--------|
| P2 | test-password in legacy-auth.sh | Service retirement 2026-06-16 | @security-team | 2026-04-30 | Active |

---

## V. METRICS & DASHBOARDS

### A. Governance KPIs

| Metric | Target | Owner | Escalation |
|--------|--------|-------|------------|
| **Secrets leaked per month** | 0 | Security | >0 = P0 incident |
| **IaC violations per PR** | 0% | DevOps | >10% = project gate |
| **Script header compliance** | 100% | DevOps | Blocks merge if <95% |
| **Duplication ratio** | <5% | Architecture | Fails CI if >5% |
| **Config variants** | <5 total | Architecture | Blocks merge if >5 |
| **Waiver rate** | <2% of PRs | QA | Review if >2% |

---

## VI. POLICY APPROVAL & ROLLOUT

### A. Implementation Phases

**Phase 1 (Week 1)**: Warnings only (advisory)
- CI runs all checks but logs warnings instead of blocking
- Team becomes familiar with standards

**Phase 2 (Week 2)**: Soft enforcement (blocks with waiver path)
- CI blocks merge for policy violations
- Waivers allow temporary exceptions with approval

**Phase 3 (Week 3+)**: Hard enforcement (no exceptions)
- All waivers expired (unless explicitly extended)
- Zero tolerance for violations

---

## VII. REVISION HISTORY

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-04-16 | Initial framework (Policies P1-P4, T1-T3, W1-W2, C1-C2, D1-D2) | DevOps |

---

**Document Status**: DRAFT  
**Last Updated**: 2026-04-16  
**Next Review**: 2026-04-23
