# Governance Violations & Fixes
## Common Issues & How to Resolve Them

**Status**: Training Material for April 21, 2026
**Purpose**: Help developers understand violations and fix them quickly
**Soft Launch**: April 21-25 (CI feedback, PRs not blocked)
**Hard Enforcement**: April 28 (failed checks block merge)

---

## TIER 1: Hard Stop Violations (CI/CD enforced)

### Violation 1.1: Phase-Numbered Terraform Files

**Error Message**:
```
❌ CI CHECK FAILED: phase-numbered-terraform-files
   phase-13-iac.tf, phase-14-iac.tf found in PR
   These files create confusion about active configuration
```

**Why It Fails**:
- Multiple terraform files with `phase-NN-` prefix cause confusion about which is active
- Old phase files get left behind, creating dead code accumulation
- Single source of truth must be in `terraform/main.tf`, `terraform/locals.tf`

**How to Fix**:

❌ **Wrong**:
```bash
# Don't create new phase files
git add terraform/phase-26-rate-limiting.tf
git add terraform/phase-27-mobile.tf
```

✅ **Correct**:
```bash
# Update existing terraform files
git add terraform/main.tf terraform/locals.tf

# If you need to document a phase, use docs/
git add docs/phases/phase-26-rate-limiting/README.md
```

**Checklist**:
- [ ] No `phase-*.tf` files in terraform/ directory
- [ ] All IaC changes in `terraform/main.tf` or `terraform/locals.tf`
- [ ] Phase documentation in `docs/phases/{phase-name}/` instead
- [ ] `git status` shows only main.tf and locals.tf changed (no phase files)

---

### Violation 1.2: Multiple Docker Compose Files

**Error Message**:
```
❌ CI CHECK FAILED: single-docker-compose-source
   Found 8 docker-compose files:
   - docker-compose.yml (active)
   - docker-compose-phase-15.yml (deprecated)
   - docker-compose-phase-16.yml (deprecated)
   ...
```

**Why It Fails**:
- Multiple compose files creates uncertainty about which is active
- Old files don't get cleaned up, accumulate over time
- Config drifts when some services are updated in one file but not others

**How to Fix**:

❌ **Wrong**:
```bash
# Don't create new compose files for each phase
git add docker-compose-phase-26.yml
```

✅ **Correct**:
```bash
# Generate from terraform (ONE source of truth)
cd terraform/
terraform plan

# This regenerates docker-compose.yml automatically
# Commit only the result:
git add docker-compose.yml
git commit -m "chore: Update docker-compose from terraform"
```

**Cleanup Old Files**:
```bash
# Remove all phase-specific compose files
git rm docker-compose-phase-*.yml
git rm docker-compose.*.yml
git commit -m "chore: Remove obsolete docker-compose files (use terraform as source)"
```

**Checklist**:
- [ ] Only `docker-compose.yml` in root (no `docker-compose-*.yml`)
- [ ] File generated from terraform (not hand-edited)
- [ ] `git log` shows terraform changes, not compose changes
- [ ] OLD compose files deleted from Git history

---

### Violation 1.3: Unquoted Docker Image Tags

**Error Message**:
```
❌ CI CHECK FAILED: quoted-docker-image-tags
   docker-compose.yml: line 24
   image: nginx:latest ← Tag 'latest' is mutable
```

**Why It Fails**:
- `latest` tag changes without version bump (security risk)
- Containers restart with unpredictable versions
- Rollback/troubleshooting becomes impossible

**How to Fix**:

❌ **Wrong**:
```yaml
services:
  caddy:
    image: caddy:latest  # ← Mutable, unpredictable
  code-server:
    image: codercom/code-server  # ← No tag, implies 'latest'
  postgres:
    image: postgres:15  # ← OK, specific version
```

✅ **Correct**:
```yaml
services:
  caddy:
    image: "caddy:2.7.6"  # ← Quoted, pinned version
  code-server:
    image: "codercom/code-server:4.19.1"  # ← Quoted, explicit version
  postgres:
    image: "postgres:15.2"  # ← Quoted, patch version
```

**Checklist**:
- [ ] All image tags are pinned (no `latest`, no untagged images)
- [ ] All image tags are quoted: `image: "name:version"`
- [ ] Versions are specific: `15.2` not `15`, `2.7.6` not `2.7`
- [ ] `docker-compose.yml` validates without errors

---

### Violation 1.4: Missing Container Health Checks

**Error Message**:
```
❌ CI CHECK FAILED: container-health-checks
   docker-compose.yml: services without healthcheck
   - code-server: no healthcheck defined
   - caddy: no healthcheck defined
```

**Why It Fails**:
- Docker Compose can't detect hung or crashed services
- Failed services stay "running" until manually restarted
- Automated recovery and alerting impossible

**How to Fix**:

❌ **Wrong**:
```yaml
services:
  code-server:
    image: "codercom/code-server:4.19.1"
    # ← No healthcheck, Docker doesn't know if it's healthy
```

✅ **Correct**:
```yaml
services:
  code-server:
    image: "codercom/code-server:4.19.1"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

**Health Check Templates**:

**HTTP Services** (code-server, Grafana, API):
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:XXXX"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**Database Services** (PostgreSQL, Redis):
```yaml
healthcheck:
  test: ["CMD", "pg_isready", "-U", "postgres"]  # PostgreSQL
  # OR
  test: ["CMD", "redis-cli", "ping"]  # Redis
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

**Custom Services**:
```yaml
healthcheck:
  test: ["CMD-SHELL", "your-custom-health-check-script"]
  interval: 30s
  timeout: 10s
  retries: 3
```

**Checklist**:
- [ ] Every service has a `healthcheck` block
- [ ] Health check command verifies the service is actually working
- [ ] Interval is 30s or less
- [ ] Timeout is 10s or less
- [ ] Retries >= 3

---

## TIER 2: Style & Best Practices (Warnings, feedback only)

### Violation 2.1: Uncommitted Infrastructure Changes

**Warning Message**:
```
⚠️ CI CHECK WARNING: infrastructure-code-style
   Caddyfile, Dockerfile modified but not tracked
   docker-compose.yml generated locally but not committed
```

**Why It Matters**:
- Local changes don't get backed up to Git
- Teammates can't see infrastructure state
- Drift from source control makes debugging harder

**How to Fix**:

```bash
# Check what's uncommitted
git status

# Stage infrastructure files
git add Caddyfile docker-compose.yml terraform/

# Commit with descriptive message
git commit -m "feat: Update infrastructure for Phase 26 rate limiting"

# Push to your feature branch
git push origin feature/phase-26-rate-limiting
```

---

### Violation 2.2: Missing Commit Message Context

**Warning Message**:
```
⚠️ CI CHECK WARNING: commit-message-style
   Commit: "fix stuff"
   Missing: Feature scope, context, links to issues
```

**Why It Matters**:
- Future developers need to understand why changes were made
- Troubleshooting requires viewing Git blame comments
- Automatic changelog generation requires structured messages

**How to Fix**:

❌ **Poor Commit Messages**:
```
fix stuff
update docker compose
phase 26 work
final changes
```

✅ **Good Commit Messages** (Conventional Commits):
```
feat(phase-26-rate-limiting): Implement API rate limiting with 3-tier model

- Free tier: 60 req/min, 10k req/day
- Pro tier: 600 req/min, 100k req/day
- Enterprise: unlimited with custom limits
- Deployed to staging April 17, production April 20

Fixes #275
Relates-To: #264, #269
```

**Commit Message Template**:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`
**Scope**: `phase-26-rate-limiting`, `observability`, `governance`, etc.
**Subject**: Imperative mood, lowercase, no period, <50 chars

---

## Test Your Changes Locally

### Before Committing:

```bash
# 1. Validate docker-compose.yml
docker-compose config > /dev/null && echo "✅ Valid" || echo "❌ Invalid"

# 2. Check for phase-numbered files (HARD STOP)
git status | grep "phase-[0-9]" && echo "❌ Phase files found!" || echo "✅ No phase files"

# 3. Lint Caddyfile
docker run --rm -v $(pwd):/workspace caddy caddy validate --config /workspace/Caddyfile

# 4. Validate terraform
cd terraform/
terraform validate
terraform fmt -check

# 5. Run pre-commit hooks (if configured)
pre-commit run --all-files
```

### Before Pushing:

```bash
# Check your commits
git log --oneline origin/main..HEAD

# Verify nothing is left uncommitted
git status

# Final validation
docker-compose config
```

---

## Emergency: How to Roll Back a Violation

If you accidentally committed a violation, don't panic:

```bash
# View your commits
git log --oneline -5

# Option 1: Amend the last commit (if not pushed yet)
git reset HEAD~1
# Fix the files, then recommit
git add .
git commit -m "feat: Fix governance violations"

# Option 2: Create a fix commit (if already pushed)
# Fix the issue, then:
git add .
git commit -m "fix: Resolve governance violation from commit abcd123"
git push origin feature-branch

# Option 3: Revert entirely (if merged)
git revert commit-sha -m "Revert governance violation"
git push
```

---

## Questions During Training?

| Issue | Response |
|-------|----------|
| "What if I need to break a rule temporarily?" | Open an issue, tag @infrastructure, explain why. We'll create an exception process. |
| "How do I clean up old files without breaking history?" | Use `git rm` + commit. Or email infrastructure team for batch cleanup. |
| "Can I have multiple terraform files?" | YES, as modules in `terraform/modules/`. NO for phase-numbered files. |
| "Why so strict about image tags?" | Security: Mutable tags hide updates. One restart could pull a week-old image. |

---

## After Training (April 21-28)

**Week 1: Soft Launch (April 21-25)**
- CI checks run and show violations in PR comments
- Violations DO NOT block merge (feedback only)
- Fix violations at your pace
- Provide feedback: Use reactions + comments on GitHub

**Week 2: Hard Enforcement (April 28+)**
- Failed CI checks BLOCK PR merge
- No exceptions unless approved by tech lead
- Status checks required to pass before merge

---

**Questions?** Reply to GitHub Issue #274 or comment on your PR
**Need help?** Tag @infrastructure-team in PR comments

---

*Last Updated: April 14, 2026*
*Applies to: All PRs to main branch after April 21*
