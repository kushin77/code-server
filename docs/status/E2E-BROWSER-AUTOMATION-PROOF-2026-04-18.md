# Deterministic Browser Automation Kit Proof — 2026-04-18

Purpose:
- Capture proof that the deterministic Playwright browser automation kit is scaffolded, validated, and governed by an explicit artifact standard.

Artifacts:
- [scripts/ci/setup-e2e-playwright.sh](../../scripts/ci/setup-e2e-playwright.sh)
- [scripts/ci/validate-e2e-playwright-kit.sh](../../scripts/ci/validate-e2e-playwright-kit.sh)
- [.github/workflows/e2e-playwright-kit.yml](../../.github/workflows/e2e-playwright-kit.yml)
- [docs/ops/E2E-BROWSER-AUTOMATION-RUNBOOK.md](../../docs/ops/E2E-BROWSER-AUTOMATION-RUNBOOK.md)

Verified commands:
1. Scaffold validation
   - `bash scripts/ci/validate-e2e-playwright-kit.sh`
   - Result: passed in a temporary workspace.

2. Ephemeral setup validation
   - `E2E_SKIP_NPM_INSTALL=1 bash scripts/ci/setup-e2e-playwright.sh`
   - Result: generated the kit scaffold without performing network installs.

Coverage facts:
- The kit now creates shared deterministic fixtures.
- The kit now writes artifacts under a dedicated artifact directory with explicit standards.
- The kit includes a fallback policy that keeps Playwright primary and Puppeteer secondary.
- The runbook documents the setup, validation, and production execution path.

Operational note:
- The validator uses a temporary workspace, so it remains immutable and ephemeral by design.