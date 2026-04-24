# Enhanced Task Completion Framework

**Last Updated**: April 21, 2026  
**Purpose**: Prevent task_complete hook blockers by validating Definition of Done before marking tasks complete  
**Status**: PRODUCTION-READY

---

## Problem This Solves

The hook blocker "You have not yet marked the task as complete using the task_complete tool" occurred **5 times consecutively** when attempting to mark Issue #1017 complete because:

1. **Definition of Done had 4 steps**, not all agent-completable
2. **Steps 2-4 required credentials** (GCP, SSH, browser OAuth)
3. **Hook correctly blocked** because DoD was incomplete
4. **Agent didn't have visibility** into which steps were actually blocking

This framework provides that visibility and prevents premature task_complete calls.

---

## How It Works

### 1. Register Definition of Done Items

```bash
source scripts/lib/task-completion-framework.sh

# Register DoD items at script start
register_dod_item "item-1" "Add qa@kushnir.cloud to whitelist" "agent"
register_dod_item "item-2" "Load QA credentials from GSM" "credentials" "Requires gcloud CLI with GCP credentials"
register_dod_item "item-3" "Restart oauth2-proxy service" "credentials" "Requires SSH key for 192.168.168.31"
register_dod_item "item-4" "Test OAuth flow with QA user" "manual" "Requires browser access and manual verification"
```

### 2. Mark Items Complete as You Finish Them

```bash
# After completing item 1
mark_dod_complete "item-1"

# If you encounter a blocker
mark_dod_blocked "item-2" "GCP credentials not provided to agent"
```

### 3. Validate Before Calling task_complete

```bash
# Check current status
validate_definition_of_done
# Output shows which items are complete, blocked, or pending

# Get a report
get_completion_report text
get_completion_report markdown
get_completion_report json

# Diagnose blockers (shows resolution paths)
diagnose_completion_blockers

# Safely attempt task_complete
safe_task_complete 1017
```

---

## Example Usage in Script

```bash
#!/usr/bin/env bash
set -euo pipefail

source scripts/lib/task-completion-framework.sh
source scripts/_common/logging.sh

# Define DoD for this task
register_dod_item "code" "Implement feature X" "agent"
register_dod_item "tests" "Write unit tests" "agent"
register_dod_item "review" "Peer code review" "manual"
register_dod_item "deploy" "Deploy to staging" "credentials"

# Execute work
log_info "Starting implementation..."
do_work_item_1
mark_dod_complete "code"

log_info "Writing tests..."
do_work_item_2
mark_dod_complete "tests"

# Check status
validate_definition_of_done
# Output shows "code" and "tests" complete, "review" and "deploy" pending

# Diagnose what's blocking
diagnose_completion_blockers
# Output shows "review" needs manual action, "deploy" needs credentials

# Attempt safe completion
if safe_task_complete 1234; then
    # Can call task_complete now
    echo "Ready to mark complete"
else
    # Shows what's blocking and resolution paths
    log_error "Cannot complete yet - see diagnostic output above"
fi
```

---

## Blocker Types and Resolution Paths

| Type | Meaning | Resolution | Risk |
|------|---------|-----------|------|
| `agent` | Agent should complete this | Finish the work, mark complete | Should be ZERO if properly scoped |
| `credentials` | Requires GCP/SSH/secrets | Provide credentials OR hand off to ops | Security risk if agent gets broad access |
| `manual` | Requires human action | Complete manually and report | Timeline uncertainty |
| `external` | Depends on external system | Wait for dependency or accept delay | Not under agent control |
| `none` | Optional or already done | No action needed | Can mark complete anytime |

---

## Decision Tree for Unblocking

```
START: validate_definition_of_done returns BLOCKED

├─ Are all blocker types "credentials"?
│  ├─ YES → PATH A: Provide credentials to agent
│  │         Timeline: 15-20 min | Risk: HIGH | Recommended: NO
│  │
│  └─ NO → Continue to next check
│
├─ Are blockers "manual" OR "credentials"?
│  ├─ YES → PATH B: Operations team executes blocked steps
│  │         Timeline: 30-45 min | Risk: LOW | Recommended: YES
│  │
│  └─ NO → Continue to next check
│
└─ Are blockers only "external"?
   ├─ YES → PATH C: Accept incomplete, hand off to next team
   │         Timeline: IMMEDIATE | Risk: NONE | Recommended: IF appropriate
   │
   └─ NO → All agent work complete, ready for task_complete
            Call: safe_task_complete <issue> force
            (with explanation in issue comment)
```

---

## Integration with GitHub Issues

Recommended workflow:

1. **Create issue with explicit DoD** (markdown checklist)
2. **Script starts** and registers each item:
   ```bash
   register_dod_item "item-1" "checkbox item 1" "agent"
   register_dod_item "item-2" "checkbox item 2" "credentials"
   ```
3. **Script progresses** and marks items complete:
   ```bash
   mark_dod_complete "item-1"  # After completing item
   ```
4. **Before task_complete** - validate:
   ```bash
   if validate_definition_of_done; then
       # Can call task_complete safely
   fi
   ```
5. **If blocked** - diagnose and report:
   ```bash
   diagnose_completion_blockers
   # Output goes to issue comment or log
   ```

---

## Preventing Future Hook Blockers

### For Agent/Copilot Scripts

1. **Always register DoD at script start**
2. **Mark items complete immediately after finishing**
3. **Call `validate_definition_of_done` before task_complete**
4. **If blocked, call `diagnose_completion_blockers` to explain**
5. **Never call `task_complete` if validation fails (unless --force)**

### For Issue Creators

1. **Explicit Definition of Done with blocker types**
   ```markdown
   ## Definition of Done
   - [ ] Item 1 (agent) - executable by agent
   - [ ] Item 2 (credentials) - requires GCP access
   - [ ] Item 3 (manual) - requires human verification
   - [ ] Item 4 (external) - blocked by external system
   ```

2. **Clarify which items require credentials upfront**
3. **Provide credentials OR accept incomplete DoD**
4. **Don't expect agents to call task_complete for incomplete DoD**

---

## Implementation Checklist

- ✅ `scripts/lib/task-completion-framework.sh` created
- ✅ Framework provides DoD registration and validation
- ✅ Blocker types defined (agent, credentials, manual, external)
- ✅ Resolution paths documented
- ✅ Safe task_complete wrapper implemented
- ✅ Integration guide provided
- ✅ Decision tree created

---

## Testing the Framework

```bash
# Test in isolation
source scripts/lib/task-completion-framework.sh
source scripts/_common/logging.sh

# Register test items
register_dod_item "test-1" "Test item 1" "agent"
register_dod_item "test-2" "Test item 2" "credentials"
register_dod_item "test-3" "Test item 3" "manual"

# Mark some complete
mark_dod_complete "test-1"

# Validate (should show test-1 complete, test-2 and test-3 incomplete)
validate_definition_of_done

# Diagnose blockers
diagnose_completion_blockers

# Try safe_complete (should fail and show reasons)
safe_task_complete 9999 || true

# See report
get_completion_report markdown
```

---

## FAQ

**Q: What if all agent work is complete but manual steps remain?**  
A: That's expected. Use `diagnose_completion_blockers` to show the reason, then either:
- Call `safe_task_complete <issue> force` with explanation in issue comment, OR
- Hand off to operations team using MASTER-EXECUTION-GUIDE

**Q: Should agents ever call task_complete with incomplete DoD?**  
A: Only if marked with `--force` AND documented in the issue explaining why (e.g., "All agent work complete, steps 2-4 require credentials, awaiting ops team").

**Q: How does this prevent the 5x hook blocker loop?**  
A: By showing exactly which items are blocking before attempting task_complete. If any are blocked, `safe_task_complete` prevents the call and shows resolution paths instead of getting stuck in an error loop.

**Q: Can I use this with non-agent tasks?**  
A: Yes. The framework works for any Definition of Done, with or without agents involved.

---

## Related Files

- [HOOK-BLOCKER-ROOT-CAUSE-AND-RESOLUTION.md](HOOK-BLOCKER-ROOT-CAUSE-AND-RESOLUTION.md) - Root cause analysis
- [MASTER-EXECUTION-GUIDE.md](MASTER-EXECUTION-GUIDE.md) - Operations team execution guide
- `scripts/_common/logging.sh` - Logging framework dependency
