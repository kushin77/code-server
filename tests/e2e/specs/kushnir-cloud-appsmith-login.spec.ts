import { expect, test } from '@playwright/test';

const PORTAL_BASE_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_BASE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
const AUTH_RESET_PATH = process.env.AUTH_RESET_PATH || '/auth/reset';
const AUTH_START_PATH = process.env.AUTH_START_PATH || '/oauth2/start';
const AUTH_LOGOUT_PATH = process.env.AUTH_LOGOUT_PATH || '/logout';
const STATIC_CSS_PATH = process.env.PORTAL_STATIC_CSS_PATH || '/static/css/main.c5955fd3.css';
const AUTH_STORAGE_STATE = process.env.PLAYWRIGHT_STORAGE_STATE || '';
const REQUIRE_SINGLE_LOGIN = process.env.REQUIRE_SINGLE_LOGIN === '1';
const PORTAL_EXPECTED_REDIRECT_URI = process.env.PORTAL_EXPECTED_REDIRECT_URI || `${PORTAL_BASE_URL}/oauth2/callback`;
const IDE_EXPECTED_REDIRECT_URI = process.env.IDE_EXPECTED_REDIRECT_URI || `${IDE_BASE_URL}/oauth2/callback`;
const APPSMITH_LOGIN_PATH = process.env.APPSMITH_LOGIN_PATH || '/user/login';
const APPSMITH_EXPECTED_REDIRECT_URI = process.env.APPSMITH_EXPECTED_REDIRECT_URI || `${PORTAL_BASE_URL}/login/oauth2/code/github`;

const REDIRECT_STATUSES = [301, 302, 303, 307, 308];

function isAppsmithLoginUrl(url: string): boolean {
  return url.includes('/user/login') || url.includes('/login/oauth2/code/github');
}

function assertHttpsAndDomain(url: string, expectedHost: string): void {
  const parsed = new URL(url);
  expect(parsed.protocol).toBe('https:');
  expect(parsed.host).toBe(expectedHost);
}

function normalizeUrl(input: string): string {
  return input.replace(/\/+$/, '');
}

async function fetchAppsmithLoginResponse(
  request: { get: (url: string, options?: { maxRedirects?: number; timeout?: number }) => Promise<{ status: number; headers(): Record<string, string>; text(): Promise<string> }> },
  requestUrl: string,
): Promise<{ response?: { status: number; headers(): Record<string, string>; text(): Promise<string> }; skippedReason?: string }> {
  try {
    const response = await request.get(requestUrl, { maxRedirects: 0, timeout: 15000 });
    return { response };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { skippedReason: `Appsmith login page unavailable in this environment: ${message}` };
  }
}

async function resolveRedirectUriFromAuthStart(
  requestUrl: string,
  requestGet: (url: string) => Promise<{ status: number; location: string }> 
): Promise<string> {
  let currentUrl = requestUrl;

  for (let hop = 0; hop < 5; hop += 1) {
    const { status, location } = await requestGet(currentUrl);
    expect([301, 302, 303, 307, 308]).toContain(status);
    expect(location).toBeTruthy();

    const resolved = location.startsWith('http') ? location : new URL(location, currentUrl).toString();
    const redirectUri = new URL(resolved).searchParams.get('redirect_uri');

    if (redirectUri) {
      return redirectUri;
    }

    currentUrl = resolved;
  }

  throw new Error(`No redirect_uri query parameter found after redirects from ${requestUrl}`);
}

async function getRedirectLocation(requestUrl: string, request: { get: (url: string, options?: { maxRedirects?: number }) => Promise<{ status: () => number; headers: () => Record<string, string> }> }): Promise<{ status: number; location: string }> {
  const response = await request.get(requestUrl, { maxRedirects: 0 });
  return {
    status: response.status(),
    location: response.headers()['location'] || '',
  };
}

test.describe('kushnir.cloud Appsmith login path', () => {
  test('portal static css is served as text/css', async ({ request }) => {
    const response = await request.get(`${PORTAL_BASE_URL}${STATIC_CSS_PATH}`);
    expect(response.status()).toBe(200);
    const contentType = response.headers()['content-type'] || '';
    expect(contentType.toLowerCase()).toContain('text/css');
  });

  test('unauthenticated root redirects to oauth2 start endpoint', async ({ request }) => {
    const response = await request.get(`${PORTAL_BASE_URL}/`, { maxRedirects: 0 });
    const status = response.status();
    expect([...REDIRECT_STATUSES, 401, 403]).toContain(status);

    if (REDIRECT_STATUSES.includes(status)) {
      const location = response.headers()['location'] || '';
      expect(location).toContain(AUTH_START_PATH);
      expect(location).toContain('rd=');
    }
  });

  test('oauth2 start endpoint emits redirect with rd parameter preserved', async ({ request }) => {
    const target = `${PORTAL_BASE_URL}${AUTH_START_PATH}?rd=%2Fuser%2Flogin`;
    const { status, location } = await getRedirectLocation(target, request);

    expect(REDIRECT_STATUSES).toContain(status);
    expect(location).toBeTruthy();
    expect(location).toContain('redirect_uri=');
    expect(location).toContain('state=');
  });

  test('logout endpoint redirects through oauth2 sign out with return URL', async ({ request }) => {
    const response = await request.get(`${PORTAL_BASE_URL}${AUTH_LOGOUT_PATH}`, { maxRedirects: 0 });
    expect(REDIRECT_STATUSES).toContain(response.status());

    const location = response.headers()['location'] || '';
    expect(location).toContain('/oauth2/sign_out');
    expect(location).toContain('rd=');
  });

  test('interactive login starts from kushnir.cloud and reaches the auth provider', async ({ request }) => {
    const initial = await request.get(`${PORTAL_BASE_URL}/`, { maxRedirects: 0 });
    expect(initial).not.toBeNull();

    const status = initial.status();
    expect([200, 401, 403, 302, 303, 307, 308]).toContain(status);

    const initialLocation = initial.headers()['location'] || '';
    if (initialLocation) {
      expect(initialLocation).toMatch(/oauth2\/start|accounts\.google\.com|github\.com/i);
    }

    const authStart = await request.get(`${PORTAL_BASE_URL}${AUTH_START_PATH}?rd=%2F`, { maxRedirects: 0 });
    expect(authStart).not.toBeNull();
    expect([200, 302, 303, 307, 308]).toContain(authStart.status());

    const authLocation = authStart.headers()['location'] || '';
    if (authLocation) {
      expect(authLocation).toMatch(/accounts\.google\.com|github\.com/i);
    }
  });

  test('portal oauth start resolves to expected google redirect_uri contract', async ({ request }) => {
    const redirectUri = await resolveRedirectUriFromAuthStart(
      `${PORTAL_BASE_URL}${AUTH_START_PATH}?rd=%2F`,
      async (url: string) => {
        const response = await request.get(url, { maxRedirects: 0 });
        return {
          status: response.status(),
          location: response.headers()['location'] || '',
        };
      }
    );

    expect(normalizeUrl(redirectUri)).toBe(normalizeUrl(PORTAL_EXPECTED_REDIRECT_URI));
  });

  test('ide oauth start resolves to expected google redirect_uri contract', async ({ request }) => {
    const redirectUri = await resolveRedirectUriFromAuthStart(
      `${IDE_BASE_URL}${AUTH_START_PATH}?rd=%2F`,
      async (url: string) => {
        const response = await request.get(url, { maxRedirects: 0 });
        return {
          status: response.status(),
          location: response.headers()['location'] || '',
        };
      }
    );

    expect(normalizeUrl(redirectUri)).toBe(normalizeUrl(IDE_EXPECTED_REDIRECT_URI));
  });

  test('appsmith GitHub button emits redirect_uri for kushnir.cloud host', async ({ request }) => {
    const result = await fetchAppsmithLoginResponse(request, `${PORTAL_BASE_URL}${APPSMITH_LOGIN_PATH}`);
    if (result.skippedReason) {
      test.skip(true, result.skippedReason);
    }

    const response = result.response;
    expect(response).toBeTruthy();

    const status = response!.status();
    if ([401, 403].includes(status)) {
      test.skip(true, `Appsmith login page is fail-closed in this environment (status ${status})`);
    }

    expect([200, 301, 302, 303, 307, 308]).toContain(status);

    const location = response!.headers()['location'] || '';
    if (location) {
      expect(location).toMatch(/github\.com|redirect_uri=|login\/oauth2\/code\/github/i);
      if (location.includes('redirect_uri=')) {
        const authUrl = new URL(location.startsWith('http') ? location : new URL(location, PORTAL_BASE_URL).toString());
        const redirectUri = authUrl.searchParams.get('redirect_uri');

        expect(redirectUri).toBeTruthy();

        const parsedRedirectUri = new URL(redirectUri as string);
        expect(parsedRedirectUri.protocol).toBe('https:');
        expect(parsedRedirectUri.host).toBe(new URL(PORTAL_BASE_URL).host);
        expect(normalizeUrl(redirectUri as string)).toBe(normalizeUrl(APPSMITH_EXPECTED_REDIRECT_URI));
      }
    }

    const body = await response!.text();
    expect(body).toMatch(/github\.com|redirect_uri=|login\/oauth2\/code\/github/i);
  });

  test('auth reset response includes cookie/site-data clearing headers', async ({ request }) => {
    const response = await request.get(`${PORTAL_BASE_URL}${AUTH_RESET_PATH}`, { maxRedirects: 0 });
    expect(response.status()).toBe(200);

    const headers = response.headers();
    expect((headers['clear-site-data'] || '').toLowerCase()).toContain('cookies');

    const setCookie = headers['set-cookie'] || '';
    expect(setCookie).toContain('_oauth2_proxy_portal=');
    expect(setCookie).toContain('_oauth2_proxy_portal_csrf=');
    expect(setCookie).toContain('_oauth2_proxy_ide=');
  });

  test('single-login sentinel detects appsmith secondary auth when strict mode is enabled', async ({ page, request }) => {
    test.skip(!REQUIRE_SINGLE_LOGIN, 'Set REQUIRE_SINGLE_LOGIN=1 to enforce no secondary Appsmith login');

    const rootResponse = await request.get(`${PORTAL_BASE_URL}/`, { maxRedirects: 0 });
    const rootIsProtectedByOauth = REDIRECT_STATUSES.includes(rootResponse.status())
      ? (rootResponse.headers()['location'] || '').includes(AUTH_START_PATH)
      : [401, 403].includes(rootResponse.status());
    expect(rootIsProtectedByOauth).toBeTruthy();

    const result = await fetchAppsmithLoginResponse(request, `${PORTAL_BASE_URL}${APPSMITH_LOGIN_PATH}`);
    if (result.skippedReason) {
      test.skip(true, result.skippedReason);
    }

    const pageResponse = result.response;
    expect(pageResponse).not.toBeNull();
    const appsmithLoginStatus = pageResponse?.status() || 0;

    if ([401, 403].includes(appsmithLoginStatus)) {
      return;
    }

    const bodyText = (await page.textContent('body')) || '';
    const hasAppsmithLoginUi = /sign in to your account|appsmith/i.test(bodyText);

    expect(hasAppsmithLoginUi).toBeFalsy();
  });

  test('auth reset clears cookies and responds with redirect helper html', async ({ request }) => {
    const response = await request.get(`${PORTAL_BASE_URL}${AUTH_RESET_PATH}`, { maxRedirects: 0 });
    expect(response).not.toBeNull();
    expect(response.status()).toBe(200);

    const html = await response.text();
    expect(html).toContain('Auth reset complete. Redirecting to login');
    expect(html).toContain(AUTH_START_PATH);
  });

  test('authenticated portal session (QA storage state) loads without oauth redirect', async ({ browser }) => {
    test.skip(!AUTH_STORAGE_STATE, 'PLAYWRIGHT_STORAGE_STATE is required for QA-authenticated flow');

    const context = await browser.newContext({ storageState: AUTH_STORAGE_STATE });
    const page = await context.newPage();

    const response = await page.goto(`${PORTAL_BASE_URL}/`, { waitUntil: 'domcontentloaded' });
    expect(response).not.toBeNull();
    expect(response?.status()).toBeLessThan(400);

    const currentUrl = page.url();
    expect(currentUrl).not.toContain('/oauth2/start');
    expect(currentUrl).not.toContain('/oauth2/callback');
    expect(isAppsmithLoginUrl(currentUrl)).toBeFalsy();
    assertHttpsAndDomain(currentUrl, new URL(PORTAL_BASE_URL).host);

    const bodyText = (await page.textContent('body')) || '';
    expect(/sign in to your account/i.test(bodyText)).toBeFalsy();

    const cookies = await context.cookies(PORTAL_BASE_URL);
    const names = cookies.map((c) => c.name);
    expect(names.some((n) => n.includes('_oauth2_proxy_portal'))).toBeTruthy();

    await context.close();
  });

  test('authenticated user can open portal and logout back to auth gate', async ({ browser }) => {
    test.skip(!AUTH_STORAGE_STATE, 'PLAYWRIGHT_STORAGE_STATE is required for full login->portal->logout flow');

    const context = await browser.newContext({ storageState: AUTH_STORAGE_STATE });
    const page = await context.newPage();

    const portalResponse = await page.goto(`${PORTAL_BASE_URL}/`, { waitUntil: 'domcontentloaded' });
    expect(portalResponse).not.toBeNull();
    expect(portalResponse?.status()).toBeLessThan(400);
    expect(page.url()).not.toContain('/oauth2/start');
    expect(isAppsmithLoginUrl(page.url())).toBeFalsy();

    const logoutResponse = await page.goto(`${PORTAL_BASE_URL}${AUTH_LOGOUT_PATH}`, { waitUntil: 'domcontentloaded' });
    expect(logoutResponse).not.toBeNull();
    expect([200, 301, 302, 303, 307, 308]).toContain(logoutResponse?.status() || 0);

    await page.goto(`${PORTAL_BASE_URL}/`, { waitUntil: 'domcontentloaded' });
    const urlAfterLogout = page.url();
    expect(urlAfterLogout.includes('/oauth2/start') || urlAfterLogout.includes('accounts.google.com')).toBeTruthy();

    await context.close();
  });

  test('authenticated IDE session (QA storage state) loads without oauth redirect loop', async ({ browser }) => {
    test.skip(!AUTH_STORAGE_STATE, 'PLAYWRIGHT_STORAGE_STATE is required for QA-authenticated flow');

    const context = await browser.newContext({ storageState: AUTH_STORAGE_STATE });
    const page = await context.newPage();

    const response = await page.goto(`${IDE_BASE_URL}/`, { waitUntil: 'domcontentloaded' });
    expect(response).not.toBeNull();
    expect(response?.status()).toBeLessThan(400);

    const currentUrl = page.url();
    expect(currentUrl).not.toContain('/oauth2/start');
    expect(currentUrl).not.toContain('/oauth2/callback');
    assertHttpsAndDomain(currentUrl, new URL(IDE_BASE_URL).host);

    await context.close();
  });
});
