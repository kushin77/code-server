---
name: Governance remediation
description: Track and remediate governance policy violations from CI or audits
title: 'chore(governance): remediate <policy/check> violation in <scope>'
labels: ["governance", "remediation"]
assignees: ''
---

## Duplicate Check (required before submitting)

- [ ] I searched [existing issues](https://github.com/kushin77/code-server/issues?q=is%3Aissue) for this remediation topic
- [ ] No canonical open issue already tracks this same policy violation
- [ ] If duplicate, I linked and closed in favor of canonical issue

## Failing Signal

- Check/workflow name:
- Run URL:
- Failing file(s):
- Severity: P0 / P1 / P2 / P3

## Policy Mapping

- Governance policy section:
- Required standard: immutable / idempotent / independent / duplicate-free / on-prem
- Is waiver requested?: yes / no

## Root Cause

<!-- Why this violation exists today (not just the symptom) -->

## Remediation Plan

1. 
2. 
3. 

## Verification

- [ ] Local verification completed
- [ ] CI check passes on PR
- [ ] On-prem validation completed on 192.168.168.31 (if runtime-affecting)
- [ ] No duplicate policy regressions introduced

## Closure Criteria

- [ ] PR includes `Fixes #N`
- [ ] Superseded/duplicate issues linked and closed
- [ ] Remaining follow-up work split into separate canonical issues
