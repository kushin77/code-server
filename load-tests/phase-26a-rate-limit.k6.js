import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Counter } from 'k6/metrics';

// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║ Phase 26-A: Rate Limiting Load Test (k6)                                 ║
// ║                                                                           ║
// ║ Purpose: Validate tier-based rate limiting under sustained load          ║
// ║ - Tests free/pro/enterprise tiers with different rate limits             ║
// ║ - Measures latency percentiles (p50, p95, p99)                           ║
// ║ - Verifies rate limit violations are captured correctly                  ║
// ║ - Tracks per-tier token consumption                                      ║
// ║                                                                           ║
// ║ Scenarios:                                                               ║
// ║  - ramp_up: 0 → 100 → 500 → 1000 VUs over 18 minutes                    ║
// ║  - free_tier_violation: 120 req/min (2x free tier limit)                ║
// ║                                                                           ║
// ║ Run: k6 run phase-26a-rate-limit.k6.js                                  ║
// ║      BASE_URL=http://api.example.com:4000 k6 run ...                     ║
// ╚═══════════════════════════════════════════════════════════════════════════╝

const BASE_URL = __ENV.BASE_URL || 'http://192.168.168.31:4000';

// Custom metrics
const rateLimitViolations = new Counter('rate_limit_violations');
const rateLimitCheckTime = new Rate('rate_limit_check_duration');
const tierTokensRemaining = new Gauge('tier_tokens_remaining');

// Test organizations mapped to tiers
const testOrgs = {
  'org-free-001': { tier: 'free', limit: 60 },     // 60 req/min
  'org-free-002': { tier: 'free', limit: 60 },
  'org-pro-001': { tier: 'pro', limit: 600 },      // 600 req/min
  'org-pro-002': { tier: 'pro', limit: 600 },
  'org-enterprise-001': { tier: 'enterprise', limit: null }, // unlimited
};

export const options = {
  scenarios: {
    // Scenario 1: Ramp up - gradual increase in load
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '3m', target: 100 },    // 0 → 100 VUs over 3 min
        { duration: '5m', target: 500 },    // 100 → 500 VUs over 5 min
        { duration: '10m', target: 1000 },  // 500 → 1000 VUs over 10 min
      ],
      gracefulRampDown: '1m',
    },
    
    // Scenario 2: Free tier violation - constant 120 req/min per org
    // (exceeds free tier limit of 60 req/min)
    free_tier_violation: {
      executor: 'constant-arrival-rate',
      rate: 120,        // 120 requests per time unit
      timeUnit: '1m',   // per minute
      duration: '15m',
      maxVUs: 100,
    },
  },

  // Thresholds for test success/failure
  thresholds: {
    http_req_duration: [
      { threshold: 'p(99) < 100', abortOnFail: false },  // p99 < 100ms
      { threshold: 'p(95) < 50', abortOnFail: false },   // p95 < 50ms
    ],
    http_req_failed: [
      { threshold: 'rate < 0.001', abortOnFail: false }, // Error rate < 0.1%
    ],
    'rate_limit_violations{tier:free}': [
      { threshold: 'count > 0', abortOnFail: false },    // Must detect violations
    ],
  },
};

// Test Suite 1: Rate Limiting Validation
export function rateLimitingTests() {
  const orgEntries = Object.entries(testOrgs);
  let currentOrgIndex = __VU % orgEntries.length;
  
  const [orgId, orgConfig] = orgEntries[currentOrgIndex];

  group(`Rate Limiting - ${orgConfig.tier.toUpperCase()} Tier (${orgId})`, () => {
    // Create GraphQL query
    const query = `
      query {
        rateLimitStatus {
          organization {
            id
            tier
          }
          currentMinute {
            requestCount
            limit
            remaining
          }
          currentHour {
            requestCount
            limit
            remaining
          }
        }
      }
    `;

    const payload = JSON.stringify({ query });
    const params = {
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': `test-key-${orgId}`,
        'X-Organization-ID': orgId,
      },
    };

    // Test 1: Check rate limit status
    const res = http.post(
      `${BASE_URL}/graphql`,
      payload,
      params
    );

    const success = res.status === 200 && !res.body.includes('errors');
    check(res, {
      'status is 200': (r) => r.status === 200,
      'response has no GraphQL errors': (r) => !r.body.includes('errors'),
      'response time < 100ms': (r) => r.timings.duration < 100,
    });

    rateLimitCheckTime.add(res.timings.duration > 100 ? 1 : 0);

    // Parse response and track tokens
    try {
      const body = JSON.parse(res.body);
      if (body.data?.rateLimitStatus?.currentMinute) {
        const remaining = body.data.rateLimitStatus.currentMinute.remaining;
        tierTokensRemaining.add(remaining, {
          tier: orgConfig.tier,
          org: orgId,
        });

        // Track violations (when we exceed the limit)
        if (remaining <= 0) {
          rateLimitViolations.add(1, { tier: orgConfig.tier });
        }
      }
    } catch (e) {
      // Ignore parse errors
    }

    sleep(1);
  });

  // Test 2: Parallel requests to simulate burst
  group(`Burst Load - ${orgConfig.tier.toUpperCase()} Tier`, () => {
    const burst = http.batch([
      [
        'POST',
        `${BASE_URL}/graphql`,
        JSON.stringify({
          query: `query { user { id email tier } }`,
        }),
        {
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': `test-key-${orgId}`,
            'X-Organization-ID': orgId,
          },
        },
      ],
      [
        'GET',
        `${BASE_URL}/api/v1/organizations/${orgId}/usage`,
        null,
        {
          headers: {
            'X-API-Key': `test-key-${orgId}`,
          },
        },
      ],
    ]);

    check(burst[0], { 'GraphQL burst succeeded': (r) => r.status === 200 });
    check(burst[1], { 'Usage endpoint burst succeeded': (r) => r.status === 200 });

    sleep(2);
  });
}

// Test Suite 2: Enterprise Tier (Unlimited)
export function enterpriseTierTests() {
  const orgId = 'org-enterprise-001';

  group(`Enterprise Unlimited - Sustained Load (${orgId})`, () => {
    const query = `
      query {
        organization(id: "${orgId}") {
          id
          tier
          quotas {
            requestsPerMinute
            currentMinuteUsage
          }
        }
      }
    `;

    const payload = JSON.stringify({ query });
    const params = {
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': `test-key-${orgId}`,
      },
    };

    for (let i = 0; i < 10; i++) {
      const res = http.post(`${BASE_URL}/graphql`, payload, params);
      check(res, {
        'enterprise: status is 200': (r) => r.status === 200,
        'enterprise: no rate limiting': (r) => 
          !r.headers['X-RateLimit-Remaining'] || 
          r.headers['X-RateLimit-Remaining'] === 'unlimited',
      });
    }

    sleep(1);
  });
}

// Main export - runs by scenario
export default function () {
  if (__SCENARIO.name === 'ramp_up') {
    rateLimitingTests();
  } else if (__SCENARIO.name === 'free_tier_violation') {
    // Hammer free tier orgs
    const freeOrgs = Object.entries(testOrgs).filter(([_, cfg]) => cfg.tier === 'free');
    const orgId = freeOrgs[__VU % freeOrgs.length][0];

    const query = `query { rateLimitStatus { currentMinute { remaining } } }`;
    const res = http.post(
      `${BASE_URL}/graphql`,
      JSON.stringify({ query }),
      {
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': `test-key-${orgId}`,
          'X-Organization-ID': orgId,
        },
      }
    );

    if (res.status === 429) {
      rateLimitViolations.add(1, { tier: 'free' });
    }

    check(res, {
      'request completed': (r) => r.status === 200 || r.status === 429,
    });

    sleep(0.5);
  }
}

// Summary handler - output results as JSON
export function handleSummary(data) {
  const summary = {
    timestamp: new Date().toISOString(),
    scenarios: Object.keys(options.scenarios),
    metrics: {
      requests: data.metrics.http_reqs?.value || 0,
      errors: data.metrics.http_req_failed?.value || 0,
      duration_seconds: data.state.testRunDurationMs / 1000,
      rate_limit_violations: data.metrics.rate_limit_violations?.value || 0,
      rate_limit_check_time_ratio: data.metrics.rate_limit_check_duration?.rate || 0,
    },
    thresholds: data.metrics,
  };

  console.log(JSON.stringify(summary, null, 2));

  // Write to file if running in non-browser environment
  if (typeof open !== 'undefined') {
    return {
      'load-test-results.json': JSON.stringify(summary, null, 2),
    };
  }
}
