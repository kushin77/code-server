# UAT Test Plan

**Product:** code-server-enterprise  
**Issue:** #1537 — Testing & QA 100x  
**Status:** Active  
**Governance:** GOV-002

---

## Purpose

This document defines User Acceptance Testing (UAT) scenarios to be executed by any team member before each production release. All scenarios are executable without deep technical knowledge.

---

## Prerequisites

| Requirement | Value |
|-------------|-------|
| QA Account | qa@kushnir.cloud |
| VPN | WireGuard (connected to kushnir.cloud network) |
| Browser | Chrome or Firefox (latest) |
| Environment | https://ide.kushnir.cloud |

---

## UAT Scenarios

### UAT-001: Access & Authentication
**Objective:** Verify OAuth2 login flow works end-to-end.

| Step | Action | Expected Result |
|------|--------|----------------|
| 1 | Open https://ide.kushnir.cloud in a private/incognito window | Redirected to Google OAuth sign-in |
| 2 | Sign in with qa@kushnir.cloud credentials | Redirected back to IDE |
| 3 | Observe browser address bar | URL is https://ide.kushnir.cloud (no auth params) |
| 4 | Reload page (F5) | IDE reloads without re-prompting for login |

**Pass criteria:** User reaches IDE without manual token entry. Session survives page reload.

---

### UAT-002: IDE Workspace Open
**Objective:** Verify workspace opens and editor functions.

| Step | Action | Expected Result |
|------|--------|----------------|
| 1 | After login, wait for IDE to load | VS Code interface visible with activity bar |
| 2 | Press Ctrl+Shift+E (Explorer) | File tree appears in sidebar |
| 3 | Click any existing file | File opens in editor tab |
| 4 | Modify a line of text | Dot (unsaved indicator) appears in tab |
| 5 | Press Ctrl+S | Dot disappears (file saved) |

**Pass criteria:** Explorer opens, file editing and saving works.

---

### UAT-003: Integrated Terminal
**Objective:** Verify integrated terminal is functional.

| Step | Action | Expected Result |
|------|--------|----------------|
| 1 | Press Ctrl+` (backtick) | Terminal panel opens at bottom |
| 2 | Type `whoami` and press Enter | Username is displayed |
| 3 | Type `ls /` and press Enter | Root directory listing shown |
| 4 | Type `git status` and press Enter | Git output (or "not a git repository") |
| 5 | Type `exit` and press Enter | Terminal session closes |

**Pass criteria:** Terminal accepts input and shows output correctly.

---

### UAT-004: Extension Marketplace
**Objective:** Verify extension installation works.

| Step | Action | Expected Result |
|------|--------|----------------|
| 1 | Click Extensions icon (Ctrl+Shift+X) | Extensions panel opens |
| 2 | Search for "Prettier" | Prettier extension appears in results |
| 3 | Click "Install" on Prettier | Install progress bar appears, then "Installed" status |
| 4 | Open Command Palette (Ctrl+Shift+P) | Palette opens |
| 5 | Type "Prettier" and observe | Prettier commands appear in list |

**Pass criteria:** Extension installs without error and appears in command palette.

---

### UAT-005: Git Workflow
**Objective:** Verify git operations work in the IDE.

| Step | Action | Expected Result |
|------|--------|----------------|
| 1 | Create a new file: `test-uat-{date}.txt` | File appears in Explorer |
| 2 | Add content and save | File saved |
| 3 | Click Source Control icon (Ctrl+Shift+G) | Source Control panel shows changed file |
| 4 | Click `+` next to the file (Stage Changes) | File moves to Staged Changes |
| 5 | Type commit message: `chore: uat-test` | Message entered in input |
| 6 | Click Commit (✓) | Commit created (file disappears from changes) |

**Pass criteria:** Git staging and commit works without CLI fallback.

---

### UAT-006: Session Reconnect
**Objective:** Verify session continuity after disconnect.

| Step | Action | Expected Result |
|------|--------|----------------|
| 1 | Open IDE, open a file, start typing | Unsaved changes visible |
| 2 | Close browser tab | Tab closes |
| 3 | Reopen https://ide.kushnir.cloud | IDE loads without re-login |
| 4 | Check previously opened files | Tab may restore (dependent on VS Code settings) |
| 5 | Check terminal history | Previous commands may appear in history |

**Pass criteria:** No login required on reconnect. Session stable.

---

### UAT-007: Performance Baseline
**Objective:** Verify IDE loads within acceptable time.

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Time to sign-in page | < 2s | Browser DevTools → Network → First load |
| Time from login to IDE loaded | < 10s | Stopwatch from OAuth redirect |
| File open time (< 100KB) | < 1s | DevTools → Timeline |
| Terminal open time | < 2s | Visual observation |

**Pass criteria:** All metrics within target.

---

## Sign-Off Checklist

For each release, the following must be completed and signed:

```
Release Version: _________________
UAT Date:        _________________
Tester:          _________________

[ ] UAT-001: Authentication — PASS / FAIL
[ ] UAT-002: Workspace     — PASS / FAIL
[ ] UAT-003: Terminal       — PASS / FAIL
[ ] UAT-004: Extensions     — PASS / FAIL
[ ] UAT-005: Git Workflow   — PASS / FAIL
[ ] UAT-006: Session Reconnect — PASS / FAIL
[ ] UAT-007: Performance    — PASS / FAIL

Notes:
_________________________________________________

Approved for production: YES / NO
Signature: _________________
```

---

*GOV-002: This document must be updated when new UAT scenarios are added to the epic.*
