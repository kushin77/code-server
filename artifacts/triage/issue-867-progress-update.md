## Code smell audit progress update for #867

I removed a few low-risk lint issues and re-ran the guard so the issue now reflects real code debt, not just local tooling availability.

Remediation completed in this pass:
- `apps/extensions/agent-farm/src/ml/ResourceConstraintManager.ts`
  - Reduced allocation logic complexity by extracting `canAllocateWorkload(...)`.
  - The complexity hotspot reported by ESLint at `allocateResources` is now resolved at the source level.
- `apps/extensions/agent-farm/src/ml/QueryUnderstanding.ts`
  - Removed an unused parameter by making the stub helper parameterless.
- `apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts`
  - Removed unused function parameters/locals that were generating warnings.

Validation outcome after the cleanup:
- The audit now runs and reports only warnings, no errors, in the touched ML modules.
- `get_errors` is clean for the touched files.
- Remaining audit findings are concentrated in:
  - `apps/extensions/agent-farm/src/ml/EdgeOptimizationEngine.ts`
  - `apps/extensions/agent-farm/src/phases/*.test.ts`
  - `apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts`
  - `apps/extensions/agent-farm/src/phases/phase6/*.test.ts`

Interpretation:
- The original complexity error in `ResourceConstraintManager` has been addressed.
- The remaining blocker is now the broader set of warnings in the `agent-farm` phase/test surfaces, which need either direct cleanup or issue-linked suppression decisions.

Status:
- Keep #867 open.
- The issue is now narrowed to residual warnings in specific agent-farm source/test files rather than the original complexity hotspot plus tooling availability.