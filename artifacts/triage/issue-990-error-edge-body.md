## E2E: Error Handling and Edge Case Coverage

### Objective
Comprehensive E2E testing for error scenarios, edge cases, and defensive behavior across the authentication and IDE path.

### Current State
- No dedicated error handling tests
- Edge cases untested
- Error messages not validated

### Target Test Matrix (20+ tests)

#### Authentication Errors (6 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 1 | `auth-invalid-credentials` | Wrong password shows clear error |
| 2 | `auth-account-disabled` | Disabled account gets helpful message |
| 3 | `auth-not-whitelisted` | Non-whitelisted user rejected gracefully |
| 4 | `auth-oauth-timeout` | Google OAuth timeout handled |
| 5 | `auth-csrf-mismatch` | CSRF mismatch blocked with message |
| 6 | `auth-rate-limited` | Too many attempts → rate limit message |

#### Network Errors (4 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 7 | `network-502-gateway` | 502 error shows maintenance message |
| 8 | `network-503-unavailable` | 503 shows retry guidance |
| 9 | `network-timeout` | Request timeout shows fallback |
| 10 | `network-dns-failure` | DNS failure shows network check message |

#### IDE Errors (5 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 11 | `ide-session-expired` | Expired IDE session prompts re-login |
| 12 | `ide-container-crashed` | Container crash shows recovery option |
| 13 | `ide-workspace-full` | Disk full shows cleanup guidance |
| 14 | `ide-extension-crash` | Extension crash doesn't break IDE |
| 15 | `ide-save-failed` | Save failure shows retry option |

#### Edge Cases (5 tests)

| # | Test Name | Description |
|---|-----------|-------------|
| 16 | `edge-unicode-filename` | Unicode filenames handled correctly |
| 17 | `edge-large-file` | Large file (>10MB) opens with warning |
| 18 | `edge-special-chars-url` | Special chars in URL encoded correctly |
| 19 | `edge-concurrent-saves` | Concurrent saves don't corrupt file |
| 20 | `edge-browser-back` | Back button doesn't break state |

### Implementation

**File**: `tests/e2e/specs/error-edge-cases.spec.ts`

```typescript
import { test, expect } from '../fixtures/auth-fixture';

const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';

test.describe('Error Handling', () => {
  test.describe('Authentication Errors', () => {
    test('non-whitelisted user gets clear rejection', async ({ page }) => {
      // Use a known non-whitelisted email
      // This test uses browser automation without storage state
      
      await page.goto(PORTAL_URL);
      
      // At Google OAuth, use non-whitelisted account
      // This requires manual setup or mock
      
      // Expected: oauth2-proxy returns 403
      // Verify error page has helpful message
      await expect(page.locator('.error-message')).toContainText(
        /not authorized|contact administrator|whitelist/i
      );
    });

    test('CSRF mismatch blocked with message', async ({ page }) => {
      // Attempt callback with wrong state parameter
      const maliciousCallback = `${PORTAL_URL}/oauth2/callback?state=invalid_state&code=fake_code`;
      
      await page.goto(maliciousCallback);
      
      // Should show CSRF error
      await expect(page.locator('body')).toContainText(/CSRF|state mismatch|invalid/i);
    });
  });

  test.describe('Network Errors', () => {
    test('502 error shows maintenance message', async ({ page }) => {
      // Intercept request and return 502
      await page.route('**/health', route => {
        route.fulfill({
          status: 502,
          body: 'Bad Gateway'
        });
      });
      
      await page.goto(`${PORTAL_URL}/health`);
      
      // Verify user-friendly error page (not raw 502)
      // Note: This depends on Caddy/nginx error page configuration
    });

    test('request timeout handled gracefully', async ({ page }) => {
      // Set short timeout and slow response
      page.setDefaultTimeout(5000);
      
      await page.route('**/*', async route => {
        await new Promise(r => setTimeout(r, 10000)); // 10s delay
        route.continue();
      });
      
      try {
        await page.goto(PORTAL_URL);
      } catch (e) {
        // Expected: timeout
      }
      
      // Page should show timeout message or retry option
    });
  });

  test.describe('IDE Errors', () => {
    test.use({ storageState: 'tests/e2e/.auth/qa-storage-state.json' });

    test('extension crash does not break IDE', async ({ page }) => {
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Trigger extension error (via console)
      await page.evaluate(() => {
        // Simulate extension crash by throwing in extension host
        // This is a simplified example
        throw new Error('Simulated extension crash');
      });
      
      // IDE should still be functional
      await page.keyboard.press('Control+Shift+P');
      await expect(page.locator('.quick-input-widget')).toBeVisible();
    });
  });

  test.describe('Edge Cases', () => {
    test.use({ storageState: 'tests/e2e/.auth/qa-storage-state.json' });

    test('unicode filename handled correctly', async ({ page }) => {
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Create file with unicode name
      await page.keyboard.press('Control+Shift+P');
      await page.keyboard.type('New File');
      await page.keyboard.press('Enter');
      
      // Save with unicode filename
      await page.keyboard.press('Control+S');
      await page.keyboard.type('测试文件-тест.txt');
      await page.keyboard.press('Enter');
      
      // Verify file appears in explorer
      await expect(page.locator('.explorer-folders-view'))
        .toContainText('测试文件-тест.txt');
    });

    test('browser back button does not break state', async ({ page }) => {
      await page.goto(PORTAL_URL);
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Go back
      await page.goBack();
      
      // Go forward
      await page.goForward();
      
      // IDE should still work
      await page.waitForSelector('.monaco-workbench');
    });

    test('concurrent saves do not corrupt file', async ({ page }) => {
      await page.goto(IDE_URL);
      await page.waitForSelector('.monaco-workbench');
      
      // Create file
      await page.keyboard.press('Control+N');
      
      // Rapid typing and saving
      for (let i = 0; i < 10; i++) {
        await page.keyboard.type(`Line ${i}\n`);
        await page.keyboard.press('Control+S');
        // Don't wait - simulate rapid saves
      }
      
      // Wait for all saves to complete
      await page.waitForTimeout(2000);
      
      // Verify file content is intact
      const content = await page.locator('.monaco-editor').textContent();
      expect(content).toContain('Line 9');
    });
  });
});
```

### Error Page Validation

We need to verify error pages are user-friendly:

```typescript
// fixtures/error-page-checker.ts
export async function validateErrorPage(page: Page, expectedElements: string[]) {
  // Should have clear error title
  await expect(page.locator('h1, .error-title')).toBeVisible();
  
  // Should have helpful message
  await expect(page.locator('.error-message, .error-description')).toBeVisible();
  
  // Should have action button (retry, contact, etc.)
  await expect(page.locator('button, a.button')).toBeVisible();
  
  // Should NOT show raw error codes or stack traces
  await expect(page.locator('body')).not.toContainText(/at .+:\d+:\d+/); // stack trace
  await expect(page.locator('body')).not.toContainText(/Error: .+\n\s+at/); // error stack
}
```

### Definition of Done

- [ ] 20+ error/edge case tests implemented
- [ ] Authentication error scenarios covered
- [ ] Network error handling verified
- [ ] IDE error recovery tested
- [ ] Edge cases validated
- [ ] Error pages are user-friendly (no raw errors)
- [ ] All tests stable across runs

Parent: #982
Depends on: #983, #984 (QA account)
