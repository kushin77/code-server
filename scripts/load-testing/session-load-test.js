// Session Load Test using k6
// Tests concurrent session creation and management

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const sessionCreationLatency = new Trend('session_creation_latency');
const sessionSuccessRate = new Rate('session_creation_success');
const sessionErrors = new Counter('session_creation_errors');
const activeSessionsGauge = new Gauge('active_sessions');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'https://ide.kushnir.cloud';
const API_BASE = __ENV.API_BASE || 'https://api.kushnir.cloud';
const JWT_TOKEN = __ENV.JWT_TOKEN || ''; // Should be pre-generated

export const options = {
  stages: [
    { duration: '1m', target: 50 },     // Ramp up to 50 concurrent sessions
    { duration: '2m', target: 100 },    // Ramp up to 100
    { duration: '3m', target: 200 },    // Ramp up to 200
    { duration: '2m', target: 100 },    // Back down to 100
    { duration: '1m', target: 0 },      // Ramp down
  ],
  thresholds: {
    'session_creation_latency': ['p(95)<2000', 'p(99)<5000'],
    'session_creation_success': ['rate>0.98'],
    'http_req_duration': ['p(95)<2000'],
  },
};

export default function() {
  activeSessionsGauge.add(1);

  group('Session Creation', function() {
    const sessionStartTime = new Date().getTime();

    // Create new session via API
    let sessionRes = http.post(
      `${API_BASE}/api/v1/sessions`,
      JSON.stringify({
        name: `session-${__VU}-${__ITER}`,
        type: 'ide',
        metadata: {
          user_agent: 'k6-load-test',
          ip_address: '127.0.0.1',
        },
      }),
      {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${JWT_TOKEN}`,
        },
      }
    );

    const sessionEndTime = new Date().getTime();
    const sessionCreationTime = sessionEndTime - sessionStartTime;
    
    sessionCreationLatency.add(sessionCreationTime);
    sessionSuccessRate.add(sessionRes.status === 201 || sessionRes.status === 200);

    if (sessionRes.status !== 201 && sessionRes.status !== 200) {
      sessionErrors.add(1);
    }

    check(sessionRes, {
      'Session created': (r) => r.status === 201 || r.status === 200,
      'Session has ID': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.id && body.id.length > 0;
        } catch {
          return false;
        }
      },
    });

    // Parse session if successful
    if (sessionRes.status === 201 || sessionRes.status === 200) {
      try {
        const sessionData = JSON.parse(sessionRes.body);
        const sessionId = sessionData.id;
        const sessionCookie = sessionRes.headers['Set-Cookie'];

        group('Session Validation', function() {
          // Verify session exists and is accessible
          let verifyRes = http.get(
            `${API_BASE}/api/v1/sessions/${sessionId}`,
            {
              headers: {
                'Authorization': `Bearer ${JWT_TOKEN}`,
                'Cookie': sessionCookie || '',
              },
            }
          );

          check(verifyRes, {
            'Session accessible': (r) => r.status === 200,
            'Session state valid': (r) => {
              try {
                const body = JSON.parse(r.body);
                return body.status === 'active' || body.status === 'created';
              } catch {
                return false;
              }
            },
          });

          sleep(Math.random()); // Simulate session usage
        });

        group('Session Cleanup', function() {
          // Delete session to test cleanup
          let deleteRes = http.del(
            `${API_BASE}/api/v1/sessions/${sessionId}`,
            null,
            {
              headers: {
                'Authorization': `Bearer ${JWT_TOKEN}`,
              },
            }
          );

          check(deleteRes, {
            'Session deleted': (r) => r.status === 204 || r.status === 200,
          });
        });
      } catch (e) {
        // Session parsing failed
      }
    }
  });

  activeSessionsGauge.add(-1);
  sleep(Math.random() * 2);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'artifacts/load-tests/session-summary.json': JSON.stringify(data),
  };
}

function textSummary(data, options = {}) {
  const indent = options.indent || '';
  let summary = '\n=== Session Load Test Summary ===\n';
  
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
