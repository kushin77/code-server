# GitHub Issue Creation Governance (Rule 8)

**Effective Date**: April 22, 2026  
**Status**: MANDATED  
**Scope**: kushin77/code-server + all organization repositories

---

## Executive Summary

All GitHub issue creation across the organization **MUST** use the unified issue creation script (`scripts/_common/issue-create-unified.sh`). Direct `gh issue create` calls are **FORBIDDEN** and will be caught by CI/CD enforcement.

This governance ensures:
- ✅ **Zero duplicate issues** - Automatic deduplication before creation
- ✅ **100% label compliance** - Every issue has priority (P0/P1/P2/P3)
- ✅ **Consistent format** - Standardized labels across all repos
- ✅ **Seamless Copilot integration** - Works across all Copilot sessions
- ✅ **Production-first focus** - P0/P1 issues prioritized before new features

---

## Rule: GitHub Issue Creation Governance

### The Mandate

**✅ DO THIS** — Use unified issue creation:
```bash
source scripts/_common/issue-create-unified.sh
copilot_create_issue \
  --title "Issue title" \
  --body "Full description" \
  --priority P1 \
  --type feature
```

**❌ DON'T DO THIS** — Direct gh CLI calls:
```bash
gh issue create --title "..." --body "..." --label "..."  # FORBIDDEN
```

### Why This Matters

1. **Deduplication**: Automatic duplicate detection prevents wasting time on duplicate tracking
2. **Label Enforcement**: Every issue MUST have a priority label (P0/P1/P2/P3)
3. **Consistency**: Unified label format enables reliable automation
4. **Copilot Integration**: Every Copilot session gets the same behavior
5. **Production Priority**: Prevents feature work when P0/P1 issues exist

### Enforcement Mechanism

**CI/CD Guard**: `scripts/ci/check-issue-governance.sh`
- Runs on every PR
- Scans all shell scripts (.sh), Python (.py), and workflows (.yml)
- Detects direct `gh issue create` calls
- Blocks merge if violations found

**Error Message** (if violated):
```
VIOLATION: Direct 'gh issue create' detected in scripts/ops/my-script.sh:42
  Line: gh issue create --title "..." --body "..."
  FIX: Use 'copilot_create_issue' from scripts/_common/issue-create-unified.sh
```

---

## Usage Guide

### Basic Issue Creation (Copilot)

```bash
# Load the unified script (do once per session)
source scripts/_common/issue-create-unified.sh

# Create a feature request
copilot_create_issue \
  --title "Add authentication caching" \
  --body "Store JWT tokens in Redis for performance" \
  --priority P2 \
  --type feature \
  --check-duplicates
```

### Production Issue (P0/P1)

```bash
copilot_create_issue \
  --title "P0 SECURITY: Hardcoded password in Caddyfile" \
  --body "Found 'secret734' hardcoded in Caddyfile line 78\n\nRisk: Session affinity bypass" \
  --priority P0 \
  --type security \
  --check-duplicates
```

### Bug Report

```bash
copilot_create_issue \
  --title "Session broker crashes on Docker stop" \
  --body "Steps:\n1. docker stop session-broker\n2. Check logs\n\nActual: Exit 1 without graceful shutdown" \
  --priority P1 \
  --type bug \
  --check-duplicates
```

### Infrastructure/Ops Issue

```bash
copilot_create_issue \
  --title "Automate certificate renewal" \
  --body "Set up automated Let's Encrypt renewal before expiry" \
  --priority P2 \
  --type infrastructure \
  --repo kushin77/code-server
```

### With Custom Labels

```bash
copilot_create_issue \
  --title "Refactor AdminControlsPage component" \
  --body "Split into 6 sub-components for maintainability" \
  --priority P2 \
  --type refactor \
  --labels "code-quality,frontend" \
  --check-duplicates
```

### Dry-Run (Safe Preview)

```bash
# Preview what would be created without actually creating
copilot_create_issue \
  --title "Test issue" \
  --priority P3 \
  --dry-run
```

---

## Required Parameters

### --title (REQUIRED)
- The issue title (max 200 characters)
- Example: `"P1 SECURITY: Hardcoded password in config"`

### --priority (REQUIRED)
- Issue severity: `P0`, `P1`, `P2`, or `P3`
- **P0**: Critical (outage, data loss, security breach) — fix immediately
- **P1**: High (major degradation, core broken) — this sprint
- **P2**: Medium (enhancement, non-critical) — next sprint
- **P3**: Low (nice-to-have, docs, tech debt) — backlog

### --type (OPTIONAL but recommended)
- Issue classification: `feature`, `bug`, `fix`, `refactor`, `docs`, `infrastructure`, `security`, `ops`, `testing`, `performance`, `accessibility`
- Applied as label automatically (e.g., `--type feature` → label `enhancement`)

### --body (OPTIONAL)
- Detailed issue description
- Can include markdown, code blocks, links

### --repo (OPTIONAL)
- Target repository (default: `kushin77/code-server`)
- Example: `--repo kushin77/other-repo`

### --labels (OPTIONAL)
- Additional custom labels (comma-separated)
- Example: `--labels "urgent,frontend,ui"`

### --check-duplicates (OPTIONAL, default: ON)
- Search for similar open issues before creating
- Recommended to always include
- Use `--force-create` to bypass

### --dry-run (OPTIONAL)
- Preview creation without executing
- Safe way to test

---

## Label System

### Priority Labels (REQUIRED)
Every issue must have exactly ONE:
- `P0` — Critical production issue
- `P1` — High priority
- `P2` — Medium priority
- `P3` — Low priority / tech debt

### Type Labels (AUTOMATIC from --type)
- `enhancement` (from `--type feature`)
- `bug` (from `--type bug` or `fix`)
- `refactor` (from `--type refactor`)
- `documentation` (from `--type docs`)
- `infrastructure` (from `--type infrastructure`)
- `security` (from `--type security`)
- `ops` (from `--type ops`)
- `testing` (from `--type testing`)
- `performance` (from `--type performance`)
- `accessibility` (from `--type accessibility`)

### Custom Labels
Additional labels via `--labels`:
- `urgent` — Needs immediate review
- `frontend` — UI/UX component
- `backend` — API/service
- `database` — Data layer
- `deployment` — Release/deployment
- `devops` — Infrastructure automation
- And any others as needed

---

## Copilot Integration

### Every Copilot Session

1. **Script is auto-loaded**: `scripts/_common/issue-create-unified.sh` is available
2. **Functions are exported**: `copilot_create_issue()` is ready to use
3. **Production check happens first**: Copilot checks if P0/P1 issues exist before working on features

### Copilot Behavior Rules

**BEFORE creating ANY issue**, Copilot MUST:
1. Load the unified script
2. Check for duplicates (`--check-duplicates` flag)
3. Assign appropriate priority (P0/P1/P2/P3)
4. Verify production priorities (if P0/P1 exist, suggest fixing those first)
5. Apply relevant type label

**PRODUCTION-FIRST RULE**:
```bash
# Check if production issues exist
should_prioritize_production kushin77/code-server

# List all P0/P1 issues
list_production_priorities kushin77/code-server
```

If P0 or P1 issues are open:
- ✅ Copilot should focus on those
- ❌ Don't create new features until production issues are resolved

---

## Governance Workflow

### For Issue Creators

1. **Source the script**:
   ```bash
   source scripts/_common/issue-create-unified.sh
   ```

2. **Check production priorities** (optional but recommended):
   ```bash
   should_prioritize_production kushin77/code-server
   ```

3. **Create your issue**:
   ```bash
   copilot_create_issue \
     --title "..." \
     --priority P1 \
     --type feature \
     --check-duplicates
   ```

4. **Verify** the issue was created (check GitHub)

### For CI/CD Pipeline

Governance check runs automatically:
```bash
bash scripts/ci/check-issue-governance.sh
```

**If violations found**:
- PR merge is blocked
- Error message shows which files violated the rule
- Fix by replacing `gh issue create` with `copilot_create_issue`

### For Repository Maintainers

**To add this to your PR workflow**:

1. Add to `.github/workflows/pr-checks.yml`:
   ```yaml
   - name: Check Issue Creation Governance
     run: bash scripts/ci/check-issue-governance.sh
   ```

2. Add reminder to PR template (`.github/pull_request_template.md`):
   ```markdown
   ### Issue Creation
   - [ ] If creating GitHub issues, used `copilot_create_issue` from `scripts/_common/issue-create-unified.sh`
   - [ ] No direct `gh issue create` calls in this PR
   ```

---

## Troubleshooting

### Q: How do I fix a governance violation?

**A**: Replace `gh issue create` with `copilot_create_issue`:

**Before** (violates governance):
```bash
gh issue create --repo kushin77/code-server --title "Bug X" --label P1
```

**After** (compliant):
```bash
source scripts/_common/issue-create-unified.sh
copilot_create_issue --title "Bug X" --priority P1 --repo kushin77/code-server
```

### Q: Can I bypass deduplication?

**A**: Yes, use `--force-create`:
```bash
copilot_create_issue --title "..." --priority P1 --force-create
```

But only do this when you're CERTAIN the issue is not a duplicate.

### Q: What if I need custom labels?

**A**: Use `--labels` parameter:
```bash
copilot_create_issue \
  --title "..." \
  --priority P1 \
  --labels "urgent,frontend,ui"
```

### Q: Can this work with other repos?

**A**: Yes! Use `--repo`:
```bash
copilot_create_issue \
  --title "..." \
  --priority P1 \
  --repo owner/other-repo
```

### Q: How do I test without creating?

**A**: Use `--dry-run`:
```bash
copilot_create_issue \
  --title "Test" \
  --priority P1 \
  --dry-run
```

---

## References

- **Script location**: `scripts/_common/issue-create-unified.sh`
- **CI guard**: `scripts/ci/check-issue-governance.sh`
- **Copilot instructions**: `.github/copilot-instructions.md` (Rule 8)
- **Repository**: kushin77/code-server
- **Last updated**: April 22, 2026

---

## FAQ

**Q: Do all scripts need to use this?**  
A: Yes. Any script that creates GitHub issues must use `copilot_create_issue`.

**Q: What about GitHub Actions workflows?**  
A: Same rule applies. Use `copilot_create_issue` instead of direct `gh` calls.

**Q: Can I use this across different organizations?**  
A: Yes, use `--repo owner/repo` to target any repository.

**Q: What if I find this rule too restrictive?**  
A: File an issue with feedback at kushin77/code-server. Rules can evolve with team feedback.

**Q: How are duplicates detected?**  
A: Simple title prefix matching (first 50 characters) against open issues. If matches found, creation is blocked and similar issues are listed.

---

## Governance Authority

This rule is canonical and enforceable:
- ✅ Defined in `.github/copilot-instructions.md` (Rule 8)
- ✅ Implemented in `scripts/_common/issue-create-unified.sh`
- ✅ Enforced by CI/CD (`scripts/ci/check-issue-governance.sh`)
- ✅ Required for all PRs and commits

Changes to this rule require:
1. Update to `.github/copilot-instructions.md`
2. Update to this documentation file
3. PR review and merge to `main`
4. Communication to team

---

*For questions or clarifications, see Rule 8 in .github/copilot-instructions.md*
