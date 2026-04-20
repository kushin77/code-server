## Code smell audit validation update for #867

I updated the code smell guard to support a pnpm fallback path in environments where pnpm is not directly on PATH, which allowed the audit to execute and surface real monorepo findings.

Guard update:
- `scripts/ci/check-code-smells.sh`
  - Added fallback runner selection:
    - direct `pnpm` when available
    - `npm exec --yes pnpm@latest --` fallback when pnpm is missing but npm is present
  - This keeps CI behavior intact while allowing local validation in more shells.

Validation result after fallback patch:
- The audit now executes and surfaces actual repository issues rather than failing on missing tooling.
- Current reported findings include:
  - ESLint warning: unused variable in `apps/extensions/agent-farm/src/ml/QueryUnderstanding.ts`
  - ESLint error: complexity 18 > max 10 in `apps/extensions/agent-farm/src/ml/ResourceConstraintManager.ts`
  - ESLint warnings: unused variables in `apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts` and test files
  - Additional warnings across phase/test files

Interpretation:
- The guard itself is working and is now proving there are still code-smell violations to remediate.
- #867 should remain open until the underlying complexity and unused-variable issues are actually fixed or intentionally suppressed with issue-linked rationale.

Net effect:
- Tooling blocker removed.
- Real repository debt is now visible and prioritized by the guard.