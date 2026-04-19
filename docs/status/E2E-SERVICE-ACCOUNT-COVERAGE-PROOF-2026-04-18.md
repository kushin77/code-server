# E2E Service Account Coverage Proof — 2026-04-18

Purpose:
- Capture proof that the dedicated E2E service-account profile is validated by a deterministic coverage checker and CI workflow.

Artifacts:
- [config/e2e-service-account-profile.yml](../../config/e2e-service-account-profile.yml)
- [scripts/ci/validate-e2e-profile-coverage.sh](../../scripts/ci/validate-e2e-profile-coverage.sh)
- [.github/workflows/e2e-profile-coverage.yml](../../.github/workflows/e2e-profile-coverage.yml)

Verified commands:
1. Local validator
   - `bash scripts/ci/validate-e2e-profile-coverage.sh`
   - Result: passed with all required capabilities and release-gate flags present.

Coverage facts:
- The profile contains the expected dedicated service-account identity.
- VPN is required for the production E2E path.
- Critical capabilities are explicitly marked and release-gate enforcement is enabled.
- The coverage script is idempotent and file-based; it does not require ephemeral network state.

Operational note:
- The validator proves the coverage contract is present and enforced.
- Full browser-run production evidence still belongs to the broader E2E program, but the regression coverage gate itself is now implemented and validated.