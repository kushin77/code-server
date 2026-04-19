# Playwright Storage State Provisioning (#750)

## Purpose

Provision non-interactive authenticated Playwright storage state for authenticated continuity tests (#733).

A Playwright storage state is a JSON snapshot of browser cookies, local storage, and session data from an authenticated browser session. This enables tests to run in headless/non-interactive mode without requiring interactive login.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Phase 1: Local Capture (one-time, operator machine)                │
│                                                                      │
│  E2E Account Credentials                                            │
│         ↓                                                             │
│  scripts/ci/capture-playwright-storage-state.sh                     │
│         ↓                                                             │
│  playwright-storage-state.json (unencrypted, local)                 │
│         ↓                                                             │
│  scripts/ci/prepare-playwright-storage-state.sh                     │
│         ↓                                                             │
│  PLAYWRIGHT_STORAGE_STATE_B64 (base64 single-line)                  │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ Phase 2: Repository Secret Storage                                  │
│                                                                      │
│  GitHub Settings → Secrets                                          │
│         ↓                                                             │
│  PLAYWRIGHT_STORAGE_STATE_B64 (ephemeral per job, cleaned up)       │
│         ↓                                                             │
│  Workflow: e2e-authenticated-failover-continuity.yml                │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **E2E Service Account**: A test user account with access to `ide.kushnir.cloud`.
   - Google account (recommended): Configured in OAuth2 provider
   - Or local account if running against local authentication

2. **Credentials Storage**: E2E account credentials stored securely:
   - In GSM (preferred for production)
   - In local `.env` (for local development only, not committed)
   - As GitHub Org secret (for workflow access)

3. **Playwright**: Node.js and Playwright installed locally (run scripts/ci/setup-e2e-playwright.sh)

## Provisioning Process

### Step 1: Capture Storage State Locally

Run the capture script with E2E credentials:

```bash
# Password-based authentication (Google OAuth)
E2E_USER_EMAIL=e2e-test@bioenergystrategies.com \
E2E_USER_PASSWORD='your-password' \
TARGET_URL=https://ide.kushnir.cloud \
bash scripts/ci/capture-playwright-storage-state.sh
```

This will:
1. Launch a headless Chromium browser
2. Navigate to the OAuth login flow
3. Authenticate with the provided credentials
4. Capture the resulting storage state (cookies, tokens, localStorage)
5. Save to `/tmp/playwright-storage-state.json`

### Step 2: Encode Storage State to Base64

Prepare the single-line base64 payload:

```bash
bash scripts/ci/prepare-playwright-storage-state.sh /tmp/playwright-storage-state.json
```

Copy the output (a single long base64 string).

### Step 3: Store as GitHub Secret

Create or update the GitHub repository secret:

```bash
gh secret set PLAYWRIGHT_STORAGE_STATE_B64 --body "$(cat /tmp/playwright-storage-state.json | base64 -w 0)"
```

Or via GitHub web UI:
1. Settings → Secrets and variables → Actions
2. Create "PLAYWRIGHT_STORAGE_STATE_B64"
3. Paste the base64 string

### Step 4: Verify in Workflow

The workflow `.github/workflows/e2e-authenticated-failover-continuity.yml` will automatically:
1. Decode the secret from base64
2. Write to `/tmp/e2e-auth/storage-state.json`
3. Pass to the Playwright failover test

## When to Re-provision

- **Storage state expires**: (~7-30 days depending on provider policy)
- **E2E account password changes**: Immediately
- **OAuth tokens revoked**: Immediately
- **Regular rotation**: Monthly or per security policy

To refresh:
```bash
# Same capture command with new credentials
E2E_USER_EMAIL=... E2E_USER_PASSWORD=... bash scripts/ci/capture-playwright-storage-state.sh

# Re-encode and update secret
bash scripts/ci/prepare-playwright-storage-state.sh /tmp/playwright-storage-state.json
gh secret set PLAYWRIGHT_STORAGE_STATE_B64 --body "$(cat /tmp/playwright-storage-state.json | base64 -w 0)"
```

## Troubleshooting

### "Authentication form selectors not found"

The capture script uses standard Google OAuth selectors. If selectors don't match:
1. Check the actual login form HTML
2. Update the selectors in `scripts/ci/capture-playwright-storage-state.sh`
3. Test locally with `HEADLESS=false` to see the browser UI

### "Storage state already invalid"

If the storage state has expired:
1. Re-run capture with fresh E2E credentials
2. Re-encode and update the GitHub secret
3. Re-run the workflow

### "Workflow fails with 'PLAYWRIGHT_STORAGE_STATE_B64 secret is not set'"

1. Verify the secret was created in the repo
2. Check the secret value is valid base64 (run `echo "value" | base64 -d | head`)
3. Verify the workflow runs in the correct repository context

## Related Issues

- #733: Validated authenticated code-server session continuity with Playwright during failover
- #710: P0 EPIC - Stateful code-server failover

## References

- [Playwright Storage State Documentation](https://playwright.dev/docs/api/class-browsercontext#browser-context-storage-state)
- [Authenticated Failover Continuity Runbook](./AUTHENTICATED-FAILOVER-CONTINUITY-733.md)
- [E2E Browser Automation Runbook](./E2E-BROWSER-AUTOMATION-RUNBOOK.md)
