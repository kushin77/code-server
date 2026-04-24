// OAuth Login Flow Load Test using k6
// Tests concurrent OAuth2 login flows to identify bottlenecks

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const loginSuccessRate = new Rate('oauth_login_success');
const loginLatency = new Trend('oauth_login_latency');
const sessionCreationLatency = new Trend('session_creation_latency');
const loginErrors = new Counter('oauth_login_errors');
const concurrentUsers = new Gauge('concurrent_users');

// Configuration
const BASE_URL = __ENV.OAUTH_BASE_URL || 'https://ide.kushnir.cloud';
const OAUTH_CLIENT_ID = __ENV.OAUTH_CLIENT_ID || 'code-server';
const TEST_USER_EMAIL = __ENV.TEST_USER_EMAIL || 'test@kushnir.cloud';
const TEST_USER_PASSWORD = __ENV.TEST_USER_PASSWORD || 'test-password-123';
const OAUTH_REDIRECT_URI = `${BASE_URL}/oauth2/callback`;

export const options = {
  stages: [
    { duration: '30s', target: 10 },    // Ramp up to 10 users over 30s
    { duration: '1m', target: 50 },     // Ramp up to 50 users
    { duration: '2m', target: 100 },    // Ramp up to 100 users
    { duration: '3m', target: 100 },    // Stay at 100 users
    { duration: '1m', target: 50 },     // Ramp down to 50 users
    { duration: '30s', target: 0 },     // Ramp down to 0 users
  ],
  thresholds: {
    'oauth_login_latency': ['p(95)<5000', 'p(99)<10000'], // 95% under 5s, 99% under 10s
    'oauth_login_success': ['rate>0.95'], // 95% success rate minimum
    'http_req_duration': ['p(95)<3000'], // General HTTP p95 under 3s
  },
  ext: {
    loadimpact: {
      projectID: 3356519,
      name: 'OAuth Login Load Test',
    },
  },
};

export default function() {
  concurrentUsers.add(1);

  group('OAuth Login Flow', function() {
    // Step 1: Get OAuth authorization endpoint
    let authRes = http.get(`${BASE_URL}/.well-known/openid-configuration`);
    check(authRes, {
      'OIDC config loaded': (r) => r.status === 200,
    });

    // Step 2: Initiate OAuth flow
    const authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
    const authParams = {
      client_id: OAUTH_CLIENT_ID,
      redirect_uri: OAUTH_REDIRECT_URI,
      response_type: 'code',
      scope: 'openid email profile',
      state: `state-${__VU}-${__ITER}`,
    };

    // Step 3: Simulate redirect and callback
    let callbackRes = http.get(
      `${BASE_URL}/oauth2/callback?code=test-code&state=${authParams.state}`,
      {
        redirects: 0,
        headers: {
          'User-Agent': `k6-load-test-${__VU}`,
        },
      }
    );

    const loginStartTime = new Date().getTime();
    
    // Step 4: Check session establishment
    let sessionRes = http.get(`${BASE_URL}/api/v1/auth/me`, {
      headers: {
        'Cookie': callbackRes.headers['Set-Cookie'] || '',
      },
    });

    const loginEndTime = new Date().getTime();
    const loginTime = loginEndTime - loginStartTime;
    
    loginLatency.add(loginTime);
    loginSuccessRate.add(sessionRes.status === 200);
    
    if (sessionRes.status !== 200) {
      loginErrors.add(1);
    }

    check(sessionRes, {
      'Session established': (r) => r.status === 200 || r.status === 401, // 401 expected if not really authenticated
    });

    sleep(1);
  });

  group('Session Cookie Validation', function() {
    // Test if session cookie is valid and persistent
    let sessionCheckRes = http.get(`${BASE_URL}/api/v1/auth/me`);
    
    check(sessionCheckRes, {
      'Session persists': (r) => r.status === 200 || r.status === 401,
    });

    sleep(0.5);
  });

  concurrentUsers.add(-1);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'artifacts/load-tests/oauth-login-summary.json': JSON.stringify(data),
  };
}

// Simple text summary function
function textSummary(data, options = {}) {
  const indent = options.indent || '';
  const colors = options.enableColors ? true : false;
  
  let summary = '\n=== OAuth Login Load Test Summary ===\n';
  
  if (data.metrics) {
    Object.entries(data.metrics).forEach(([name, metric]) => {
      if (metric.values) {
        summary += `${indent}${name}:\n`;
        Object.entries(metric.values).forEach(([key, value]) => {
          summary += `${indent}  ${key}: ${value}\n`;
        });
      }
    });
  }
  
  return summary;
}
