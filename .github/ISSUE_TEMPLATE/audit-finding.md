---
name: Infrastructure Audit Finding
about: Track infrastructure audit issues from workspace code review
title: "[AUDIT] "
labels: audit-remediation, infrastructure
assignees: ''

---

## Issue Type
- [ ] SSOT Violation (multiple sources of truth)
- [ ] Code Duplication (repeated logic)
- [ ] Configuration Drift (inconsistent configs)
- [ ] IaC Gap (manual processes)
- [ ] Documentation Outdated
- [ ] Dependency/Governance Issue
- [ ] Other

## Severity
- [ ] HIGH - Critical production risk
- [ ] MEDIUM - Technical debt/maintainability
- [ ] LOW - Nice-to-have/housekeeping

## Description
<!-- Clear description of the issue found during audit -->

## Root Cause
<!-- Why does this duplication/violation exist? -->

## Current State (WRONG)
<!-- What is the current problematic setup? -->

## Desired State (CORRECT)
<!-- What should the SSOT/canonical setup be? -->

## Files Affected
<!-- List all files involved in the duplication -->
- 
- 
- 

## Canonical Source
<!-- Where is (or should be) the single source of truth? -->

## Phase
- [ ] Phase 1: Quick Wins (1-2 weeks)
- [ ] Phase 2: Core Refactoring (2-4 weeks)
- [ ] Phase 3: IaC Hardening (ongoing)

## Effort Estimate
- [ ] Quick (< 1 day)
- [ ] Medium (1-3 days)
- [ ] High (> 3 days)

## Acceptance Criteria
- [ ] SSOT established/consolidated
- [ ] Duplicates eliminated or consolidated
- [ ] Configuration consistency verified
- [ ] Tests passing
- [ ] Documentation updated

## Related Issues
<!-- Link to related issues -->
Fixes #
Related to #

## Notes
<!-- Additional context -->
