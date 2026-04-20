# Issue #932 Remediation Evidence

Generated: "2026-04-20T00:38:30Z"

## Scope implemented
- Retired shim policy enforced for:
  - scripts/common-functions.sh (archived marker-only stub)
  - scripts/logging.sh (archived marker-only stub)
- Canonical active script surfaces preserved:
  - scripts/code-server-entrypoint.sh
  - scripts/git-credential-gsm
  - scripts/ops/drift-detect.sh
- CI guard updated and enforced:
  - scripts/ci/check-deprecated-script-shims.sh
  - .github/workflows/deprecated-script-shims-guard.yml
- Related governance/docs alignment:
  - scripts/ci/check-error-handling-consistency.sh (removed shim exception)
  - scripts/ci/detect-duplicate-helpers.sh (removed shim exclusion)
  - .pre-commit-hooks.yaml (removed shim skip clauses)
  - docs/SHARED-LIBRARIES.md (retired-to-archive-stub policy)
  - scripts/_common/README.md (retired-to-archive-stub policy)

## Validation
Command:
- bash scripts/ci/check-deprecated-script-shims.sh

Result:
- PASS (Deprecated script shim guard passed)

Artifact:
- artifacts/triage/issue-932-deprecated-shim-guard.log
