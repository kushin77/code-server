// L-oad Test Script for Phase 26-A: API Rate Limiting
// Framework: k6 (Load testing framework)
// Purpose: Validate rate limiting under load (1000+ concurrent users)
// Target: GraphQL API (192.168.168.31:4000/graphql)

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import exec from 'k6/execution';

// ════════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ════════════════════════════════════════════════════════════════════════════

const API_URL = __ENV.API_URL || 'http://192.168.168.31:4000/graphql';
const LOAD_PROFILE = __ENV.LOAD_PROFILE || 'ramp';  // ramp|peak|burst
const MAX_VUS = parseInt(__ENV.MAX_VUS) || 100;     // Virtual Users
const TEST_DURATION = __ENV.TEST_DURATION || '5m';
const ENABLE_TRACING = __ENV.TRACING_ENABLED === 'true';

export const options = {
  stages: [
    // Ramp up: 0 → MAX_VUS linearly over 2 minutes
    { duration: '2m', target: MAX_VUS, name: 'ramping-up' },
    // Plateau: Stay at MAX_VUS for 3 minutes
    { duration: '3m', target: MAX_VUS, name: 'plateau' },
    // Ramp down: MAX_VUS → 0 over 1 minute
    { duration: '1m', target: 0, name: 'ramping-down' },
  ],
  
  thresholds: {
    // API response time thresholds
    'http_req_duration{scenario:graphql}': ['p(99) < 200'],  // p99 < 200ms
    'http_req_duration{scenario:search}': ['p(99) < 500'],    // p99 < 500ms
    
    // Error rate thresholds
    'http_req_failed{scenario:graphql}': ['rate < 0.01'],   // <1% error rate
    'http_req_failed': ['rate < 0.05'],                      // <5% overall error
    
    // Rate limit compliance
    'rate_limit_hit_count': ['value < 5'],  // <5 rate limit hits acceptable
    'rate_limit_accuracy': ['value > 0.99'], // >99% accuracy
  },
};

// ════════════════════════════════════════════════════════════════════════════
// TEST QUERIES
// ════════════════════════════════════════════════════════════════════════════

// Simple query to test basic rate limiting
const SIMPLE_QUERY = `
  query {
    user(id: "test-user") {
      id
      name
      email
    }
  }
`;

// Complex query to test query cost calculation
const COMPLEX_QUERY = `
  query {
    organization(id: "org-1") {
      id
      name
      members(first: 100) {
        edges {
          node {
            id
            name
            email
            apiKeys(first: 10) {
              edges {
                node {
                  id
                  name
                  lastUsedAt
                }
              }
            }
          }
        }
      }
      webhook(first: 50) {
        edges {
          node {
            id
            url
            events
          }
        }
      }
    }
  }
`;

// Mutation to test mutation rate limiting
const MUTATION_QUERY = `
  mutation {
    createApiKey(input: {
      name: "test-key-${Date.now()}"
      tier: FREE
    }) {
      apiKey {
        id
        key
      }
      errors
    }
  }
`;

// ════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ════════════════════════════════════════════════════════════════════════════

let rateLimitHits = 0;
let totalRequests = 0;
let correctRateLimitResponses = 0;

function makeGraphQLRequest(query, scenario = 'graphql', apiKey = null) {
  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  
  if (apiKey) {
    headers['Authorization'] = `Bearer ${apiKey}`;
  }
  
  const payload = JSON.stringify({ query });
  
  const response = http.post(API_URL, payload, {
    headers,
    tags: { scenario },
  });
  
  totalRequests++;
  
  // Check rate limit headers
  const remaining = response.headers['X-RateLimit-Remaining'];
  const limit = response.headers['X-RateLimit-Limit'];
  const reset = response.headers['X-RateLimit-Reset'];
  
  // Validate rate limit headers are present
  if (response.status !== 429) {  // Not rate limited
    check(response, {
      'has rate limit headers': (r) => remaining !== undefined && limit !== undefined,
      'rate limit remaining is numeric': (r) => !isNaN(parseInt(remaining)),
      'rate limit reset is future timestamp': (r) => parseInt(reset) > Date.now() / 1000,
    }, { scenario });
    
    if (remaining !== undefined && limit !== undefined) {
      correctRateLimitResponses++;
    }
  } else {
    // Rate limited (429)
    rateLimitHits++;
    check(response, {
      'rate limited response is valid': (r) => r.status === 429,
      'rate limit remaining is 0': (r) => remaining === '0',
      'suggests retry after': (r) => reset !== undefined,
    }, { scenario, rateLimited: 'true' });
  }
  
  // Response time check
  check(response, {
    'response time < 500ms': (r) => r.timings.duration < 500,
    'response time < 1000ms': (r) => r.timings.duration < 1000,
  }, { scenario });
  
  return response;
}

function sleep_smart(min = 0.5, max = 2.0) {
  const sleepTime = Math.random() * (max - min) + min;
  sleep(sleepTime);
}

// ════════════════════════════════════════════════════════════════════════════
// TEST SCENARIOS
// ════════════════════════════════════════════════════════════════════════════

export default function () {
  const vu = exec.vu.idInTest;
  const iteration = exec.vu.iterationInInstance;
  
  // Determine user tier based on VU ID
  let tier = 'free';
  if (vu % 4 === 0) tier = 'pro';
  if (vu % 10 === 0) tier = 'enterprise';
  
  // Simulate user-specific API key
  const apiKey = `key_${tier}_${vu}`;
  
  group('Simple Query - Rate Limit Validation', () => {
    // Each user makes 2-3 simple queries per iteration
    const queryCount = Math.floor(Math.random() * 2) + 2;
    
    for (let i = 0; i < queryCount; i++) {
      makeGraphQLRequest(SIMPLE_QUERY, 'simple-query', apiKey);
      sleep_smart(0.1, 0.5);  // Small delay between queries
    }
  });
  
  group('Complex Query - Cost Calculation', () => {
    // Heavy queries less frequently
    if (iteration % 3 === 0) {
      makeGraphQLRequest(COMPLEX_QUERY, 'complex-query', apiKey);
      sleep_smart(0.5, 1.0);
    }
  });
  
  group('Mutations - Transaction Rate Limiting', () => {
    // Mutations even less frequently (1 per 5 iterations)
    if (iteration % 5 === 0) {
      makeGraphQLRequest(MUTATION_QUERY, 'mutation', apiKey);
      sleep_smart(1.0, 2.0);
    }
  });
  
  // Realistic inter-request delay
  sleep_smart(0.5, 2.0);
}

// ════════════════════════════════════════════════════════════════════════════
// TEARDOWN & REPORTING
// ════════════════════════════════════════════════════════════════════════════

export function teardown(data) {
  // Calculate rate limit accuracy
  const accuracy = totalRequests > 0 ? correctRateLimitResponses / totalRequests : 0;
  
  console.log('');
  console.log('╔════════════════════════════════════════════════════════════════════════════╗');
  console.log('║                 PHASE 26-A RATE LIMITING TEST RESULTS                     ║');
  console.log('╚════════════════════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`Total Requests:        ${totalRequests}`);
  console.log(`Rate Limit Hits (429): ${rateLimitHits}`);
  console.log(`Rate Limit Hit Rate:   ${((rateLimitHits / totalRequests) * 100).toFixed(2)}%`);
  console.log(`Header Accuracy:       ${(accuracy * 100).toFixed(2)}%`);
  console.log('');
  console.log('📊 SUCCESS CRITERIA:');
  console.log(`  ✅ Rate limit hits < 5%:              ${(rateLimitHits / totalRequests) * 100 < 5 ? 'PASS' : 'FAIL'}`);
  console.log(`  ✅ Header accuracy > 99%:             ${accuracy > 0.99 ? 'PASS' : 'FAIL'}`);
  console.log(`  ✅ p99 latency < 200ms:               Check k6 thresholds report`);
  console.log(`  ✅ Error rate < 1%:                   Check k6 thresholds report`);
  console.log('');
  console.log('📈 NEXT STEPS:');
  console.log('  1. Review rate limit accuracy (target: >99%)');
  console.log('  2. Verify no 429 errors during normal operation');
  console.log('  3. Check Prometheus metrics in Grafana');
  console.log('  4. Validate X-RateLimit headers in all responses');
  console.log('  5. Deploy to production if all thresholds pass');
  console.log('');
}
