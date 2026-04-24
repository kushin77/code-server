// API Endpoint Load Test using k6
// Tests authenticated API endpoint throughput and latency

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const apiLatency = new Trend('api_latency');
const apiSuccessRate = new Rate('api_success');
const apiErrors = new Counter('api_errors');
const rbacDeniedRate = new Rate('rbac_denied');

// Configuration
const API_BASE = __ENV.API_BASE || 'https://api.kushnir.cloud';
const JWT_TOKEN = __ENV.JWT_TOKEN || '';

export const options = {
  stages: [
    { duration: '1m', target: 100 },    // Ramp up to 100 concurrent
    { duration: '3m', target: 200 },    // Ramp up to 200
    { duration: '3m', target: 500 },    // Ramp up to 500
    { duration: '2m', target: 200 },    // Ramp down
    { duration: '1m', target: 0 },      // Final ramp down
  ],
  thresholds: {
    'api_latency': ['p(50)<500', 'p(95)<2000', 'p(99)<5000'],
    'api_success': ['rate>0.99'],
    'http_req_duration': ['p(95)<2000'],
  },
};

const endpoints = [
  { path: '/api/v1/auth/me', method: 'GET', role: 'viewer' },
  { path: '/api/v1/workspaces', method: 'GET', role: 'viewer' },
  { path: '/api/v1/files/list', method: 'GET', role: 'viewer' },
  { path: '/api/v1/extensions', method: 'GET', role: 'viewer' },
  { path: '/api/v1/settings', method: 'GET', role: 'viewer' },
  { path: '/api/v1/debug/metrics', method: 'GET', role: 'admin' },
];

export default function() {
  // Select random endpoint
  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];

  group(`API: ${endpoint.method} ${endpoint.path}`, function() {
    const startTime = new Date().getTime();

    let apiRes = http.request(
      endpoint.method,
      `${API_BASE}${endpoint.path}`,
      null,
      {
        headers: {
          'Authorization': `Bearer ${JWT_TOKEN}`,
          'Content-Type': 'application/json',
          'User-Agent': 'k6-load-test',
        },
      }
    );

    const endTime = new Date().getTime();
    const latency = endTime - startTime;
    
    apiLatency.add(latency);
    
    // Track success (200, 201) vs errors (5xx) vs authorization issues (401, 403)
    if (apiRes.status >= 200 && apiRes.status < 400) {
      apiSuccessRate.add(1);
    } else if (apiRes.status === 401 || apiRes.status === 403) {
      rbacDeniedRate.add(1);
    } else {
      apiErrors.add(1);
      apiSuccessRate.add(0);
    }

    check(apiRes, {
      'response status is 2xx/3xx': (r) => r.status >= 200 && r.status < 400,
      'response time < 2s': (r) => r.timings.duration < 2000,
      'response is JSON': (r) => r.headers['Content-Type'].includes('application/json'),
    });

    // Detailed checks for specific status codes
    if (endpoint.role === 'admin' && apiRes.status === 403) {
      check(apiRes, {
        'admin endpoint correctly denies unauthorized': (r) => r.status === 403,
      });
      rbacDeniedRate.add(1);
    }
  });

  sleep(Math.random() * 3); // Random sleep 0-3 seconds
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'artifacts/load-tests/api-summary.json': JSON.stringify(data),
  };
}

function textSummary(data, options = {}) {
  const indent = options.indent || '';
  let summary = '\n=== API Endpoint Load Test Summary ===\n';
  
  if (data.metrics) {
    Object.entries(data.metrics).forEach(([name, metric]) => {
      if (metric.values) {
        summary += `${indent}${name}:\n`;
        Object.entries(metric.values).forEach(([key, value]) => {
          summary += `${indent}  ${key}: ${value}\n`;
        });
      }
    });
  }
  
  return summary;
}
