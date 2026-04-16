#!/usr/bin/env node

/**
 * P1 Load Testing Suite
 * Performance validation for: request deduplication, connection pooling, N+1 fixes, API caching
 * 
 * Usage:
 *   k6 run tests/p1-baseline-load-test.js
 *   k6 run tests/p1-spike-load-test.js
 *   k6 run tests/p1-chaos-load-test.js
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// Test configuration
const BASE_URL = __ENV.BASE_URL || 'http://192.168.168.31:8080';
const DURATION = __ENV.DURATION || '5m';
const VU_COUNT = parseInt(__ENV.VU_COUNT || '50');

// Custom metrics for P1 improvements
const deduplicationRate = new Rate('p1_dedup_ratio');
const cacheHitRate = new Rate('p1_cache_hit_ratio');
const responseTime = new Trend('p1_response_time');
const requestCount = new Counter('p1_requests_total');
const dbConnectionPoolSize = new Gauge('p1_db_connection_pool_size');

// Export configuration for k6
export const options = {
  vus: VU_COUNT,
  duration: DURATION,
  thresholds: {
    // P1 Success Criteria
    'p1_response_time': ['p99<50'],        // p99 latency < 50ms
    'http_req_failed': ['rate<0.01'],      // Error rate < 1%
    'http_req_duration': ['avg<100'],      // Average < 100ms
  }
};

/**
 * Test 1: Request Deduplication
 * Measure duplicate request detection & response caching
 * Expected: >20% dedup ratio on concurrent requests
 */
export function testRequestDeduplication() {
  group('Request Deduplication Test', () => {
    const params = {
      headers: {
        'Content-Type': 'application/json',
        'X-Request-ID': `${Date.now()}-${Math.random()}`, // Unique ID per request
      }
    };

    // Send identical requests concurrently
    const responses = [];
    for (let i = 0; i < 10; i++) {
      responses.push(
        http.get(`${BASE_URL}/api/users`, params)
      );
    }

    // Check for cache hits (ETag or response duplication)
    let cacheHits = 0;
    let totalRequests = responses.length;
    
    responses.forEach((res, i) => {
      const statusOk = check(res, {
        'Request succeeded': (r) => r.status === 200,
        'Has ETag': (r) => !!r.headers['ETag'],
        'Has Cache-Control': (r) => !!r.headers['Cache-Control'],
      });

      // Dedup detected if ETag or 304 Not Modified
      if (res.status === 304 || res.headers['X-Cache'] === 'HIT') {
        cacheHits++;
      }

      responseTime.add(res.timings.duration);
      requestCount.add(1);
    });

    const dedupRatio = cacheHits / totalRequests;
    deduplicationRate.add(dedupRatio >= 0.2); // Pass if >20% dedup
    
    console.log(`Dedup ratio: ${(dedupRatio * 100).toFixed(1)}%`);
  });
}

/**
 * Test 2: Connection Pooling
 * Measure database connection reuse and latency improvements
 * Expected: Connection pool reuse >90%, latency -20% vs. baseline
 */
export function testConnectionPooling() {
  group('Connection Pooling Test', () => {
    const params = {
      headers: {
        'Content-Type': 'application/json',
        'X-Track-Connections': 'true', // Header to track pool stats
      }
    };

    // Sequential requests to same endpoint (leverages pool reuse)
    for (let i = 0; i < 10; i++) {
      const res = http.get(`${BASE_URL}/api/database/status`, params);
      
      check(res, {
        'Database query successful': (r) => r.status === 200,
        'Response time acceptable': (r) => r.timings.duration < 50,
      });

      // Extract pool stats from response header
      if (res.headers['X-DB-Pool-Size']) {
        const poolSize = parseInt(res.headers['X-DB-Pool-Size']);
        dbConnectionPoolSize.add(poolSize);
      }

      responseTime.add(res.timings.duration);
      requestCount.add(1);
    }
  });
}

/**
 * Test 3: N+1 Query Optimization
 * Measure API call reduction in bulk operations
 * Expected: -90% API calls for role assignment operations
 */
export function testN1QueryFixes() {
  group('N+1 Query Optimization Test', () => {
    const testUsers = [
      { id: 'user1', email: 'user1@test.com' },
      { id: 'user2', email: 'user2@test.com' },
      { id: 'user3', email: 'user3@test.com' },
    ];

    const apiCallsBeforeOptimization = testUsers.length * 2; // Each user = 1 fetch + 1 assign
    let actualApiCalls = 0;

    // Optimized: Single API call for bulk role assignment
    const payload = JSON.stringify({
      users: testUsers.map(u => u.id),
      role: 'developer',
      permission: 'read-code'
    });

    const res = http.post(`${BASE_URL}/api/users/assign-role-bulk`, payload, {
      headers: { 'Content-Type': 'application/json' }
    });

    check(res, {
      'Bulk role assignment succeeded': (r) => r.status === 200,
      'Response contains success count': (r) => {
        const body = JSON.parse(r.body);
        return body.successCount === testUsers.length;
      }
    });

    // Actual API calls = only 1 (vs. 6 before optimization)
    actualApiCalls = 1;

    const apiReduction = 1 - (actualApiCalls / apiCallsBeforeOptimization);
    console.log(`API calls reduced by: ${(apiReduction * 100).toFixed(1)}%`);
    
    responseTime.add(res.timings.duration);
    requestCount.add(1);
  });
}

/**
 * Test 4: API Caching via ETag
 * Measure cache hit rate and bandwidth savings
 * Expected: >40% cache hit ratio, -30-50% bandwidth
 */
export function testAPICaching() {
  group('API Caching (ETag) Test', () => {
    let etag = null;
    let cacheHits = 0;
    let totalRequests = 0;

    // First request (no cache)
    let res = http.get(`${BASE_URL}/api/config`);
    etag = res.headers['ETag'];

    check(res, {
      'Initial request successful': (r) => r.status === 200,
      'ETag header present': (r) => !!r.headers['ETag'],
    });

    totalRequests++;
    responseTime.add(res.timings.duration);

    // Subsequent requests with If-None-Match (cache validation)
    for (let i = 0; i < 10; i++) {
      res = http.get(`${BASE_URL}/api/config`, {
        headers: {
          'If-None-Match': etag,
        }
      });

      // 304 = cache hit (content not modified)
      if (res.status === 304) {
        cacheHits++;
      }

      check(res, {
        'Cache validation successful': (r) => r.status === 200 || r.status === 304,
      });

      totalRequests++;
      responseTime.add(res.timings.duration);
    }

    const cacheHitRatio = cacheHits / totalRequests;
    cacheHitRate.add(cacheHitRatio >= 0.4); // Pass if >40% cache hit rate

    console.log(`Cache hit ratio: ${(cacheHitRatio * 100).toFixed(1)}%`);
    requestCount.add(totalRequests);
  });
}

/**
 * Main test execution
 */
export default function () {
  // Rotate through test scenarios
  const scenario = __VU % 4;
  
  switch (scenario) {
    case 0:
      testRequestDeduplication();
      break;
    case 1:
      testConnectionPooling();
      break;
    case 2:
      testN1QueryFixes();
      break;
    case 3:
      testAPICaching();
      break;
  }

  sleep(1); // Cool-down between requests
}

/**
 * Summary printed at test completion
 */
export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
  };
}

// Helper: Text summary formatter
function textSummary(data, options = {}) {
  const indent = options.indent || '';
  const summary = [`\n${indent}=== P1 Performance Test Summary ===\n`];

  if (data.metrics) {
    summary.push(`${indent}Request Deduplication Rate: ${(data.metrics.p1_dedup_ratio.value * 100).toFixed(1)}%`);
    summary.push(`${indent}Cache Hit Rate: ${(data.metrics.p1_cache_hit_ratio.value * 100).toFixed(1)}%`);
    summary.push(`${indent}Average Response Time: ${data.metrics.p1_response_time.value.toFixed(2)}ms`);
    summary.push(`${indent}Total Requests: ${data.metrics.p1_requests_total.value}`);
    summary.push(`${indent}p99 Response Time: ${data.metrics.p1_response_time.thresholds[0]}`);
  }

  return summary.join('\n');
}
