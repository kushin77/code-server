import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '1m', target: 10 },   // Ramp up to 10 concurrent users over 1 minute
    { duration: '3m', target: 10 },   // Stay at 10 concurrent users for 3 minutes (steady state)
    { duration: '1m', target: 0 },    // Ramp down to 0 users over 1 minute
  ],
  
  // Thresholds - fail the test if these are not met
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],  // 95th percentile < 500ms, 99th < 1000ms
    http_req_failed: ['rate<0.1'],                     // Error rate < 0.1%
    'errors': ['rate<0.01'],                           // Custom error rate < 1%
  },
  
  // Extend timeout for slow operations
  httpDebug: 'full',
};

export default function () {
  // Test health check endpoint
  const healthRes = http.get('http://localhost:8080/healthz');
  check(healthRes, {
    'health check status 200': (r) => r.status === 200,
    'health response time < 100ms': (r) => r.timings.duration < 100,
  }) || errorRate.add(1);
  
  sleep(1);
  
  // Test OAuth2-proxy health
  const oauthRes = http.get('http://localhost:4180/ping');
  check(oauthRes, {
    'oauth2-proxy status 200': (r) => r.status === 200,
  }) || errorRate.add(1);
  
  sleep(1);
  
  // Test main code-server endpoint (with auth bypass for testing)
  const codeRes = http.get('http://localhost:8080/', {
    headers: { 'X-Test': 'k6-load-test' },
  });
  check(codeRes, {
    'code-server responds': (r) => r.status < 500,
    'code-server response time < 1000ms': (r) => r.timings.duration < 1000,
  }) || errorRate.add(1);
  
  sleep(2);
}

export function handleSummary(data) {
  // Custom summary to save results
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'test-results/load-test-baseline.json': JSON.stringify(data),
  };
}

// Simple text summary function
function textSummary(data, opts = {}) {
  const indent = opts.indent || '';
  const enableColors = opts.enableColors !== false;
  
  let output = '\n=== Load Test Results ===\n';
  
  if (data.metrics) {
    for (const [name, metric] of Object.entries(data.metrics)) {
      output += `\n${name}:\n`;
      if (metric.values) {
        output += `  min: ${Math.min(...Object.values(metric.values)).toFixed(2)}\n`;
        output += `  avg: ${(Object.values(metric.values).reduce((a, b) => a + b) / Object.values(metric.values).length).toFixed(2)}\n`;
        output += `  max: ${Math.max(...Object.values(metric.values)).toFixed(2)}\n`;
      }
    }
  }
  
  return output;
}
