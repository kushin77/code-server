#!/usr/bin/env node
/**
 * @file        scripts/performance/baseline-load-test.js
 * @module      operations/performance-testing
 * @description k6 baseline load test - 100 concurrent users for 10 minutes
 * @owner       QA/Operations
 * @status      Production ready - April 23, 2026
 *
 * Usage:
 *   k6 run scripts/performance/baseline-load-test.js
 *
 * Environment Variables:
 *   BASE_URL: Target URL (default: http://localhost:3000)
 *   RAMP_UP_DURATION: Ramp-up time (default: 2m)
 *   TEST_DURATION: Test duration (default: 10m)
 *   MAX_USERS: Max concurrent users (default: 100)
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const duration = new Trend('response_time');
const requestCounter = new Counter('requests');
const activeUsers = new Gauge('active_users');

export const options = {
  stages: [
    // Ramp-up: 0 to 100 users over 2 minutes
    { duration: __ENV.RAMP_UP_DURATION || '2m', target: __ENV.MAX_USERS || 100 },
    // Sustained load: 100 users for 10 minutes
    { duration: __ENV.TEST_DURATION || '10m', target: __ENV.MAX_USERS || 100 },
    // Ramp-down: 100 to 0 users over 1 minute
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    'response_time': ['p(95)<5000', 'p(99)<10000'], // 95th percentile < 5s, 99th < 10s
    'errors': ['rate<0.001'], // Error rate < 0.1%
  },
  ext: {
    loadimpact: {
      projectID: 3518339,
      name: 'Baseline Load Test - 100 users / 10 minutes',
    },
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export default function () {
  activeUsers.add(1);

  group('Health Check', () => {
    const res = http.get(`${BASE_URL}/health`);
    check(res, {
      'health status is 200': (r) => r.status === 200,
      'health response time < 500ms': (r) => r.timings.duration < 500,
    }) || errorRate.add(1);
    duration.add(res.timings.duration);
    requestCounter.add(1);
  });

  group('Collaboration Services', () => {
    // Test inline communication endpoints
    const threadRes = http.get(`${BASE_URL}/api/inline-communication/threads`);
    check(threadRes, {
      'list threads status is 200': (r) => r.status === 200,
      'list threads response time < 1000ms': (r) => r.timings.duration < 1000,
    }) || errorRate.add(1);
    duration.add(threadRes.timings.duration);
    requestCounter.add(1);

    // Test statistics endpoint
    const statsRes = http.get(`${BASE_URL}/api/inline-communication/statistics`);
    check(statsRes, {
      'stats status is 200': (r) => r.status === 200,
      'stats response time < 500ms': (r) => r.timings.duration < 500,
    }) || errorRate.add(1);
    duration.add(statsRes.timings.duration);
    requestCounter.add(1);
  });

  group('Voice Channel', () => {
    // Test voice channel endpoints
    const voiceRes = http.get(`${BASE_URL}/api/voice/sessions`);
    check(voiceRes, {
      'voice sessions accessible': (r) => r.status === 200 || r.status === 404,
    }) || errorRate.add(1);
    duration.add(voiceRes.timings.duration);
    requestCounter.add(1);
  });

  group('Co-Editing', () => {
    // Test co-editing endpoints
    const coEditRes = http.get(`${BASE_URL}/api/co-edit/sessions`);
    check(coEditRes, {
      'co-edit sessions accessible': (r) => r.status === 200 || r.status === 404,
    }) || errorRate.add(1);
    duration.add(coEditRes.timings.duration);
    requestCounter.add(1);
  });

  sleep(1);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'artifacts/performance/baseline-results.json': JSON.stringify(data, null, 2),
  };
}

function textSummary(data, options = {}) {
  const indent = options.indent || '';
  const metrics = data.metrics;

  let output = '\n' + '='.repeat(80) + '\n';
  output += 'BASELINE LOAD TEST RESULTS\n';
  output += '='.repeat(80) + '\n\n';

  // Summary metrics
  if (metrics['response_time']) {
    output += indent + 'Response Time:\n';
    output += indent + `  Average: ${Math.round(metrics['response_time'].values.avg)}ms\n`;
    output += indent + `  P50: ${Math.round(metrics['response_time'].values['p(50)'])}ms\n`;
    output += indent + `  P95: ${Math.round(metrics['response_time'].values['p(95)'])}ms\n`;
    output += indent + `  P99: ${Math.round(metrics['response_time'].values['p(99)'])}ms\n`;
  }

  if (metrics['requests']) {
    output += '\n' + indent + 'Requests:\n';
    output += indent + `  Total: ${metrics['requests'].values.count}\n`;
    output += indent + `  Rate: ${(metrics['requests'].values.rate).toFixed(2)} req/s\n`;
  }

  if (metrics['errors']) {
    const errorRate = metrics['errors'].values.rate || 0;
    output += '\n' + indent + 'Errors:\n';
    output += indent + `  Error Rate: ${(errorRate * 100).toFixed(3)}%\n`;
    output += indent + `  Status: ${errorRate < 0.001 ? 'PASS' : 'FAIL'} (threshold: <0.1%)\n`;
  }

  output += '\n' + '='.repeat(80) + '\n';

  return output;
}
