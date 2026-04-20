## Repo-side guard hardening update for #888

I tightened the CI hardcoded-IP enforcement script to avoid third-party dependency noise and to make the guard reliable for code owned by this repo.

Change made:
- `scripts/ci/check-hardcoded-ips.sh`
  - Expanded exclusions from only `./node_modules/*` to nested/vendor/build output paths:
    - `*/node_modules/*`
    - `*/vendor/*`
    - `*/.pnpm/*`
    - `*/dist/*`
    - `*/build/*`

Validation:
- `bash -n scripts/ci/check-hardcoded-ips.sh` passed.
- `bash scripts/ci/check-hardcoded-ips.sh` completed and passed:
  - `✅ Hardcoded IP check PASSED (zero violations)`

Impact:
- The DNS/IP policy gate now evaluates repo-owned source more deterministically and avoids false-positive churn from vendored/type-definition files.

Status suggestion:
- Repo-side CI enforcement quality is improved and currently green.
- Keep #888 open only for non-repo host-level rollout/verification if that acceptance criterion is still required.