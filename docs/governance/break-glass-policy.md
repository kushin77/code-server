# Break Glass Policy

**Purpose**: Break Glass Policy reference document.

---
title: Break-Glass Emergency Access Policy
description: Strict controls for break-glass waiver exceptions in kushnir.cloud governance
owner: "@kushin77"
last_review_date: 2026-04-20
status: active
related_issues: ["#705", "#700", "#856"]
---

# Break-Glass Emergency Access Policy

## Purpose

This policy defines the controls, process, and accountability requirements for
break-glass access — the mechanism for temporarily bypassing a governance control
in a production emergency when normal approval channels are unavailable.

Break-glass is the **last resort**. It must never be used as a convenience shortcut.

---

## Applicability

This policy applies to:

- Bypassing required status checks on `main` or `release/*` branches
- Bypassing branch protection rules (required reviews, linear history)
- Bypassing governance waiver expiry enforcement
- Bypassing Cloudflare Access for admin endpoints during outage
- Any temporary deviation from the [org governance baseline](../../config/github-org-ruleset-baseline.json)

---

## Eligibility

Only the repository owner (`@kushin77`) may execute a break-glass action.
No automated system or CI job may initiate a break-glass.

---

## Pre-Conditions (All Required)

Before any break-glass action:

1. **P0/P1 Incident declared** — A GitHub issue labeled `incident`, `P0` must be open.
2. **Incident timeline documented** — At minimum: what failed, when, what service impact.
3. **Normal approval exhausted** — At least 2 attempts made to use normal review path.
4. **Duration scoped** — Break-glass must have a defined max duration, not to exceed 4 hours.

---

## Process

### Step 1 — Declare Break-Glass

Open a GitHub issue with label `break-glass` and `governance` using the template:

```markdown
## Break-Glass Request

- **Incident**: #<incident-issue-number>
- **Control being bypassed**: <e.g. required reviews on main>
- **Justification**: <specific reason normal process is unavailable>
- **Scope**: <specific repos, branches, endpoints affected>
- **Max duration**: <datetime UTC — must be ≤ 4 hours from now>
- **Approver**: @kushin77
- **Approval date (YYYY-MM-DD)**: <date>
- **Approval signature (sha256:<64-hex>)**: sha256:<sha256 of: "break-glass:<issue-number>:<date>:<scope>">

<!-- governance-break-glass-request -->
```

### Step 2 — Create Break-Glass Waiver Entry

Add an entry to `config/governance-waivers.json` using schema v1.0:

```json
{
  "id": "WVR-<year>-<seq>",
  "issue_number": <break-glass-issue-number>,
  "policy_id": "BREAK-GLASS",
  "owner": "@kushin77",
  "approver": "@kushin77",
  "scope": {
    "repositories": ["code-server"],
    "paths": ["<specific branch or endpoint>"]
  },
  "rationale": "<verbatim from break-glass issue>",
  "expires_at": "<max-duration datetime>",
  "status": "active",
  "approval": {
    "approved_at": "<datetime UTC>",
    "signature": "sha256:<computed-signature>"
  }
}
```

Commit this to the branch being used for the emergency. The waiver entry is
required before the break-glass action begins.

### Step 3 — Execute and Document

- Perform only the minimum necessary action.
- Document every command run in the incident issue comments.
- Do not scope-creep. If additional bypass is needed, repeat Step 1.

### Step 4 — Restore Controls

Immediately after the emergency is resolved:

1. Reverse the bypass (re-enable branch protection, Cloudflare Access policy, etc.)
2. Update the waiver `status` to `"revoked"` with a revocation timestamp comment.
3. Run `bash scripts/governance/validate-waiver-registry.sh --registry config/governance-waivers.json`
   to confirm the waiver is revoked.
4. Post a Post-Incident Review (PIR) summary to the incident issue within 24 hours.
5. Close the `break-glass` issue.

---

## Audit and Logging

Every break-glass event generates:

- A GitHub issue (labeled `break-glass`, `governance`) — the permanent audit record.
- A waiver registry entry in `config/governance-waivers.json`.
- A waiver inventory export entry in `artifacts/governance/waiver-inventory.md`.

The daily `governance-waiver-audit` CI workflow (`cron: '0 5 * * *'`) validates:
- No active waivers beyond `expires_at`.
- Every active break-glass waiver has a valid approval signature.
- Any invalid/expired break-glass waivers trigger a P1 GitHub issue.

---

## Signature Computation

The approval signature must be computed as:

```
sha256(break-glass:<issue-number>:<approval-date-YYYY-MM-DD>:<scope-hash>)
```

Where `scope-hash` is the sha256 of the `scope` JSON field (sorted keys, no spaces).

Example:
```bash
echo -n "break-glass:900:2026-04-20:$(echo '{"paths":["main"],"repositories":["code-server"]}' | sha256sum | cut -d' ' -f1)" | sha256sum
```

---

## Strict Controls Summary

| Control | Requirement |
|---|---|
| Initiator | Repository owner only |
| Pre-conditions | Active P0/P1 incident, exhausted normal path |
| Max duration | 4 hours |
| Waiver entry | Required before action begins |
| Audit trail | GitHub issue + waiver registry entry + CI daily validation |
| Post-action | Controls restored + waiver revoked + PIR within 24h |
| Exception stacking | Not permitted — each bypass requires a new break-glass request |

---

## Escalation

If break-glass is abused (e.g., used outside of P0/P1, not reverted within max duration):

1. **Automated**: `governance-waiver-audit` creates P0 GitHub issue on expired break-glass.
2. **Manual review**: Post-incident review required with root-cause analysis.
3. **Policy update**: Update this document within 48 hours if process gap is found.

---

## Related Documents

- [Governance Waiver Schema](../../config/governance-waiver-schema.json)
- [Waiver Registry](../../config/governance-waivers.json)
- [Waiver Inventory Export](../../artifacts/governance/waiver-inventory.md)
- [Waiver Audit Workflow](../../.github/workflows/governance-waiver-audit.yml)
- [Validate Waiver Registry](../../scripts/governance/validate-waiver-registry.sh)
- [Org Governance Baseline](../../config/github-org-ruleset-baseline.json)
