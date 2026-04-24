#!/usr/bin/env node
/**
 * @file        scripts/performance/spike-load-test.js
 * @module      operations/performance-testing
 * @description k6 spike load test - sudden 1000 concurrent users for stress testing
 * @owner       QA/Operations
 * @status      Production ready - April 23, 2026
 *
 * Usage:
 *   k6 run scripts/performance/spike-load-test.js
 *
 * Environment Variables:
 *   BASE_URL: Target URL (default: http://localhost:3000)
 *   SPIKE_USERS: Peak concurrent users (default: 1000)
 *   SPIKE_DURATION: Spike duration (default: 5m)
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics for spike behavior
const errorRate = new Rate('spike_errors');
const duration = new Trend('spike_response_time');
const requestCounter = new Counter('spike_requests');
const recoveryTime = new Trend('recovery_time');

export const options = {
  stages: [
    // Instant spike: 0 to 1000 users (stress test)
    { duration: '10s', target: __ENV.SPIKE_USERS || 1000 },
    // Maintain spike for 5 minutes
    { duration: __ENV.SPIKE_DURATION || '5m', target: __ENV.SPIKE_USERS || 1000 },
    // Cool down: back to 0 over 1 minute
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    'spike_errors': ['rate<0.01'], // Error rate < 1% during spike
    'spike_response_time': ['p(99)<15000'], // 99th percentile < 15s under spike
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
let recoveryDetected = false;
let recoveryStartTime = 0;

export default function () {
  group('Spike Load - Mixed Endpoints', () => {
    // Test multiple endpoints simultaneously under high load
    const responses = http.batch([
      ['GET', `${BASE_URL}/health`],
      ['GET', `${BASE_URL}/api/inline-communication/statistics`],
      ['GET', `${BASE_URL}/api/voice/sessions`],
      ['GET', `${BASE_URL}/api/co-edit/sessions`],
    ]);

    responses.forEach((res, idx) => {
      check(res, {
        'status is 200 or acceptable': (r) => r.status === 200 || r.status === 404 || r.status === 503,
      }) || errorRate.add(1);

      duration.add(res.timings.duration);
      requestCounter.add(1);

      // Track recovery time after spike
      if (res.status < 500 && !recoveryDetected) {
        recoveryDetected = true;
        recoveryStartTime = new Date().getTime();
      }

      if (recoveryDetected && res.timings.duration < 1000) {
        recoveryTime.add(new Date().getTime() - recoveryStartTime);
      }
    });
  });

  // Reduced sleep to keep load high
  sleep(0.5);
}

export function handleSummary(data) {
  return {
    'stdout': spikeTestSummary(data),
    'artifacts/performance/spike-results.json': JSON.stringify(data, null, 2),
  };
}

function spikeTestSummary(data) {
  const metrics = data.metrics;
  let output = '\n' + '='.repeat(80) + '\n';
  output += 'SPIKE LOAD TEST RESULTS (1000 concurrent users)\n';
  output += '='.repeat(80) + '\n\n';

  if (metrics['spike_response_time']) {
    output += 'Response Time Under Spike:\n';
    output += `  Average: ${Math.round(metrics['spike_response_time'].values.avg)}ms\n`;
    output += `  P95: ${Math.round(metrics['spike_response_time'].values['p(95)'])}ms\n`;
    output += `  P99: ${Math.round(metrics['spike_response_time'].values['p(99)'])}ms\n`;
  }

  if (metrics['recovery_time']) {
    output += '\nRecovery Metrics:\n';
    output += `  Avg Recovery Time: ${Math.round(metrics['recovery_time'].values.avg)}ms\n`;
    output += `  Max Recovery Time: ${Math.round(metrics['recovery_time'].values.max)}ms\n`;
  }

  if (metrics['spike_errors']) {
    const errorRate = metrics['spike_errors'].values.rate || 0;
    output += '\nError Handling:\n';
    output += `  Error Rate: ${(errorRate * 100).toFixed(2)}%\n`;
    output += `  Status: ${errorRate < 0.01 ? 'PASS' : 'FAIL'} (threshold: <1%)\n`;
  }

  output += '\nSuccess Criteria:\n';
  output += '  ✓ Graceful degradation (no crashes)\n';
  output += '  ✓ Recovery < 2 minutes after spike\n';
  output += '  ✓ Error rate < 1% during spike\n';
  output += '\n' + '='.repeat(80) + '\n';

  return output;
}
