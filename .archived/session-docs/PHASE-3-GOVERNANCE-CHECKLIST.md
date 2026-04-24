# Phase 3 Governance Rollout - Implementation Checklist

**Phase**: Phase 3 - Governance Implementation  
**Dates**: April 21-28, 2026  
**Owner**: @kushin77 (DevOps Lead)  
**Status**: 📋 READY FOR EXECUTION

---

## Overview

Phase 3 transitions from Phase 2's non-blocking CI validation (info/warning) to enforced governance with team feedback collection and soft launch of blocking rules.

**Key Activities**:
1. Team alignment on governance expectations
2. Soft launch: CI checks warn but don't block
3. Collect feedback on violations & false positives
4. Refine rules based on feedback
5. Document exceptions & processes

---

## Pre-Execution Setup (This Week)

### Task 1: Enable Status Checks on Main Branch ⏳

**Current State**: Workflow deployed but not required for merges

**Action**:
```
GitHub Settings → branch/main → Requirements
☐ Require status checks to pass before merging
☐ Select check: validate-config
☐ Make mandatory dismissal of stale reviews
☐ Require code review (1 approval minimum)
```

**Verification**:
- [ ] Go to `https://github.com/kushin77/code-server/settings/branches`
- [ ] Confirm `validate-config` is listed as required check
- [ ] Test with a PR (should require passing checks)

### Task 2: Create Test PR for Validation ⏳

**Purpose**: Verify workflow functions correctly before enforcement

**Test Cases**:
1. ✅ Valid case: Modify comment in docker-compose.yml
   - Expected: All checks PASS
   
2. ✅ Modification: Fix a Terraform format issue
   - Expected: `terraform fmt` check PASS
   
3. ❌ Secrets detection: Add fake API key to .env.backup
   - Expected: Secrets scanning FAIL
   - Action: Move to .gitignore, re-run checks
   
4. ❌ Syntax error: Break docker-compose.yml YAML
   - Expected: docker-compose validation FAIL
   - Action: Fix YAML, re-run checks

**Expected Workflow**: Each push to test PR should trigger validation automatically

### Task 3: Team Alignment (Async/Synchronous)

**If Individual Contributor**:
- [ ] Review GOVERNANCE-AND-GUARDRAILS.md thoroughly
- [ ] Read CONTRIBUTING.md CI section
- [ ] Understand each rule and why it exists

**If Managing Team**:
- [ ] Schedule 30-min governance walkthrough meeting
- [ ] Share governance deck with team before meeting
- [ ] Record session for async team members
- [ ] Provide Q&A Slack channel
- [ ] Document FAQs

### Task 4: Document CI Validation Rules

**Create or Update**: `.github/VALIDATION-GUIDE.md`

```markdown
# CI Validation Guide

This document explains the automated checks that run on every PR.

## Docker Compose Validation
- **Check**: docker-compose syntax validation
- **Why**: Bad YAML syntax = deployment failure
- **Failure**: ❌ PR cannot merge
- **How to fix**: Run `docker-compose config` locally

## Caddyfile Validation
- **Check**: Caddy v2 server configuration
- **Why**: Invalid Caddyfile = reverse proxy down
- **Failure**: ❌ PR cannot merge
- **How to fix**: Run `caddy validate --config Caddyfile`

## Terraform Validation
- **Checks**:
  - Format (`terraform fmt -check`)
  - Syntax validation (`terraform validate`)
- **Why**: Prevents deployment failures, maintains consistency
- **Failure**: Format fails but can be auto-fixed; syntax fails PR
- **How to fix**: Run `terraform fmt -recursive .` then `terraform validate`

## Shell Script Validation
- **Checks**:
  - Bash syntax (`bash -n script.sh`)
  - ShellCheck linting (warnings only)
- **Why**: Scripts with syntax errors fail deployments
- **Failure**: Syntax errors ❌ block PR; ShellCheck warnings ⚠️ info only
- **How to fix**: Fix syntax errors, address ShellCheck warnings

## Secrets Scanning
- **Check**: TruffleHog + regex patterns for API keys, tokens, creds
- **Why**: Prevent credential leakage to git
- **Failure**: ❌ PR cannot merge if secrets detected
- **How to fix**: 
  - Remove credentials from file
  - Move to .env (gitignore)
  - Use Vault/AWS Secrets Manager in production

## Obsolete File Detection
- **Check**: phase-{N}-*.{tf,yml,sh,ps1} filenames in root
- **Why**: Prevent dead code accumulation
- **Failure**: ⚠️ Warning only (non-blocking)
- **How to fix**: Move to `docs/phases-archived/` or delete if unused
```

---

## Phase 3 Rollout Week (April 21-28)

### Week 1: Soft Launch & Feedback

**April 21-23: Soft Launch**
- Governance rules active
- CI checks running and reporting
- Status checks REQUIRED but violations can be overridden by maintainer
- Collect violations and false positives

**April 24-25: Analysis**
- Review all violations from recent PRs
- Identify false positives (rules that need refinement)
- Document exceptions and edge cases
- Plan adjustments for Phase 4

**April 26-28: Refinement**
- Update CI workflow based on feedback
- Document exceptions explicitly
- Prepare for Phase 4 hard enforcement

### Feedback Collection Process

**Option 1: Spreadsheet + Slack**
```
Track in shared doc:
- Date
- PR #
- Rule violated
- False positive? (Y/N)
- Impact on developer (comment)
- Suggested fix
```

**Option 2: GitHub Issues**
```
Create issue: "Phase 3 Governance Feedback"
- Team comments on violations they encountered
- Reference PRs that had issues
- Link to specific rules
```

**Option 3: Weekly Retrospective**
```
Meeting: Friday 2PM UTC
Duration: 20 min
Topics:
- Notable violations from week
- Any overwhelming false positives?
- Adjustments for next week
```

---

## Transition Matrix

| Aspect | Phase 2 | Phase 3 | Phase 4 | Phase 5 |
|--------|---------|---------|---------|---------|
| **CI Checks** | Info/Warning | Warn + Track | Block on errors | Full enforcement |
| **Docker Compose** | ⚠️ Warn | ⚠️ Warn | ❌ Block | ❌ Block |
| **Caddyfile** | ⚠️ Warn | ⚠️ Warn | ❌ Block | ❌ Block |
| **Terraform** | ⚠️ Warn | ⚠️ Warn | ❌ Block syntax | ❌ Block all |
| **Secrets** | ⚠️ Warn | ⚠️ Warn | ❌ Block | ❌ Block |
| **Code Review** | Optional | Optional | Required | Required |
| **Feedback Loop** | — | ✅ Active | ✅ Refine | ✅ Monitor |

---

## Success Criteria for Phase 3

✅ **Phase 3 Complete When**:
- [ ] Branch protection requires status checks
- [ ] Test PR successfully validates all rules
- [ ] Test PR successfully fails on violations
- [ ] Team understands governance expectations OR individual is aligned
- [ ] At least 3 PRs processed through validation
- [ ] Feedback collected (violations, false positives)
- [ ] No critical showstoppers with CI workflow
- [ ] Violations are documented and tracked

✅ **Ready for Phase 4 When**:
- [ ] No major false positives from Phase 3
- [ ] Team satisfied with rule clarity
- [ ] Consensus on blocking vs warning checks
- [ ] Documentation complete
- [ ] Easter egg: Team knowledge of WHY each rule exists

---

## Rollback Plan (If Needed)

**If CI workflow becomes too strict or has critical issues**:

1. **Quick Disable**:
   ```bash
   # Comment out the validation workflow
   git checkout .github/workflows/validate-config.yml
   # Remove validation from branch protection settings
   # Restore to Phase 2 level (info only)
   ```

2. **Root Cause Analysis**:
   - Identify which check is problematic
   - Isolate the check in a separate branch
   - Fix the issue
   - Re-test before re-enabling

3. **Communication**:
   - Notify team of temporary rollback
   - ETA for re-enablement
   - Link to incident post-mortem

---

## Related Documentation

- [GOVERNANCE-AND-GUARDRAILS.md](./GOVERNANCE-AND-GUARDRAILS.md) - Rules & policies
- [GOVERNANCE-ROLLOUT-PLAN-PHASES-2-5.md](./GOVERNANCE-ROLLOUT-PLAN-PHASES-2-5.md) - Detailed timeline
- [CONTRIBUTING.md](./CONTRIBUTING.md) - Developer guide (includes CI section)
- `.github/workflows/validate-config.yml` - Workflow implementation
- `.github/VALIDATION-GUIDE.md` - Validation rule details

---

## Timeline

- **Apr 14**: Phase 2 CI workflow deployed ✅
- **Apr 17**: Enable status checks, create test PR
- **Apr 21**: Phase 3 soft launch begins
- **Apr 24-25**: Feedback analysis
- **Apr 28**: Phase 3 complete, hand off to Phase 4
- **May 2**: Phase 4 enforcement begins
- **May 2+**: Phase 5 full enforcement

---

## Owner Notes

**For @kushin77**:
1. Verify validate-config.yml is working correctly
2. Run through test PR scenarios personally
3. Document any quirks or edge cases discovered
4. Set up feedback collection process before soft launch
5. Be prepared to adjust workflow based on real-world usage

**Key Decision**: When should certain rules transition from ⚠️ warn to ❌ block?
- Secrets: ALWAYS block immediately (no grace period)
- Format: ⚠️ info only (developers can fix before committing)
- Syntax: ⏳ after Phase 3 feedback (depends on rule clarity)

