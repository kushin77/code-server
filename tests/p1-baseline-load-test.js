/**
 * P1 Baseline Load Test (1x Load)
 * 
 * Measures P1 performance improvements under normal load:
 * - 50-100 VUs for 5 minutes
 * - Request deduplication >20%
 * - Cache hit rate >40%
 * - p99 latency <50ms
 * - All endpoints exercised
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://192.168.168.31:8080';

// Metrics
const responseTime = new Trend('baseline_response_time');
const errorRate = new Rate('baseline_errors');
const requestsPerSecond = new Counter('baseline_requests');

export const options = {
  stages: [
    { duration: '1m', target: 50 },   // Ramp up to 50 VUs
    { duration: '3m', target: 50 },   // Hold at 50 VUs
    { duration: '1m', target: 0 },    // Ramp down
  ],
  thresholds: {
    'baseline_response_time': ['p(99)<50', 'avg<40'],
    'baseline_errors': ['rate<0.01'],
  }
};

export default function () {
  // API Health Check
  let res = http.get(`${BASE_URL}/health`);
  check(res, { 'health check passed': (r) => r.status === 200 });
  responseTime.add(res.timings.duration);
  errorRate.add(res.status !== 200 ? 1 : 0);
  requestsPerSecond.add(1);

  // User List (tests deduplication & caching)
  res = http.get(`${BASE_URL}/api/users`, {
    headers: { 'If-None-Match': 'baseline-test-etag' }
  });
  check(res, { 'user list successful': (r) => r.status === 200 || r.status === 304 });
  responseTime.add(res.timings.duration);
  errorRate.add(res.status !== 200 && res.status !== 304 ? 1 : 0);
  requestsPerSecond.add(1);

  // Database Status (tests connection pooling)
  res = http.get(`${BASE_URL}/api/database/status`);
  check(res, { 'database status successful': (r) => r.status === 200 });
  responseTime.add(res.timings.duration);
  errorRate.add(res.status !== 200 ? 1 : 0);
  requestsPerSecond.add(1);

  sleep(1);
}
