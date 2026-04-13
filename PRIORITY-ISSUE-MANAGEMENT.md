# Priority-Based Issue Management Guide
## How Copilot & Team Must Handle GitHub Issues

### Overview
All GitHub issues **MUST** be created with and categorized by priority levels (P0-P3). This ensures:
- Critical work is never lost in the backlog
- Team focus aligns with impact
- Copilot always pulls the right issue to work on next
- Random issue selection is eliminated

---

## Priority Levels Defined

### 🔴 **P0 - Critical/Blocking**
**Response Time**: < 1 hour
- Customer-facing outages or data loss
- Security vulnerabilities
- Core infrastructure failures
- Complete feature breakage
- Payment/billing system issues
- Data corruption or loss

**Examples:**
- "Production API returns 500 errors for all requests"
- "User authentication completely broken"
- "Database replication corrupted"

### 🟠 **P1 - High Priority**
**Response Time**: < 4 hours
- Significant feature degradation
- Major performance issues (p99 > 1000ms)
- Widespread user impact (50%+ of users)
- Dependency issues blocking multiple teams
- Important security concerns (not critical)
- Major pain points in workflow

**Examples:**
- "Login takes 30 seconds (usually 100ms)"
- "Chat feature works only 40% of the time"
- "IDE becomes unresponsive with large files"

### 🟡 **P2 - Medium Priority**
**Response Time**: < 1 week
- Moderate feature gaps or degradation
- Minor user experience issues
- Non-critical enhancements
- Performance improvements for non-critical paths
- Accessibility improvements
- Minor bugs affecting workflow

**Examples:**
- "Search results sometimes show duplicates"
- "UI button styling inconsistent on mobile"
- "Notification sometimes delayed by 5 minutes"

### 🟢 **P3 - Low Priority**
**Response Time**: Best effort
- Nice-to-have features
- Minor UI/UX improvements
- Code cleanup and refactoring
- Documentation updates
- Technical debt
- Future capability exploration

**Examples:**
- "Add dark mode support"
- "Improve code formatting"
- "Update contributing.md examples"

---

## Creating Issues (For Copilot & Team Members)

### ✅ CORRECT - Always Include Priority

```bash
# Using PowerShell script:
./scripts/priority-issue-management.ps1 -Action create `
  -Title "Production API timeout during peak hours" `
  -Body "API starts timing out at 3pm daily under load" `
  -Priority P1 `
  -Labels @("performance", "investigation-needed")

# Using Bash CLI:
./scripts/priority-issue-cli.sh create \
  --title "Production API timeout during peak hours" \
  --body "API starts timing out at 3pm daily under load" \
  --priority P1 \
  --labels "performance,investigation-needed"

# Using GitHub CLI (gh):
gh issue create \
  --title "Production API timeout during peak hours" \
  --body "API starts timing out at 3pm daily under load" \
  --label "P1" \
  --label "performance" \
  --label "investigation-needed"
```

### ❌ WRONG - No Priority Specified

```bash
# BAD - Missing priority:
gh issue create \
  --title "Something broke" \
  --body "Fix it"
# ❌ Will auto-add "needs-priority" label
```

---

## Pulling & Working on Issues

### Get Next Issue by Priority

**PowerShell:**
```powershell
# Get highest priority open issue
$nextIssue = ./scripts/priority-issue-management.ps1 -Action next

# Output example:
# ✅ Next Priority Issue:
#   #1234: Production API timeout during peak hours
#   Priority: P1
#   Status: open
#   URL: https://github.com/kushin77/code-server/issues/1234
```

**Bash:**
```bash
# Get highest priority open issue
./scripts/priority-issue-cli.sh next

# Output example:
# Getting next priority issue...
# Next Issue (Priority: P1)
#   #1234: Production API timeout during peak hours
#   URL: https://github.com/kushin77/code-server/issues/1234
```

**GitHub CLI:**
```bash
# List P0 issues (highest priority first)
gh issue list --label P0 --state open --limit 10

# List P1 issues
gh issue list --label P1 --state open --limit 10

# Search by priority
gh issue list --search "label:P0 OR label:P1" --state open
```

### List Issues by Priority

**PowerShell:**
```powershell
# List all issues organized by priority
./scripts/priority-issue-management.ps1 -Action list -State open

# Filter by specific priority
./scripts/priority-issue-management.ps1 -Action list -Priority P0 -Count 20

# Output example:
# Issues by Priority [kushin77/code-server]
# =================================
# 
# 🔴 P0 (Critical)
#   #1000: Database replication broken
#   #1001: API endpoints returning 500
# 
# 🟠 P1 (High)
#   #1234: Performance degradation
#   #1235: Memory leak in worker processes
```

**Bash:**
```bash
./scripts/priority-issue-cli.sh list --priority all --state open --count 20

# Or specific priority:
./scripts/priority-issue-cli.sh list --priority P0 --state open
```

---

## Updating Issue Priority

If an issue was created without a priority, set it immediately:

**PowerShell:**
```powershell
./scripts/priority-issue-management.ps1 `
  -Action prioritize `
  -Title "1234" `
  -Priority "P1"
```

**Bash:**
```bash
./scripts/priority-issue-cli.sh set-priority 1234 P1
```

**GitHub CLI:**
```bash
# Add priority label
gh issue edit 1234 --add-label P1

# Remove old priority if needed
gh issue edit 1234 --remove-label P0
```

---

## Copilot Mandate: Always Create with Priority

### When Copilot Creates Issues:
1. **Every issue creation MUST include a priority label (P0-P3)**
2. **Default to P1** if priority level is ambiguous
3. **Adjust upward to P0** only for truly critical/blocking issues
4. **Never create without a priority** - the system will flag it

### Copilot Instructions Enforcement:

```
When asked to create a GitHub issue, ALWAYS:

1. Determine appropriate priority level:
   - P0: Customer outage, data loss, security breach
   - P1: Feature broken, major degradation, significant user impact
   - P2: Minor issue, non-critical enhancement
   - P3: Nice-to-have, documentation, cleanup

2. Use the priority-based creation tool:
   bash ./scripts/priority-issue-cli.sh create \
     --title "..." \
     --priority P0|P1|P2|P3 \
     --body "..." \
     --labels "..."

3. Confirm issue created with priority visible in output

4. When responding to user, show the priority level assigned

Example: "✅ Created issue #1234 (P1 - High Priority)"
```

---

## Automation: GitHub Workflow Enforcement

A GitHub workflow automatically:
- ✅ Labels new issues with `needs-priority` if no P0-P3 label
- ✅ Adds a comment requesting priority selection
- ✅ Removes `needs-priority` once priority is assigned
- ✅ Enables sorting issues by priority in project boards

**File:** `.github/workflows/enforce-priority-labels.yml`

---

## Checking Statistics

Monitor priority distribution:

**PowerShell:**
```powershell
# Run as scheduled job to monitor
Get-Content ./scripts/priority-issue-management.ps1 | 
  Invoke-Expression -Fragment "." | 
  Get-IssuesByPriority -Priority all
```

**Bash:**
```bash
./scripts/priority-issue-cli.sh priority-stats

# Example output:
# Priority Distribution
# =====================
# P0: 2 issues
# P1: 8 issues
# P2: 15 issues
# P3: 42 issues
# Unprioritized: 3 issues ⚠️
```

---

## Integration with Copilot Chat

When Copilot Chat is asked "What should I work on?":

```
User: "What should I work on next?"

Copilot Response:
[Runs: ./scripts/priority-issue-cli.sh next]

"Based on priority queue, your next issue is:
• #1234: Production API timeout (🔴 P0 - Critical)
• Assigned to: [you]
• Time estimate: 2-4 hours
• See: https://github.com/kushin77/code-server/issues/1234"
```

---

## Frequently Asked Questions

### Q: Issue was created without priority. What now?
**A:** The system auto-adds `needs-priority` label. Use:
```bash
./scripts/priority-issue-cli.sh set-priority <number> P1
```

### Q: How to change priority after creation?
**A:** Use the same tool:
```bash
./scripts/priority-issue-cli.sh set-priority 1234 P0
```

### Q: Can multiple priorities be assigned?
**A:** No. Each issue has exactly ONE priority (P0-P3). Use other labels for additional categorization.

### Q: What about issues from Copilot without priority?
**A:** The enforcement workflow flags them immediately. They'll show in `needs-priority` filter until resolved.

### Q: How does this affect GitHub API limits?
**A:** Minimal - we batch label checks and use webhook-based triggering rather than polling.

---

## Implementation Checklist

- ✅ Priority-issue-management.ps1 script deployed
- ✅ priority-issue-cli.sh bash script deployed
- ✅ Enforce-priority-labels.yml workflow activated
- ✅ Copilot instructions updated to mandate priority
- ✅ Team trained on priority classification
- [ ] Monitor `needs-priority` label daily
- [ ] Review priority assignments weekly
- [ ] Adjust priority levels based on actual impact

---

## Next Steps

1. **Now**: Use priority tools when creating any issue
2. **This Week**: Review all current issues and add missing priorities
3. **Ongoing**: Enforce in all issue creation workflows
4. **Monthly**: Review priority distribution and adjust levels if needed

---

**Effective Date:** April 2026  
**Maintained By:** Alex Kushnir  
**Last Updated:** April 14, 2026
