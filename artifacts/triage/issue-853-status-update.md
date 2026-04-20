Status update for #853 (implementation completed):

I implemented and validated the test-failure log-to-issue routing path for unit, integration, and authenticated failover E2E workflows.

What was added:
- scripts/ops/test-failure-triage.sh
	- Parses Playwright JSON and deterministic flake JSON inputs.
	- Computes deterministic failure fingerprints and routes by create-or-update semantics.
	- Escalates severity to P1 for auth/login/failover/continuity suites.
	- Adds recurrence comments when the same fingerprint reappears.
- .github/workflows/TEMPLATE-ci-tests.yml
	- Added issues: write permission.
	- Added failure routing steps for unit and integration jobs.
- .github/workflows/e2e-authenticated-failover-continuity.yml
	- Added issues: write permission.
	- Added failure routing step using Playwright JSON when present.
- scripts/README.md
	- Added documentation entry for scripts/ops/test-failure-triage.sh.

Validation evidence:
- bash -n scripts/ops/test-failure-triage.sh (syntax check passed)
- Dry-run execution produced expected severity and fingerprint output:
	- Severity: P1
	- Fingerprint: 18726001d697
	- Title format: [fingerprint] priority + suite context

Conclusion:
- #853 is now ready to close: fingerprint-keyed issue lifecycle and critical auth-flow escalation are wired into CI/E2E workflow failure paths.
