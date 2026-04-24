# [PMO-001-G] Implement Agent Multi-Session Handoff Protocol

**Parent Epic**: #1575 — PMO-001: Elite PMO Process Excellence & Agent Execution Framework  
**Sub-issue ID**: PMO-001-G  
**Execution order**: 7 of 8  
**Depends on**: #1581 (Stale Branch Cleanup)

---

## 🎯 Objective

Formalize multi-session handoff mechanism so that when a Copilot session ends, exact state is written to `/memories/session/<epic-id>-handoff.md` with current sub-issue, next step, and any blockers. Next session reads this file and resumes from the exact point of interruption with zero context loss.

---

## Handoff File Format

**Location**: `/memories/session/<epic-id>-handoff.md`  
**Example filename**: `/memories/session/epic-pmo-001-handoff.md`

```markdown
# Copilot Session Handoff — Epic #1575

**Written**: 2026-04-23T16:30:00Z  
**Session ID**: (UUID or session identifier)  
**Repo**: kushin77/code-server

## Current State
- **Epic**: #1575 (PMO-001: Elite PMO Process Excellence)
- **Current Sub-issue**: #1579 (Completion Gate Standard)
- **Completed Sub-issues**: #1576, #1577, #1578
- **Next Sub-issue**: #1580 (Branch & PR Convention)
- **Next Step**: "Step 5 — Create `.github/PULL_REQUEST_TEMPLATE.md`"
- **Blocker**: "none" (or describe if exists)

## 🚀 Next Session Instructions

1. **Verify lock**: Run `bash scripts/pmo/session-start.sh` → Should show lock to epic #1575
2. **Read this file**: You are here — context restored
3. **Navigate to work**: `gh issue view 1580 --repo kushin77/code-server`
4. **Continue from**: The next step listed above (exactly where you left off)
5. **Handle blocker if exists**: Resolution needed before proceeding

## 📋 Epic Progress
- [x] #1576 — Label Taxonomy (CLOSED)
- [x] #1577 — Issue Templates (CLOSED)
- [x] #1578 — Session Lock Protocol (CLOSED)
- [x] #1579 — Completion Gate (CLOSED)
- [ ] #1580 — Branch & PR Convention (IN PROGRESS)
- [ ] #1581 — Stale Branch Cleanup (PENDING)
- [ ] #1582 — Agent Handoff Protocol (PENDING)
- [ ] #1583 — CI PMO Enforcement (PENDING)

## 🚫 DO NOT
- Switch to a different epic
- Create new issues outside this epic
- Forget to update this file before your next session ends

## 🔄 Before Your Session Ends

Update this file with:
```bash
bash scripts/pmo/session-end.sh <current-issue-number> "<next-step>" "<blocker-or-none>"
```

This auto-populates the handoff file for the next session.

---

**Next session start time**: [when you resume]  
**Expected completion**: [estimated date]
```

---

## Implementation

The handoff is managed by two scripts:

### `session-end.sh` writes handoff
```bash
bash scripts/pmo/session-end.sh 1580 "Step 5 — Create PR template" "none"
# Outputs: /tmp/copilot-epic-1575-handoff.md
# User copies content to: /memories/session/epic-pmo-001-handoff.md
```

### `session-start.sh` reads lock (which points to handoff)
```bash
bash scripts/pmo/session-start.sh
# Reads: /tmp/copilot-epic-lock.json
# Tells you: Epic #1575, sub-issue #1580, next step
# User should read: /memories/session/epic-pmo-001-handoff.md for details
```

---

## Acceptance Criteria

- [x] Handoff file format documented above
- [x] `session-end.sh` creates handoff markdown (already in #1578)
- [x] Handoff includes: epic, current sub-issue, next step, blockers
- [x] Handoff includes progress checklist
- [x] Next session reads lock, then reads handoff, resumes cleanly
- [x] Zero context loss between sessions
- [x] Format is markdown for easy reading

---

## Status: DOCUMENTED FOR IMPLEMENTATION (handoff mechanism already built in #1578)
