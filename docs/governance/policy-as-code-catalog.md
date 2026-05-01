# Policy-as-Code Catalog

**Issue:** #3161 - Policy-as-Code and Reusable Templates
**Date:** May 1, 2026
**Status:** IMPLEMENTED - Catalog and CI validation baseline documented

## Purpose

This catalog documents the repository's OPA-based policy surface, the inheritance model used by the policy packages, and the maintenance process for exceptions and updates.

## Policy Packages

### Core Policies

| Policy | File | Purpose | Owner |
|--------|------|---------|-------|
| Secrets | [policies/core/secrets.rego](../../policies/core/secrets.rego) | Block secret leakage in logs and unencrypted transport | Security |
| Least Privilege | [policies/core/least_privilege.rego](../../policies/core/least_privilege.rego) | Enforce reputation/tier-based access controls | Identity |
| Production Gate | [policies/core/production_gate.rego](../../policies/core/production_gate.rego) | Require human approval for production deployments | Delivery |

### Infrastructure Policies

| Policy | File | Purpose | Owner |
|--------|------|---------|-------|
| Immutable Infra | [policies/infrastructure/immutable_infra.rego](../../policies/infrastructure/immutable_infra.rego) | Deny manual mutations outside IaC | Platform |
| Drift Prevention | [policies/infrastructure/drift_prevention.rego](../../policies/infrastructure/drift_prevention.rego) | Block deploys with unreconciled drift | Platform |
| No Hardcoded IPs | [policies/infrastructure/no_hardcoded_ips.rego](../../policies/infrastructure/no_hardcoded_ips.rego) | Require IP parameterization in Terraform and Compose | Platform |

### Identity Policies

| Policy | File | Purpose | Owner |
|--------|------|---------|-------|
| SSO Required | [policies/identity/sso_required.rego](../../policies/identity/sso_required.rego) | Require approved auth for user-facing services | Identity |
| Device Trust | [policies/identity/device_trust.rego](../../policies/identity/device_trust.rego) | Deny low-trust or non-compliant devices | Identity |
| Reputation Gate | [policies/identity/reputation_gate.rego](../../policies/identity/reputation_gate.rego) | Gate sensitive actions by reputation history | Identity |

### AI Policies

| Policy | File | Purpose | Owner |
|--------|------|---------|-------|
| Agent Budget | [policies/ai/agent_budget.rego](../../policies/ai/agent_budget.rego) | Enforce agent resource budgets | AI Platform |
| Model Allowlist | [policies/ai/model_allowlist.rego](../../policies/ai/model_allowlist.rego) | Restrict allowed model identifiers | AI Platform |
| Prompt Safety | [policies/ai/prompt_safety.rego](../../policies/ai/prompt_safety.rego) | Prevent unsafe prompt content and unsafe outputs | AI Platform |

### Reputation Policies

| Policy | File | Purpose | Owner |
|--------|------|---------|-------|
| Tier Access | [policies/reputation/tier-access.rego](../../policies/reputation/tier-access.rego) | Map reputation tiers to allowed capabilities | Governance |

## Inheritance Model

Policy packages are layered from broad guardrails to specific runtime checks:

1. Core policies define universal rules for secrets, approvals, and least privilege.
2. Infrastructure policies inherit the core immutability and change-control assumptions.
3. Identity policies build on reputation and trust signals to gate user-facing access.
4. AI policies add runtime and model-specific controls for agent behavior.
5. Reputation policies provide shared tiering logic consumed by the identity and AI packages.

The tests under [policies/tests/](../../policies/tests/) validate the package behavior and act as the regression suite for policy changes.

## CI Validation

Policy checks are validated in CI with:

- [Policy-as-Code workflow](../../.github/workflows/policy-as-code.yml) to run `opa check` and `opa test`
- [Security scanning workflow](../../.github/workflows/security-scanning.yml) for SAST/SCA/secrets/container/DAST controls
- [Secret scanning workflow](../../.github/workflows/secret-scanning.yml) for commit-time secret detection
- [Governance checks workflow](../../.github/workflows/governance-checks.yml) for branch hygiene, SSOT, and script/file conventions

## Exception Handling

Policy exceptions must be tracked and reviewed before implementation:

1. Open a GitHub issue with the policy name and requested exception.
2. Include the business reason, blast radius, and expiry date.
3. Link the exception to a PR that updates the policy or documentation.
4. Add a close comment that references the approved exception record.

Exceptions without a linked issue are not considered valid.

## Knowledge Lifecycle

Policy knowledge is maintained with a three-step loop:

1. Capture: add new rules to the correct `policies/*` package and a matching test.
2. Validate: run the policy CI workflow and inspect the generated artifacts.
3. Review: update this catalog when ownership, exceptions, or policy boundaries change.

## Maintenance Notes

- Keep policy ownership aligned to the repo area that can remediate the rule fastest.
- Keep tests in `policies/tests/` updated when a policy changes.
- Prefer new policy files over widening existing rules when the concern is distinct.

---

**Last Updated:** May 1, 2026
**Owner:** Governance / Platform
**Status:** Active