# Governance & Guardrails: kushin77/code-server-enterprise

**Effective**: April 14, 2026  
**Scope**: All contributions, all developers, all phases  
**Status**: **Mandatory** — Non-compliance blocks PRs

---

## Mission: Zero Accumulation of Dead Code

**Goal**: Prevent 50+ dead files from accumulating again  
**Method**: Guardrails, governance, and automated checks  
**Enforcement**: CI/CD, code review, monthly audits  

---

## TIER 1: HARD STOPS (CI/CD Enforced)

### Rule 1.1: No Phase-Numbered Terraform Files

❌ **FORBIDDEN**:
```
phase-13-iac.tf
phase-14-iac.tf
phase-21-iac.tf
```

✅ **REQUIRED**:
```
main.tf              # Current active configuration
variables.tf         # Variable definitions
terraform/modules/   # Reusable modules
```

**Why**: Phase files created confusion about which version was active, leaving 8+ obsolete files.

**Enforcement**:
- Pre-commit hook: Reject any `phase-*.tf` in PR
- CI check: Fail if filename matches `phase-[0-9]+-.*\.tf`
- Code review: Mandatory block if violated

**Exception Process**:
- If you MUST create phase documentation, place in `docs/phases-archived/{phaseN}/`
- Never in root or terraform/ for IaC

---

### Rule 1.2: Single Source of Truth for Docker Compose

❌ **FORBIDDEN**:
```
docker-compose.{production,base,staging,dev}.yml
docker-compose-phase-*.yml
```

✅ **REQUIRED**:
```
docker-compose.yml      # Generated from .tpl (read-only)
docker-compose.tpl      # Terraform template (edit this)
```

**Why**: 11 docker-compose variants left developers confused. Only one should ever be deployed.

**Enforcement**:
- Pre-commit hook: Reject any `docker-compose-*.yml` except `.tpl`
- CI check: Fail if new docker-compose.{suffix}.yml detected
- Terraform validates: `terraform plan` must reference docker-compose.tpl
- Code review: Automatic block

**Exception Process**:
- Need variant for testing? Use `docker-compose.test.yml` in `tests/` directory only
- Must delete after merge (not committed to main)

---

### Rule 1.3: No Orphaned Configuration Files

❌ **FORBIDDEN** (Active but not used):
```
Caddyfile.production    # Not imported or used
alertmanager-prod.yml   # Variant that conflicts
.env.oauth2-proxy       # Service no longer exists
```

✅ **REQUIRED**:
```
Caddyfile                   # Active
Caddyfile.base              # Imported by Caddyfile
alertmanager.yml            # Active
.env.example                # Template (check into git)
```

**Enforcement**:
- Code review: Mandatory block if file clearly unused
- Monthly audit: Identify orphaned files (see Tier 2.2)
- Issue filing: Create cleanup issue if found
- Cleanup: Remove orphans within 30 days of identification

---

### Rule 1.4: No Deployment Scripts with Hardcoded Wrong Hosts

❌ **FORBIDDEN**:
```
deploy-iac.ps1  # Targets 192.168.168.32 (old)
deploy.sh       # Hardcoded prod IP in script
```

✅ **REQUIRED**:
```
scripts/deploy/deploy.sh         # Parameterized
terraform/                       # Infrastructure as Code
environment variables            # HOST, REGION, etc.
```

**Why**: deploy-iac.ps1 and deploy-iac.sh targeted wrong production host, would cause deployment failure.

**Enforcement**:
- Pre-commit hook: Reject hardcoded IPs (pattern: `192\.168\..*`)
- Code review: Block if host target mismatch detected
- Test: `-target-host` flag must work for all deploy scripts

**Exception Process**:
- Docker container IPs? Use `localhost` or DNS names: `caddy`, `ollama`, `code-server`
- External IPs? Use environment variables: `$PROD_HOST`, `$STAGING_HOST`

---

## TIER 2: GOVERNANCE (Code Review + Process)

### Rule 2.1: All Changes Must Link to GitHub Issues

✅ **EVERY PR MUST HAVE**:
```
# In PR description:
Fixes #123
Fixes #456

# Or:
Related to #789
Implements requirements from #234
```

❌ **NOT ACCEPTABLE**:
```
Random cleanup
Bug fix
Updates

(Without issue number)
```

**Why**: Many dead files accumulated without tracking why they existed. Issues provide context.

**Process**:
1. Create issue first (includes motivation, acceptance criteria)
2. Create PR linked to issue (see issue in PR description)
3. Code review references issue context
4. On merge, GitHub auto-closes issue with commit message

**Template for Issues**:
```markdown
# Title: [Feature/Fix/Cleanup]: Clear description

## Motivation
Why does this exist? What problem does it solve?

## Acceptance Criteria
- [ ] Specific, testable objectives
- [ ] No ambiguity about completion

## Affected Files
- file1.tf
- file2.sh

## Dependencies
- Issue #123 (must complete first)
- No external service calls

## Follow-up
- Other issues created as result
- Cleanup tasks identified
```

**Enforcement**:
- GitHub branch protection: Require issue reference in PR title or description
- CI check: Fail if `Fixes #` or `Related to #` not found
- Code review: Reject if no issue context

---

### Rule 2.2: Monthly Dead Code Audit

**Frequency**: First Monday of each month  
**Owner**: Tech Lead / DevOps  
**Duration**: ~1 hour

**Checklist**:
- [ ] Scan for files not referenced in Terraform
- [ ] Scan for files not used in CI/CD
- [ ] Scan for `.bak`, `.old`, `.deprecated` suffixes
- [ ] Scan git commit history: any file untouched for 6+ months?
- [ ] Check `archived/` for files ready to delete permanently
- [ ] Review in team Slack/meeting
- [ ] Create cleanup issues for consensus items

**Report Template** (post to #engineering):
```
**Monthly Cleanup Audit - [Month]**

Files Identified for Archival:
- file1.tf (last touched 8 months ago)
- file2.yml (never imported)

Files Ready for Permanent Deletion:
- archived/old-phase-files/* (archived 3+ months ago)

Action Items:
- [ ] Team reviewed and approved cleanup
- [ ] Issues created for disputed files
- [ ] Cleanup completed by [date]

Questions? See GitHub Issue #GH-XXX
```

**GitOps Integration** (Proposed):
```bash
# Automated scan script (runs monthly)
terraform validate      # Find unreferenced vars/modules
grep -r "import\|include" . | grep -v archived/  # Audit imports
find . -name "*.old" -o -name "*.bak" -o -name "*.deprecated"
```

---

### Rule 2.3: Code Review Standards for Infrastructure Code

**All `.tf` files require**:
- ✅ Clear variable documentation
- ✅ Resource tagging for cost tracking
- ✅ Lifecycle rules (prevent accidental deletion)
- ✅ Comments explaining "why" (not just "what")
- ✅ Dependency declarations explicit
- ✅ Version pinning for Docker images
- ✅ References to GitHub issue

**Anti-patterns to block**:
- ❌ Hardcoded values (use variables)
- ❌ Wildcard CIDR ranges (0.0.0.0/0 requires documentation)
- ❌ No error handling in scripts
- ❌ Silent failures (set -e, error handling)
- ❌ Unused variables or outputs

**Review Checklist**:
```
- [ ] Issue linked in PR description
- [ ] Variables clearly documented
- [ ] No hardcoded IPs/domains
- [ ] Docker image versions pinned
- [ ] Terraform plan output reviewed (zero surprises)
- [ ] Scripts have error handling
- [ ] No dead code paths
- [ ] Works in staging first
```

---

### Rule 2.4: Breaking Changes Require ADR (Architecture Decision Record)

If your change:
- ❌ Removes a service or port
- ❌ Changes deployment method
- ❌ Alters secret management
- ❌ Replaces a major component

**You MUST**:
1. Create `docs/adr/ADR-NNN-shortname.md`
2. Document: Context, Decision, Consequences, Alternatives
3. Link in PR description
4. Get tech lead approval before merge

**Example**:
```
docs/adr/ADR-015-replace-oauth2-proxy-with-caddy.md

# ADR-015: Replace oauth2-proxy with Caddy Reverse Proxy

## Context
oauth2-proxy adds complexity and overhead for our use case.

## Decision
Use Caddy's built-in reverse proxy instead.

## Consequences
- Removes oauth2-proxy service (saves resources)
- .env.oauth2-proxy no longer needed
- Simpler authentication flow

## Alternatives Considered
- Keep both (overhead)
- Use nginx (less flexible)
```

---

## TIER 3: AUTOMATION (CI/CD Checks)

### Check 3.1: Terraform Validation

```hcl
# .github/workflows/terraform.yml

terraform validate     # Syntax check
terraform fmt -check  # Formatting (consistent style)
tflint                # Linting (best practices)
```

Rejects:
- ❌ Syntax errors
- ❌ Missing required variables
- ❌ Inconsistent formatting
- ❌ Resources without tagging

---

### Check 3.2: Dead Code Detection

```bash
# Pre-merge CI check

# Find unreferenced files
find . -name "*.tf" | while read tf; do
  if ! grep -r "$(basename $tf .tf)" . | grep -v "$tf"; then
    echo "UNREFERENCED: $tf"
    exit 1
  fi
done

# Find orphaned env files
ls -la .env.* | grep -v ".env.example" && exit 1

# Find phase-numbered files
ls -la phase-*.{tf,sh,py} 2>/dev/null && exit 1
```

---

### Check 3.3: Hardcoded IP/Domain Detection

```bash
# Grep for dangerous patterns
grep -r "192\.168\." . --exclude-dir=.git --exclude="*.md" && exit 1
grep -r "10\.\d+\.\d+\.\d+" . --exclude-dir=.git --exclude="*.md" && exit 1
grep -r "production-ip\|prod-host\|staging-server" . && exit 1
```

**Exceptions** (documented):
- Docker container IPs (localhost, service DNS names OK)
- Example documentation (.md files)
- Environment variable templates (.env.example)

---

### Check 3.4: File Organization Check

```bash
# Verify no root-level clutter
# Files should be in subdirs: scripts/, config/, deployment/, terraform/, docs/

BAD_FILES=$(find . -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" -o -name "Dockerfile*" \) | wc -l)
if [ $BAD_FILES -gt 10 ]; then
  echo "ERROR: Too many scripts/dockerfiles at root level"
  echo "Move to scripts/, deployment/, or config/ directories"
  exit 1
fi
```

---

### Check 3.5: PR Title Validation

```python
# GitHub Actions: Check PR title for issue reference

import os
import sys

pr_title = os.getenv("PR_TITLE", "")

if not any(pattern in pr_title for pattern in ["Fixes #", "Related to #", "Implements #"]):
    print("ERROR: PR title must reference GitHub issue")
    print("Good examples:")
    print("  - Fixes #123: Clear description")
    print("  - Implements requirements from #456")
    sys.exit(1)
```

---

## TIER 4: DOCUMENTATION (Standards)

### Rule 4.1: Every Terraform Module Must Have README

```
terraform/modules/code-server/
├── README.md          ← REQUIRED
├── main.tf
├── variables.tf
└── outputs.tf

# README.md must include:
- Module purpose
- Required variables
- Example usage
- Module outputs
- Dependencies
- Maintenance notes
```

---

### Rule 4.2: Architecture Decisions Are Documented

**Created ADR for**:
- ✅ Moving from phase-based to main.tf structure
- ✅ Replacing oauth2-proxy with Caddy
- ✅ Service additions/removals
- ✅ Breaking changes

**Location**: `docs/adr/ADR-NNN-*.md`

**Format**:
```markdown
# ADR-NNN: Short Title

## Status
Proposed / **Accepted** / Superseded by ADR-MMM

## Context
Why does this decision matter?

## Decision
What are we doing?

## Consequences
What changes as a result?

## Alternatives Considered
What else was evaluated?

## Follow-up
- Related ADRs: ADR-###
- Related Issues: #GH-XXX
```

---

### Rule 4.3: Deployment Documentation

**Every deployment method must have**:
- ✅ README with prerequisites
- ✅ Step-by-step instructions
- ✅ Rollback procedure
- ✅ Health check commands
- ✅ Expected output/logs

**Location**: `docs/deployments/{phase-name}/README.md`

---

## ENFORCEMENT LEVELS

### Level 1: Warn (Informational)
- Pre-commit hook messages
- Linting suggestions
- Low-severity code review comments

### Level 2: Block (Hard Stop)
- CI/CD failures: Merge button disabled
- Examples:
  - Phase-numbered terraform files
  - Hardcoded IPs in scripts
  - Missing issue reference
  - Terraform validation failure

### Level 3: Manual Review (Tech Lead)
- Non-obvious dead code
- Exceptions to rules
- Disputed cleanup items
- Examples:
  - Should we keep this file?
  - New phase files (if absolutely required)

### Level 4: Permanent Block
- Unsafe operations (delete production data)
- Security violations
- Compliance failures

---

## EXCEPTIONS: When & How to Request

Some rules need flexibility. Here's the process:

### Exception Request Template
```markdown
## Exception Request

**Rule**: 1.2 - Single source of truth for Docker Compose

**Why**: Our testing framework needs a separate compose file

**Duration**: 3 months (expires 2026-07-14)

**Scope**: 
- Only in `tests/docker-compose.test.yml`
- Never deployed to production
- Auto-deleted after test run

**Approval**: [Tech Lead sign-off]

**Follow-up**: [Plan to eliminate need for exception]
```

### Approval Process
1. File exception request as GitHub issue
2. Tech lead reviews and approval
3. Add to `.gitignore` or `pre-commit.yaml` whitelist
4. Set expiration date (auto-revisit)
5. Document in `EXCEPTIONS.md`

---

## ONBOARDING: New Developers

Every new developer must read:
1. ✅ This file (GOVERNANCE-AND-GUARDRAILS.md)
2. ✅ [CODE-REVIEW-COMPREHENSIVE.md](CODE-REVIEW-COMPREHENSIVE.md) — understand what happened
3. ✅ [CLEANUP-COMPLETION-REPORT.md](CLEANUP-COMPLETION-REPORT.md) — see completeness
4. ✅ [archived/README.md](archived/README.md) — know what's dead
5. ✅ Main README.md — how to get started

**Checklist for onboarding**:
- [ ] Can explain why phase-*.tf files are forbidden
- [ ] Can explain why there's only one docker-compose.yml
- [ ] Knows how to file GitHub issues properly
- [ ] Knows the monthly audit exists
- [ ] Knows how to request exceptions

---

## COMPLIANCE CHECKLIST

### For Every PR
- [ ] Issue reference in PR title/description
- [ ] No phase-numbered files added
- [ ] No docker-compose variants added
- [ ] No hardcoded IPs/domains (except comments)
- [ ] All scripts tested locally
- [ ] Terraform `plan` output reviewed
- [ ] No dead code paths

### For Every Release
- [ ] Automated checks all pass
- [ ] Manual code review completed
- [ ] Staging deployment successful
- [ ] Rollback plan documented
- [ ] GitHub issue updated with status

### For Tech Lead (Monthly)
- [ ] Dead code audit completed
- [ ] Cleanup issues filed for consensus items
- [ ] No exceptions past their expiration
- [ ] Team has no questions

---

## REFERENCES

**Related Documents**:
- [CODE-REVIEW-COMPREHENSIVE.md](CODE-REVIEW-COMPREHENSIVE.md) — What problems this solves
- [CLEANUP-COMPLETION-REPORT.md](CLEANUP-COMPLETION-REPORT.md) — Progress to date
- [archived/README.md](archived/README.md) — What's archived and why
- [CONTRIBUTING.md](CONTRIBUTING.md) — General contribution guidelines

**GitHub Issues**:
- [#GH-XXX - Code Cleanup & Governance](https://github.com/kushin77/code-server-enterprise/issues/GH-XXX)
- [#GH-YYY - Merge phase-21-observability.tf](https://github.com/kushin77/code-server-enterprise/issues/GH-YYY)

**Tools & Automation**:
- Pre-commit hooks: `.pre-commit-config.yaml` (install via `setup-dev.sh`)
- Terraform: `main.tf`, `variables.tf`
- CI/CD: `.github/workflows/*.yml`

---

## CHANGE HISTORY

| Date | Change | Author |
|------|--------|--------|
| 2026-04-14 | Initial governance framework | Cleanup Project |
| TBD | Add automated ADR linting | Tech Lead |
| TBD | Add SBOM/dependency scanning | DevOps |

---

## Questions & Escalation

**Q**: My feature requires a phase-numbered terraform file  
**A**: Open an exception request. Likely you don't need a phase file — use main.tf with feature flags or variables.

**Q**: I need a docker-compose variant for testing  
**A**: Use `tests/docker-compose.test.yml` (not in root). Delete after test.

**Q**: The monthly audit found my unused file  
**A**: Either justify keeping it (opens GitHub issue discussion) or archive it.

**Q**: Can I make an exception to these rules?  
**A**: Yes, file an exception request with tech lead approval and expiration date.

---

**Status**: ✅ **EFFECTIVE IMMEDIATELY**  
**Enforcement**: Starting with next PR after April 14, 2026  
**Review Cycle**: Quarterly (April, July, October, January)  
**Next Review**: July 14, 2026

---

*These guardrails exist to maintain code quality, prevent waste, and protect the long-term sustainability of the kushin77/code-server-enterprise project. Questions? Reach out to the tech lead or open an issue.*
