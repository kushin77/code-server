# Authenticated Failover Continuity (#733)

Purpose:
- Provide the operational procedure to run authenticated Playwright failover continuity checks for `ide.kushnir.cloud`.

When to use:
- Before closing issue #733.
- During game-day or post-change validation where authenticated IDE session continuity must be proven.

## Preconditions

- Self-hosted runner can reach `https://ide.kushnir.cloud`.
- Workflow file exists: `.github/workflows/e2e-authenticated-failover-continuity.yml`.
- Script exists: `scripts/ci/run-playwright-failover-continuity.sh`.
- A valid Playwright storage state JSON for the E2E service account has been captured.

## Prepare Secret Payload

Run locally where the storage state JSON exists:

```bash
bash scripts/ci/prepare-playwright-storage-state.sh /path/to/storage-state.json
```

Copy the output and store as repository secret:

- Name: `PLAYWRIGHT_STORAGE_STATE_B64`
- Value: single-line base64 output from the helper script

## Execute Workflow

Trigger workflow manually:

- Workflow: `E2E Authenticated Failover Continuity`
- Inputs:
  - `failover_wait_ms`: default `45000`
  - `failover_trigger_cmd`: optional

Recommended failover trigger command (runner must have required host access):

```bash
docker stop keepalived >/dev/null; sleep 6; docker start keepalived >/dev/null
```

## Evidence Required for #733

- Workflow run URL
- Test summary (pass/fail)
- Continuity timing details from runner logs
- Note whether editor reconnect/save behavior was acceptable

## Troubleshooting

- `PLAYWRIGHT_STORAGE_STATE_B64 secret is not set`:
  - Add repository secret and re-run.
- Storage state expired:
  - Re-capture auth state and update secret.
- Runner cannot trigger failover:
  - Leave `failover_trigger_cmd` empty and execute failover manually in parallel, then re-run with the same timing window.