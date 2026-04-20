# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: oauth-login.spec.ts >> OAuth login smoke test >> redirects to OAuth provider on unauthenticated access
- Location: specs\oauth-login.spec.ts:7:7

# Error details

```
Error: page.goto: net::ERR_SSL_PROTOCOL_ERROR at https://kushnir.cloud/
Call log:
  - navigating to "https://kushnir.cloud/", waiting until "load"

```

# Test source

```ts
  1  | import { test, expect } from '@playwright/test';
  2  | 
  3  | // Service-account E2E: Validate OAuth login redirects and load order
  4  | // Corresponds to e2e-service-account-profile.yml :: oauth-login capability
  5  | 
  6  | test.describe('OAuth login smoke test', () => {
  7  |   test('redirects to OAuth provider on unauthenticated access', async ({ page }) => {
> 8  |     const response = await page.goto('/');
     |                                 ^ Error: page.goto: net::ERR_SSL_PROTOCOL_ERROR at https://kushnir.cloud/
  9  |     // Should redirect to /oauth2/sign_in or Google OAuth
  10 |     const url = page.url();
  11 |     expect(url).toMatch(/oauth2|accounts\.google\.com/);
  12 |   });
  13 | 
  14 |   test('health check endpoint is reachable without auth', async ({ page }) => {
  15 |     const response = await page.goto('/health');
  16 |     // Health check returns 200 without OAuth
  17 |     expect(response?.status()).toBeLessThanOrEqual(404); // 200 or 404 (not 502)
  18 |   });
  19 | });
  20 | 
```