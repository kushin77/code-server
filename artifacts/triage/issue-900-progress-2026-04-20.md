## Progress update for #900 (GitHub Free maximization)

Implemented in this pass:

- Pinned all previously mutable GitHub Action refs in the targeted cost/governance workflows:
  - `.github/workflows/docs-standards-enforcement.yml`
  - `.github/workflows/docker-storage-hygiene.yml`
  - `.github/workflows/dependency-health-audit.yml`
  - `.github/workflows/deprecated-workflows-removed-guard.yml`
  - `.github/workflows/deprecated-docs-pointer-guard.yml`
- Additional pinning completed for remaining mutable refs discovered during verification:
  - `pnpm/action-setup@v2` -> `pnpm/action-setup@fc06bc1257f339d1d5d8b3a19a8cae5388b55320`
  - `actions/github-script@v7` -> `actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea`

Validation evidence:

- Repo workflow inventory snapshot:
  - `workflow_files=96`
  - `uses_entries=224`
  - `mutable_refs` was previously measured at `45` before pinning work
- Post-change verification:
  - `mutable_refs_remaining=0` across `.github/workflows/*.yml`
  - Targeted workflows no longer contain `@v4`, `@master`, or legacy mutable patterns

CI-minute trend evidence (available GH run metadata window):

- Available sample window from `gh run list --limit 2000`: `2026-04-19T19:36:59Z` to `2026-04-20T15:30:08Z`
- Runtime proxy used: `updatedAt - startedAt`
- First half: `1817 runs`, `150.12` total minutes, `0.083` min/run
- Second half: `183 runs`, `24.92` total minutes, `0.136` min/run
- Result: minute/run trend in this sampled window is **not reduced** yet (`+63.86%`)

Current closure decision:

- Significant progress landed on security/cost-governance hardening (mutable refs eliminated).
- Keep #900 **OPEN** until we can provide measurable minute-usage reduction (or equivalent cost trend) over a stable comparison window and complete the issue-body checklist with that evidence.
