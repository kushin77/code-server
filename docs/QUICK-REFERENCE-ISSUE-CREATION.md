# GitHub Issue Creation - Quick Reference Card

**Keep this handy!** Bookmark or print this for daily use.

---

## The Rule (Rule 8)

```
✅ DO THIS:         copilot_create_issue --title "..." --priority P1
❌ DON'T DO THIS:   gh issue create --title "..." --label "..."
```

---

## Quick Start (Copy-Paste)

```bash
# 1. Load the script (once per session)
source scripts/_common/issue-create-unified.sh

# 2. Check production priorities (optional)
should_prioritize_production kushin77/code-server

# 3. Create an issue
copilot_create_issue \
  --title "Your issue title" \
  --priority P1 \
  --type feature \
  --body "Issue description" \
  --check-duplicates
```

---

## Priority Levels

| Level | Use For | Example |
|-------|---------|---------|
| **P0** | 🔴 Critical (outage, data loss, security) | "API down in production" |
| **P1** | 🟠 High (major degradation, core broken) | "Login fails for 50% users" |
| **P2** | 🟡 Medium (enhancement, non-critical) | "Add new feature XYZ" |
| **P3** | 🟢 Low (nice-to-have, tech debt) | "Refactor old code" |

---

## Issue Types (Optional)

```
--type feature         → enhancement
--type bug             → bug
--type refactor        → refactor
--type docs            → documentation
--type infrastructure  → infrastructure
--type security        → security
--type ops             → ops
--type testing         → testing
--type performance     → performance
--type accessibility   → accessibility
```

---

## Common Commands

### Create Feature
```bash
copilot_create_issue --title "Feature name" --priority P2 --type feature --check-duplicates
```

### Report Bug
```bash
copilot_create_issue --title "Bug description" --priority P1 --type bug --check-duplicates
```

### P0 Incident
```bash
copilot_create_issue --title "P0 INCIDENT: Issue" --priority P0 --body "Full details" --type infrastructure
```

### Preview (Dry Run)
```bash
copilot_create_issue --title "..." --priority P1 --dry-run
```

### With Custom Labels
```bash
copilot_create_issue --title "..." --priority P2 --labels "urgent,frontend,ui"
```

### Force Create (Skip Dedup)
```bash
copilot_create_issue --title "..." --priority P1 --force-create
```

---

## Production Check

```bash
# Before working on new features, check:
should_prioritize_production kushin77/code-server

# If P0/P1 exist, fix those first!
list_production_priorities kushin77/code-server
```

---

## Labels Applied Automatically

### Priority (REQUIRED - Choose 1)
- `P0` / `P1` / `P2` / `P3`

### Type (Applied if --type specified)
- `enhancement`, `bug`, `refactor`, `documentation`, `infrastructure`, `security`, `ops`, `testing`, `performance`, `accessibility`

### Custom (Optional)
- `urgent`, `frontend`, `backend`, `database`, etc.

---

## What Gets Created?

```
Issue Title:  "Add Redis caching"
Priority:    P2
Type:        feature → enhancement label
Labels:      P2, enhancement, [custom labels if any]
Body:        Your full description
```

---

## Pro Tips

✅ **Always include --check-duplicates** (prevents duplicate tracking)  
✅ **Start with dry-run --dry-run** (safe preview)  
✅ **Check P0/P1 before new features** (production first)  
✅ **Include reproduction steps** (in --body for bugs)  
✅ **Add impact statement** (for prioritization)

---

## If Something Goes Wrong

| Problem | Solution |
|---------|----------|
| `command not found` | `source scripts/_common/issue-create-unified.sh` |
| "Duplicate found" | Review listed issues, use `--force-create` if new |
| GitHub auth fails | `gh auth login` |
| CI check fails | Check: Did you use direct `gh issue create`? |
| Label not applied | Check: Did you use `--priority`? (required) |

---

## Full Parameter List

```
--title TEXT         (REQUIRED) Issue title (max 200 chars)
--priority P0|P1|P2|P3 (REQUIRED) Priority level
--body TEXT          (optional) Issue description
--type WORD          (optional) Issue classification
--labels LABELS      (optional) Custom labels (comma-separated)
--repo OWNER/REPO    (optional) Target repo (default: kushin77/code-server)
--check-duplicates   (optional) Check before creating (recommended)
--force-create       (optional) Bypass duplicate check
--dry-run            (optional) Preview without creating
```

---

## Example: Real-World Issue

```bash
copilot_create_issue \
  --title "Reduce auth latency for mobile users" \
  --priority P1 \
  --type performance \
  --body "Mobile users (4G networks) report 30+ sec login

Current flow:
- /auth (2 API calls)
- OAuth callback (3 API calls)  
- Dashboard load (2 API calls)
Total: 7 sequential API calls × 50ms latency = 350ms

Proposed: Batch API calls, parallel where possible
Target: <3 seconds on 4G (100ms latency)
Effort: 8 hours" \
  --labels "customer-report,mobile,optimization" \
  --check-duplicates
```

---

## For Copilot Users

✅ Unified script is **auto-loaded** in every session  
✅ `copilot_create_issue()` is **always available**  
✅ Production check happens **before new features**  
✅ Governance is **enforced via CI/CD**

---

## Governance Enforcement

**CI Guard**: Every PR checked for compliance  
**Rule**: All issues must use unified script  
**Penalty**: PR merge blocked if direct `gh` calls detected  
**Fix**: Use `copilot_create_issue` instead

---

## Need Help?

📖 **Full Guide**: `docs/GITHUB-ISSUE-CREATION-GOVERNANCE.md`  
🚀 **Integration**: `docs/ISSUE-CREATION-INTEGRATION-GUIDE.md`  
📋 **Rule 8**: `.github/copilot-instructions.md` (search for "Rule 8")

---

## Checklist Before Creating Issue

- [ ] Read the title - Is it clear?
- [ ] Chose priority - P0/P1/P2/P3?
- [ ] Ran dry-run - `--dry-run` to preview?
- [ ] Checked duplicates - Similar issue exists?
- [ ] Added body - Details included?
- [ ] Checked production - P0/P1 issues addressed first?

---

## One-Liner Templates

```bash
# Feature
copilot_create_issue --title "FEATURE: [name]" --priority P2 --type feature --body "[description]" --check-duplicates

# Bug
copilot_create_issue --title "BUG: [issue]" --priority P1 --type bug --body "[steps]\n[actual]\n[expected]" --check-duplicates

# Security
copilot_create_issue --title "P0 SECURITY: [issue]" --priority P0 --type security --body "[details]" --check-duplicates

# Ops/Infrastructure
copilot_create_issue --title "OPS: [task]" --priority P2 --type ops --body "[description]" --check-duplicates

# Tech Debt
copilot_create_issue --title "TECH-DEBT: [refactor]" --priority P3 --type refactor --body "[why][benefit]" --check-duplicates
```

---

## Remember

> **Zero duplicates. 100% labels. One script.**

```bash
source scripts/_common/issue-create-unified.sh
copilot_create_issue --title "..." --priority P1 --check-duplicates
```

---

*Laminated version available - Print and pin to desk!*

Last updated: April 22, 2026
