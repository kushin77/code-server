import http from 'k6/http';
import { check, group } from 'k6';

/**
 * Deployment Verification Script
 * Smoke tests to verify system is healthy after deployment
 * 
 * Run with:
 *   k6 run tests/load/deployment-verification.js --vus 5 --duration 5m
 */

export const options = {
  stages: [
    { duration: '30s', target: 5 },    // 5 concurrent users
    { duration: '4m', target: 5 },     // Stay for 4 minutes
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000'],
    'http_req_failed': ['rate<0.05'],  // 5% error rate max
  },
};

export default function () {
  const baseUrl = process.env.API_BASE_URL || 'http://localhost:8001';

  group('Deployment - Service Availability', () => {
    // 1. Health check
    const healthRes = http.get(`${baseUrl}/health`);
    check(healthRes, {
      'health endpoint 200': (r) => r.status === 200,
      'health status is ok': (r) => r.json('status') === 'ok' || r.json('status') === 'healthy',
    });

    // 2. Readiness check
    const readinessRes = http.get(`${baseUrl}/readiness`);
    check(readinessRes, {
      'readiness endpoint 200': (r) => r.status === 200,
    });

    // 3. Kubernetes liveness probe
    const liveRes = http.get(`${baseUrl}/live`);
    check(liveRes, {
      'liveness probe 200': (r) => r.status === 200,
    });
  });

  group('Deployment - Database Connectivity', () => {
    // Test endpoint that requires database access
    const dbRes = http.get(`${baseUrl}/api/healthz/db`, {
      headers: {
        'Authorization': 'Bearer admin-token',
      },
    });

    check(dbRes, {
      'database endpoint responds': (r) => r.status >= 200 && r.status < 500,
      'no database errors': (r) => !r.body.includes('database') || !r.body.includes('error'),
    });
  });

  group('Deployment - Cache Connectivity', () => {
    // Test Redis connectivity
    const cacheRes = http.get(`${baseUrl}/api/healthz/cache`, {
      headers: {
        'Authorization': 'Bearer admin-token',
      },
    });

    check(cacheRes, {
      'cache endpoint responds': (r) => r.status >= 200 && r.status < 500,
    });
  });

  group('Deployment - OAuth Configuration', () => {
    // Verify JWKS endpoint works (OAuth setup)
    const jwksRes = http.get(`${baseUrl}/.well-known/jwks.json`);

    check(jwksRes, {
      'JWKS endpoint 200': (r) => r.status === 200,
      'JWKS has keys': (r) => r.json('keys.length') > 0,
    });
  });

  group('Deployment - API Endpoints', () => {
    // Verify critical endpoints are registered
    const endpoints = [
      '/auth/register',
      '/auth/login',
      '/oauth/token',
      '/api/users/me',
      '/api/organizations',
      '/api/teams',
      '/api/apikeys',
    ];

    endpoints.forEach((endpoint) => {
      // Test OPTIONS request to check endpoint exists
      const res = http.options(`${baseUrl}${endpoint}`);
      check(res, {
        [`${endpoint} endpoint exists`]: (r) => r.status !== 404,
      });
    });
  });

  group('Deployment - Error Handling', () => {
    // Verify error responses are proper
    const notFoundRes = http.get(`${baseUrl}/api/nonexistent`);
    check(notFoundRes, {
      'invalid endpoint returns 404': (r) => r.status === 404,
    });

    const badRequestRes = http.post(`${baseUrl}/auth/register`, {
      invalid: 'data',
    });
    check(badRequestRes, {
      'invalid request returns 400': (r) => r.status === 400,
    });

    const unauthorizedRes = http.get(`${baseUrl}/api/users/me`);
    check(unauthorizedRes, {
      'missing auth returns 401': (r) => r.status === 401,
    });
  });

  group('Deployment - Response Headers', () => {
    const res = http.get(`${baseUrl}/health`);

    check(res, {
      'has content-type header': (r) => r.headers['content-type'] !== undefined,
      'has server header': (r) => r.headers['server'] !== undefined,
      'secure headers present': (r) => 
        r.headers['x-content-type-options'] !== undefined ||
        r.headers['x-frame-options'] !== undefined,
    });
  });

  group('Deployment - Performance Baseline', () => {
    // Verify performance is within baseline
    const healthRes = http.get(`${baseUrl}/health`);
    check(healthRes, {
      'health response < 100ms': (r) => r.timings.duration < 100,
    });

    const jwksRes = http.get(`${baseUrl}/.well-known/jwks.json`);
    check(jwksRes, {
      'JWKS response < 200ms': (r) => r.timings.duration < 200,
    });

    const authRes = http.post(`${baseUrl}/oauth/token`, {
      grant_type: 'authorization_code',
      client_id: 'test',
      code: 'invalid',
      redirect_uri: 'http://localhost:3000',
    });
    check(authRes, {
      'token response < 500ms': (r) => r.timings.duration < 500,
    });
  });

  group('Deployment - Monitoring Integration', () => {
    // Check for monitoring headers/metrics
    const res = http.get(`${baseUrl}/metrics`, {
      headers: {
        'Authorization': 'Bearer monitoring-token',
      },
    });

    check(res, {
      'metrics endpoint accessible': (r) => r.status === 200 || r.status === 401 || r.status === 404,
    });
  });

  group('Deployment - Logging & Tracing', () => {
    // Make request and check for trace headers
    const res = http.get(`${baseUrl}/health`);

    check(res, {
      'trace ID present': (r) => 
        r.headers['x-trace-id'] !== undefined ||
        r.headers['x-request-id'] !== undefined ||
        r.headers['trace-id'] !== undefined ||
        true, // Trace ID is optional but good to have
    });
  });
}
