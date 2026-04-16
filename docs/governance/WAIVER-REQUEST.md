# Governance Waiver Request Process

**Version**: 1.0  
**Effective**: April 22, 2026  
**Owner**: Infrastructure Team

---

## Overview

A **waiver** is a documented exception to the code quality governance policy. Waivers are time-limited and require approval from infrastructure leadership.

### When to Request a Waiver

Request a waiver when:
1. **Technical impossibility**: Compliance is genuinely impossible (not just inconvenient)
2. **Vendor constraint**: Third-party code/tool cannot be modified
3. **Legacy system**: Brownfield migration requires gradual remediation
4. **Risk-acceptable violation**: Business case justifies the exception

### When NOT to Request a Waiver

Do NOT request waivers for:
- Refusal to follow standards ("I don't like this rule")
- Insufficient effort to remediate ("It takes too long")
- Avoiding security requirements
- Issues affecting < 1% of codebase (fix them instead)

---

## Waiver Request Format

All waivers recorded in `docs/governance/WAIVERS.md`

### Required Information

```markdown
### Waiver #[AUTO_INCREMENT]

**Date Requested**: YYYY-MM-DD  
**Requested By**: @github_username  
**PR/Issue**: [GitHub link to PR or issue]  
**Policy Violated**: [Name of policy section violated]  
**Violation Details**: [Specific violation, e.g., "Script without error handling header"]  
**Justification**: [2-3 sentences explaining why waiver is necessary]  
**Expiration**: [Date or version when this waiver expires]  
**Impact**: [How many files/lines affected]  

**Approved By**: @maintainer_github_handle  
**Approval Date**: YYYY-MM-DD  
**Approval Notes**: [Any conditions or requirements for waiver]  

---
```

---

## Approval Criteria

Waivers approved if:

| Criterion | Status | Notes |
|-----------|--------|-------|
| Technical justification provided | Required | "Vendor can't modify" > "Don't want to" |
| Risk assessment documented | Required | "No security impact" must be stated |
| Expiration date set | Required | Max 180 days or next version release |
| Impact quantified | Required | "5 files, 200 lines" not "some code" |
| Owner assigned for remediation | Required | Name of person fixing post-expiration |
| No security bypass | Required | Waivers cannot approve security violations |

---

## Waiver Lifecycle

### 1. Request Phase

**Location**: GitHub PR comments  
**Format**: Use template above  
**Timing**: Before pushing code requiring waiver

### 2. Review Phase

**Owner**: Infrastructure lead (@kushnir)  
**SLA**: 24 hours for decision  
**Decision**: Approve (with conditions) OR Reject (request modification)

### 3. Approval Phase

**Action**: Infrastructure lead adds waiver to `docs/governance/WAIVERS.md`  
**Notification**: Automated comment on PR with approval

### 4. Post-Expiration

**Before expiration date**:
- Infrastructure team notifies issue owner: "Your waiver expires on DATE"
- Owner must either remediate or request 90-day extension

**After expiration date**:
- Waiver no longer valid
- Code must meet policy or be removed
- CI/CD rejects any new use of that pattern

---

## Waiver Metrics

Tracked monthly in governance dashboard:
- Active waiver count
- Waivers expiring in 7 days
- Expired waivers not yet remediated

---

## Escalation

If waiver request rejected:

1. **Request clarification**: Ask for specific remediation path
2. **Propose alternative**: "Can we use pattern X instead?"
3. **Escalate**: Request meeting with infrastructure lead
4. **Final appeal**: Infrastructure lead has final say

---

**Last Updated**: April 22, 2026  
**Owner**: @kushnir (Infrastructure Lead)
