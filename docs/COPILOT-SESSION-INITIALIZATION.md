# Copilot Session Initialization - IaC Search-Before-Execute System

**Effective Date**: April 22, 2026  
**Status**: PRODUCTION READY  
**Scope**: kushin77/code-server (all Copilot sessions)

---

## Executive Summary

A comprehensive **search-before-execute system** that makes Copilot automatically check for existing work, duplicate issues, and implementations before starting any task. 

**Key Principles**:
- ✅ **IaC** - Search logic is code, deterministic, version-controlled
- ✅ **Immutable** - Read-only checks, human makes decisions
- ✅ **Idempotent** - Can run multiple times with same result
- ✅ **Always-On** - Integrated into every Copilot session

---

## The Problem This Solves

### Before (Manual)
- Copilot starts task without checking existing work
- Duplicate issues created
- Duplicate PRs submitted
- Duplicate implementations written
- Team wasted time on rework

### After (Session Init)
- Copilot searches for existing work **before** starting
- Duplicate issues detected and linked instead of created
- Existing implementations found and reused
- Related work identified for collaboration
- Team focuses on unique contributions

---

## How It Works

### 5-Stage Pre-Execution Check

```
COPILOT TASK REQUEST
    ↓
[1] VALIDATE IDEMPOTENCY
    ✓ Check operation is safe to run multiple times
    ✗ BLOCK if: DELETE, DROP, force-push, destructive operations
    ↓
[2] CHECK IF WORK COMPLETED
    ✓ Search for closed/completed issues on same topic
    ⚠ WARN if: Issue already resolved, link for context
    ↓
[3] SEARCH DUPLICATE ISSUES
    ✓ Find related open issues with similar keywords
    ⚠ LIST if found: Review before starting
    ↓
[4] CHECK WORK IN PROGRESS
    ✓ Scan open PRs for related implementations
    ⚠ ALERT if: Someone else working on same task
    ↓
[5] SEARCH EXISTING CODE
    ✓ Scan repository for existing implementations
    ⚠ FIND if: Similar components exist, reuse instead of rewrite
    ↓
GREEN LIGHT OR CAUTION
    ✓ Proceed with task (0)
    ⚠ Review findings and adjust plan (1)
```

---

## Usage

### Basic Usage

Every Copilot task starts with:

```bash
# 1. Source the session init script
source scripts/_common/copilot-session-init.sh

# 2. Run pre-execution check
copilot_pre_execute_check \
  --task "description of work" \
  --repo kushin77/code-server \
  --issue 1234  # optional

# 3. Check return code
# rc=0 → green light, proceed
# rc=1 → review findings, adjust plan
```

### Real-World Examples

#### Example 1: Creating a New Feature

```bash
source scripts/_common/copilot-session-init.sh

copilot_pre_execute_check \
  --task "Implement JWT token refresh caching in Redis" \
  --repo kushin77/code-server

# Output:
# ✓ Task is idempotent
# ✓ No completed issues found
# ⚠ Found 2 related JWT issues (#388, #1018)
# ⚠ Found 1 PR in progress (feat/1019-jwt-auth)
# ⚠ Found existing token client code in apps/backend/src/services/auth/
#
# Recommendation: Review #388 and #1019 - likely related work exists
```

#### Example 2: Fixing a Bug

```bash
copilot_pre_execute_check \
  --task "Fix AdminControlsPage rendering loop" \
  --issue 1023 \
  --repo kushin77/code-server

# Output:
# ✓ Task is idempotent
# ✓ Issue #1023 is OPEN (not completed)
# ✓ No duplicates found
# ✓ No work in progress
# ⚠ Found AdminControlsPage component (3 related files)
#
# Recommendation: Green light - proceed with fix
```

#### Example 3: Infrastructure Work

```bash
copilot_pre_execute_check \
  --task "Configure Redis HA with Sentinel" \
  --repo kushin77/code-server

# Output:
# ✓ Task is idempotent
# ✓ No completed infrastructure issues found
# ⚠ Found 1 related issue (#1018 Phase 2 OIDC)
# ⚠ Found branch: feat/1030-phase-3-rbac-enforcement (related)
# ⚠ Found: redis-sentinel service config already exists
#
# Recommendation: Review existing Sentinel config - may need update instead of new
```

---

## Workflow: Search-Guided Task Execution

### Flow for New Features

```
1. Copilot receives feature request
   ↓
2. copilot_pre_execute_check --task "feature description"
   ↓
3a. GREEN LIGHT (no conflicts)
   → Create branch from main
   → Implement feature
   → Create PR (Fixes #N if existing issue)
   → Merge after review
   
3b. CAUTION (related issues found)
   → Review found issues:
     * Related issue open? → link or update existing
     * PR in progress? → collaborate or wait
     * Code exists? → refactor instead of rewrite
   → Adjust plan based on findings
   → Proceed with updated approach
```

### Flow for Bug Fixes

```
1. Copilot receives bug report
   ↓
2. copilot_pre_execute_check --task "bug description" --issue <number>
   ↓
3a. GREEN LIGHT (bug is open, no duplicates)
   → Reproduce bug locally
   → Implement fix
   → Test fix
   → Create PR (Fixes #N)
   → Merge after review
   
3b. ISSUE ALREADY CLOSED
   → Review closed issue for context
   → Check if bug regressed or is different
   → Create new issue if different, or link if same
```

### Flow for Infrastructure/Ops

```
1. Copilot receives ops task
   ↓
2. copilot_pre_execute_check --task "ops task description"
   ↓
3a. GREEN LIGHT
   → Create ops script/runbook
   → Test in dry-run mode
   → Document procedure
   → Create PR for review
   
3b. CODE EXISTS
   → Review existing implementation
   → Decide: update existing vs. create new
   → Link related issues
```

---

## IaC, Immutable, Idempotent Principles

### IaC (Infrastructure as Code)

**What it means**: Configuration and decision logic are code, not manual processes.

**Implementation**:
- Search logic: `scripts/_common/copilot-session-init.sh` (bash code)
- Checks are deterministic and repeatable
- Results are reproducible across sessions
- Audit trail via git and GitHub API logs
- Can be tested and improved iteratively

**Example**:
```bash
# Search logic is code (not manual steps)
search_for_existing_issues() {
    local task_description="$1"
    # Deterministic search using gh CLI
    gh issue list --repo "$repo" \
        --state open \
        --limit 50 \
        --json "number,title,labels,state,updatedAt"
}
```

### Immutable (Read-Only Checks)

**What it means**: Session init checks don't modify state; human makes decisions.

**Implementation**:
- All checks are read-only (no git commits, no GitHub updates)
- Results are reported but not applied automatically
- Human reviews findings and makes decision
- Check outputs cannot be overwritten or ignored
- Audit trail shows what was found and what decision was made

**Guarantees**:
- ✅ No accidental issue closures
- ✅ No auto-comments on issues
- ✅ No automatic branch creation
- ✅ No blind execution based on findings

### Idempotent (Run Multiple Times Safely)

**What it means**: Running the check multiple times produces the same results without side effects.

**Implementation**:
- Check itself has no side effects (read-only)
- Findings are consistent if state hasn't changed
- Can run before each attempt without harm
- Task design prevents non-idempotent operations
- Rejected operations: DELETE, DROP, truncate, force-push

**Guarantees**:
- ✅ Safe to run check multiple times
- ✅ No state changes from running check
- ✅ Tasks are re-runnable without data loss
- ✅ Failures can be recovered without cleanup

---

## Detection Rules

### Idempotency Anti-Patterns (Automatically Rejected)

These phrases in task descriptions trigger rejection:

```bash
"delete database"          → ✗ REJECTED (destructive)
"remove all"               → ✗ REJECTED (destructive)
"clear everything"         → ✗ REJECTED (destructive)
"truncate table"           → ✗ REJECTED (destructive)
"DROP TABLE"               → ✗ REJECTED (destructive)
"force push"               → ✗ REJECTED (destructive)
"force delete"             → ✗ REJECTED (destructive)
"clean up old"             → ⚠ CAUTION (potential data loss)
```

### Keyword Extraction (For Searching)

Task descriptions are parsed to extract keywords:

```
Input: "Fix AdminControlsPage rendering loop on mount"
Keywords extracted: ["Fix", "AdminControlsPage", "rendering", "loop", "mount"]
Search query: repo:kushin77/code-server is:open Fix AdminControlsPage rendering
```

### Duplicate Detection (High Confidence)

Issues are considered duplicates if:

```
- Title contains same 4+ letter keywords (case-insensitive)
- Title contains "duplicate", "existing", "already", "pending"
- Updated within last 7 days
- Still in OPEN state
```

---

## Configuration

### Environment Variables

```bash
# Repository context (override default)
GITHUB_REPO="kushin77/code-server"

# Cache settings (optional)
COPILOT_SESSION_CACHE="/tmp/copilot-session-$(date +%Y%m%d-%H%M%S).json"
COPILOT_CACHE_TTL=300  # 5 minutes
```

### Customization

Session init is highly customizable:

```bash
# Run with custom search depth
copilot_pre_execute_check \
  --task "..." \
  --repo kushin77/code-server \
  --issue 1234 \
  --max-results 100  # Find more issues (default: 50)

# Run with specific search terms
search_for_existing_issues "JWT authentication" kushin77/code-server
```

---

## Integration Points

### 1. Copilot Instructions (Rule 9)

Every Copilot session loads Rule 9 from `.github/copilot-instructions.md`:
- Mandates search-before-execute
- Documents always-on principle
- Links to this guide

### 2. Issue Creation Script

Integrates with `scripts/_common/issue-create-unified.sh`:

```bash
# Before creating issue, check for duplicates
copilot_pre_execute_check --task "New issue title"
# If rc=1 and duplicates found, link existing issue instead
copilot_create_issue --title "..." --priority P1 --check-duplicates
```

### 3. CI Enforcement (Planned)

Planned CI check: `scripts/ci/check-copilot-session-compliance.sh`
- Validates that major PRs have pre-execution check documented
- Enforces that duplicate prevention was attempted
- Reports compliance metrics

### 4. Session Hooks (Future)

When Copilot session hooks are available:
- Auto-load session init on every Copilot prompt
- Auto-run pre-execution check
- Prompt user to confirm before proceeding
- Log findings for audit trail

---

## Troubleshooting

### Issue: "Command not found: gh"

**Error**: `GitHub CLI (gh) not found`

**Fix**:
```bash
# Install GitHub CLI
brew install gh        # macOS
apt install gh         # Linux
choco install gh       # Windows

# Verify installation
gh auth status
```

### Issue: "GitHub CLI not authenticated"

**Error**: `GitHub CLI not authenticated`

**Fix**:
```bash
# Login to GitHub
gh auth login

# Select: GitHub.com
# Select: HTTPS
# Select: Paste personal access token (or create new)
```

### Issue: Pre-execution check fails unexpectedly

**Troubleshoot**:
```bash
# Run with debug output
bash -x scripts/_common/copilot-session-init.sh

# Check GitHub API rate limits
gh api rate_limit

# Verify repository access
gh repo view kushin77/code-server
```

### Issue: Too many unrelated issues found

**Tune search**:
```bash
# Use more specific task description
# Instead of: "Fix bug"
# Use: "Fix AdminControlsPage rendering loop issue on mount"

# Or filter by labels in task
copilot_pre_execute_check --task "Feature (P2): ..." --repo kushin77/code-server
```

---

## Best Practices

1. **Always search first**
   - Running check takes < 10 seconds
   - Saving rework time is worth the upfront check
   - Makes you aware of related work

2. **Review findings thoroughly**
   - Don't ignore caution warnings
   - Click links and actually review found issues
   - Make informed decision to proceed

3. **Use specific task descriptions**
   - Generic: "Fix bug" → too many false positives
   - Specific: "Fix AdminControlsPage rendering loop" → targeted results

4. **Link related work**
   - Found related issue? Link it in PR description
   - Found duplicate? Close new one and link existing
   - Cross-reference in comments

5. **Document search results**
   - Save pre-execution check output in PR description
   - Helps reviewers understand duplicate prevention
   - Creates audit trail for future reference

---

## Compliance & Governance

### Rule 9 Mandate

This is part of `.github/copilot-instructions.md` Rule 9 (Copilot Session Initialization).

**Non-negotiable requirements**:
- Every task begins with search ✅
- Idempotency is enforced ✅
- Findings must be reviewed ✅
- Workflow is human-guided ✅
- Audit trail is maintained ✅

### CI Enforcement

CI check will verify:
- [ ] Pre-execution check was run (documented in PR)
- [ ] Duplicate prevention was attempted
- [ ] Findings were reviewed
- [ ] Related work was linked

### Violations & Escalation

**Minor violation**: Missing pre-execution check documentation
- Request during review
- Require documentation before merge

**Major violation**: Duplicate issue created when search should have found it
- Close duplicate
- Link to original
- Request refactor to use Issue #N instead

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│               COPILOT SESSION START                     │
│                                                         │
│  User provides task description (feature/bug/ops)      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  LOAD: scripts/_common/copilot-session-init.sh         │
│  Execute: copilot_pre_execute_check --task "..."       │
└─────────────────────────────────────────────────────────┘
                          ↓
        ┌─────────────────┼─────────────────┐
        ↓                 ↓                 ↓
   [1] Idempotency  [2] Completion    [3] Duplicates
   Validation      Check             Search
        ↓                 ↓                 ↓
   ✓ Safe?         ✓ Open?           ⚠ Found?
   ✗ Block         ✗ Skip            → List
        ↓                 ↓                 ↓
        └─────────────────┼─────────────────┘
                          ↓
        ┌─────────────────┼─────────────────┐
        ↓                 ↓
   [4] WIP Scan    [5] Code Search
   Open PRs        Existing impl
        ↓                 ↓
   ⚠ Found?        ⚠ Found?
   → List          → List
        ↓                 ↓
        └─────────────────┼─────────────────┘
                          ↓
        ┌─────────────────────────────────┐
        │  SUMMARY & RECOMMENDATION        │
        │                                 │
        │  ✓ GREEN LIGHT (rc=0)           │
        │    → Proceed with task          │
        │                                 │
        │  ⚠ CAUTION (rc=1)               │
        │    → Review findings            │
        │    → Update plan                │
        │    → Proceed or link existing   │
        └─────────────────────────────────┘
```

---

## Related Documentation

- **Implementation**: `scripts/_common/copilot-session-init.sh` (main script)
- **CI Guard**: `scripts/ci/check-copilot-session-compliance.sh` (planned)
- **Governance**: `.github/copilot-instructions.md` Rule 9
- **Issue Creation**: `scripts/_common/issue-create-unified.sh` (integration)

---

## Future Enhancements

### Phase 2: Automatic Session Hooks
- Auto-run pre-execution check on every Copilot prompt
- Don't execute work until check completes
- Prompt user to confirm findings before proceeding

### Phase 3: Machine Learning
- Learn from user decisions (which findings led to rework?)
- Improve search queries based on patterns
- Predict which related issues are truly blocking

### Phase 4: Integration with Analytics
- Track metrics: % duplicate prevention, avg search time
- Report team productivity improvements
- Identify patterns in duplicate work

---

## Conclusion

The Copilot Session Initialization system makes the team **search-aware, duplicate-preventing, and focused** by enforcing a simple principle:

**Every task begins with a search. Before execution, find existing work.**

This is **IaC** (code-based, deterministic), **Immutable** (read-only, human-guided), and **Idempotent** (safe to run multiple times).

When every Copilot session starts with this check, duplicate issues disappear, rework is prevented, and the team focuses on unique contributions.

---

*Created: April 22, 2026*  
*Status: PRODUCTION READY*  
*Rule: Copilot Instructions Rule 9 (Always-On)*
