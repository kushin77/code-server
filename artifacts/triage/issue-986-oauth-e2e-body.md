## E2E: OAuth Login Flow Comprehensive Validation

### Objective
Expand OAuth login test coverage from 2 tests to 20+ tests covering all authentication scenarios, error handling, and edge cases.

### Current State
- `oauth-login.spec.ts`: 2 smoke tests (redirect check, health endpoint)
- `kushnir-cloud-appsmith-login.spec.ts`: ~10 tests (redirect chains, static assets)
- **Gap**: No actual login completion, error handling, session validation

### Target Test Matrix

#### Happy Path Tests (8 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 1 | `oauth-login-complete` | Full OAuth flow: start → Google → callback → authenticated |
| 2 | `oauth-login-preserves-redirect` | Login preserves `rd=` parameter and redirects after auth |
| 3 | `oauth-login-sets-cookies` | Login sets all required cookies (_oauth2_proxy, XSRF-TOKEN) |
| 4 | `oauth-login-cookie-attributes` | Cookies have correct SameSite, Secure, HttpOnly flags |
| 5 | `oauth-login-session-valid` | Authenticated session remains valid for expected duration |
| 6 | `oauth-login-refresh-token` | Refresh token extends session without re-login |
| 7 | `oauth-login-cross-subdomain` | Session valid across kushnir.cloud and ide.kushnir.cloud |
| 8 | `oauth-login-idempotent` | Multiple login attempts don't create duplicate sessions |

#### Error Handling Tests (6 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 9 | `oauth-login-invalid-user` | Non-whitelisted user gets clear error message |
| 10 | `oauth-login-cancelled` | User cancels at Google prompt → graceful error |
| 11 | `oauth-login-expired-code` | Stale OAuth code rejected with retry guidance |
| 12 | `oauth-login-csrf-mismatch` | CSRF token mismatch blocked and logged |
| 13 | `oauth-login-network-timeout` | Google unreachable → timeout with retry option |
| 14 | `oauth-login-rate-limited` | Too many attempts → clear rate limit message |

#### Edge Cases (6 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 15 | `oauth-login-concurrent-sessions` | Multiple browser tabs don't interfere |
| 16 | `oauth-login-cookie-tampering` | Modified cookies invalidate session |
| 17 | `oauth-login-back-button` | Back button after login doesn't break session |
| 18 | `oauth-login-deep-link` | Direct access to /admin preserves redirect after login |
| 19 | `oauth-login-mobile-ua` | Login works with mobile user agent |
| 20 | `oauth-login-incognito` | Login works in incognito mode (no cached state) |

### Implementation

**File**: `tests/e2e/specs/oauth-login-comprehensive.spec.ts`

```typescript
import { test, expect } from '@playwright/test';

const QA_EMAIL = process.env.E2E_USER_EMAIL;
const QA_PASSWORD = process.env.E2E_USER_PASSWORD;
const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';

test.describe('OAuth Login Comprehensive', () => {
  
  test.describe('Happy Path', () => {
    test('complete OAuth flow results in authenticated session', async ({ page }) => {
      // Navigate to protected resource
      await page.goto(PORTAL_URL);
      
      // Should redirect to Google
      await page.waitForURL(/accounts\.google\.com/);
      
      // Enter QA credentials
      await page.fill('input[type="email"]', QA_EMAIL);
      await page.click('#identifierNext');
      await page.fill('input[type="password"]', QA_PASSWORD);
      await page.click('#passwordNext');
      
      // Should redirect back to portal
      await page.waitForURL(`${PORTAL_URL}/**`);
      
      // Verify authenticated state
      const cookies = await page.context().cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie).toBeDefined();
    });

    test('login sets secure cookie attributes', async ({ page }) => {
      // ... (login flow)
      
      const cookies = await page.context().cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      
      expect(oauthCookie?.secure).toBe(true);
      expect(oauthCookie?.httpOnly).toBe(true);
      expect(oauthCookie?.sameSite).toBe('Lax');
    });

    test('session valid across subdomains', async ({ page, context }) => {
      // Login to portal
      // ... (login flow to PORTAL_URL)
      
      // Navigate to IDE subdomain
      await page.goto(IDE_URL);
      
      // Should NOT redirect to Google (session shared)
      await expect(page).not.toHaveURL(/accounts\.google\.com/);
    });
  });

  test.describe('Error Handling', () => {
    test('non-whitelisted user gets clear error', async ({ page }) => {
      // This test uses a non-whitelisted test account
      // Expected: oauth2-proxy returns 403 with error message
    });

    test('CSRF mismatch blocked', async ({ page }) => {
      // Manipulate state parameter
      // Expected: oauth2-proxy rejects callback
    });
  });

  test.describe('Edge Cases', () => {
    test('cookie tampering invalidates session', async ({ page, context }) => {
      // ... (login flow)
      
      // Tamper with cookie
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      await context.addCookies([{
        ...oauthCookie,
        value: 'tampered_value'
      }]);
      
      // Navigate to protected resource
      await page.goto(PORTAL_URL);
      
      // Should redirect to login (session invalidated)
      await page.waitForURL(/oauth2|accounts\.google\.com/);
    });
  });
});
```

### Test Data Requirements

| Requirement | Source | Description |
|-------------|--------|-------------|
| QA user email | GSM: `qa-user-email` | Whitelisted test account |
| QA user password | GSM: `qa-user-password` | QA account password |
| Invalid user email | Hardcoded | `invalid-test@example.com` (not whitelisted) |

### Environment Variables

```bash
E2E_USER_EMAIL=qa@kushnir.cloud
E2E_USER_PASSWORD=[from GSM]
PORTAL_BASE_URL=https://kushnir.cloud
IDE_BASE_URL=https://ide.kushnir.cloud
```

### Definition of Done

- [ ] 20+ OAuth login tests implemented
- [ ] All happy path scenarios covered
- [ ] All error handling scenarios covered
- [ ] Edge cases validated
- [ ] Tests pass with QA account credentials
- [ ] Test coverage report shows >90% of auth code paths
- [ ] No flaky tests (stable across 10 consecutive runs)

Parent: #982
Depends on: #983 (QA user), #984 (credentials in GSM)
