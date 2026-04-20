# Issue #903 Campaign Orchestration Evidence

Validated implementation updates:

- Added Puppeteer parity runner: `scripts/ci/run-kushnir-cloud-appsmith-login-puppeteer.sh`
- Added shared Puppeteer probe script: `scripts/ci/puppeteer-parity-probe.cjs`
- Wired Puppeteer phase into campaign runner summary and markdown output:
  - `puppeteer_parity` status block in JSON report
  - `## Puppeteer Parity` section in markdown report
- Added optional defect auto-fileing toggle to campaign runner:
  - `AUTO_FILE_DEFECTS=1` and `DEFECT_REPO`/`DEFECT_LABELS_CSV`
  - campaign failures can emit a defect issue and attach metadata paths
- Fixed profile-scaling bug so `CAMPAIGN_PROFILE=100x` now applies higher defaults when values are not explicitly set:
  - baseline request count -> 50
  - soak request count -> 100

Validation runs:

1. Smoke orchestration (optional heavy stages disabled)
   - `CAMPAIGN_BASENAME=resilience-campaign-smoke ... RUN_PUPPETEER_PARITY=0`
   - Result: campaign summary generated successfully.

2. Puppeteer parity path
   - `CAMPAIGN_BASENAME=resilience-campaign-puppeteer-check4 ... RUN_PUPPETEER_PARITY=1`
   - Result: `Puppeteer parity check passed`.

3. 100x profile behavior
   - `CAMPAIGN_PROFILE=100x CAMPAIGN_BASENAME=resilience-campaign-100x-check2 ...`
   - Result: baseline and soak counts elevated (`50` / `100`) as expected.

4. Authenticated + parity slice
   - `CAMPAIGN_BASENAME=resilience-campaign-auth-check RUN_AUTHENTICATED_SMOKE=1 AUTH_SMOKE_REQUIRE_QA_STORAGE_STATE=0 RUN_PUPPETEER_PARITY=1`
   - Result: authenticated smoke passed and Puppeteer parity passed in one campaign run.

Key artifacts:

- `artifacts/triage/resilience-campaign-auth-check.json`
- `artifacts/triage/resilience-campaign-auth-check.md`
- `artifacts/triage/resilience-campaign-auth-check-authenticated-smoke.log`
- `artifacts/triage/resilience-campaign-auth-check-puppeteer-parity.log`
- `artifacts/triage/resilience-campaign-100x-check2.json`

Status:

- Campaign runner supports baseline + 100x profile defaults.
- Authenticated smoke and Playwright flow remain integrated.
- Puppeteer parity coverage is integrated and executable.
- Campaign report includes per-phase pass/fail and defect-link field support.