# External Browser QA Smoke Tests

This runbook defines external-network browser validation for portal and IDE access.

## Quick Start

Use this path when you need a fast operator check and do not need the full evidence bundle yet.

1. Confirm the target host, VPN path, and QA account.
2. Open the portal URL, sign in, and confirm the requested page loads after redirect.
3. Open the IDE URL, sign in, and confirm the editor or landing page loads normally.
4. Verify one static asset and one interactive action on each surface.
5. Capture a short pass/fail summary before collecting the full evidence bundle.
6. Attach screenshots and the summary to the issue or PR.

## Preconditions

- Test from VPN or non-local network path.
- Use dedicated QA account from GSM or Vault (never repository-stored credentials).
- Confirm target environment and failover state before test start.

## Test Scope

- Portal login: `https://kushnir.cloud`
- IDE login: `https://ide.kushnir.cloud`
- Static asset delivery and post-login redirects
- Session behavior during controlled failover/failback
- Mobile browser sanity check

## Entry Criteria

- No active P0 incident
- Core services healthy on target host
- QA account validated and not expired

## Smoke Test Steps

1. Open portal URL and complete login.
2. Confirm no redirect loop and successful page render.
3. Open IDE URL and complete login.
4. Verify authenticated IDE load and editor interaction.
5. Validate static asset fetch status (200 for CSS/JS assets).
6. Execute controlled failover or simulated service move.
7. Re-check session continuity or expected re-auth behavior.
8. Validate mobile browser access for portal and IDE.

## Evidence to Capture

- Browser screenshots for portal and IDE login success
- Network trace or HAR snippet for static asset success
- Failover timestamp and observed session behavior
- Pass/fail checklist with tester and date

## Human-Readable Success Summary

Use this one-line summary format in issue comments or test notes:

- Portal: `pass` or `fail`, the login or redirect outcome, and one sentence about what the user sees next.
- IDE: `pass` or `fail`, the editor load outcome, and whether the requested destination was preserved.
- Recovery: `pass` or `fail`, whether the operator had to retry, and whether any manual cleanup was needed.

Example:

- Portal: pass, login succeeded, and the browser returned to the requested portal page.
- IDE: pass, the editor loaded, and the original destination was preserved.
- Recovery: pass, no retry was needed, and no manual cleanup was required.

## Exit Criteria

- Portal and IDE logins pass
- Static assets return expected status and content type
- Failover behavior matches documented expectation
- Evidence attached to related issue or PR

## Related Docs

- [OPERATIONS-INDEX.md](OPERATIONS-INDEX.md)
- [DISASTER-RECOVERY-PLAN.md](DISASTER-RECOVERY-PLAN.md)
- [INCIDENT-RESPONSE-PLAYBOOK.md](INCIDENT-RESPONSE-PLAYBOOK.md)
