import http from 'k6/http';
import { check, group, sleep } from 'k6';

/**
 * User Management Load Test Script
 * Tests user endpoints under load (200 concurrent users)
 * 
 * Run with:
 *   k6 run tests/load/user-load-test.js --vus 200 --duration 5m
 */

export const options = {
  stages: [
    { duration: '30s', target: 50 },    // Ramp up
    { duration: '1m30s', target: 200 }, // Ramp to 200 users
    { duration: '3m', target: 200 },    // Stay at 200
    { duration: '1m', target: 100 },    // Ramp down
    { duration: '30s', target: 0 },     // Ramp to 0
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000', 'p(99)<2000'],
    'http_req_failed': ['rate<0.1'],
  },
};

export default function () {
  const baseUrl = 'http://localhost:3100';
  const userId = Math.floor(Math.random() * 10000);
  const timestamp = Date.now();

  // 1. User Registration
  group('User - Registration', () => {
    const res = http.post(`${baseUrl}/auth/register`, {
      email: `k6-user-${timestamp}-${userId}@example.com`,
      password: 'K6LoadTestPassword123!@#',
      name: `K6 Test User ${userId}`,
    });

    check(res, {
      'status is 201 or 400': (r) => r.status === 201 || r.status === 400,
      'response time < 1000ms': (r) => r.timings.duration < 1000,
    });
  });

  sleep(1);

  // 2. User Login
  group('User - Login', () => {
    const res = http.post(`${baseUrl}/auth/login`, {
      email: `test-${userId}@example.com`,
      password: 'TestPassword123!@#',
    });

    check(res, {
      'status is 200, 400, or 401': (r) => r.status === 200 || r.status === 400 || r.status === 401,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
  });

  sleep(0.5);

  // 3. Get User Profile
  group('User - Get Profile', () => {
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

  sleep(0.5);

  // 4. Update User Profile
  group('User - Update Profile', () => {
    const res = http.patch(`${baseUrl}/api/users/me`, {
      name: `Updated User ${userId}`,
      timezone: 'America/New_York',
    }, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 200, 400, 401, or 403': (r) => 
        r.status === 200 || r.status === 400 || r.status === 401 || r.status === 403,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
  });

  sleep(0.5);

  // 5. Password Reset Request
  group('User - Password Reset', () => {
    const res = http.post(`${baseUrl}/auth/password-reset/request`, {
      email: `user-${userId}@example.com`,
    });

    check(res, {
      'status is 200 or 202': (r) => r.status === 200 || r.status === 202,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
  });

  sleep(0.5);

  // 6. Enable MFA
  group('User - MFA Setup', () => {
    const res = http.post(`${baseUrl}/api/mfa/authenticator/setup`, {}, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 200, 401, or 403': (r) => r.status === 200 || r.status === 401 || r.status === 403,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
  });

  sleep(1);
}
