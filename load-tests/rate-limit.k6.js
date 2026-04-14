import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Counter, Gauge, Histogram, Rate, Trend } from 'k6/metrics';

/**
 * GraphQL API Rate Limiting Load Test
 * Tests rate limiting behavior under sustained 1000 req/sec load
 * Duration: 5 minutes
 * VUs: 500 concurrent users
 */

// ════════════════════════════════════════════════════════════════════════
// Custom Metrics
// ════════════════════════════════════════════════════════════════════════

const rateLimitViolations = new Counter('rate_limit_violations');
const rateLimitSuccess = new Counter('rate_limit_success');
const headerCalculationTime = new Trend('header_calculation_duration_ms');
const currentConcurrentRequests = new Gauge('concurrent_requests');
const requestsByTier = new Counter('requests_by_tier');
const requestDuration = new Trend('request_duration');
const requestFailureRate = new Rate('request_failure_rate');
const tierDistribution = new Gauge('tier_distribution');

// ════════════════════════════════════════════════════════════════════════
// Test Configuration
// ════════════════════════════════════════════════════════════════════════

export const options = {
  stages: [
    // Ramp up to target load
    { duration: '1m', target: 100 },   // 100 users for 1 minute
    { duration: '1m', target: 250 },   // 250 users for 1 minute
    { duration: '1m', target: 500 },   // 500 users for 1 minute

    // Sustained load
    { duration: '5m', target: 500 },   // 500 concurrent users for 5 minutes (target: 1000 req/sec)

    // Ramp down
    { duration: '1m', target: 250 },   // 250 users for 1 minute
    { duration: '1m', target: 100 },   // 100 users for 1 minute
    { duration: '1m', target: 0 },     // Cool down
  ],
  thresholds: {
    'http_req_duration': ['p(99)<100'],  // p99 latency < 100ms
    'rate_limit_violations': ['rate<0.001'],  // < 0.1% violation rate
    'request_failure_rate': ['rate<0.001'],   // < 0.1% failure rate
  },
  ext: {
    loadimpact: {
      projectID: 3374667,
      name: 'Phase 26-A Rate Limiter',
    },
  },
};

// ════════════════════════════════════════════════════════════════════════
// Helper Functions
// ════════════════════════════════════════════════════════════════════════

const API_BASE_URL = __ENV.API_BASE_URL || 'http://localhost:8080';
const GraphQL_QUERY = `
  query {
    user {
      id
      name
      email
    }
  }
`;

function getRandomTier() {
  const rand = Math.random();
  if (rand < 0.6) return 'free';        // 60% free tier
  if (rand < 0.9) return 'pro';         // 30% pro tier
  return 'enterprise';                   // 10% enterprise tier
}

function makeGraphQLRequest(tier) {
  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-User-Tier': tier,
      'X-User-ID': `user-${Math.floor(Math.random() * 10000)}`,
    },
    tags: { name: 'GraphQL' },
  };

  const payload = JSON.stringify({
    query: GraphQL_QUERY,
  });

  const response = http.post(`${API_BASE_URL}/graphql`, payload, params);

  // Track metrics
  currentConcurrentRequests.add(1);

  // Record request duration
  requestDuration.add(response.timings.duration);

  // Check for rate limiting
  if (response.status === 429) {
    rateLimitViolations.add(1);
    requestFailureRate.add(true);
  } else {
    rateLimitSuccess.add(1);
    requestFailureRate.add(false);
  }

  // Extract and measure header calculation time
  if (response.headers['X-RateLimit-Remaining']) {
    const remainingTime = parseFloat(response.headers['X-RateLimit-Calculation-Time'] || '0');
    headerCalculationTime.add(remainingTime);
  }

  requestsByTier.add(1, { tier });
  currentConcurrentRequests.add(-1);

  return response;
}

// ════════════════════════════════════════════════════════════════════════
// Test Scenarios
// ════════════════════════════════════════════════════════════════════════

export default function() {
  const tier = getRandomTier();
  tierDistribution.add(1, { tier });

  group(`Rate Limiting Test - ${tier} Tier`, () => {
    const response = makeGraphQLRequest(tier);

    // Validate response
    check(response, {
      'status is 200 or 429': (r) => r.status === 200 || r.status === 429,
      'has rate limit headers': (r) =>
        r.headers['X-RateLimit-Limit'] !== undefined ||
        r.status === 429,
      'response time < 100ms p99': (r) => r.timings.duration < 100,
      'response is valid JSON': (r) => {
        try {
          JSON.parse(r.body);
          return true;
        } catch {
          return false;
        }
      },
    });

    // Tier-specific validations
    if (tier === 'free') {
      check(response, {
        'free tier limit honored': (r) =>
          r.headers['X-RateLimit-Limit'] === '60' || r.status === 429,
      });
    } else if (tier === 'pro') {
      check(response, {
        'pro tier limit honored': (r) =>
          r.headers['X-RateLimit-Limit'] === '1000' || r.status === 429,
      });
    } else if (tier === 'enterprise') {
      check(response, {
        'enterprise tier limit honored': (r) =>
          r.headers['X-RateLimit-Limit'] === '10000' || r.status === 429,
      });
    }
  });

  sleep(0.1);  // Light sleep between requests
}

// ════════════════════════════════════════════════════════════════════════
// Teardown - Generate Summary
// ════════════════════════════════════════════════════════════════════════

export function teardown(data) {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('Load Test Summary:');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`Total Requests: ${data.total}`);
  console.log(`Successful Requests: ${data.success}`);
  console.log(`Rate Limit Violations: ${data.violations}`);
  console.log(`Failure Rate: ${((data.violations / data.total) * 100).toFixed(2)}%`);
  console.log('═══════════════════════════════════════════════════════════');
}
