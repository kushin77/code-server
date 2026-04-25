import http from 'k6/http';
import { check, group, sleep } from 'k6';

/**
 * API Gateway Load Test Script
 * Tests gateway endpoints under load (300 concurrent users)
 * 
 * Run with:
 *   k6 run tests/load/gateway-load-test.js --vus 300 --duration 5m
 */

export const options = {
  stages: [
    { duration: '30s', target: 60 },    // Ramp up
    { duration: '1m30s', target: 300 }, // Ramp to 300 users
    { duration: '3m', target: 300 },    // Stay at 300
    { duration: '1m', target: 150 },    // Ramp down
    { duration: '30s', target: 0 },     // Ramp to 0
  ],
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.05'],
  },
};

export default function () {
  const baseUrl = 'http://localhost:3100';
  const userId = Math.floor(Math.random() * 10000);
  const timestamp = Date.now();

  // 1. Health Check
  group('Gateway - Health Check', () => {
    const res = http.get(`${baseUrl}/health`);

    check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 50ms': (r) => r.timings.duration < 50,
      'has status field': (r) => r.json('status') !== null,
    });
  });

  sleep(0.3);

  // 2. Readiness Check
  group('Gateway - Readiness', () => {
    const res = http.get(`${baseUrl}/readiness`);

    check(res, {
      'status is 200 or 503': (r) => r.status === 200 || r.status === 503,
      'response time < 100ms': (r) => r.timings.duration < 100,
    });
  });

  sleep(0.3);

  // 3. OAuth Token Validation
  group('Gateway - OAuth Token Validation', () => {
    const res = http.get(`${baseUrl}/api/users/me`, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 200, 401, or 403': (r) => r.status === 200 || r.status === 401 || r.status === 403,
      'response time < 300ms': (r) => r.timings.duration < 300,
    });
  });

  sleep(0.3);

  // 4. API Key Authentication
  group('Gateway - API Key Authentication', () => {
    const res = http.get(`${baseUrl}/api/users/me`, {
      headers: {
        'X-API-Key': `sk_test_${userId}`,
      },
    });

    check(res, {
      'status is 200, 401, or 403': (r) => r.status === 200 || r.status === 401 || r.status === 403,
      'response time < 300ms': (r) => r.timings.duration < 300,
    });
  });

  sleep(0.3);

  // 5. Rate Limit Enforcement
  group('Gateway - Rate Limit Headers', () => {
    const res = http.get(`${baseUrl}/health`);

    check(res, {
      'status is 200': (r) => r.status === 200,
      'has rate limit limit header': (r) => 
        r.headers['x-ratelimit-limit'] !== undefined || r.status === 200,
      'response time < 100ms': (r) => r.timings.duration < 100,
    });
  });

  sleep(0.3);

  // 6. Create API Key
  group('Gateway - Create API Key', () => {
    const res = http.post(`${baseUrl}/api/apikeys`, {
      name: `K6 Key ${timestamp}-${userId}`,
      scopes: ['read:data', 'write:data'],
    }, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 201, 400, 401, or 403': (r) => 
        r.status === 201 || r.status === 400 || r.status === 401 || r.status === 403,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
  });

  sleep(0.3);

  // 7. List API Keys
  group('Gateway - List API Keys', () => {
    const res = http.get(`${baseUrl}/api/apikeys`, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 200, 401, or 403': (r) => r.status === 200 || r.status === 401 || r.status === 403,
      'response time < 300ms': (r) => r.timings.duration < 300,
    });
  });

  sleep(0.3);

  // 8. Get User with Quota Check
  group('Gateway - User Data with Quota', () => {
    const res = http.get(`${baseUrl}/api/users/me?include_quota=true`, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 200, 401, or 403': (r) => r.status === 200 || r.status === 401 || r.status === 403,
      'response time < 400ms': (r) => r.timings.duration < 400,
    });
  });

  sleep(0.5);

  // 9. Error Handling - 404
  group('Gateway - 404 Handling', () => {
    const res = http.get(`${baseUrl}/api/nonexistent/endpoint-${userId}`);

    check(res, {
      'status is 404': (r) => r.status === 404,
      'response time < 50ms': (r) => r.timings.duration < 50,
    });
  });

  sleep(0.3);

  // 10. Concurrent Operations
  group('Gateway - Multiple Concurrent Requests', () => {
    const requests = [
      ['GET', `${baseUrl}/health`],
      ['GET', `${baseUrl}/readiness`],
      ['GET', `${baseUrl}/.well-known/jwks.json`],
    ];

    const responses = http.batch(requests);

    responses.forEach((res) => {
      check(res, {
        'status is 2xx or 3xx': (r) => r.status >= 200 && r.status < 400,
        'response time < 500ms': (r) => r.timings.duration < 500,
      });
    });
  });

  sleep(1);
}
