# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: failover-session-continuity.spec.ts >> unauthenticated continuity across failover window
- Location: specs\failover-session-continuity.spec.ts:5:5

# Error details

```
Error: page.goto: net::ERR_SSL_PROTOCOL_ERROR at https://kushnir.cloud/
Call log:
  - navigating to "https://kushnir.cloud/", waiting until "domcontentloaded"

```

# Test source

```ts
  1  | import { test, expect } from '@playwright/test';
  2  | 
  3  | const waitMs = Number(process.env.FAILOVER_WAIT_MS || '45000');
  4  | 
  5  | test('unauthenticated continuity across failover window', async ({ page }) => {
> 6  |   const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
     |                               ^ Error: page.goto: net::ERR_SSL_PROTOCOL_ERROR at https://kushnir.cloud/
  7  |   expect(response).not.toBeNull();
  8  |   expect([200, 301, 302, 303, 307, 308, 401, 403]).toContain(response?.status() || 0);
  9  |   expect(page.url()).toMatch(/kushnir\.cloud/);
  10 | 
  11 |   await page.waitForTimeout(waitMs);
  12 |   const reloadResponse = await page.reload({ waitUntil: 'domcontentloaded' });
  13 |   expect(reloadResponse).not.toBeNull();
  14 |   expect([200, 301, 302, 303, 307, 308, 401, 403]).toContain(reloadResponse?.status() || 0);
  15 |   expect(page.url()).toMatch(/kushnir\.cloud/);
  16 | });
  17 | 
```