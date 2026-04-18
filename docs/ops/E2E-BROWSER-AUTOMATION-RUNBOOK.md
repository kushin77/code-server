# Deterministic Browser Automation Kit Runbook

Objective:
- Provision and validate the deterministic Playwright browser automation kit for the E2E service-account path.

Scope:
- Applies to the E2E kit scaffold created by [scripts/ci/setup-e2e-playwright.sh](../../scripts/ci/setup-e2e-playwright.sh).
- Uses the deterministic fixture and artifact layout stored inside the E2E workspace directory.

Prerequisites:
- Node.js available for browser automation.
- Playwright install permitted for the target workspace.
- VPN gate satisfied for production E2E execution.

Workflow:
1. Scaffold the kit.
   - `bash scripts/ci/setup-e2e-playwright.sh`

2. Validate the scaffold without network installs when you only need structure proof.
   - `E2E_SKIP_NPM_INSTALL=1 bash scripts/ci/setup-e2e-playwright.sh`

3. Validate the kit contract.
   - `bash scripts/ci/validate-e2e-playwright-kit.sh`

4. Run production E2E when the VPN gate passes.
   - `bash scripts/ci/check-vpn-gate.sh`
   - `cd tests/e2e && npx playwright test`

Shared fixture policy:
- Keep browser context deterministic: locale, timezone, viewport, and rendering defaults must not vary by host.
- Put reusable browser helpers in `fixtures/` instead of embedding them in each test.

Artifact policy:
- Write reports and traces under `artifacts/` in the kit workspace.
- Keep outputs ephemeral unless they are attached as evidence to an issue or PR.
- Prefer JSON and HTML reports; keep screenshots and traces for failures only.

Fallback policy:
- Playwright is the primary browser engine.
- Puppeteer is a local fallback only when Playwright setup is blocked.
- Both engines must use the same deterministic fixture and artifact layout.

Validation criteria:
- Setup script creates package, config, fixtures, artifact standards, and fallback policy.
- Validator passes on a fresh temporary workspace.
- VPN gate passes before production E2E execution.