# Monorepo Architecture and Dependency Governance

This document is the monorepo SSOT for workspace boundaries and dependency management.

## Workspace Model

- Root orchestrates shared tooling, CI policy, and governance checks.
- Domain-specific packages/services should live in dedicated subtrees with clear ownership.
- Shared libraries must be reused instead of duplicated helpers.

## Dependency Rules

1. Use pinned versions for production-critical dependencies.
2. Keep dependency ownership visible per package or service.
3. Consolidate duplicate dependencies to reduce drift.
4. Add or update lockfiles only through package manager workflows.
5. Require CI validation for dependency graph and policy checks.

## Package Manager and Workspace

- Workspace manager: `pnpm` (`pnpm-workspace.yaml`)
- Root dependency metadata: `package.json`
- Lockfile SSOT: `pnpm-lock.yaml`

## Governance Requirements

- No duplicate helper implementations when canonical shared libs exist.
- New scripts must follow metadata header policy.
- Configuration values must come from env/config SSOT, not hardcoded literals.
- Security-sensitive dependency changes require explicit review evidence.
- Shared helper entrypoints and their exports are documented in [SHARED-LIBRARIES.md](SHARED-LIBRARIES.md).

## Operational Checklist for Dependency Changes

- [ ] Dependency rationale documented in issue or PR
- [ ] Version pinned and lockfile updated
- [ ] No duplicate transitive additions without justification
- [ ] CI policy and test suites pass
- [ ] Rollback strategy defined for runtime-impacting upgrades

## References

- Workspace governance index: [governance/elite-best-practices/README.md](governance/elite-best-practices/README.md)
- Existing monorepo plan: [governance/elite-best-practices/monorepo/MONOREPO-PNPM-PLAN.md](governance/elite-best-practices/monorepo/MONOREPO-PNPM-PLAN.md)
- Documentation SSOT map: [structure/README.md](structure/README.md)
