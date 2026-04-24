# PMO Session Lock & Handoff Protocol

**Purpose**: Enable Copilot to maintain epic focus across multiple sessions with zero context loss.

## Overview

The protocol consists of 3 key mechanisms:

1. **Session Lock** — Restricts Copilot to ONE epic per session
2. **Handoff Protocol** — Captures exact continuation state at session end
3. **Resume Protocol** — Restores context on session start

---

## Session Lock Mechanism

### Lock Lifecycle

```
┌────────────────────────────────────────────────────────────────┐
│ SESSION START                                                   │
├────────────────────────────────────────────────────────────────┤
│ 1. bash scripts/pmo/session-start.sh                           │
│    ↓                                                             │
│ 2. Query: Find highest-priority open epic (P0 > P1 > P2 > P3) │
│    ↓                                                             │
│ 3. Lock file created: /memories/session/epic-lock.md           │
│    ↓                                                             │
│ 4. Lock status: LOCKED to epic #N (cannot touch other epics)  │
│    ↓                                                             │
│ 5. Print resume instructions                                    │
├────────────────────────────────────────────────────────────────┤
│ SESSION WORK (in-progress)                                     │
│ Execute sub-issues #N-A, #N-B, #N-C, ...                     │
│ Follow 4-gate completion standard                              │
│ Do NOT create branches for other epics                         │
├────────────────────────────────────────────────────────────────┤
│ SESSION END                                                     │
├────────────────────────────────────────────────────────────────┤
│ 1. bash scripts/pmo/handoff-write.sh <issue> "<step>" "<note>" │
│    ↓                                                             │
│ 2. Handoff file created: /memories/session/epic-N-handoff.md  │
│    ↓                                                             │
│ 3. Session ends (lock remains until next session reads it)     │
├────────────────────────────────────────────────────────────────┤
│ NEXT SESSION START                                              │
│ 1. bash scripts/pmo/handoff-read.sh                            │
│    ↓                                                             │
│ 2. Load epic lock and last handoff                             │
│    ↓                                                             │
│ 3. Resume exact continuation point                             │
└────────────────────────────────────────────────────────────────┘
```

### Lock File Format

**Location**: `/memories/session/epic-lock.md`

**Content**:
```markdown
# PMO Session Lock

**Date:** 2026-04-23 15:42:55 UTC
**Repository:** kushin77/code-server
**Locked Epic:** #1575 — Elite PMO Process Excellence Framework
**Status:** LOCKED

## Rules
1. Do NOT work on any other epic while this lock is active
2. Execute sub-issues in strict linear order (A → B → C → ...)
3. Follow 4-gate completion: commit → merge → deploy → clean
4. Before ending session: run handoff-write.sh with next sub-issue
5. Do NOT abandon epic unless explicitly approved

## Unlock Instructions
rm -f /memories/session/epic-lock.md
```

### Lock Commands

**Check current lock:**
```bash
bash scripts/pmo/session-lock.sh status

# Output:
# LOCKED: Epic #1575 (Elite PMO Process Excellence)
# Started: 2026-04-23 15:42:55 UTC
# Allowed to work on: #1576, #1577, #1578, #1579, #1580, #1581, #1582, #1583
```

**Clear lock** (only if unblocked):
```bash
bash scripts/pmo/session-lock.sh clear-lock
```

**Query lock state:**
```bash
bash scripts/pmo/session-lock.sh read-lock
```

---

## Handoff Protocol

### Writing Handoff (Session End)

**Purpose**: Capture exact state so next session resumes with zero ramp-up.

**Command**:
```bash
bash scripts/pmo/handoff-write.sh <issue> "<step>" "<blocker>" "<notes>"
```

**Example**:
```bash
bash scripts/pmo/handoff-write.sh 1576 \
  "Step 4: Testing label provisioning on GitHub" \
  "None" \
  "All 33 labels created successfully. Next session can run: bash scripts/pmo/complete-issue.sh kushin77/code-server 1576"
```

**Handoff File**:
```
/memories/session/epic-1575-handoff.md
```

**Content Created**:
```markdown
# Epic #1575 Handoff — Session End

**Written:** 2026-04-23 16:15:30 UTC
**Next Sub-Issue:** #1576
**Step:** Step 4: Testing label provisioning on GitHub
**Blocker Status:** None

## Continuation Instructions

1. Review epic lock file: cat /memories/session/epic-lock.md
2. Read this handoff: cat /memories/session/epic-1575-handoff.md
3. Check the current sub-issue: gh issue view 1576 --repo kushin77/code-server
4. Resume from: Step 4: Testing label provisioning on GitHub
5. If blocked: None

## Session Notes
All 33 labels created successfully. Next session can run: 
bash scripts/pmo/complete-issue.sh kushin77/code-server 1576

## Previous Work
- Provisioned 33 labels across 5 dimensions (priority, type, status, epic, agent/gate)
- Tested script idempotency (ran twice, second run skipped existing labels)
- Committed: scripts/pmo/provision-labels.sh

## Next Steps
1. Checkout feature branch: git checkout feat/pmo-001-a-1576-label-taxonomy
2. Continue from step: Step 4: Testing label provisioning on GitHub
3. Follow the sub-issue instructions on GitHub
4. When complete: bash scripts/pmo/complete-issue.sh kushin77/code-server 1576
5. Write next handoff: bash scripts/pmo/handoff-write.sh <next_issue> "<step>" "<blocker>"
```

### Reading Handoff (Session Start)

**Command**:
```bash
bash scripts/pmo/handoff-read.sh
```

**Output**:
```
┌─────────────────────────────────────────────────────────────┐
│ PMO SESSION RESUME                                          │
├─────────────────────────────────────────────────────────────┤
│ # Epic #1575 Handoff — Session End                          │
│                                                              │
│ **Written:** 2026-04-23 16:15:30 UTC                        │
│ **Next Sub-Issue:** #1576                                    │
│ **Step:** Step 4: Testing label provisioning on GitHub      │
│ **Blocker Status:** None                                     │
│                                                              │
│ ## Continuation Instructions                                 │
│ ...                                                           │
└─────────────────────────────────────────────────────────────┘

Handoff loaded from: /memories/session/epic-1575-handoff.md
```

---

## Complete Session Workflow

### Scenario: Multi-Session Epic Execution

**Session 1: Initial Setup**

```bash
# Step 1: Lock to epic
bash scripts/pmo/session-start.sh
# Output: LOCKED to Epic #1575 (PMO Excellence)
# Sub-issues: #1576, #1577, #1578, #1579, #1580, #1581, #1582, #1583

# Step 2: Work on first sub-issue
git checkout -b feat/pmo-001-a-1576-label-taxonomy
# ... implement provision-labels.sh ...
git commit -m "feat: implement label provisioning (#1576)"
git push -u origin HEAD
# PR opens, Gate 1 applied

# Step 3: At session end (before logging off)
bash scripts/pmo/handoff-write.sh 1576 \
  "PR #N opened, awaiting review approval" \
  "Waiting for maintainer review" \
  "Labels implementation complete. 33 labels provisioned."
```

**Session 2: Resume & Continue**

```bash
# Step 1: Start new session
bash scripts/pmo/session-start.sh
# Finds same epic #1575 still locked

# Step 2: Check handoff
bash scripts/pmo/handoff-read.sh
# Outputs: Continue with #1576, awaiting review approval

# Step 3: Resume work
git fetch origin
git checkout feat/pmo-001-a-1576-label-taxonomy
# PR is approved, merge it
gh pr merge <PR_NUMBER> --merge

# Step 4: Complete issue with full 4-gate enforcement
bash scripts/pmo/complete-issue.sh kushin77/code-server 1576
# Gate 1: Verified ✓ (commits exist)
# Gate 2: Verified ✓ (PR merged to main)
# Gate 3: Deploy (docker compose up -d)
# Gate 4: Cleanup (delete branch)
# → Issue #1576 closed

# Step 5: Move to next sub-issue
git checkout -b feat/pmo-001-b-1577-issue-templates
# ... implement issue templates ...

# Step 6: Handoff at session end
bash scripts/pmo/handoff-write.sh 1577 \
  "All 4 YAML templates created, testing locally" \
  "None" \
  "Created: epic.yml, feature.yml, bug.yml, task.yml"
```

**Session 3: Final Completion**

```bash
# Resume from previous handoff
bash scripts/pmo/handoff-read.sh
# Continue with issue #1577, testing templates...

# ... complete remaining sub-issues ...

# Final session handoff after issue #1583
bash scripts/pmo/handoff-write.sh 1583 \
  "CI workflow complete, ready for final gates" \
  "None" \
  "All 8 sub-issues completed. Ready to close epic #1575."

# Next session closes epic
bash scripts/pmo/complete-issue.sh kushin77/code-server 1575
# → Epic #1575 closed, all sub-issues closed
# → lock file can be cleared
```

---

## Rules & Constraints

1. **ONE EPIC PER SESSION** — Lock file prevents multitasking
2. **LINEAR EXECUTION** — Sub-issues A → B → C → ... (cannot skip ahead)
3. **HANDOFF MANDATORY** — Must write handoff before session ends (not optional)
4. **NO SCOPE CREEP** — Do not create new issues while locked to an epic
5. **BLOCKED ≠ ABANDON** — If blocked: label `status:blocked`, document blocker, move to next sub-issue in THIS epic only
6. **SESSION PERSISTENCE** — Handoff file is the single source of truth for context

---

## Troubleshooting

### "Lock File Already Exists"

If lock file persists from previous session:

```bash
# Check what's locked
cat /memories/session/epic-lock.md

# If still valid (same epic, same work):
bash scripts/pmo/session-start.sh  # Re-run, it will re-lock the same epic

# If stale (different epic or old date):
rm /memories/session/epic-lock.md
bash scripts/pmo/session-start.sh  # Start fresh
```

### "Handoff File Not Found"

If starting fresh (no previous handoff):

```bash
bash scripts/pmo/handoff-read.sh
# Output: No handoff found for epic #1575
# This is normal for first session

# Proceed with normal start:
bash scripts/pmo/session-start.sh
```

### "Session Lock Violation" (Trying to Work on Wrong Epic)

If you accidentally try to work on a different epic:

```bash
# CI will block: "ERROR: Issue #2000 is not linked to locked epic #1575"
# Fix: Only work on sub-issues of the locked epic (#1576-#1583)

# If you MUST switch epics: clear lock, then start new session
bash scripts/pmo/session-lock.sh clear-lock
bash scripts/pmo/session-start.sh  # This will lock to highest-priority epic
```

---

## Automation & Integration

### GitHub Actions Integration

CI workflow `.github/workflows/pmo-compliance.yml` validates:
- Branch naming follows convention
- Commits are Conventional Commits format
- PR body includes "Closes #N" matching a sub-issue of an open epic
- Lock file is checked at PR creation time

### Copilot Session Integration

When Copilot session starts:
```
if [[ -f /memories/session/epic-lock.md ]]; then
    # Session lock exists
    echo "Resuming locked epic..."
    bash scripts/pmo/handoff-read.sh
    # Resume work
else
    # No active session
    echo "Starting new session..."
    bash scripts/pmo/session-start.sh
    # Start fresh
fi
```

---

## Q&A

**Q: What if I need to emergency-switch epics?**  
A: Communicate blocker/reason. Then:  
```bash
bash scripts/pmo/session-lock.sh clear-lock
# Document: bash scripts/pmo/handoff-write.sh <current_issue> "ABANDONED: <reason>" "..." 
bash scripts/pmo/session-start.sh  # Lock to new epic
```

**Q: How long can a session lock persist?**  
A: Until all sub-issues (#N-A through #N-H) are closed. Typical: 1-5 sessions depending on complexity.

**Q: Can humans and Copilot collaborate on same epic?**  
A: Yes — handoff works for any session, human or AI. Handoff format is universal.

**Q: What if handoff notes are too brief?**  
A: They will be vague in next session. Add detail: "Step 4: Testing label provisioning. All 33 labels created. Next: run complete-issue.sh to deploy. If deployment fails, check docker logs on 192.168.168.31."

---

**Version**: 1.0  
**Last Updated**: April 23, 2026  
**References**:  
- Rule 9: Copilot Session Lock Protocol  
- PMO-001-C: Sub-Issue #1578 (Session Lock)  
- PMO-001-G: Sub-Issue #1582 (Handoff Protocol)
