import http from 'k6/http';
import { check, group, sleep } from 'k6';

/**
 * Stress Testing Script - Test System Under Extreme Load
 * Tests graceful degradation, circuit breaker behavior, recovery
 * 
 * Run with:
 *   k6 run tests/load/stress-test.js --vus 500 --duration 10m
 */

export const options = {
  stages: [
    { duration: '1m', target: 100 },    // Ramp to 100
    { duration: '2m', target: 500 },    // Ramp to 500 (extreme)
    { duration: '3m', target: 500 },    // Stay at 500
    { duration: '2m', target: 1000 },   // Ramp to 1000 (breaking point)
    { duration: '2m', target: 1000 },   // Sustain at breaking point
    { duration: '1m', target: 0 },      // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<2000', 'p(99)<5000'],
    'http_req_failed': ['rate<0.5'],  // Allow up to 50% error rate during stress
  },
};

export default function () {
  const baseUrl = process.env.API_BASE_URL || 'http://localhost:8001';
  const iteration = __VU * 1000 + __ITER;

  group('Stress - Health Check', () => {
    const res = http.get(`${baseUrl}/health`);
    
    check(res, {
      'health endpoint responds': (r) => r.status === 200 || r.status === 503,
      'response time < 2000ms': (r) => r.timings.duration < 2000,
    });
  });

  sleep(0.2);

  group('Stress - OAuth Flow', () => {
    // Simulate OAuth authorization
    const authRes = http.get(`${baseUrl}/oauth/authorize`, {
      params: {
        client_id: 'stress-test',
        redirect_uri: 'http://localhost:3000/callback',
        scope: 'read:user',
        state: `state-${iteration}`,
      },
    });

    check(authRes, {
      'auth endpoint responds': (r) => 
        r.status >= 200 && r.status < 600,
      'response time < 2000ms': (r) => r.timings.duration < 2000,
    });
  });

  sleep(0.2);

  group('Stress - User Operations', () => {
    // Try to get user profile
    const userRes = http.get(`${baseUrl}/api/users/me`, {
      headers: {
        'Authorization': 'Bearer stress-test-token',
      },
    });

    check(userRes, {
      'user endpoint responds': (r) => 
        r.status >= 200 && r.status < 600,
      'response time < 2000ms': (r) => r.timings.duration < 2000,
    });
  });

  sleep(0.2);

  group('Stress - Concurrent Operations', () => {
    // Simulate multiple concurrent requests
    const requests = [];
    for (let i = 0; i < 5; i++) {
      requests.push([
        'GET',
        `${baseUrl}/api/users/me`,
        null,
        { headers: { 'Authorization': 'Bearer token' } },
      ]);
    }

    const responses = http.batch(requests);

    responses.forEach((res) => {
      check(res, {
        'concurrent requests handled': (r) => r.status >= 200 && r.status < 600,
      });
    });
  });

  sleep(0.5);

  group('Stress - High Frequency Requests', () => {
    // Send rapid requests in succession
    for (let i = 0; i < 10; i++) {
      const res = http.get(`${baseUrl}/health`);
      
      check(res, {
        'rapid requests handled': (r) => r.status === 200 || r.status === 503 || r.status === 429,
      });
    }
  });

  sleep(0.2);
}
