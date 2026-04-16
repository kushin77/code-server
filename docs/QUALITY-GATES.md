# QUALITY GATES POLICY #380 — Production-First Mandate

**Status**: ACTIVE — All PRs required to pass  
**Effective**: April 22, 2026  
**Owner**: Security + DevOps  

---

## MANDATORY QUALITY GATES

Every commit to **main** and **phase-7-deployment** branches must pass ALL gates:

### ✅ 1. SHELL SCRIPT VALIDATION (shellcheck)

**Purpose**: Prevent bash syntax errors, unsafe patterns, portability issues

**Tool**: `shellcheck` (v0.8.0+)  
**Local**: Run `./scripts/validate-quality.sh` before commit  
**CI**: `.github/workflows/quality-gates-380.yml`

**Common Violations & Fixes**:

```bash
# ❌ WRONG: Missing quotes
for file in $(ls); do
  rm $file
done

# ✅ CORRECT: Proper quoting + while loop
while IFS= read -r file; do
  rm "$file"
done < <(find . -type f)
```

**Disabled Rules** (if needed):
```bash
shellcheck -x --exclude=SC1091,SC2086 script.sh
```

### ✅ 2. YAML VALIDATION (yamllint)

**Purpose**: Enforce consistent YAML formatting, prevent parse errors

**Tool**: `yamllint` (v1.28.0+)  
**Config**: Line length 200, indentation 2 spaces  
**Local**: Run `./scripts/validate-quality.sh` before commit  
**CI**: `.github/workflows/quality-gates-380.yml`

**Common Violations**:

```yaml
# ❌ WRONG: Inconsistent indentation, line too long
services:
  postgres:
    environment:
      POSTGRES_PASSWORD: very-long-password-that-exceeds-the-200-character-limit-by-a-large-margin-and-should-be-broken-into-multiple-lines
    ports:
      - "5432:5432"

# ✅ CORRECT: Consistent indentation, reasonable line length
services:
  postgres:
    environment:
      POSTGRES_PASSWORD: >-
        very-long-password-that-exceeds-200-chars-and-is-properly
        broken-into-multiple-lines
    ports:
      - "5432:5432"
```

### ✅ 3. DOCKERFILE VALIDATION (hadolint)

**Purpose**: Enforce Docker best practices, security hardening

**Tool**: `hadolint` (v2.12.0+)  
**Local**: Run `./scripts/validate-quality.sh` before commit  
**CI**: `.github/workflows/quality-gates-380.yml`

**Common Violations**:

```dockerfile
# ❌ WRONG: Multiple FROM statements without AS, no health check
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y curl
FROM ubuntu:20.04
RUN apt-get install -y nginx

# ✅ CORRECT: Proper multi-stage, health check, minimal base
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install --no-install-recommends -y curl && rm -rf /var/apt/lists/*

FROM ubuntu:22.04
COPY --from=builder /usr/bin/curl /usr/bin/curl
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
```

### ✅ 4. SECRET SCANNING

**Purpose**: Prevent hardcoded credentials, API keys, tokens

**Tool**: Pattern matching (regex) + manual review  
**Patterns Checked**:
- `password = ` (case-insensitive)  
- `api_key = `, `apikey = `  
- `secret = `, `token = `  
- `private_key = `  
- AWS secret patterns, GitHub tokens, etc.

**Whitelist Rules**:
- `PLACEHOLDER`, `REDACTED`, `changeme`, `example` are allowed  
- Use for test fixtures and documentation only  

**Local Validation**:
```bash
# Check current changes
git diff --cached | grep -iE 'password|secret|token|api.?key' | grep -v PLACEHOLDER

# Check all files
./scripts/validate-quality.sh
```

**Common Issues**:

```bash
# ❌ WRONG: Hardcoded secret
export DATABASE_PASSWORD="super-secret-password-123"

# ✅ CORRECT: Use environment variable
export DATABASE_PASSWORD="${DATABASE_PASSWORD:-}"  # Load from .env or Vault

# ✅ CORRECT: Reference placeholder in code
export DATABASE_PASSWORD="PLACEHOLDER_REPLACE_WITH_VAULT_SECRET"
```

### ✅ 5. CODE DUPLICATION DETECTION (jscpd)

**Purpose**: Identify copy-paste code, encourage DRY principle

**Tool**: `jscpd` (v3.5.0+)  
**Threshold**: Max 10% duplicates allowed  
**Exclusions**: Archived, vendored, config directories  
**Local**: Run `./scripts/validate-quality.sh` before commit  
**CI**: `.github/workflows/quality-gates-380.yml`

**Rules**:
- If duplication >10%, **MUST** refactor before merge  
- Use functions, templates, or configuration to eliminate duplication  
- Acceptable exceptions (require code review approval):
  - Test fixtures (allowed up to 30% duplication)  
  - Generated code (from templates or tools)  

### ✅ 6. TERRAFORM VALIDATION

**Purpose**: Ensure IaC syntax correctness, type checking, output validation

**Tool**: `terraform validate`, `terraform fmt`  
**Local**: Run `./scripts/validate-quality.sh` before commit  
**CI**: `.github/workflows/quality-gates-380.yml`

**Requirements**:
- All `.tf` files MUST pass `terraform validate`  
- Format MUST match `terraform fmt` output (auto-format via pre-commit)  
- Variables MUST have descriptions and type constraints  
- Outputs MUST be documented  

**Pre-Commit Setup**:
```bash
cd terraform
terraform fmt -recursive .
terraform validate
```

### ✅ 7. DEPENDENCY AUDIT

**Purpose**: Detect vulnerabilities in npm/pip packages

**Tool**: `npm audit`, `pip safety`  
**Threshold**: No HIGH or CRITICAL vulnerabilities allowed  
**MODERATE**: Allowed if documented and remediation planned  
**Local**: Run `./scripts/validate-quality.sh` before commit  
**CI**: Runs automatically on PRs

**Remediation**:
```bash
# npm
npm audit fix
npm audit fix --force (use with caution)

# pip
pip install --upgrade package-name
safety check --scan
```

---

## PR REQUIREMENTS (In Addition to Quality Gates)

Every PR MUST include:

1. **Clear Title & Description**
   - What problem does this solve?  
   - How does it solve it?  
   - What's the impact?  

2. **Issue Link**
   - Link to GitHub issue (`Closes #123`)  
   - Or reference issue in description  

3. **Testing Evidence**
   - Unit tests passing  
   - Integration tests (if applicable)  
   - Load test results (if performance-sensitive)  

4. **Security Review** (for P0/P1 work)
   - Secrets scanning passed  
   - Permissions minimal (RBAC)  
   - No defaults enabled  

5. **Documentation**
   - README/docs updated  
   - API changes documented  
   - Breaking changes flagged  

6. **Acceptance Criteria**
   - All criteria from linked issue met  
   - Reviewer sign-off required  

---

## COMMON VIOLATIONS & HOW TO FIX

### Shell Scripts

```bash
# ❌ Unquoted variables
for file in $files; do

# ✅ Fixed
for file in $files; do  # Note: Use "${files[@]}" for arrays

# ❌ Unset variable check
rm "$file"

# ✅ Fixed
[[ -n "$file" ]] && rm "$file"

# ❌ Command substitution without quotes
rm $(find . -name "*.tmp")

# ✅ Fixed
while IFS= read -r file; do
  rm "$file"
done < <(find . -name "*.tmp")
```

### Terraform

```hcl
# ❌ Missing variable type
variable "instance_count" {
  default = 3
}

# ✅ Fixed
variable "instance_count" {
  type        = number
  default     = 3
  description = "Number of instances to create"
  validation {
    condition     = var.instance_count > 0 && var.instance_count < 100
    error_message = "Instance count must be 1-99."
  }
}
```

### Code Duplication

```python
# ❌ Copy-pasted functions
def validate_email(email):
  if "@" not in email:
    raise ValueError("Invalid email")
  return email.lower()

def validate_username(username):
  if "@" in username:
    raise ValueError("Invalid username")
  return username.lower()

# ✅ Refactored
def validate_field(value, forbidden_chars=None):
  if forbidden_chars and any(c in value for c in forbidden_chars):
    raise ValueError(f"Invalid value: contains {forbidden_chars}")
  return value.lower()

email = validate_field(email, forbidden_chars=[])
username = validate_field(username, forbidden_chars=["@"])
```

---

## WORKFLOW: LOCAL VALIDATION

**Before every commit**:

```bash
# 1. Run quality gates locally
./scripts/validate-quality.sh

# 2. Fix any violations
# ... edit files ...

# 3. Terraform auto-format
cd terraform && terraform fmt -recursive . && cd ..

# 4. Re-run validation
./scripts/validate-quality.sh

# 5. Commit when ALL gates pass
git add .
git commit -m "feat: description of changes"
```

---

## WORKFLOW: CI/CD GATES

**Automated on every PR**:

1. GitHub Actions runs `.github/workflows/quality-gates-380.yml`  
2. All checks execute in parallel (5-10 minutes)  
3. Results posted to PR as:
   - Status check (must pass before merge)  
   - Comment with detailed violations  
   - Suggested fixes  

4. If any check fails:
   - `Merge` button disabled  
   - Author must fix + push  
   - CI re-runs automatically  

5. When all pass:
   - `Merge` button enabled  
   - Reviewers can approve  
   - Maintainer merges  

---

## ENFORCEMENT & EXCEPTIONS

### Merge Blocking

These violations **BLOCK MERGE** — no exceptions:

❌ Shell script errors  
❌ Hardcoded secrets  
❌ Terraform validation failures  
❌ HIGH/CRITICAL vulnerabilities  
❌ Code duplication >10% (unless approved)  

### Warnings (Allowed with Justification)

⚠️ YAML/Dockerfile formatting (auto-fixable)  
⚠️ MODERATE CVEs (if remediation planned)  
⚠️ Code duplication 8-10% (requires comment)  

### Exceptions Process

For unavoidable violations:

1. Comment in PR with: **Why** this exception is needed  
2. Proposed **remediation timeline**  
3. Request approval from **lead reviewer**  
4. Add **GitHub label** `exception-granted-380`  
5. Link to **tracking issue** for remediation  

**Example**:
```
@maintainers: Requesting exception for #380 code duplication

This PR adds 2 new deployment scripts with ~5% duplication.
Duplication will be eliminated in #XXX (planned for next sprint).

Approval: [maintainer sign-off required]
```

---

## POLICIES & COMPLIANCE

### IaC Immutability
✅ All configuration in git  
✅ No manual production changes  
✅ Every change has audit trail  

### Security by Default
✅ No hardcoded secrets ever  
✅ Minimal permissions enforced  
✅ Audit logging mandatory  

### Production Readiness
✅ Backwards-compatible changes only  
✅ SLO targets documented  
✅ Rollback procedure <60 seconds  

---

## SUPPORT & QUESTIONS

**Issues with quality gates?**

1. Run locally: `./scripts/validate-quality.sh`  
2. Check documentation: `docs/QUALITY-GATES.md`  
3. Review PR comments for specific violations  
4. Ask in #dev-help Slack channel  
5. Open issue with `quality-gates` label  

**Report false positives**:
- Create issue with `quality-gates` + `false-positive` labels  
- Include reproduction steps  
- Example file that should pass  

---

## ROADMAP & FUTURE ENHANCEMENTS

| Phase | Item | Timeline |
|-------|------|----------|
| **1** | Shell + YAML + Docker gates | ✅ Week 1 (Apr 22) |
| **2** | Secret scanning + duplication | ✅ Week 1 (Apr 22) |
| **3** | Terraform + dependencies | ✅ Week 1 (Apr 22) |
| **4** | SAST (SonarQube) integration | Week 2-3 (May 1) |
| **5** | Performance gates (load tests) | Week 4-5 (May 13) |
| **6** | Cost gates (cloud spending) | Q2 2026 |
| **7** | Compliance gates (CIS, PCI-DSS) | Q3 2026 |

---

## VERSION HISTORY

| Version | Date | Changes |
|---------|------|---------|
| **1.0** | Apr 22, 2026 | Initial release — gates for shell, YAML, Docker, secrets, duplication, Terraform, dependencies |

---

**Policy Owner**: DevOps Lead  
**Last Updated**: April 22, 2026  
**Next Review**: May 5, 2026 (end of Week 1)  
**Status**: ACTIVE — All developers required to comply
