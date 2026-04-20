# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: kushnir-cloud-appsmith-login.spec.ts >> kushnir.cloud Appsmith login path >> logout endpoint redirects through oauth2 sign out with return URL
- Location: specs\kushnir-cloud-appsmith-login.spec.ts:107:7

# Error details

```
Error: apiRequestContext.get: write EPROTO 78190000:error:0A000438:SSL routines:ssl3_read_bytes:tlsv1 alert internal error:openssl\ssl\record\rec_layer_s3.c:916:SSL alert number 80

Call log:
  - → GET https://kushnir.cloud/logout
    - user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.7727.15 Safari/537.36
    - accept: */*
    - accept-encoding: gzip,deflate,br

```

# Test source

```ts
  8   | const STATIC_CSS_PATH = process.env.PORTAL_STATIC_CSS_PATH || '/static/css/main.c5955fd3.css';
  9   | const AUTH_STORAGE_STATE = process.env.PLAYWRIGHT_STORAGE_STATE || '';
  10  | const REQUIRE_SINGLE_LOGIN = process.env.REQUIRE_SINGLE_LOGIN === '1';
  11  | const PORTAL_EXPECTED_REDIRECT_URI = process.env.PORTAL_EXPECTED_REDIRECT_URI || `${PORTAL_BASE_URL}/oauth2/callback`;
  12  | const IDE_EXPECTED_REDIRECT_URI = process.env.IDE_EXPECTED_REDIRECT_URI || `${IDE_BASE_URL}/oauth2/callback`;
  13  | const APPSMITH_LOGIN_PATH = process.env.APPSMITH_LOGIN_PATH || '/user/login';
  14  | const APPSMITH_EXPECTED_REDIRECT_URI = process.env.APPSMITH_EXPECTED_REDIRECT_URI || `${PORTAL_BASE_URL}/login/oauth2/code/github`;
  15  | 
  16  | const REDIRECT_STATUSES = [301, 302, 303, 307, 308];
  17  | 
  18  | function isAppsmithLoginUrl(url: string): boolean {
  19  |   return url.includes('/user/login') || url.includes('/login/oauth2/code/github');
  20  | }
  21  | 
  22  | function assertHttpsAndDomain(url: string, expectedHost: string): void {
  23  |   const parsed = new URL(url);
  24  |   expect(parsed.protocol).toBe('https:');
  25  |   expect(parsed.host).toBe(expectedHost);
  26  | }
  27  | 
  28  | function normalizeUrl(input: string): string {
  29  |   return input.replace(/\/+$/, '');
  30  | }
  31  | 
  32  | async function fetchAppsmithLoginResponse(
  33  |   request: { get: (url: string, options?: { maxRedirects?: number; timeout?: number }) => Promise<{ status: number; headers(): Record<string, string>; text(): Promise<string> }> },
  34  |   requestUrl: string,
  35  | ): Promise<{ response?: { status: number; headers(): Record<string, string>; text(): Promise<string> }; skippedReason?: string }> {
  36  |   try {
  37  |     const response = await request.get(requestUrl, { maxRedirects: 0, timeout: 15000 });
  38  |     return { response };
  39  |   } catch (error) {
  40  |     const message = error instanceof Error ? error.message : String(error);
  41  |     return { skippedReason: `Appsmith login page unavailable in this environment: ${message}` };
  42  |   }
  43  | }
  44  | 
  45  | async function resolveRedirectUriFromAuthStart(
  46  |   requestUrl: string,
  47  |   requestGet: (url: string) => Promise<{ status: number; location: string }> 
  48  | ): Promise<string> {
  49  |   let currentUrl = requestUrl;
  50  | 
  51  |   for (let hop = 0; hop < 5; hop += 1) {
  52  |     const { status, location } = await requestGet(currentUrl);
  53  |     expect([301, 302, 303, 307, 308]).toContain(status);
  54  |     expect(location).toBeTruthy();
  55  | 
  56  |     const resolved = location.startsWith('http') ? location : new URL(location, currentUrl).toString();
  57  |     const redirectUri = new URL(resolved).searchParams.get('redirect_uri');
  58  | 
  59  |     if (redirectUri) {
  60  |       return redirectUri;
  61  |     }
  62  | 
  63  |     currentUrl = resolved;
  64  |   }
  65  | 
  66  |   throw new Error(`No redirect_uri query parameter found after redirects from ${requestUrl}`);
  67  | }
  68  | 
  69  | async function getRedirectLocation(requestUrl: string, request: { get: (url: string, options?: { maxRedirects?: number }) => Promise<{ status: () => number; headers: () => Record<string, string> }> }): Promise<{ status: number; location: string }> {
  70  |   const response = await request.get(requestUrl, { maxRedirects: 0 });
  71  |   return {
  72  |     status: response.status(),
  73  |     location: response.headers()['location'] || '',
  74  |   };
  75  | }
  76  | 
  77  | test.describe('kushnir.cloud Appsmith login path', () => {
  78  |   test('portal static css is served as text/css', async ({ request }) => {
  79  |     const response = await request.get(`${PORTAL_BASE_URL}${STATIC_CSS_PATH}`);
  80  |     expect(response.status()).toBe(200);
  81  |     const contentType = response.headers()['content-type'] || '';
  82  |     expect(contentType.toLowerCase()).toContain('text/css');
  83  |   });
  84  | 
  85  |   test('unauthenticated root redirects to oauth2 start endpoint', async ({ request }) => {
  86  |     const response = await request.get(`${PORTAL_BASE_URL}/`, { maxRedirects: 0 });
  87  |     const status = response.status();
  88  |     expect([...REDIRECT_STATUSES, 401, 403]).toContain(status);
  89  | 
  90  |     if (REDIRECT_STATUSES.includes(status)) {
  91  |       const location = response.headers()['location'] || '';
  92  |       expect(location).toContain(AUTH_START_PATH);
  93  |       expect(location).toContain('rd=');
  94  |     }
  95  |   });
  96  | 
  97  |   test('oauth2 start endpoint emits redirect with rd parameter preserved', async ({ request }) => {
  98  |     const target = `${PORTAL_BASE_URL}${AUTH_START_PATH}?rd=%2Fuser%2Flogin`;
  99  |     const { status, location } = await getRedirectLocation(target, request);
  100 | 
  101 |     expect(REDIRECT_STATUSES).toContain(status);
  102 |     expect(location).toBeTruthy();
  103 |     expect(location).toContain('redirect_uri=');
  104 |     expect(location).toContain('state=');
  105 |   });
  106 | 
  107 |   test('logout endpoint redirects through oauth2 sign out with return URL', async ({ request }) => {
> 108 |     const response = await request.get(`${PORTAL_BASE_URL}${AUTH_LOGOUT_PATH}`, { maxRedirects: 0 });
      |                                    ^ Error: apiRequestContext.get: write EPROTO 78190000:error:0A000438:SSL routines:ssl3_read_bytes:tlsv1 alert internal error:openssl\ssl\record\rec_layer_s3.c:916:SSL alert number 80
  109 |     expect(REDIRECT_STATUSES).toContain(response.status());
  110 | 
  111 |     const location = response.headers()['location'] || '';
  112 |     expect(location).toContain('/oauth2/sign_out');
  113 |     expect(location).toContain('rd=');
  114 |   });
  115 | 
  116 |   test('interactive login starts from kushnir.cloud and reaches the auth provider', async ({ request }) => {
  117 |     const initial = await request.get(`${PORTAL_BASE_URL}/`, { maxRedirects: 0 });
  118 |     expect(initial).not.toBeNull();
  119 | 
  120 |     const status = initial.status();
  121 |     expect([200, 401, 403, 302, 303, 307, 308]).toContain(status);
  122 | 
  123 |     const initialLocation = initial.headers()['location'] || '';
  124 |     if (initialLocation) {
  125 |       expect(initialLocation).toMatch(/oauth2\/start|accounts\.google\.com|github\.com/i);
  126 |     }
  127 | 
  128 |     const authStart = await request.get(`${PORTAL_BASE_URL}${AUTH_START_PATH}?rd=%2F`, { maxRedirects: 0 });
  129 |     expect(authStart).not.toBeNull();
  130 |     expect([200, 302, 303, 307, 308]).toContain(authStart.status());
  131 | 
  132 |     const authLocation = authStart.headers()['location'] || '';
  133 |     if (authLocation) {
  134 |       expect(authLocation).toMatch(/accounts\.google\.com|github\.com/i);
  135 |     }
  136 |   });
  137 | 
  138 |   test('portal oauth start resolves to expected google redirect_uri contract', async ({ request }) => {
  139 |     const redirectUri = await resolveRedirectUriFromAuthStart(
  140 |       `${PORTAL_BASE_URL}${AUTH_START_PATH}?rd=%2F`,
  141 |       async (url: string) => {
  142 |         const response = await request.get(url, { maxRedirects: 0 });
  143 |         return {
  144 |           status: response.status(),
  145 |           location: response.headers()['location'] || '',
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
```