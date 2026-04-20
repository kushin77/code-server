Status update for #850 (implementation completed):

I implemented the remaining lifecycle gap by wiring automated stale-issue closure into the shared fingerprint triage workflow while preserving reopen-on-recurrence behavior.

What was added:
- .github/workflows/error-triage.yml
  - Added `Auto-close stale fingerprint issues` step (`id: autoclose`).
  - Targets open issues that contain `error-triage-fingerprint:` markers.
  - Closes stale fingerprinted issues after 7 days without recurrence updates.
  - Supports dry-run mode (`workflow_dispatch` dry_run input).
  - Exposes `issues_closed` output and publishes it in the workflow summary table.

What was already in place and remains active:
- Fingerprint dedup marker routing (`error-triage-fingerprint`) for create-or-update behavior.
- Reopen-on-recurrence for previously closed fingerprint issues.

Validation evidence:
- Workflow diagnostics show the new auto-close step and summary wiring present:
  - Step name: `Auto-close stale fingerprint issues`
  - Step id: `autoclose`
  - Output key: `issues_closed`
  - Summary row: `Issues Auto-closed`
- Problem check reports no errors for `.github/workflows/error-triage.yml`.

Conclusion:
- #850 is ready to close: dedup suppression, create/update continuity, reopen-on-recurrence, and auto-close lifecycle execution are now all wired in the routing path.