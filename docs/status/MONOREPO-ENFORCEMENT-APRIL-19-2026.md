# Monorepo Enforcement - April 19, 2026

Status: Active
Scope: Enforce FAANG-style naming and pnpm monorepo boundary contracts beyond documentation.

## Purpose

This is the canonical enforcement artifact for issue #806. It turns the monorepo SSOT into an executable enforcement roadmap with naming rules, package contracts, and boundary checks.

## Evidence Reviewed

- [../MONOREPO.md](../MONOREPO.md)
- [../governance/elite-best-practices/README.md](../governance/elite-best-practices/README.md)
- [../governance/elite-best-practices/pnpm/PNPM-WORKSPACE-STANDARDS.md](../governance/elite-best-practices/pnpm/PNPM-WORKSPACE-STANDARDS.md)
- [../../scripts/ci/check-error-handling-consistency.sh](../../scripts/ci/check-error-handling-consistency.sh)
- [../../validate_workflows.py](../../validate_workflows.py)

## Canonical Rules

| Rule Area | Canonical Requirement | Enforcement Path |
| --- | --- | --- |
| Naming | Script, service, and artifact names must be descriptive and consistent. | Review against the monorepo SSOT and naming guidance before merge. |
| Workspace members | Every pnpm package must expose the expected contract for build/test/lint/type-check. | Add validation in CI for package metadata and workspace membership. |
| Boundary imports | Cross-boundary imports between apps, packages, and infra must be explicit and justified. | Fail CI when a boundary rule is violated. |
| Shared helpers | Shared functionality must live in canonical helper modules. | Block one-off duplicates unless a migration waiver exists. |

## Enforcement Roadmap

1. Keep the monorepo SSOT as the canonical source for workspace boundaries.
2. Add or retain CI checks for naming and package-contract drift.
3. Inventory non-conforming names and contracts.
4. Migrate offending paths to canonical naming and package structure.
5. Require the boundary checks for ongoing change approval.

## Validation Targets

- CI fails when a package member drops the required contract.
- CI fails when a cross-boundary import is introduced without a rule.
- Non-conforming names are visible in an inventory before they are changed.
- The docs and the enforcement rules describe the same target state.

## Closure Criteria

- The naming contract is explicit and testable.
- The pnpm workspace contract is enforced in CI.
- Boundary violations fail early, not after merge.
- Legacy names and package contracts are inventoried and tracked.

## Cross-References

- Status index: [README.md](README.md)
- Monorepo SSOT: [../MONOREPO.md](../MONOREPO.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
