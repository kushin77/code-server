# Task Completion Framework - Quick Reference

## Problem Solved

**The 5x Hook Blocker Loop**: Agent calls `task_complete` but hook blocks because Definition of Done (DoD) has credential-dependent steps. Agent doesn't know which steps are blocking.

**Solution**: Validate DoD **before** calling `task_complete` to show exactly what's blocking and why.

---

## One-Minute Usage

```bash
source scripts/lib/task-completion-framework.sh

# Register what needs to be done
register_dod_item "step-1" "Description" "agent"        # Agent completes
register_dod_item "step-2" "Description" "credentials"  # Needs GCP/SSH
register_dod_item "step-3" "Description" "manual"       # Needs human
register_dod_item "step-4" "Description" "external"     # Blocked by something else

# Do the work
do_work_step_1
mark_dod_complete "step-1"

# Check status BEFORE calling task_complete
validate_definition_of_done
# Shows which are complete/blocked/pending

diagnose_completion_blockers
# Shows WHY they're blocked and HOW to resolve

# Safe completion
if safe_task_complete 1234; then
    # Ready for task_complete
else
    # Shows resolution paths (A/B/C)
fi
```

---

## Blocker Types

| Type | Meaning | Who Does It | Example |
|------|---------|-----------|---------|
| `agent` | Agent must do this | Agent/Copilot | Write code, run tests |
| `credentials` | Needs secret access | Human + credentials | GCP secrets, SSH keys |
| `manual` | Needs human judgment | Human | Browser testing, approval |
| `external` | Blocked by other system | Whoever owns system | Waiting for deployment, third-party API |
| `none` | Optional/done already | N/A | Nice-to-haves, completed externally |

---

## Resolution Paths When Blocked

```
IF all blockers are "agent" AND unfixed
  → PROBLEM: Work should be done but isn't
  → ACTION: Fix the code/tests/work

IF blockers are "credentials" ONLY
  → PATH A: Provide secrets to agent (⚠️  HIGH RISK)
  → PATH B: Operations team does it (✅ RECOMMENDED)

IF blockers are "manual" or "credentials" or MIX
  → PATH B: Operations team executes (✅ RECOMMENDED)
     Timeline: 30-45 min | Risk: LOW

IF blockers are "external" ONLY
  → PATH C: Accept incomplete DoD
     Hand off to next team member with docs

IF agent work 100% complete BUT manual/credential steps remain
  → Can call: safe_task_complete <issue> force
     With note in issue explaining blockers
```

---

## Quick Checks

```bash
# See which items are done
get_completion_report text

# Export for GitHub issue
get_completion_report markdown > completion-report.md
gh issue comment 1234 --body-file completion-report.md

# Get raw data
get_completion_report json | jq
```

---

## Prevents Hook Blocker By

1. **Visibility**: Shows exactly what's blocking before task_complete
2. **Prevention**: `safe_task_complete` fails gracefully instead of looping
3. **Guidance**: Suggests which resolution path (A/B/C) is appropriate
4. **Documentation**: Blocker analysis can be reported to issue

---

## Before vs After

### Before (5x Blocker Loop)
```
Agent: task_complete
Hook: DoD incomplete
Agent: But all work is done!
Hook: DoD incomplete  ← Repeats 3 more times
[Frustration, no clarity]
```

### After (With Framework)
```
Agent: validate_definition_of_done()
Framework: 1/4 complete, 3/4 blocked by credentials
Agent: diagnose_completion_blockers()
Framework: Shows PATH B recommended (ops team does steps 2-3)
Agent: Reports to issue with clear next steps
User: Knows exactly what to do
```

---

## Files

- **Framework**: `scripts/lib/task-completion-framework.sh`
- **Guide**: `TASK-COMPLETION-FRAMEWORK-GUIDE.md`
- **Example**: `scripts/task-completion-example.sh` (run with `bash`)
- **Root Cause**: `HOOK-BLOCKER-ROOT-CAUSE-AND-RESOLUTION.md`

---

## Quickstart

```bash
# See example in action
bash scripts/task-completion-example.sh

# Use in your script
source scripts/lib/task-completion-framework.sh
source scripts/_common/logging.sh

# Your script here
register_dod_item "item-1" "do something" "agent"
# ... do work ...
mark_dod_complete "item-1"
validate_definition_of_done
safe_task_complete 1234
```

---

## Key Learning

**The hook is NOT broken. It's correctly blocking incomplete work.**

This framework gives visibility into what's actually blocking so you can:
1. Know exactly what you need (credentials/manual steps)
2. Know who should do it (agent/ops/human)
3. Know the timeline and risk for each path
4. Make informed decisions instead of guessing

**Result**: No more 5x blocker loops. Just clear next steps.
