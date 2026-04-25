import http from 'k6/http';
import { check, group, sleep } from 'k6';

/**
 * OAuth Load Test Script
 * Tests OAuth endpoints under load (100 concurrent users)
 * 
 * Run with:
 *   k6 run tests/load/oauth-load-test.js --vus 100 --duration 5m
 */

export const options = {
  stages: [
    { duration: '30s', target: 20 },   // Ramp up
    { duration: '1m30s', target: 100 }, // Ramp to 100 users
    { duration: '3m', target: 100 },    // Stay at 100
    { duration: '1m', target: 50 },     // Ramp down
    { duration: '30s', target: 0 },     // Ramp to 0
  ],
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.1'],
  },
};

export default function () {
  const baseUrl = 'http://localhost:3100';

  // 1. Authorization Request
  group('OAuth - Authorization Request', () => {
    const state = `state-${Date.now()}-${Math.random()}`;
    const res = http.get(`${baseUrl}/oauth/authorize`, {
      params: {
        client_id: 'k6-test-app',
        redirect_uri: 'http://localhost:3000/oauth/callback',
        scope: 'read:user openid profile email',
        state: state,
        code_challenge: 'E9Mrozoa2owUednMZ9ZSXK-6OyPgNnnW8_mwQvTUI30',
        code_challenge_method: 'S256',
      },
    });

    check(res, {
      'status is 200 or 302': (r) => r.status === 200 || r.status === 302,
      'response time < 500ms': (r) => r.timings.duration < 500,
      'has location header': (r) => r.status === 302 ? r.headers.Location : true,
    });
  });

  sleep(0.5);

  // 2. Token Exchange
  group('OAuth - Token Exchange', () => {
    const res = http.post(`${baseUrl}/oauth/token`, {
      grant_type: 'authorization_code',
      client_id: 'k6-test-app',
      code: `code-${Date.now()}`,
      redirect_uri: 'http://localhost:3000/oauth/callback',
      code_verifier: 'test-code-verifier-1234567890abcdefghij',
    });

    check(res, {
      'status is 200 or 400': (r) => r.status === 200 || r.status === 400,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
  });

  sleep(0.5);

  // 3. JWKS Endpoint
  group('OAuth - JWKS Endpoint', () => {
    const res = http.get(`${baseUrl}/.well-known/jwks.json`);

    check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 200ms': (r) => r.timings.duration < 200,
      'has keys': (r) => r.json('keys').length > 0,
    });
  });

  sleep(0.5);

  // 4. GitHub OAuth Callback
  group('OAuth - Provider Callback', () => {
    const res = http.get(`${baseUrl}/oauth/github/callback`, {
      params: {
        code: `github-${Date.now()}`,
        state: `state-${Date.now()}`,
      },
    });

    check(res, {
      'status is 200, 302, 400, or 401': (r) => 
        r.status === 200 || r.status === 302 || r.status === 400 || r.status === 401,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
  });

  sleep(1);
}
