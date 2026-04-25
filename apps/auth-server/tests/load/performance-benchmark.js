import http from 'k6/http';
import { check, group } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

/**
 * Performance Benchmarking Script
 * Establishes baseline metrics for OAuth, user, team, and gateway endpoints
 * 
 * Run with:
 *   k6 run tests/load/performance-benchmark.js --vus 50 --duration 5m
 */

// Custom metrics
const authDuration = new Trend('auth_duration');
const oauthDuration = new Trend('oauth_duration');
const userDuration = new Trend('user_duration');
const teamDuration = new Trend('team_duration');
const gatewayDuration = new Trend('gateway_duration');

const authErrors = new Counter('auth_errors');
const oauthErrors = new Counter('oauth_errors');
const userErrors = new Counter('user_errors');
const teamErrors = new Counter('team_errors');
const gatewayErrors = new Counter('gateway_errors');

const concurrentUsers = new Gauge('concurrent_users');

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up
    { duration: '2m', target: 50 },    // Ramp to 50 users
    { duration: '2m', target: 50 },    // Stay at 50
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000', 'p(99)<2000'],
    'http_req_failed': ['rate<0.05'],
  },
};

export default function () {
  const baseUrl = 'http://localhost:3100';
  
  concurrentUsers.add(__VU);

  // ===== OAUTH BENCHMARKS =====
  group('Benchmark - OAuth', () => {
    // 1. Authorization endpoint
    const authRes = http.get(`${baseUrl}/oauth/authorize`, {
      params: {
        client_id: 'benchmark',
        redirect_uri: 'http://localhost:3000/callback',
        scope: 'openid profile email',
        state: `state-${__VU}-${__ITER}`,
      },
    });

    oauthDuration.add(authRes.timings.duration, { endpoint: 'authorize' });
    if (authRes.status > 400) oauthErrors.add(1);
    
    check(authRes, {
      'authorize < 500ms': (r) => r.timings.duration < 500,
    });

    // 2. Token endpoint
    const tokenRes = http.post(`${baseUrl}/oauth/token`, {
      grant_type: 'authorization_code',
      client_id: 'benchmark',
      code: `code-${__ITER}`,
      redirect_uri: 'http://localhost:3000/callback',
    });

    oauthDuration.add(tokenRes.timings.duration, { endpoint: 'token' });
    if (tokenRes.status > 400) oauthErrors.add(1);
    
    check(tokenRes, {
      'token < 500ms': (r) => r.timings.duration < 500,
    });

    // 3. JWKS endpoint
    const jwksRes = http.get(`${baseUrl}/.well-known/jwks.json`);

    oauthDuration.add(jwksRes.timings.duration, { endpoint: 'jwks' });
    if (jwksRes.status > 400) oauthErrors.add(1);
    
    check(jwksRes, {
      'JWKS < 200ms': (r) => r.timings.duration < 200,
    });
  });

  // ===== USER BENCHMARKS =====
  group('Benchmark - User', () => {
    // 1. Registration
    const regRes = http.post(`${baseUrl}/auth/register`, {
      email: `bench-${__VU}-${__ITER}@example.com`,
      password: 'BenchmarkPassword123!@#',
      name: 'Benchmark User',
    });

    userDuration.add(regRes.timings.duration, { endpoint: 'register' });
    if (regRes.status > 400) userErrors.add(1);
    
    check(regRes, {
      'register < 1000ms': (r) => r.timings.duration < 1000,
    });

    // 2. Login
    const loginRes = http.post(`${baseUrl}/auth/login`, {
      email: `user-${__VU}@example.com`,
      password: 'Password123!@#',
    });

    userDuration.add(loginRes.timings.duration, { endpoint: 'login' });
    if (loginRes.status > 400) userErrors.add(1);
    
    check(loginRes, {
      'login < 500ms': (r) => r.timings.duration < 500,
    });

    // 3. Profile
    const profileRes = http.get(`${baseUrl}/api/users/me`, {
      headers: {
        'Authorization': 'Bearer test-token',
      },
    });

    userDuration.add(profileRes.timings.duration, { endpoint: 'profile' });
    if (profileRes.status > 400) userErrors.add(1);
    
    check(profileRes, {
      'profile < 300ms': (r) => r.timings.duration < 300,
    });
  });

  // ===== TEAM BENCHMARKS =====
  group('Benchmark - Team', () => {
    // 1. Create Organization
    const orgRes = http.post(`${baseUrl}/api/organizations`, {
      name: `Bench Org ${__VU}-${__ITER}`,
      slug: `bench-org-${__VU}-${__ITER}`,
    }, {
      headers: {
        'Authorization': 'Bearer test-token',
      },
    });

    teamDuration.add(orgRes.timings.duration, { endpoint: 'create_org' });
    if (orgRes.status > 400) teamErrors.add(1);
    
    check(orgRes, {
      'create org < 800ms': (r) => r.timings.duration < 800,
    });

    // 2. Create Team
    const teamRes = http.post(`${baseUrl}/api/organizations/org-${__VU}/teams`, {
      name: `Bench Team ${__VU}-${__ITER}`,
      slug: `bench-team-${__VU}-${__ITER}`,
    }, {
      headers: {
        'Authorization': 'Bearer test-token',
      },
    });

    teamDuration.add(teamRes.timings.duration, { endpoint: 'create_team' });
    if (teamRes.status > 400) teamErrors.add(1);
    
    check(teamRes, {
      'create team < 800ms': (r) => r.timings.duration < 800,
    });

    // 3. List Members
    const membersRes = http.get(`${baseUrl}/api/teams/team-${__VU}/members`, {
      headers: {
        'Authorization': 'Bearer test-token',
      },
    });

    teamDuration.add(membersRes.timings.duration, { endpoint: 'list_members' });
    if (membersRes.status > 400) teamErrors.add(1);
    
    check(membersRes, {
      'list members < 400ms': (r) => r.timings.duration < 400,
    });
  });

  // ===== GATEWAY BENCHMARKS =====
  group('Benchmark - Gateway', () => {
    // 1. Health Check
    const healthRes = http.get(`${baseUrl}/health`);

    gatewayDuration.add(healthRes.timings.duration, { endpoint: 'health' });
    if (healthRes.status > 400) gatewayErrors.add(1);
    
    check(healthRes, {
      'health < 100ms': (r) => r.timings.duration < 100,
    });

    // 2. Readiness
    const readinessRes = http.get(`${baseUrl}/readiness`);

    gatewayDuration.add(readinessRes.timings.duration, { endpoint: 'readiness' });
    if (readinessRes.status > 400) gatewayErrors.add(1);
    
    check(readinessRes, {
      'readiness < 200ms': (r) => r.timings.duration < 200,
    });

    // 3. API Key Auth
    const apiKeyRes = http.get(`${baseUrl}/api/apikeys`, {
      headers: {
        'Authorization': 'Bearer test-token',
      },
    });

    gatewayDuration.add(apiKeyRes.timings.duration, { endpoint: 'api_key' });
    if (apiKeyRes.status > 400) gatewayErrors.add(1);
    
    check(apiKeyRes, {
      'API key auth < 300ms': (r) => r.timings.duration < 300,
    });

    // 4. Rate Limit Check
    const rateLimitRes = http.get(`${baseUrl}/health`);

    gatewayDuration.add(rateLimitRes.timings.duration, { endpoint: 'rate_limit' });
    if (rateLimitRes.status === 429) gatewayErrors.add(1);
    
    check(rateLimitRes, {
      'rate limit enforced or allowed': (r) => r.status === 200 || r.status === 429,
    });
  });
}
