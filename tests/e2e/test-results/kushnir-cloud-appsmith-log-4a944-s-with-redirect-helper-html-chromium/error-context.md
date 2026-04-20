# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: kushnir-cloud-appsmith-login.spec.ts >> kushnir.cloud Appsmith login path >> auth reset clears cookies and responds with redirect helper html
- Location: specs\kushnir-cloud-appsmith-login.spec.ts:245:7

# Error details

```
Error: apiRequestContext.get: write EPROTO 1C7B0000:error:0A000438:SSL routines:ssl3_read_bytes:tlsv1 alert internal error:openssl\ssl\record\rec_layer_s3.c:916:SSL alert number 80

Call log:
  - → GET https://kushnir.cloud/auth/reset
    - user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.7727.15 Safari/537.36
    - accept: */*
    - accept-encoding: gzip,deflate,br

```

# Test source

```ts
  146 |         };
  147 |       }
  148 |     );
  149 | 
  150 |     expect(normalizeUrl(redirectUri)).toBe(normalizeUrl(PORTAL_EXPECTED_REDIRECT_URI));
  151 |   });
  152 | 
  153 |   test('ide oauth start resolves to expected google redirect_uri contract', async ({ request }) => {
  154 |     const redirectUri = await resolveRedirectUriFromAuthStart(
  155 |       `${IDE_BASE_URL}${AUTH_START_PATH}?rd=%2F`,
  156 |       async (url: string) => {
  157 |         const response = await request.get(url, { maxRedirects: 0 });
  158 |         return {
  159 |           status: response.status(),
  160 |           location: response.headers()['location'] || '',
  161 |         };
  162 |       }
  163 |     );
  164 | 
  165 |     expect(normalizeUrl(redirectUri)).toBe(normalizeUrl(IDE_EXPECTED_REDIRECT_URI));
  166 |   });
  167 | 
  168 |   test('appsmith GitHub button emits redirect_uri for kushnir.cloud host', async ({ request }) => {
  169 |     const result = await fetchAppsmithLoginResponse(request, `${PORTAL_BASE_URL}${APPSMITH_LOGIN_PATH}`);
  170 |     if (result.skippedReason) {
  171 |       test.skip(true, result.skippedReason);
  172 |     }
  173 | 
  174 |     const response = result.response;
  175 |     expect(response).toBeTruthy();
  176 | 
  177 |     const status = response!.status();
  178 |     if ([401, 403].includes(status)) {
  179 |       test.skip(true, `Appsmith login page is fail-closed in this environment (status ${status})`);
  180 |     }
  181 | 
  182 |     expect([200, 301, 302, 303, 307, 308]).toContain(status);
  183 | 
  184 |     const location = response!.headers()['location'] || '';
  185 |     if (location) {
  186 |       expect(location).toMatch(/github\.com|redirect_uri=|login\/oauth2\/code\/github/i);
  187 |       if (location.includes('redirect_uri=')) {
  188 |         const authUrl = new URL(location.startsWith('http') ? location : new URL(location, PORTAL_BASE_URL).toString());
  189 |         const redirectUri = authUrl.searchParams.get('redirect_uri');
  190 | 
  191 |         expect(redirectUri).toBeTruthy();
  192 | 
  193 |         const parsedRedirectUri = new URL(redirectUri as string);
  194 |         expect(parsedRedirectUri.protocol).toBe('https:');
  195 |         expect(parsedRedirectUri.host).toBe(new URL(PORTAL_BASE_URL).host);
  196 |         expect(normalizeUrl(redirectUri as string)).toBe(normalizeUrl(APPSMITH_EXPECTED_REDIRECT_URI));
  197 |       }
  198 |     }
  199 | 
  200 |     const body = await response!.text();
  201 |     expect(body).toMatch(/github\.com|redirect_uri=|login\/oauth2\/code\/github/i);
  202 |   });
  203 | 
  204 |   test('auth reset response includes cookie/site-data clearing headers', async ({ request }) => {
  205 |     const response = await request.get(`${PORTAL_BASE_URL}${AUTH_RESET_PATH}`, { maxRedirects: 0 });
  206 |     expect(response.status()).toBe(200);
  207 | 
  208 |     const headers = response.headers();
  209 |     expect((headers['clear-site-data'] || '').toLowerCase()).toContain('cookies');
  210 | 
  211 |     const setCookie = headers['set-cookie'] || '';
  212 |     expect(setCookie).toContain('_oauth2_proxy_portal=');
  213 |     expect(setCookie).toContain('_oauth2_proxy_portal_csrf=');
  214 |     expect(setCookie).toContain('_oauth2_proxy_ide=');
  215 |   });
  216 | 
  217 |   test('single-login sentinel detects appsmith secondary auth when strict mode is enabled', async ({ page, request }) => {
  218 |     test.skip(!REQUIRE_SINGLE_LOGIN, 'Set REQUIRE_SINGLE_LOGIN=1 to enforce no secondary Appsmith login');
  219 | 
  220 |     const rootResponse = await request.get(`${PORTAL_BASE_URL}/`, { maxRedirects: 0 });
  221 |     const rootIsProtectedByOauth = REDIRECT_STATUSES.includes(rootResponse.status())
  222 |       ? (rootResponse.headers()['location'] || '').includes(AUTH_START_PATH)
  223 |       : [401, 403].includes(rootResponse.status());
  224 |     expect(rootIsProtectedByOauth).toBeTruthy();
  225 | 
  226 |     const result = await fetchAppsmithLoginResponse(request, `${PORTAL_BASE_URL}${APPSMITH_LOGIN_PATH}`);
  227 |     if (result.skippedReason) {
  228 |       test.skip(true, result.skippedReason);
  229 |     }
  230 | 
  231 |     const pageResponse = result.response;
  232 |     expect(pageResponse).not.toBeNull();
  233 |     const appsmithLoginStatus = pageResponse?.status() || 0;
  234 | 
  235 |     if ([401, 403].includes(appsmithLoginStatus)) {
  236 |       return;
  237 |     }
  238 | 
  239 |     const bodyText = (await page.textContent('body')) || '';
  240 |     const hasAppsmithLoginUi = /sign in to your account|appsmith/i.test(bodyText);
  241 | 
  242 |     expect(hasAppsmithLoginUi).toBeFalsy();
  243 |   });
  244 | 
  245 |   test('auth reset clears cookies and responds with redirect helper html', async ({ request }) => {
> 246 |     const response = await request.get(`${PORTAL_BASE_URL}${AUTH_RESET_PATH}`, { maxRedirects: 0 });
      |                                    ^ Error: apiRequestContext.get: write EPROTO 1C7B0000:error:0A000438:SSL routines:ssl3_read_bytes:tlsv1 alert internal error:openssl\ssl\record\rec_layer_s3.c:916:SSL alert number 80
  247 |     expect(response).not.toBeNull();
  248 |     expect(response.status()).toBe(200);
  249 | 
  250 |     const html = await response.text();
  251 |     expect(html).toContain('Auth reset complete. Redirecting to login');
  252 |     expect(html).toContain(AUTH_START_PATH);
  253 |   });
  254 | 
  255 |   test('authenticated portal session (QA storage state) loads without oauth redirect', async ({ browser }) => {
  256 |     test.skip(!AUTH_STORAGE_STATE, 'PLAYWRIGHT_STORAGE_STATE is required for QA-authenticated flow');
  257 | 
  258 |     const context = await browser.newContext({ storageState: AUTH_STORAGE_STATE });
  259 |     const page = await context.newPage();
  260 | 
  261 |     const response = await page.goto(`${PORTAL_BASE_URL}/`, { waitUntil: 'domcontentloaded' });
  262 |     expect(response).not.toBeNull();
  263 |     expect(response?.status()).toBeLessThan(400);
  264 | 
  265 |     const currentUrl = page.url();
  266 |     expect(currentUrl).not.toContain('/oauth2/start');
  267 |     expect(currentUrl).not.toContain('/oauth2/callback');
  268 |     expect(isAppsmithLoginUrl(currentUrl)).toBeFalsy();
  269 |     assertHttpsAndDomain(currentUrl, new URL(PORTAL_BASE_URL).host);
  270 | 
  271 |     const bodyText = (await page.textContent('body')) || '';
  272 |     expect(/sign in to your account/i.test(bodyText)).toBeFalsy();
  273 | 
  274 |     const cookies = await context.cookies(PORTAL_BASE_URL);
  275 |     const names = cookies.map((c) => c.name);
  276 |     expect(names.some((n) => n.includes('_oauth2_proxy_portal'))).toBeTruthy();
  277 | 
  278 |     await context.close();
  279 |   });
  280 | 
  281 |   test('authenticated user can open portal and logout back to auth gate', async ({ browser }) => {
  282 |     test.skip(!AUTH_STORAGE_STATE, 'PLAYWRIGHT_STORAGE_STATE is required for full login->portal->logout flow');
  283 | 
  284 |     const context = await browser.newContext({ storageState: AUTH_STORAGE_STATE });
  285 |     const page = await context.newPage();
  286 | 
  287 |     const portalResponse = await page.goto(`${PORTAL_BASE_URL}/`, { waitUntil: 'domcontentloaded' });
  288 |     expect(portalResponse).not.toBeNull();
  289 |     expect(portalResponse?.status()).toBeLessThan(400);
  290 |     expect(page.url()).not.toContain('/oauth2/start');
  291 |     expect(isAppsmithLoginUrl(page.url())).toBeFalsy();
  292 | 
  293 |     const logoutResponse = await page.goto(`${PORTAL_BASE_URL}${AUTH_LOGOUT_PATH}`, { waitUntil: 'domcontentloaded' });
  294 |     expect(logoutResponse).not.toBeNull();
  295 |     expect([200, 301, 302, 303, 307, 308]).toContain(logoutResponse?.status() || 0);
  296 | 
  297 |     await page.goto(`${PORTAL_BASE_URL}/`, { waitUntil: 'domcontentloaded' });
  298 |     const urlAfterLogout = page.url();
  299 |     expect(urlAfterLogout.includes('/oauth2/start') || urlAfterLogout.includes('accounts.google.com')).toBeTruthy();
  300 | 
  301 |     await context.close();
  302 |   });
  303 | 
  304 |   test('authenticated IDE session (QA storage state) loads without oauth redirect loop', async ({ browser }) => {
  305 |     test.skip(!AUTH_STORAGE_STATE, 'PLAYWRIGHT_STORAGE_STATE is required for QA-authenticated flow');
  306 | 
  307 |     const context = await browser.newContext({ storageState: AUTH_STORAGE_STATE });
  308 |     const page = await context.newPage();
  309 | 
  310 |     const response = await page.goto(`${IDE_BASE_URL}/`, { waitUntil: 'domcontentloaded' });
  311 |     expect(response).not.toBeNull();
  312 |     expect(response?.status()).toBeLessThan(400);
  313 | 
  314 |     const currentUrl = page.url();
  315 |     expect(currentUrl).not.toContain('/oauth2/start');
  316 |     expect(currentUrl).not.toContain('/oauth2/callback');
  317 |     assertHttpsAndDomain(currentUrl, new URL(IDE_BASE_URL).host);
  318 | 
  319 |     await context.close();
  320 |   });
  321 | });
  322 | 
```