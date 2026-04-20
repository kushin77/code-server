## E2E: Session Persistence and Failover Scenarios

### Objective
Comprehensive E2E testing for session persistence across browser events, network disruptions, and host failover scenarios.

### Current State
- `authenticated-session-persistence.spec.ts`: Basic session tests
- `failover-session-continuity.spec.ts`: Basic failover tests
- **Gap**: Edge cases, multi-host failover, data consistency

### Target Test Matrix (15+ tests)

#### Session Persistence (6 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 1 | `session-survives-refresh` | Session valid after page refresh |
| 2 | `session-survives-tab-close` | Session valid in new tab (same browser) |
| 3 | `session-survives-browser-restart` | Session valid after browser restart |
| 4 | `session-expires-after-timeout` | Session expires after configured TTL |
| 5 | `session-logout-clears-all` | Logout clears session on all tabs |
| 6 | `session-concurrent-tabs` | Multiple tabs share session state |

#### Network Disruption (4 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 7 | `network-brief-disconnect` | Session survives <30s network drop |
| 8 | `network-reconnect-resumes` | Work resumes after reconnect |
| 9 | `network-offline-mode` | Graceful degradation in offline mode |
| 10 | `network-websocket-reconnect` | WebSocket reconnects after drop |

#### Host Failover (5 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 11 | `failover-primary-down` | Session continues on replica (.42) |
| 12 | `failover-session-transfer` | OAuth cookies valid on both hosts |
| 13 | `failover-workspace-preserved` | IDE workspace state preserved |
| 14 | `failover-no-relogin` | User not prompted to re-login |
| 15 | `failover-data-consistency` | No data loss during failover |

### Implementation

**File**: `tests/e2e/specs/session-failover-comprehensive.spec.ts`

```typescript
import { test, expect } from '../fixtures/auth-fixture';

const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
const PRIMARY_HOST = '192.168.168.31';
const REPLICA_HOST = '192.168.168.42';

test.describe('Session Persistence', () => {
  test.use({ storageState: 'tests/e2e/.auth/qa-storage-state.json' });

  test.describe('Browser Events', () => {
    test('session survives page refresh', async ({ page }) => {
      // Login and navigate to IDE
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Refresh page
      await page.reload();
      
      // Should NOT redirect to login
      await expect(page).not.toHaveURL(/oauth2|accounts\.google\.com/);
      await page.waitForSelector('.monaco-workbench');
    });

    test('multiple tabs share session', async ({ page, context }) => {
      // Open first tab
      await page.goto(PORTAL_URL);
      
      // Open second tab
      const page2 = await context.newPage();
      await page2.goto(IDE_URL);
      
      // Both should be authenticated
      await expect(page).not.toHaveURL(/oauth2/);
      await expect(page2).not.toHaveURL(/oauth2/);
      
      await page2.close();
    });

    test('logout clears session on all tabs', async ({ page, context }) => {
      // Open two tabs
      await page.goto(PORTAL_URL);
      const page2 = await context.newPage();
      await page2.goto(IDE_URL);
      
      // Logout on first tab
      await page.goto(`${PORTAL_URL}/oauth2/sign_out`);
      
      // Refresh second tab
      await page2.reload();
      
      // Should redirect to login
      await page2.waitForURL(/oauth2|accounts\.google\.com/);
      
      await page2.close();
    });
  });

  test.describe('Network Disruption', () => {
    test('session survives brief network drop', async ({ page, context }) => {
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Simulate network offline
      await context.setOffline(true);
      await page.waitForTimeout(5000); // 5 second offline
      
      // Restore network
      await context.setOffline(false);
      
      // Refresh and verify session
      await page.reload();
      await expect(page).not.toHaveURL(/oauth2/);
    });
  });
});

test.describe('Host Failover', () => {
  // These tests require infrastructure coordination
  // They simulate primary host failure and verify replica takeover
  
  test.skip('session continues on replica after primary down', async ({ page }) => {
    // This test requires:
    // 1. Establish session on primary host
    // 2. Trigger primary host failure (via API or SSH)
    // 3. Verify session continues on replica
    // 4. Restore primary host
    
    // Implementation depends on failover infrastructure
  });

  test('OAuth cookies valid across both hosts', async ({ page }) => {
    // Navigate to portal
    await page.goto(PORTAL_URL);
    
    // Get cookies
    const cookies = await page.context().cookies();
    const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
    
    // Verify cookie domain allows both hosts
    expect(oauthCookie?.domain).toMatch(/\.kushnir\.cloud|kushnir\.cloud/);
  });
});
```

### Failover Test Infrastructure

For true failover testing, we need:

```bash
# scripts/ci/failover-test-orchestrator.sh

# Step 1: Establish baseline session
E2E_USER_EMAIL=qa@kushnir.cloud npx playwright test --grep "login"

# Step 2: Simulate primary failure
ssh akushnir@192.168.168.31 "docker-compose stop code-server"

# Step 3: Run failover validation tests
npx playwright test --grep "failover"

# Step 4: Restore primary
ssh akushnir@192.168.168.31 "docker-compose start code-server"

# Step 5: Run failback tests
npx playwright test --grep "failback"
```

### Redis Session Validation

During failover, verify Redis Sentinel promotes replica:

```typescript
test('Redis Sentinel failover preserves sessions', async ({ page }) => {
  // 1. Login and get session cookie
  await page.goto(PORTAL_URL);
  const cookies = await page.context().cookies();
  const sessionId = cookies.find(c => c.name === '_oauth2_proxy')?.value;
  
  // 2. Verify session exists in Redis (via API or direct query)
  // This requires a test endpoint or Redis client
  
  // 3. Trigger Redis master failover
  // ssh akushnir@192.168.168.31 "redis-cli DEBUG SLEEP 60"
  
  // 4. Wait for Sentinel promotion (<30s)
  await page.waitForTimeout(30000);
  
  // 5. Verify session still valid
  await page.reload();
  await expect(page).not.toHaveURL(/oauth2/);
});
```

### Definition of Done

- [ ] 15+ session/failover tests implemented
- [ ] Browser event persistence verified
- [ ] Network disruption handling tested
- [ ] Host failover scenarios validated
- [ ] Redis Sentinel failover tested
- [ ] No session loss during failover
- [ ] Tests stable and documented

Parent: #982
Depends on: #957 (Redis HA), #958 (Dual-host Caddy)
Related: #960 (CSRF resilience), #964 (E2E Playwright suite)
