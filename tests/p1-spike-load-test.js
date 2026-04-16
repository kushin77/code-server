/**
 * P1 Spike Load Test (5x Load)
 * 
 * Tests behavior under sudden traffic surge:
 * - 250 VUs immediately
 * - Hold for 2 minutes
 * - Verify system doesn't degrade gracefully
 * - Measure connection pool behavior under stress
 * - Verify error rate remains <1%
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://192.168.168.31:8080';

// Metrics
const responseTime = new Trend('spike_response_time');
const errorRate = new Rate('spike_errors');
const connectionPoolExhaustion = new Rate('spike_pool_exhausted');

export const options = {
  stages: [
    { duration: '10s', target: 250 },  // Sudden spike: 0 → 250 VUs
    { duration: '2m', target: 250 },   // Hold spike
    { duration: '30s', target: 0 },    // Rapid drop
  ],
  thresholds: {
    'spike_response_time': ['p(99)<100', 'avg<80'],    // Allow higher latency under spike
    'spike_errors': ['rate<0.01'],                    // Still <1% error rate
    'spike_pool_exhausted': ['rate<0.05'],           // <5% pool exhaustion
  }
};

export default function () {
  // Heavy endpoint: User list with filtering (tests deduplication + pooling)
  let res = http.get(`${BASE_URL}/api/users?status=active&limit=100`);
  
  check(res, {
    'response successful': (r) => r.status === 200 || r.status === 304,
    'response time acceptable': (r) => r.timings.duration < 100,
  });

  // Check for connection pool exhaustion (HTTP 503 or timeout)
  if (res.status === 503 || res.timings.duration > 5000) {
    connectionPoolExhaustion.add(1);
  } else {
    connectionPoolExhaustion.add(0);
  }

  responseTime.add(res.timings.duration);
  errorRate.add(res.status >= 400 ? 1 : 0);

  // Secondary endpoint: Database query
  res = http.get(`${BASE_URL}/api/database/metrics`);
  check(res, { 'metrics retrieved': (r) => r.status === 200 || r.status === 304 });
  responseTime.add(res.timings.duration);
  errorRate.add(res.status >= 400 ? 1 : 0);

  sleep(0.5);
}
