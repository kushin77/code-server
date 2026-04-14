# APRIL 21, 2026 - PHASE 3 GOVERNANCE LAUNCH RUNBOOK
## Phase 3: Governance & Guardrails - Team Training & Soft-Launch Activation

**Date**: April 21, 2026
**Duration**: 30 minutes (live session) + 1 week soft-launch period
**Attendees**: Full engineering team (8-12 developers)
**Format**: Live training + Q&A
**Owner**: Infrastructure & Governance Teams

---

## PRE-TRAINING SETUP (by April 20, 2:00 PM UTC)

### Send Team Meeting Invite

**Email Template** (Send by April 20):

```
Subject: Phase 3 Governance Training - April 21, 2:00 PM UTC
To: engineering-team@company.com

Hi Team,

We're launching Phase 3 of our governance framework on April 21.

📅 WHEN: April 21, 2:00 PM UTC (30 minutes)
📍 WHERE: [Zoom/Teams Link]
🎯 WHAT: Governance rules overview + live CI check demo

📚 PLEASE READ BEFORE TRAINING:
1. GOVERNANCE-AND-GUARDRAILS.md (5 min read)
2. GOVERNANCE-TEAM-TRAINING-MATERIALS.md (10 min review)

TRAINING AGENDA:
1. Governance rules overview (10 min)
2. Live CI check demo with real PR (8 min)
3. Common violations + fixes (8 min)
4. Q&A + feedback collection (4 min)

✅ WHAT HAPPENS NEXT:
- April 21-25: Soft-launch (CI feedback, PRs not blocked)
- April 28: Hard enforcement (failed checks block merge)
- Your feedback shapes governance until April 25

Questions? Reply to this thread or comment on GitHub Issue #XXX

Thanks,
Infrastructure Team
```

### Upload Training Materials

Place in workspace root:
- ✅ `GOVERNANCE-AND-GUARDRAILS.md` (exists)
- ✅ `GOVERNANCE-TEAM-TRAINING-MATERIALS.md` (exists)
- ✅ `GOVERNANCE-VIOLATIONS-AND-FIXES.md` (will create)

### Prepare Demo Content

Create a test PR in `test-ci-validation-pr` branch with:
- ✅ Valid docker-compose.yml (should pass)
- ❌ Invalid Caddyfile (should fail - for demo purposes)
- ❌ Unquoted shell variable in script (should fail - for demo)

### Dry Run (April 20, 2:00 PM UTC - the day before)

1. Test the Zoom/Teams link works
2. Share slides with team lead for review
3. Walk through demo PR manually
4. Verify all CI checks run and display correctly

---

## APRIL 21 TRAINING EXECUTION (2:00 PM - 2:30 PM UTC)

### Pre-Training (2:00 PM - 2:05 PM)

**Minutes 0-5: Welcome & Overview**

**Slide 1**: Governance Philosophy
```
"Elite infrastructure requires governance.
We're NOT enforcing rules - we're teaching best practices.

This week: Feedback mode (CI tells you what to fix)
Next week: Enforcement mode (CI blocks broken code)"
```

**Slide 2**: Why Governance Matters
```
Prevents: 🔴 Hardcoded secrets in code
Prevents: 🔴 Unversioned Docker images
Prevents: 🔴 Missing health checks
Prevents: 🔴 Misconfigured networking
Prevents: 🔴 Syntax errors in configs
```

### Main Training (2:05 PM - 2:20 PM)

**Minutes 5-15: Governance Rules (5 rules)**

**Rule #1: Secret Scanning**
```
What it does: Detects API keys, passwords, tokens in code
How it works: GitHub secret scanning + custom patterns
What you see: Red X ❌ if secret found
What to do: Remove secret, run: git rm --cached file.txt

Examples:
❌ GITHUB_TOKEN=ghp_xxxxxxxxxxxxx  (FAIL)
❌ password: "admin123" in config   (FAIL)
✅ password: ${GITHUB_PASSWORD}     (PASS - uses env var)
```

**Rule #2: Configuration Validation**
```
What it does: Ensures docker-compose.yml, Caddyfile, terraform files are valid
How it works: Syntax checking + schema validation
What you see: Red X ❌ if syntax invalid
What to do: Fix YAML/HCL syntax, run: docker-compose config

Examples:
❌ Invalid YAML (bad indentation)  (FAIL)
❌ Missing required fields          (FAIL)
✅ Valid yaml with proper structure (PASS)
```

**Rule #3: Image Pinning**
```
What it does: Prevents `latest` tags (immutability)
How it works: Checks all container image versions
What you see: Red X ❌ if using latest or no version
What to do: Pin to specific version

Examples:
❌ image: nginx                    (FAIL - no tag)
❌ image: nginx:latest            (FAIL - latest tag)
✅ image: nginx:1.25-alpine       (PASS - pinned version)
```

**Rule #4: Health Check Configuration**
```
What it does: Ensures all services have health checks
How it works: Validates healthcheck blocks exist
What you see: Red X ❌ if health check missing
What to do: Add healthcheck section to docker-compose

Examples:
❌ No healthcheck block           (FAIL)
✅ healthcheck: test: [CMD, curl] (PASS)
```

**Rule #5: Resource Limits**
```
What it does: Ensures memory/CPU limits are defined
How it works: Checks deploy.resources.limits
What you see: Red X ❌ if limits missing
What to do: Add memory/cpu limits

Examples:
❌ No deploy.resources section    (FAIL)
✅ memory: 1g, cpus: '0.5'       (PASS)
```

### Live Demo (2:15 PM - 2:20 PM)

**5-Minute Live Demo on Screen**

```
1. Show test PR: test-ci-validation-pr
   - Point out CI workflow is running
   - Show workflow details

2. Demo PASSING check:
   - docker-compose.yml ✅
     - Valid YAML syntax ✅
     - All images pinned ✅
     - Health checks present ✅
     - Resource limits defined ✅

3. Demo FAILING checks (intentional violations):
   - Caddyfile ❌
     - Syntax error: missing closing brace
     - Error message: "expected closing brace at line 24"

   - shell-script.sh ❌
     - Unquoted variable warning
     - Error message: "variable expansion without quotes at line 12"

4. Show how to fix:
   - Edit Caddyfile, save, push
   - CI automatically retriggers
   - All checks pass ✅

5. Explain merge process:
   - April 21-25: Checks run, appear in PR, don't block
   - April 28+: Failed checks block the "Merge" button
```

### Q&A (2:20 PM - 2:30 PM)

**10 minutes for Questions**

Expected questions & answers:

**Q1**: "What if I need to bypass the checks?"
```
A: For April 21-25 (soft-launch), you CAN merge even with failures.
   Ask your team lead for emergency bypass starting April 28.
```

**Q2**: "How do I know what the checks expect?"
```
A: Read the error messages! They tell you exactly what's wrong.
   Example: "Image must be pinned to version, not 'latest'"

   Run checks locally:
   - docker-compose config (validates YAML)
   - terraform validate (validates HCL)
   - shellcheck *.sh (validates bash)
```

**Q3**: "Can I ask for exceptions to rules?"
```
A: Yes! If a rule doesn't make sense for your use case:
   1. Comment on GitHub Issue #256
   2. Provide context why exception is needed
   3. Team votes on approval

   Example: "We need image:latest for canary deployments"
   → Discussion → Decision → Rule update
```

**Q4**: "What about my existing open PRs?"
```
A: Soft-launch applies to all PRs, existing and new.
   If your PR gets failures:
   1. Read the error message
   2. Make the fix
   3. Push a new commit
   4. CI automatically retriggers
```

**Q5**: "When does enforcement actually start?"
```
A: Timeline:
   - April 21-25: Soft-launch (CI feedback, PRs can merge anyway)
   - April 28: Hard enforcement (failed checks block merge)

   This gives everyone 1 week to learn and ask questions.
```

---

## AFTER TRAINING (April 21 - April 25)

### Soft-Launch Period

**What's Active**:
- ✅ All CI checks run on every PR
- ✅ Detailed error messages in PR checks section
- ✅ GitHub issue comments with fixes
- ❌ Merge is NOT blocked (red check doesn't prevent merge)

**Team Response**:
- Team fixes violations as they merge PRs
- Team provides feedback in GitHub Issue #256
- Ask questions in Slack #governance-support

**Expected Feedback** (4-5 examples):

```
Team Member 1:
"Why do we need health checks for background jobs?"
→ Answer: Health checks enable alerting on service death
→ Feedback collected

Team Member 2:
"The secret scanning caught a non-secret in a comment"
→ Feedback: Check is too aggressive
→ Decision: Whitelist common patterns

Team Member 3:
"The rule requires memory limits - what about ephemeral containers?"
→ Discussion: Maybe we need a rule exception
→ Decision: Add exception for temporary services

Team Member 4:
"Docker image pinning breaks our rolling automatic updates"
→ Discussion: Pinning vs. continuous deployment
→ Decision: Allow weekly version bump PRs with automation
```

### Daily Standups

**10-minute governance check-in** (during existing standup):
- "Any CI check failures blocking your work?"
- "Questions about any rules?"
- "Feedback for the governance team?"

### Support Channel

Create Slack channel: `#governance-support`
- Team lead answers questions
- Post Common Q&As daily
- Share examples of passing/failing PRs

---

## APRIL 25 DECISION POINT

### Feedback Review

Team infrastructure lead reviews:
- Feedback collected (Issue #256 comments)
- Common violations observed
- Requested exceptions

### Decision Options

**Option 1: Proceed with Hard Enforcement (April 28)**
- ✅ All feedback addressed
- ✅ Team is ready
- ✅ Minor rule tweaks completed
- **Action**: Close soft-launch, enforce starting April 28

**Option 2: Extend Soft-Launch (April 28 → May 5)**
- ⚠ Team still confused
- ⚠ Violations still too common
- ⚠ Feedback indicates rules need rework
- **Action**: Document why, extend 1 week, reconvene

---

## APRIL 28 HARD ENFORCEMENT (if proceeding)

### What Changes

**Before April 28**:
- ❌ Check shows: "Some checks have failed"
- ✅ You CAN merge anyway
- 📝 Team feedback welcome

**After April 28**:
- ❌ Check shows: "Some checks have failed" (RED)
- ❌ Merge button is DISABLED (grayed out)
- 📋 MUST fix violations before merge
- 🔄 Can retrigger by pushing new commit

### Enforcement Notification

Send final email April 28:

```
Subject: Phase 3 Governance - Hard Enforcement NOW ACTIVE

The soft-launch period (April 21-27) is complete.

Effective IMMEDIATELY (April 28):
- Failed CI checks BLOCK PR merge
- You must fix violations to proceed
- No exceptions without explicit approval

Changes made based on feedback:
- Image pinning: Allow `X.Y` versions (not just `X.Y.Z`)
- Health checks: Optional for ephemeral services
- [any other feedback-driven adjustments]

Need an emergency bypass?
- Post in #governance-exceptions
- Team will respond within 1 hour
- Explain why exception is needed
```

---

## COMMUNICATION TEMPLATE

### Success Metrics (April 21)

After training, measure:
- ✅ 100% team attendance or recorded viewing
- ✅ 0 questions = high clarity
- ✅ 10+ questions = engagement is good
- ✅ Feedback collected for rules improvements

### Training Success Indicators

✅ **Technical Clarity**: Team understands error messages
✅ **Process Clarity**: Team knows the 3-week timeline
✅ **Support Clarity**: Team knows where to get help
✅ **Engagement**: Team provides actionable feedback
✅ **Adoption**: Team fixes violations during soft-launch

---

## TROUBLESHOOTING

### Problem: "CI checks not showing in PR"
- **Cause**: Workflow file not in `.github/workflows/`
- **Fix**: Verify `.github/workflows/validate-config.yml` exists
- **Timeline**: Restart PR (close/reopen) to retrigger

### Problem: "Error message is confusing"
- **Cause**: Validation tool output is terse
- **Fix**: Team lead interprets, comments in PR with translation
- **Example**:
  - Error: "schema validation failed"
  - Translation: "Your docker-compose.yml is missing 'version' field"

### Problem: "Team wants to ignore a rule"
- **Process**:
  1. Comment in GitHub Issue #256
  2. Team votes (need 2/3 consensus)
  3. Document exception
  4. Update rules file
  5. Re-validate

### Problem: "Merge blocked but I need to deploy NOW"
- **Emergency Process** (April 28+):
  1. Post in Slack #governance-exceptions
  2. Ping team lead (on-call)
  3. Team lead reviews (5-10 min)
  4. Approve exception with justification
  5. Commit "allow emergency deployment" override
  6. Deploy
  7. Post-mortem: Why rule was too strict?

---

## DELIVERABLES

- [ ] Team meeting scheduled (April 21, 2:00 PM UTC)
- [ ] Training materials prepared
- [ ] Test PR with passing + failing checks ready
- [ ] Slack channel #governance-support created
- [ ] Post-training email template drafted
- [ ] Soft-launch support plan documented
- [ ] April 25 review checkpoint scheduled
- [ ] April 28 hard enforcement notification drafted

---

## TIMELINE SUMMARY

| Date | Event | Duration |
|------|-------|----------|
| Apr 20 | Send training invite + materials | - |
| Apr 20 (2pm) | Dry run of training | 30 min |
| **Apr 21 (2pm)** | **LIVE TRAINING** | **30 min** |
| Apr 21-25 | **Soft-launch period** (feedback mode) | **5 days** |
| Apr 25 | Feedback review + decisions | 30 min |
| **Apr 28** | **Hard enforcement** (optional, if ready) | continuous |

---

## Next Phase

**Phase 4 (~May 1-5, 2026)**: Team consolidation & guardrails hardening

- Elevated governance checks beyond Phase 3
- Advanced testing requirements
- Security scanning expansion
- Performance benchmarking

---

**Owner**: Infrastructure Team
**Last Updated**: April 14, 2026
**Status**: Ready for execution
