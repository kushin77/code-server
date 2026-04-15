# Governance Framework Implementation Guide

**Status**: ACTIVE / PRODUCTION  
**Version**: 1.0  
**Last Updated**: April 15, 2026  

---

## Quick Start

### For Developers

1. **Install pre-commit hooks locally** (one-time setup):
   ```bash
   pip install pre-commit
   pre-commit install
   ```

2. **Use the shell script template** for any new scripts:
   ```bash
   cp scripts/_templates/SHELL-SCRIPT-TEMPLATE.sh scripts/my-new-script.sh
   # Edit the header and implementation
   ```

3. **Before committing, use the code review checklist**:
   - Read: [GOVERNANCE-CODE-REVIEW-CHECKLIST.md](../docs/GOVERNANCE-CODE-REVIEW-CHECKLIST.md)
   - Check: Shell scripts have `@file` headers
   - Check: No hardcoded IPs/ports/credentials
   - Check: Docker images use pinned versions (not `:latest`)

4. **Push your branch**:
   ```bash
   git push origin my-branch
   ```

5. **Wait for CI governance checks**:
   - GitHub will automatically run `.github/workflows/governance.yml`
   - You'll see a 🏗️ "Governance Framework" check on your PR
   - Fix any failures (red flags) before requesting review

### For Code Reviewers

1. **Read the governance checklist** before each review:
   - [GOVERNANCE-CODE-REVIEW-CHECKLIST.md](../docs/GOVERNANCE-CODE-REVIEW-CHECKLIST.md)

2. **Check for red flags** (block merge if present):
   - ❌ Hardcoded credentials
   - ❌ Docker images with `:latest`
   - ❌ Missing `set -euo pipefail` in shell scripts
   - ❌ Silent error handling (`|| true`)

3. **Watch for yellow flags** (discuss, don't auto-block):
   - ⚠️ Missing `@file` headers
   - ⚠️ YAMLLint warnings
   - ⚠️ Code duplication
   - ⚠️ Runbooks not updated

4. **Approve** when:
   - All governance standards met
   - Red flags resolved
   - Yellow flags discussed
   - Tests passing

---

## Directory Structure

```
.
├── .github/
│   └── workflows/
│       ├── governance.yml              # 🚦 Main CI enforcement (10 gates)
│       └── governance-report.yml       # 📊 Weekly report (scheduled Monday 8am UTC)
├── .pre-commit-config.yaml             # 🔍 Local pre-commit hooks
├── docs/
│   ├── CODE-GOVERNANCE-FRAMEWORK.md           # 📋 Full policy (read this first)
│   ├── GOVERNANCE-CODE-REVIEW-CHECKLIST.md    # ✅ Code review guide
│   └── GOVERNANCE-WAIVERS-AND-DEBT.md         # 🔓 Waivers & debt tracking
└── scripts/
    ├── governance/
    │   └── generate-governance-report.sh     # 📊 Report generator
    └── _templates/
        └── SHELL-SCRIPT-TEMPLATE.sh          # 📝 Script boilerplate
```

---

## How the Governance Framework Works

### 1. **Local Pre-Commit Checks** (Before You Push)

When you `git commit`, these checks run automatically:

```
✅ No hardcoded credentials (P0 blocker)
✅ No hardcoded IPs (P0 blocker for new scripts)
✅ Shell script headers (warning only)
✅ Docker images must not be :latest (P0 blocker for new Dockerfiles)
```

**What to do if pre-commit fails:**
```bash
# 1. Read the error message
# 2. Fix the issue in your code
# 3. Re-commit (pre-commit will check again)

# If you need to bypass (rare): --no-verify
# BUT: Your code will still fail in CI
git commit --no-verify  # ⚠️ Not recommended; CI will catch it
```

### 2. **CI Governance Workflow** (Pull Request Checks)

When you push a PR, `.github/workflows/governance.yml` runs 10 gates sequentially:

| Gate # | Check | Failure = | Pass = |
|--------|-------|-----------|--------|
| 1 | **Gitleaks** (secret scan) | ❌ BLOCK | ✅ Continue |
| 2 | **YAMLLint** (config format) | ❌ BLOCK | ✅ Continue |
| 3 | **ShellCheck** (script lint) | ❌ BLOCK | ✅ Continue |
| 4 | **Script headers** (@file tags) | ⚠️ Warn | ✅ Continue |
| 5 | **Hardcoded values** (IPs, ports) | ⚠️ Warn | ✅ Continue |
| 6 | **Parameterization** (docker-compose) | ⚠️ Warn | ✅ Continue |
| 7 | **Duplication** (jscpd < 5%) | ❌ BLOCK | ✅ Continue |
| 8 | **Docker images** (no :latest) | ❌ BLOCK | ✅ Continue |
| 9 | **Terraform fmt** (code formatting) | ❌ BLOCK | ✅ Continue |
| 10 | **Terraform validate** (syntax) | ❌ BLOCK | ✅ Continue |

**On your PR:**
- Red ❌ gates must be fixed before merge
- Yellow ⚠️ gates are informational (discuss with reviewer)

**What to do if CI fails:**
```bash
# 1. Check the failing gate in the PR checks section
# 2. Click "Details" to see the full error log
# 3. Fix the issue locally
# 4. Commit and push again (CI will re-run automatically)
```

### 3. **Code Review** (Human Gate)

Before approving, reviewer uses [GOVERNANCE-CODE-REVIEW-CHECKLIST.md](../docs/GOVERNANCE-CODE-REVIEW-CHECKLIST.md):

- Shell scripts: Headers, strict mode, error handling
- Docker: Pinned images, no secrets
- Configs: Parameterized, no hardcoded values
- Terraform: Version pinning, validation
- General: No duplication, clear error messages

### 4. **Weekly Governance Report** (Metrics & Trends)

Every Monday at 8 AM UTC, `.github/workflows/governance-report.yml` runs and generates:

- 📊 Governance metrics (violations, waivers, trends)
- 🎯 Priority actions (P0 = urgent, P1 = this sprint)
- 📋 Debt status (what needs to be fixed, by when)
- ✅ Enforcement report (which gates are operational)
- 📅 Next steps (what to focus on this week)

Report posted to:
- GitHub Actions artifacts (90-day retention)
- Open governance issues (as comments)

---

## Common Workflows

### Adding a New Shell Script

```bash
# 1. Create from template
cp scripts/_templates/SHELL-SCRIPT-TEMPLATE.sh scripts/my-task.sh

# 2. Edit the header (required)
#!/usr/bin/env bash
# @file: my-task.sh
# @module: operations/tasks
# @description: Does something important for production. Updates database, triggers alerts, etc.

# 3. Replace template implementation with your code
# 4. Make sure your code:
#    - Uses ${PROD_HOST}, ${REPLICA_HOST} (not hardcoded IPs)
#    - Uses ${SERVICE_PORT} (not hardcoded ports)
#    - Calls log_info(), log_error() (not echo)
#    - Has proper error handling (set -euo pipefail)

# 5. Test locally
bash scripts/my-task.sh

# 6. Commit and push
git add scripts/my-task.sh
git commit -m "feat: Add my-task script for production operations"
git push origin my-branch
```

### Updating Configuration

```bash
# 1. Edit config file (docker-compose.yml, Caddyfile, etc.)

# 2. Parameterize any values:
#    WRONG: port: 8080
#    RIGHT: port: ${CODE_SERVER_PORT:-8080}

#    WRONG: host: 192.168.168.31
#    RIGHT: host: ${PROD_HOST}

# 3. Test locally
yamllint -d default your-config.yml

# 4. Commit with parameterized values
git add your-config.yml
git commit -m "config: Update X with parameterized values"
```

### Requesting a Governance Waiver

If you need an exception to a standard:

```bash
# 1. Open GitHub issue with details:
Title: Governance Waiver Request - [Standard Name]
Body:
## Standard Violated
Shell script naming convention

## Why
Cannot migrate legacy script; operators still depend on old name

## Duration
90 days (until 2026-07-15)

## Risk
Continued operational ambiguity; duplicate implementations

## Owner
@devops-team

# 2. Get approval from @architecture-team + @security-team

# 3. Once approved, tracked in GOVERNANCE-WAIVERS-AND-DEBT.md
```

---

## Understanding the Framework

### Why These Standards?

| Standard | Why It Matters |
|----------|---------------|
| **No hardcoded IPs** | Makes scripts portable; one IP change doesn't require code edits |
| **Pinned Docker versions** | Reproducible builds; no surprise changes from image updates |
| **Script headers** | Auto-discovery of scripts; clear documentation |
| **No secrets** | Prevents credential leaks in git history |
| **Parameterized configs** | One config file for all environments |
| **Error handling** | Silent failures are dangerous; loud failures are catchable |
| **Structured logging** | Centralized log aggregation; better debugging |
| **Duplication detection** | Reduces maintenance burden; DRY principle |

### How Violations Are Fixed

| Violation | Who Fixes | When | SLA |
|-----------|-----------|------|-----|
| **Hardcoded secrets** | Developer | Before commit | Pre-commit blocks |
| **Missing headers** | Developer | Before review | Yellow flag |
| **Duplicate code** | Developer | During code review | Before merge |
| **Unparameterized config** | Developer | During code review | Before merge |
| **Governance debt** | Assigned team | Per remediation SLA | P1=2 weeks, P2=4 weeks |

---

## Troubleshooting

### Pre-Commit Hook Not Installing

```bash
# Issue: pre-commit install doesn't work
# Solution:
pip install --upgrade pre-commit
pre-commit install
pre-commit run --all-files  # Test it
```

### CI Check Fails But I Don't Understand Why

```bash
# 1. Click "Details" on the failing check in GitHub PR
# 2. Scroll down to find the error message
# 3. Common issues:
#    - ShellCheck: Use `shellcheck -S warning my-script.sh` locally first
#    - YAMLLint: Check indentation (spaces, not tabs)
#    - Gitleaks: Remove any hardcoded passwords/tokens
#    - jscpd: Extract repeated code to functions
```

### I Need to Fix Code After Commit

```bash
# 1. Make your fixes locally
# 2. Re-commit (you can amend):
git add .
git commit --amend --no-edit

# 3. Force push (for your own branch):
git push --force-with-lease origin my-branch

# 4. GitHub will automatically re-run CI checks
```

### Governance Check Keeps Failing

```bash
# Get help:
# 1. Check the latest error log in GitHub Actions
# 2. Ask in #eng-infrastructure Slack
# 3. Reference issue #380 (Governance Framework)
# 4. Include: your error message, affected files, reproduction steps
```

---

## Measuring Success

### Week 1 (Adoption)
- ✅ Engineers install pre-commit hooks
- ✅ First PRs run through governance CI
- ✅ Team reviews governance framework doc

### Month 1 (Enforcement)
- ✅ All new code meets governance standards
- ✅ Weekly reports showing metrics
- ✅ Governance debt tracked and prioritized

### Quarter 1 (Excellence)
- ✅ Governance violations < 5% of PRs
- ✅ Average time to fix violations < 2 days
- ✅ Team comfortable with standards
- ✅ Governance debt < 10% of sprint capacity

---

## Key Contacts

| Question | Contact |
|----------|---------|
| **Governance policy questions** | @architecture-team |
| **Code review checklist issues** | @devops-team |
| **Waiver requests** | File GitHub issue, tag @architecture-team |
| **Framework bugs/improvements** | GitHub issue #380 |
| **Questions in real-time** | #eng-infrastructure Slack |

---

## Links

- 📋 **Full Framework**: [CODE-GOVERNANCE-FRAMEWORK.md](../docs/CODE-GOVERNANCE-FRAMEWORK.md)
- ✅ **Code Review Guide**: [GOVERNANCE-CODE-REVIEW-CHECKLIST.md](../docs/GOVERNANCE-CODE-REVIEW-CHECKLIST.md)
- 🔓 **Waivers & Debt**: [GOVERNANCE-WAIVERS-AND-DEBT.md](../docs/GOVERNANCE-WAIVERS-AND-DEBT.md)
- 📝 **Script Template**: [SHELL-SCRIPT-TEMPLATE.sh](./scripts/_templates/SHELL-SCRIPT-TEMPLATE.sh)
- 🚦 **CI Enforcement**: [.github/workflows/governance.yml](.github/workflows/governance.yml)
- 📊 **Weekly Reports**: [.github/workflows/governance-report.yml](.github/workflows/governance-report.yml)

---

**Document Version**: 1.0  
**Effective Date**: April 15, 2026  
**Maintained By**: Architecture Team  
**Last Reviewed**: April 15, 2026  
**Next Review**: July 15, 2026 (quarterly)
