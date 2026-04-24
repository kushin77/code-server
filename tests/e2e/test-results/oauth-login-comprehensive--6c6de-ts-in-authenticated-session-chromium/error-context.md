# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: oauth-login-comprehensive.spec.ts >> OAuth Login Comprehensive (#986) >> Happy Path - Login Flow >> 1: complete OAuth flow results in authenticated session
- Location: tests\e2e\specs\oauth-login-comprehensive.spec.ts:12:9

# Error details

```
TimeoutError: page.waitForURL: Timeout 10000ms exceeded.
=========================== logs ===========================
waiting for navigation until "load"
============================================================
```

# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - generic [ref=e3]:
    - img "OAuth2_Proxy_logo_v3" [ref=e5]
    - button "Sign in with Google" [ref=e23] [cursor=pointer]
  - contentinfo [ref=e24]:
    - paragraph [ref=e26]:
      - text: Secured with
      - link "OAuth2 Proxy" [ref=e27] [cursor=pointer]:
        - /url: https://github.com/oauth2-proxy/oauth2-proxy#oauth2_proxy
      - text: version v7.5.1
```

# Test source

```ts
  1   | import { test, expect } from '@playwright/test';
  2   | 
  3   | const QA_EMAIL = process.env.E2E_USER_EMAIL || 'qa@kushnir.cloud';
  4   | const QA_PASSWORD = process.env.E2E_USER_PASSWORD || '';
  5   | const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
  6   | const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
  7   | 
  8   | test.describe('OAuth Login Comprehensive (#986)', () => {
  9   |   
  10  |   test.describe('Happy Path - Login Flow', () => {
  11  |     
  12  |     test('1: complete OAuth flow results in authenticated session', async ({ page }) => {
  13  |       // Navigate to protected resource
  14  |       await page.goto(PORTAL_URL);
  15  |       
  16  |       // Should redirect to Google OAuth
> 17  |       await page.waitForURL(/accounts\.google\.com/, { timeout: 10000 });
      |                  ^ TimeoutError: page.waitForURL: Timeout 10000ms exceeded.
  18  |       
  19  |       // Enter QA email
  20  |       await page.fill('input[type="email"]', QA_EMAIL);
  21  |       await page.click('#identifierNext, button:has-text("Next")');
  22  |       
  23  |       // Wait for password field
  24  |       await page.waitForSelector('input[type="password"]', { timeout: 5000 });
  25  |       
  26  |       // Enter password
  27  |       await page.fill('input[type="password"]', QA_PASSWORD);
  28  |       await page.click('#passwordNext, button:has-text("Next")');
  29  |       
  30  |       // Should redirect back to portal after OAuth callback
  31  |       await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
  32  |       
  33  |       // Verify authenticated state via cookie
  34  |       const cookies = await page.context().cookies();
  35  |       const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
  36  |       expect(oauthCookie).toBeDefined();
  37  |       expect(oauthCookie?.value).toBeTruthy();
  38  |     });
  39  | 
  40  |     test('2: login preserves rd (redirect) parameter after authentication', async ({ page }) => {
  41  |       const redirectTarget = '/admin';
  42  |       
  43  |       // Navigate with rd parameter
  44  |       await page.goto(`${PORTAL_URL}/oauth2/start?rd=${encodeURIComponent(PORTAL_URL + redirectTarget)}`);
  45  |       
  46  |       // Go through OAuth flow
  47  |       await page.waitForURL(/accounts\.google\.com/);
  48  |       await page.fill('input[type="email"]', QA_EMAIL);
  49  |       await page.click('#identifierNext, button:has-text("Next")');
  50  |       await page.waitForSelector('input[type="password"]');
  51  |       await page.fill('input[type="password"]', QA_PASSWORD);
  52  |       await page.click('#passwordNext, button:has-text("Next")');
  53  |       
  54  |       // Should redirect to the original target, not just portal root
  55  |       await page.waitForURL(new RegExp(`.*/admin`), { timeout: 15000 });
  56  |       expect(page.url()).toContain('/admin');
  57  |     });
  58  | 
  59  |     test('3: login sets _oauth2_proxy cookie', async ({ page }) => {
  60  |       await page.goto(PORTAL_URL);
  61  |       await page.waitForURL(/accounts\.google\.com/);
  62  |       
  63  |       // Complete OAuth flow
  64  |       await page.fill('input[type="email"]', QA_EMAIL);
  65  |       await page.click('#identifierNext, button:has-text("Next")');
  66  |       await page.waitForSelector('input[type="password"]');
  67  |       await page.fill('input[type="password"]', QA_PASSWORD);
  68  |       await page.click('#passwordNext, button:has-text("Next")');
  69  |       
  70  |       await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
  71  |       
  72  |       // Verify all OAuth cookies present
  73  |       const cookies = await page.context().cookies();
  74  |       const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
  75  |       const xsrfCookie = cookies.find(c => c.name === 'XSRF-TOKEN');
  76  |       
  77  |       expect(oauthCookie).toBeDefined();
  78  |       // XSRF token may not be present in all scenarios
  79  |     });
  80  | 
  81  |     test('4: login sets secure cookie attributes (httpOnly, Secure, SameSite)', async ({ page }) => {
  82  |       await page.goto(PORTAL_URL);
  83  |       await page.waitForURL(/accounts\.google\.com/);
  84  |       
  85  |       // Complete login
  86  |       await page.fill('input[type="email"]', QA_EMAIL);
  87  |       await page.click('#identifierNext, button:has-text("Next")');
  88  |       await page.waitForSelector('input[type="password"]');
  89  |       await page.fill('input[type="password"]', QA_PASSWORD);
  90  |       await page.click('#passwordNext, button:has-text("Next")');
  91  |       
  92  |       await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
  93  |       
  94  |       const cookies = await page.context().cookies();
  95  |       const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
  96  |       
  97  |       expect(oauthCookie?.httpOnly).toBe(true);
  98  |       expect(oauthCookie?.secure).toBe(true);
  99  |       // SameSite should be either 'Strict' or 'Lax'
  100 |       expect(['Strict', 'Lax', 'None']).toContain(oauthCookie?.sameSite);
  101 |     });
  102 | 
  103 |     test('5: authenticated session remains valid during session', async ({ page, context }) => {
  104 |       // Login
  105 |       await page.goto(PORTAL_URL);
  106 |       await page.waitForURL(/accounts\.google\.com/);
  107 |       await page.fill('input[type="email"]', QA_EMAIL);
  108 |       await page.click('#identifierNext, button:has-text("Next")');
  109 |       await page.waitForSelector('input[type="password"]');
  110 |       await page.fill('input[type="password"]', QA_PASSWORD);
  111 |       await page.click('#passwordNext, button:has-text("Next")');
  112 |       await page.waitForURL(new RegExp(`^${PORTAL_URL}`), { timeout: 15000 });
  113 |       
  114 |       // Verify authenticated
  115 |       const cookies1 = await context.cookies();
  116 |       const oauth1 = cookies1.find(c => c.name === '_oauth2_proxy');
  117 |       expect(oauth1).toBeDefined();
```