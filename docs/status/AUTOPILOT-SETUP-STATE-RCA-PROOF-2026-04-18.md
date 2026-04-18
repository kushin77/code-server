# Autopilot Setup-State RCA Proof — 2026-04-18

Purpose:
- Capture proof that the setup-state RCA, regression matrix, and reconciler report contract are validated by a deterministic local checker and CI workflow.

Artifacts:
- [docs/ops/AUTOPILOT-SETUP-STATE-RCA.md](../../docs/ops/AUTOPILOT-SETUP-STATE-RCA.md)
- [docs/ops/AUTOPILOT-SETUP-STATE-REGRESSION-MATRIX.md](../../docs/ops/AUTOPILOT-SETUP-STATE-REGRESSION-MATRIX.md)
- [scripts/ci/validate-autopilot-setup-state-reconciler.sh](../../scripts/ci/validate-autopilot-setup-state-reconciler.sh)
- [.github/workflows/autopilot-setup-state-reconciler.yml](../../.github/workflows/autopilot-setup-state-reconciler.yml)
- [docs/ops/AUTOPILOT-SETUP-STATE-RUNBOOK.md](../../docs/ops/AUTOPILOT-SETUP-STATE-RUNBOOK.md)

Verified commands:
1. Reconciler validation
   - `bash scripts/ci/validate-autopilot-setup-state-reconciler.sh`
   - Result: passed.

Coverage facts:
- The RCA documents the root causes and mitigation strategy for stale setup prompts.
- The regression matrix enumerates the canonical reason codes and expected remediation behavior.
- The validator will check the report schema and the drift guard together so the contract stays immutable.
- The workflow enforces the same validation on changes to the reconciler, runbook, matrix, and proof artifacts.

Operational note:
- This proof is file-based and can be regenerated without transient network state once the validator is executed.