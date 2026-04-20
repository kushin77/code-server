Status update for #867 (code smell audit gate):

Implemented in this cycle:
- Added code smell governance script:
  - scripts/ci/check-code-smells.sh
- Added dedicated CI workflow gate:
  - .github/workflows/code-smell-governance.yml
- Extended guard with unused-export and complexity lanes:
  - ts-prune execution for apps/frontend and apps/extensions/agent-farm
  - explicit complexity threshold enforcement (max complexity: 10)

What the new guard enforces:
- ESLint strict mode (zero warnings) for active TS app surfaces when pnpm is available
- ts-prune unused-export checks for active TS app surfaces
- complexity threshold checks via ESLint rule override (`complexity <= 10`)
- No unexplained eslint-disable or noqa markers
- TODO/FIXME/HACK comment markers must include an issue reference

Validation run results in this workspace:
- Syntax validation: `bash -n scripts/ci/check-code-smells.sh` (pass)
- Full audit now reports all enforced lanes and currently fails only for local tooling availability:
  - ESLint strict lane: blocked locally (`pnpm` missing in this shell)
  - ts-prune lane: blocked locally (`pnpm` missing in this shell)
  - complexity lane: blocked locally (`pnpm` missing in this shell)
  - suppression hygiene: pass
  - TODO hygiene: pass
- CI workflow still installs pnpm before running the guard, so these lanes execute there even when local shell lacks pnpm

Additional remediation completed:
- Annotated outstanding TODO markers with issue reference in src/services/shared-workspace-acl/index.ts
- Tightened TODO detector to only match actual TODO/FIXME/HACK comment markers (not plain text mentions)

Current closure status:
- Keep #867 OPEN until CI run evidence confirms these new lanes execute end-to-end in workflow context and reports are captured from Actions artifacts.
