// JWT Token Acquisition Load Test using k6
// Tests rapid JWT token acquisition and JWKS caching effectiveness

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Custom metrics
const tokenAcquisitionLatency = new Trend('jwt_token_acquisition_latency');
const tokenSuccessRate = new Rate('jwt_token_success');
const jwksCacheHitRate = new Rate('jwks_cache_hit');
const tokenErrors = new Counter('jwt_token_errors');
const tokenRequestsPerSec = new Gauge('token_requests_per_sec');

// Configuration
const OIDC_ISSUER = __ENV.OIDC_ISSUER || 'https://oidc.kushnir.cloud';
const OAUTH2_CLIENT_SECRET = __ENV.OAUTH2_CLIENT_SECRET || 'test-secret';
const OAUTH2_CLIENT_ID = __ENV.OAUTH2_CLIENT_ID || 'code-server';

export const options = {
  stages: [
    { duration: '30s', target: 50 },    // Ramp up to 50 concurrent clients
    { duration: '2m', target: 100 },    // Ramp up to 100 concurrent
    { duration: '3m', target: 100 },    // Sustain at 100 concurrent
    { duration: '1m', target: 50 },     // Ramp down
    { duration: '30s', target: 0 },     // Final ramp down
  ],
  thresholds: {
    'jwt_token_acquisition_latency': ['p(95)<1000', 'p(99)<2000'], // Token fetch should be fast
    'jwt_token_success': ['rate>0.99'], // 99% success rate
    'http_req_duration': ['p(95)<1500'],
  },
};

export default function() {
  group('JWKS Discovery', function() {
    // This should be cached across requests
    let jwksRes = http.get(`${OIDC_ISSUER}/.well-known/jwks.json`, {
      headers: {
        'Accept': 'application/json',
      },
    });

    const fromCache = jwksRes.headers['X-Cache-Hit'] === 'true' || jwksRes.headers['Age'];
    jwksCacheHitRate.add(fromCache ? 1 : 0);

    check(jwksRes, {
      'JWKS endpoint available': (r) => r.status === 200,
      'JWKS response valid': (r) => r.body.includes('keys'),
    });
  });

  group('Token Acquisition', function() {
    const tokenStartTime = new Date().getTime();

    // Request token using client credentials flow
    let tokenRes = http.post(
      `${OIDC_ISSUER}/oauth2/token`,
      {
        grant_type: 'client_credentials',
        client_id: OAUTH2_CLIENT_ID,
        client_secret: OAUTH2_CLIENT_SECRET,
        scope: 'api:read api:write',
      },
      {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      }
    );

    const tokenEndTime = new Date().getTime();
    const tokenAcquisitionTime = tokenEndTime - tokenStartTime;
    
    tokenAcquisitionLatency.add(tokenAcquisitionTime);
    tokenSuccessRate.add(tokenRes.status === 200);

    if (tokenRes.status !== 200) {
      tokenErrors.add(1);
    }

    check(tokenRes, {
      'Token acquired': (r) => r.status === 200,
      'Token response has access_token': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.access_token && body.token_type === 'Bearer';
        } catch {
          return false;
        }
      },
    });

    // Parse token if successful
    if (tokenRes.status === 200) {
      try {
        const tokenData = JSON.parse(tokenRes.body);
        const accessToken = tokenData.access_token;
        
        group('Token Validation', function() {
          // Validate token with introspection endpoint
          let introspectRes = http.post(
            `${OIDC_ISSUER}/oauth2/introspect`,
            {
              token: accessToken,
              client_id: OAUTH2_CLIENT_ID,
              client_secret: OAUTH2_CLIENT_SECRET,
            }
          );

          check(introspectRes, {
            'Token introspection successful': (r) => r.status === 200,
            'Token is active': (r) => {
              try {
                return JSON.parse(r.body).active === true;
              } catch {
                return false;
              }
            },
          });
        });
      } catch (e) {
        // Token parsing failed
      }
    }
  });

  sleep(Math.random() * 2); // Random sleep between 0-2 seconds
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'artifacts/load-tests/jwt-token-summary.json': JSON.stringify(data),
  };
}

function textSummary(data, options = {}) {
  const indent = options.indent || '';
  let summary = '\n=== JWT Token Load Test Summary ===\n';
  
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
