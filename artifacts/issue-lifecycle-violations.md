# Issue Lifecycle Governance Report

**Generated**: 2026-04-24 20:59:34 UTC
**Period**: Last 30 days
**Compliance**: 0 / 0 (0%)
**Status**: ✅ COMPLIANT

## Summary

Every closed issue MUST have either:
1. A linked pull request (via "Fixes #N", "Closes #N", etc.), OR
2. A documented close reason (in comment or close message)

Plus: Every issue MUST have a priority label (P0/P1/P2/P3)

All issues comply with governance rules.


## Governance Rules

1. **Priority Labels** (Required)
   - Every issue must have exactly one: P0 (critical), P1 (high), P2 (medium), P3 (low)

2. **Close Documentation** (Required)
   - If closed with linked PR: PR title/description must reference issue ("Fixes #N")
   - If closed manually: Close comment must explain reason
   - Cannot close without reason

3. **PR Linking** (Enforced in CI)
   - No PR can merge without at least one issue reference
   - Reference formats: "Fixes #123", "Closes #456", etc.

4. **Stale Issues** (Automated)
   - 30 days no activity → marked "stale"
   - 14 more days no activity → auto-closed as "not planned"

## Remediation

For each violation:
1. Add priority label (P0/P1/P2/P3) if missing
2. If no linked PR, add close reason comment
3. Re-open if closure was in error

