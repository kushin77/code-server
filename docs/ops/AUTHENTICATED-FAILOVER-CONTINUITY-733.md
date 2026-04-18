# Authenticated Session Failover Continuity Testing (#733)

## Purpose

Validate that authenticated code-server users do not experience service interruption when the infrastructure undergoes failover (e.g., primary host failure → replica takeover).

This is a critical P1 test for #710 (Stateful Code-Server Failover), ensuring that developers can continue working without interruption during infrastructure transitions.

## Architecture

### High-Level Test Flow

```
┌──────────────────────────────────────────────────────────────┐
│ Phase 1: Pre-Failover (Authenticated Session)                │
│                                                               │
│  User has valid cookies/tokens loaded from PLAYWRIGHT_STORAGE_STATE  │
│  Navigate to ide.kushnir.cloud and verify authenticated access        │
│  (Not redirected to OAuth)                                             │
└──────────────────────────────────────────────────────────────┘

            ↓  (wait FAILOVER_WAIT_MS = 45 seconds)

┌──────────────────────────────────────────────────────────────┐
│ Phase 2: Failover Window (Infrastructure Change)            │
│                                                               │
│  During wait window:                                          │
│  - Primary host may crash/become unavailable                  │
│  - DNS/load balancer redirects to replica                     │
│  - Replica assumes primary role                               │
│  (externally triggered; test is passive observer)             │
└──────────────────────────────────────────────────────────────┘

            ↓  (reload page to reconnect to new backend)

┌──────────────────────────────────────────────────────────────┐
│ Phase 3: Post-Failover (Session Continuity Validation)      │
│                                                               │
│  After reload:                                                │
│  ✅ Session cookies/tokens still valid                        │
│  ✅ Not redirected to OAuth login                             │
│  ✅ Can make authenticated API calls                          │
│  ✅ User context (/api/me) returns correct user              │
│  ✅ Multiple failover cycles work                             │
└──────────────────────────────────────────────────────────────┘
```

## Test Suites

### 1. Authenticated Session Persistence (`authenticated-session-persistence.spec.ts`)

**Baseline tests** that verify the core authenticated session works normally (no failover):

| Test | Purpose | Validates |
|------|---------|-----------|
| `authenticated context loads without OAuth redirect` | Session works at app startup | Cookies/tokens loaded from storage state |
| `authenticated session persists across page reload` | Session survives normal page reload | Reload doesn't lose auth |
| `authenticated session includes valid cookies` | Session has auth-related cookies | OAuth2-proxy, session, or similar cookies present |
| `authenticated session has localStorage tokens` | App-level storage is populated | localStorage data present if app uses it |
| `authenticated user can navigate protected routes` | Protected API endpoints work | /api/health responds without auth error |
| `authenticated context survives browser restart` | New pages in same context share auth | Cookie inheritance works |

**When to run**: Every PR, every deployment, as a smoke test.

### 2. Failover Session Continuity (`failover-session-continuity.spec.ts`)

**Failover-specific tests** that validate session survives infrastructure transitions:

| Test | Purpose | Validates |
|------|---------|-----------|
| `maintains authentication across short failover window (45s)` | Core failover scenario | Not redirected to OAuth after failover |
| `preserves session cookies through failover boundary` | Cookies survive failover | Auth-related cookies present before/after |
| `can make authenticated API calls post-failover` | APIs work after failover | /api/health doesn't return 401 |
| `handles multiple failover cycles` | Repeated failovers don't break session | 2+ failover cycles handled correctly |
| `authenticated session endpoint responds correctly` | User context preserved | /api/me returns user info or succeeds |

**When to run**: 
- During failover drills (manual workflow_dispatch)
- As part of failover testing in test environment
- NOT required on every PR (only when failover code changes)

### 3. Unauthenticated Failover (Control Test)

**Control test** to ensure OAuth redirects still work during failover:

| Test | Purpose | Validates |
|------|---------|-----------|
| `unauthenticated user is redirected to OAuth before/after failover` | OAuth not bypassed | User without cookies → OAuth login before AND after failover |

**Purpose**: Proves that failover itself doesn't break auth security—unauthenticated users still can't bypass the OAuth layer.

## Running the Tests

### Option A: Local Development (Fast Iteration)

Requires local E2E account credentials and Playwright installed:

```bash
# 1. Capture storage state once (one-time setup)
E2E_USER_EMAIL=e2e@example.com \
E2E_USER_PASSWORD='password' \
bash scripts/ci/capture-playwright-storage-state.sh

# 2. Run tests locally
cd tests/e2e
PLAYWRIGHT_STORAGE_STATE=/tmp/playwright-storage-state.json \
TEST_BASE_URL=https://ide.kushnir.cloud \
npx playwright test specs/authenticated-session-persistence.spec.ts

# 3. For failover tests (requires actual failover or mock)
FAILOVER_WAIT_MS=5000 \
PLAYWRIGHT_STORAGE_STATE=/tmp/playwright-storage-state.json \
TEST_BASE_URL=https://ide.kushnir.cloud \
npx playwright test specs/failover-session-continuity.spec.ts
```

### Option B: CI Workflow (Production Testing)

Trigger via GitHub Actions:

```bash
# Dispatch workflow via GitHub CLI
gh workflow run e2e-authenticated-failover-continuity.yml \
  --ref main \
  -f failover_wait_ms=45000

# Or via GitHub Web UI
# Actions → E2E Authenticated Failover Continuity → Run workflow
```

**Prerequisites:**
- Repository secret `PLAYWRIGHT_STORAGE_STATE_B64` must be set (see #750)
- Workflow has access to test URL `https://ide.kushnir.cloud`
- Test runs on `self-hosted` runner (has network access to ide.kushnir.cloud)

### Option C: Failover Drill with External Trigger

Trigger an actual failover during the test:

```bash
gh workflow run e2e-authenticated-failover-continuity.yml \
  --ref main \
  -f failover_wait_ms=60000 \
  -f failover_trigger_cmd='bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action promote'
```

This will:
1. Start the failover continuity tests
2. During the 60-second wait, execute the failover promotion command
3. Validate that the session survives the actual failover

## Configuration

### Environment Variables

| Variable | Purpose | Example | Default |
|----------|---------|---------|---------|
| `TEST_BASE_URL` | Target service URL | `https://ide.kushnir.cloud` | `https://ide.kushnir.cloud` |
| `PLAYWRIGHT_STORAGE_STATE` | Path to authenticated storage state JSON | `/tmp/e2e-auth/storage-state.json` | `./storage-state.json` |
| `FAILOVER_WAIT_MS` | How long to wait for failover (ms) | `45000` | `45000` |
| `FAILOVER_TRIGGER_CMD` | Optional command to trigger failover | `bash scripts/.../failover.sh` | (none) |
| `HEADLESS` | Run browser in headless mode | `true` or `false` | `true` |

### Playwright Config (`tests/e2e/playwright.config.ts`)

The config is auto-generated by `scripts/ci/setup-e2e-playwright.sh` and includes:
- **Timeout**: 30 seconds per test
- **Retries**: 2 in CI, 0 locally
- **Output**: Screenshots on failure, HTML report
- **Projects**: Chromium only (single browser for determinism)

## Test Results Interpretation

### Success Criteria

All tests pass if:
```
✅ authenticated-session-persistence.spec.ts: 6 tests passed
✅ failover-session-continuity.spec.ts: 5 tests passed
✅ unauthenticated-failover (control): 1 test passed
───────────────────────────────────────
   12 tests passed in ~2-3 minutes
```

### Common Failures

| Error | Cause | Resolution |
|-------|-------|-----------|
| `PLAYWRIGHT_STORAGE_STATE_B64 secret is not set` | Secret missing from repo | See #750: Provision storage state |
| `base64: invalid input` | Secret value corrupted | Re-encode with `prepare-playwright-storage-state.sh` |
| `Navigation timed out to oauth2` | Auth redirect not working | Check OAuth2-proxy config, TLS cert |
| `Not authenticated after failover` | Session not surviving failover | Check cookie domain/path, Redis persistence |
| `Playwright not installed` | Setup script didn't run | Run `setup-e2e-playwright.sh` first |

### Artifact Collection

After workflow runs, artifacts are uploaded:
- `playwright-report/` — HTML report (screenshots, traces, details)
- `e2e-results.json` — Machine-readable summary
- Screenshots of failures (in HTML report)

Access via: Actions → Workflow run → Artifacts

## Related Issues

- **#710**: P0 EPIC - Stateful code-server failover (parent issue)
- **#750**: Playwright storage-state provisioning (dependency)
- **#733**: This issue — authenticated continuity testing

## Checklist for Implementation

- [x] Authenticated session persistence spec created
- [x] Failover continuity spec created
- [x] Unauthenticated control test created
- [x] Playwright test config ready
- [x] CI workflow configured
- [ ] Storage state provisioned (#750 must complete first)
- [ ] Workflow tested end-to-end
- [ ] Documentation complete (this file)

## Next Steps

1. **#750 Completion**: Provision `PLAYWRIGHT_STORAGE_STATE_B64` secret with actual E2E account
2. **Workflow Dispatch**: Trigger workflow manually to verify all tests pass
3. **Failover Drill**: Run with `failover_trigger_cmd` to validate against real failover
4. **Automation**: Add to post-deployment verification jobs (#710)

## References

- [Playwright Storage State Provisioning (#750)](./PLAYWRIGHT-STORAGE-STATE-PROVISIONING-750.md)
- [Playwright Docs: Browser Context Storage State](https://playwright.dev/docs/api/class-browsercontext#browser-context-storage-state)
- [Stateful Failover P0 Epic (#710)](https://github.com/kushin77/code-server/issues/710)


## Troubleshooting

- `PLAYWRIGHT_STORAGE_STATE_B64 secret is not set`:
  - Add repository secret and re-run.
- Storage state expired:
  - Re-capture auth state and update secret.
- Runner cannot trigger failover:
  - Leave `failover_trigger_cmd` empty and execute failover manually in parallel, then re-run with the same timing window.