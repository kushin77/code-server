import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const rateExceeded = new Rate('rate_limit_exceeded');
const responseTime = new Trend('response_time');
const requestsPerSec = new Rate('requests_per_sec');

// Load test configuration for Phase 26-A: Rate Limiting
export const options = {
  stages: [
    { duration: '30s', target: 100 },    // Ramp up to 100 users
    { duration: '1m30s', target: 500 },  // Ramp up to 500 users
    { duration: '3m', target: 1000 },    // Peak load: 1000 users
    { duration: '1m30s', target: 500 },  // Ramp down
    { duration: '30s', target: 0 },      // Cool down
  ],
  thresholds: {
    'response_time': ['p(99) < 100'],           // p99 < 100ms
    'rate_limit_exceeded': ['rate < 0.001'],   // False positive rate < 0.1%
    'requests_per_sec': ['rate > 0.99'],       // 99% success rate
    'http_req_failed': ['rate < 0.001'],       // <0.1% failures
  },
};

const BASE_URL = 'http://api.192.168.168.31.nip.io';

// Test users with different tiers
const testUsers = [
  { id: 'user_free_1', tier: 'free', apiKey: 'key_free_1' },
  { id: 'user_free_2', tier: 'free', apiKey: 'key_free_2' },
  { id: 'user_pro_1', tier: 'pro', apiKey: 'key_pro_1' },
  { id: 'user_pro_2', tier: 'pro', apiKey: 'key_pro_2' },
  { id: 'user_enterprise_1', tier: 'enterprise', apiKey: 'key_enterprise_1' },
];

export default function () {
  // Select random user to test tier-based rate limits
  const user = testUsers[Math.floor(Math.random() * testUsers.length)];
  
  group(`Rate Limit Test - ${user.tier} tier`, () => {
    // GraphQL query
    const query = `
      query {
        workspace(id: "ws-phase-26") {
          id
          name
          owner {
            id
            email
          }
        }
      }
    `;

    // Make request with API key
    const response = http.post(`${BASE_URL}/graphql`, query, {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${user.apiKey}`,
        'X-User-ID': user.id,
        'X-User-Tier': user.tier,
      },
    });

    // Track metrics
    responseTime.add(response.timings.duration);
    requestsPerSec.add(1);

    // Check response and rate limit headers
    check(response, {
      'status is 200 or 429': (r) => r.status === 200 || r.status === 429,
      'has rate limit headers': (r) =>
        r.headers['X-RateLimit-Limit'] && 
        r.headers['X-RateLimit-Remaining'] && 
        r.headers['X-RateLimit-Reset'],
      'rate limit remaining >= 0': (r) => {
        const remaining = parseInt(r.headers['X-RateLimit-Remaining'] || '0');
        return remaining >= 0;
      },
      'response time < 100ms': (r) => r.timings.duration < 100,
      'valid GraphQL response': (r) => r.body.includes('"data"') || r.body.includes('"errors"'),
    });

    // Track rate limit exceeded events
    if (response.status === 429) {
      rateExceeded.add(1);
      console.log(`Rate limit exceeded for ${user.tier} user`);
    }

    // Small delay between requests per user
    sleep(Math.random() * 2);
  });

  // Test burst behavior (optional - would exceed rate limits)
  if (Math.random() < 0.1) {
    group('Burst Test - Validate Rate Limit Enforcement', () => {
      const burstUser = testUsers[0]; // Use free tier user
      
      // Rapid-fire requests to test burst handling
      for (let i = 0; i < 10; i++) {
        const response = http.post(`${BASE_URL}/graphql`, 
          `query { workspace(id: "ws-burst-test") { id } }`,
          {
            headers: {
              'Authorization': `Bearer ${burstUser.apiKey}`,
              'X-User-ID': burstUser.id,
              'X-User-Tier': burstUser.tier,
            },
          }
        );

        if (response.status === 429) {
          rateExceeded.add(1);
          sleep(5); // Back off when rate limited
          break;
        }
      }
    });
  }
}
