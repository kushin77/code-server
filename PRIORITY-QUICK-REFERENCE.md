# Priority-Based Issue Management - Quick Reference

## TL;DR: Issue Priorities

**Use this decision tree to pick the right priority:**

```
Does this cause customer outage, data loss, or security breach?
├─ YES → P0 (Critical - Fix immediately)
└─ NO ↓

Is this a major feature broken or severely degraded?
├─ YES → P1 (High - Fix within hours)
└─ NO ↓

Is this a moderate issue or worthwhile enhancement?
├─ YES → P2 (Medium - Fix this week)
└─ NO ↓

Nice-to-have, cleanup, or documentation?
└─→ P3 (Low - Fix when you have time)
```

---

## Creating an Issue (The Right Way)

### Option 1: PowerShell Script (Recommended)
```powershell
./scripts/priority-issue-management.ps1 -Action create `
  -Title "Brief description" `
  -Priority P1 `
  -Body "Detailed description"

# Example:
./scripts/priority-issue-management.ps1 -Action create `
  -Title "API timeouts during peak hours" `
  -Priority P1 `
  -Body "Starting at 3pm, API requests timeout" `
  -Labels @("performance", "investigation")
```

### Option 2: Bash CLI
```bash
./scripts/priority-issue-cli.sh create \
  --title "Brief description" \
  --priority P1 \
  --body "Detailed description"

# Example:
./scripts/priority-issue-cli.sh create \
  --title "API timeouts during peak hours" \
  --priority P1 \
  --body "Starting at 3pm, API requests timeout" \
  --labels "performance,investigation"
```

### Option 3: GitHub CLI
```bash
gh issue create \
  --title "Brief description" \
  --label P1 \
  --body "Detailed description"
```

### Option 4: Web UI (GitHub website)
1. Click "New Issue"
2. Add title and description
3. **IMPORTANT**: Add label `P0`, `P1`, `P2`, or `P3`
4. Click "Submit"

⚠️ **If you skip the label**, the system auto-adds `needs-priority` and comments on the issue.

---

## Finding Work (The RIGHT Way)

### Get Top Priority Issue
```bash
# Shows highest priority open issue (P0 first)
./scripts/priority-issue-cli.sh next
```

### List All Issues by Priority
```bash
# Show all prioritized issues, organized by priority
./scripts/priority-issue-cli.sh list

# Show only critical issues
./scripts/priority-issue-cli.sh list --priority P0

# Show top 20 high-priority issues
./scripts/priority-issue-cli.sh list --priority P1 --count 20
```

### Using GitHub CLI
```bash
# List P0 issues
gh issue list --label P0 --state open

# List P1 issues  
gh issue list --label P1 --state open

# Search for high-priority work
gh issue list --search "label:P0 OR label:P1" --state open
```

---

## Changing Priority

If an issue was created without priority or priority needs adjustment:

```bash
# Add priority to existing issue
./scripts/priority-issue-cli.sh set-priority <number> <P0|P1|P2|P3>

# Example:
./scripts/priority-issue-cli.sh set-priority 1234 P1
```

Or using GitHub CLI:
```bash
gh issue edit 1234 --add-label P1
gh issue edit 1234 --remove-label P2  # if it was P2 before
```

---

## Priority Definitions (Be Honest!)

### P0 - Stop Everything (Red Alert)
- Production is down or severely broken
- Customer data is at risk
- Security vulnerability exploited
- System unable to function

✅ Do this if:
- "500 errors on every request"
- "Database corrupted - data loss"
- "API authentication bypassed"
- "System completely unavailable"

❌ Don't do this if:
- "This feature would be nice"
- "Page loads in 2 seconds instead of 1"
- "One user affected by this bug"

### P1 - Important (Fix Today)
- Major feature doesn't work right
- Many users affected
- Performance is bad
- Important dependency broken

✅ Do this if:
- "Login broken 60% of the time"
- "API response 30 seconds (usually 1 second)"
- "IDE crashes with large files"
- "Search returns wrong results often"

❌ Don't do this if:
- "Sometimes button takes 1 second to respond"
- "One user reported a typo"
- "This feature doesn't exist yet"

### P2 - Normal (This Week)
- Feature has minor issues
- Small portion of users affected
- Nice-to-have improvement
- Moderate pain point

✅ Do this if:
- "Dialog sometimes appears in wrong position"
- "Search occasionally shows duplicates"
- "Notification delayed by 5 minutes"
- "User settings don't persist reliably"

❌ Don't do this if:
- "Complete feature is broken"
- "Everyone can't use the system"
- "This is a cosmetic improvement"

### P3 - When You Have Time (Low Priority)
- Code cleanup
- Documentation
- Nice-to-have features
- Cosmetic improvements
- Technical debt removal

✅ Do this if:
- "Update README with new example"
- "Refactor utility function"
- "Add dark mode support"
- "Remove deprecated code"

❌ Don't do this if:
- "This breaks user experience"
- "This causes performance issues"
- "This is blocking other work"

---

## Common Questions

**Q: What if I'm not sure?**
A: Default to P1. It's better to start high and downgrade than to create P3 that's actually P0.

**Q: Can I change priority later?**
A: Yes! Use `set-priority` command. Priority can change based on impact.

**Q: What about multiple priorities?**
A: NO. Each issue has exactly ONE priority. Use other labels (bug, feature, docs, etc.) for categorization.

**Q: How do I know if I set the right priority?**
A: Ask yourself: "Would this wake me up at 3am if it happened in production?" 
- Yes → P0 or P1
- Maybe → P1 or P2  
- No → P2 or P3

**Q: What happens if I create an issue without priority?**
A: GitHub workflow auto-adds `needs-priority` label and comments on the issue asking you to set it.

**Q: Who decides priority?**
A: The issue creator decides, but team lead can adjust. It's about actual business impact, not effort.

---

## Integration with Copilot

When you ask Copilot "What should I work on?":

```
Copilot will:
1. Check for P0 issues (critical) first
2. If none, check P1 issues (high priority)
3. Show you the highest priority work
4. Assign it to you if you agree
5. Open the issue details

You get:
✅ No more random issue selection
✅ Always working on what matters most
✅ Clear priority visibility
✅ Team stays aligned
```

---

## Tools Reference

| Tool | Usage | Best For |
|------|-------|----------|
| `priority-issue-cli.sh` | `./scripts/priority-issue-cli.sh <action>` | Most use cases, Bash |
| `priority-issue-management.ps1` | `./scripts/priority-issue-management.ps1 -Action <action>` | PowerShell, Automation |
| GitHub CLI | `gh issue create --label P1` | Quick commands, CI/CD |
| GitHub Web UI | Visit and add labels manually | Web browser browsing |

---

## Examples in Action

### Example 1: Creating a Critical Issue
```bash
$ ./scripts/priority-issue-cli.sh create \
  --title "Production database replication broken" \
  --priority P0 \
  --body "Replication lag is 4 hours, data inconsistency between replicas"

✅ Issue #1234 created
   Priority: P0
   Title: Production database replication broken
   URL: https://github.com/kushin77/code-server/issues/1234
```

### Example 2: Finding Next Task
```bash
$ ./scripts/priority-issue-cli.sh next

Getting next priority issue...
Next Issue (Priority: P1)
  #1234: API timeout during peak hours
  URL: https://github.com/kushin77/code-server/issues/1234
```

### Example 3: Reviewing Work Queue
```bash
$ ./scripts/priority-issue-cli.sh list

Issues by Priority
==================================

🔴 P0 (Critical)
  #1000: Database replication broken
  #1001: API authentication broken

🟠 P1 (High)
  #1234: Performance degradation
  #1235: Memory leak

🟡 P2 (Medium)
  #2001: Search results sometimes show duplicates
```

---

## Enforcement

- ✅ GitHub workflow flags unprioritized issues
- ✅ `needs-priority` label auto-added to issues without P0-P3
- ✅ Bot comments asking for priority
- ✅ Team reviews compliance weekly
- ✅ Copilot trained to require priority

---

**Version**: 1.0  
**Effective**: April 2026  
**Questions?** Check `PRIORITY-ISSUE-MANAGEMENT.md` for detailed guide
