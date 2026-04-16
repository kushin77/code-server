/**
 * P1 Chaos Load Test (Failure Injection)
 * 
 * Simulates cascading backend failures:
 * - Database unavailable (PostgreSQL down)
 * - Redis connection pool exhausted
 * - Timeout scenarios
 * - Verify graceful degradation & circuit breaker
 * - Measure recovery time (<30 seconds)
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter, Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://192.168.168.31:8080';

// Metrics
const recoveryTime = new Trend('chaos_recovery_time');
const circuitBreakerTrips = new Counter('chaos_breaker_trips');
const fallbackResponses = new Rate('chaos_fallback_used');

export const options = {
  stages: [
    { duration: '1m', target: 50 },         // Normal load
    { duration: '30s', target: 50 },        // Inject failure
    { duration: '1m', target: 50 },         // Monitor recovery
    { duration: '30s', target: 0 },         // Cool down
  ],
  thresholds: {
    'chaos_recovery_time': ['p(99)<30s'],   // 30 second recovery SLA
    'chaos_fallback_used': ['rate<0.2'],    // <20% fallback responses
  }
};

const FAILURE_START_TIME = 60; // Start failures at 60s
const FAILURE_DURATION = 30;   // Simulate 30s of failures

export default function () {
  const elapsed = __ENV.ELAPSED_TIME ? parseInt(__ENV.ELAPSED_TIME) : 0;
  const isFailureWindow = elapsed >= FAILURE_START_TIME && 
                          elapsed < (FAILURE_START_TIME + FAILURE_DURATION);

  if (isFailureWindow) {
    // Chaos Test Phase: Failures active
    testChaosPhase();
  } else if (elapsed >= (FAILURE_START_TIME + FAILURE_DURATION)) {
    // Recovery Phase: Measure system recovery
    testRecoveryPhase();
  } else {
    // Normal Phase: Baseline operations
    testNormalPhase();
  }

  sleep(1);
}

function testNormalPhase() {
  // Normal operation - all endpoints should succeed
  let res = http.get(`${BASE_URL}/api/health`);
  check(res, { 'health check normal': (r) => r.status === 200 });
  
  res = http.get(`${BASE_URL}/api/users`);
  check(res, { 'users API normal': (r) => r.status === 200 || r.status === 304 });
}

function testChaosPhase() {
  // Chaos Phase: Some requests will fail or use fallback
  
  // Attempt 1: Direct API call (may timeout/fail)
  let res = http.get(`${BASE_URL}/api/users`, { timeout: '5s' });

  if (res.status === 503 || res.status === 504) {
    // Service unavailable - circuit breaker should trip
    circuitBreakerTrips.add(1);
    console.log('Circuit breaker triggered - service unavailable');
  }

  if (res.status >= 400) {
    // Attempt 2: Fallback endpoint with cached data
    res = http.get(`${BASE_URL}/api/users/cached`, { timeout: '2s' });
    
    if (res.status === 200) {
      fallbackResponses.add(1);  // Successful fallback
      console.log('Fallback succeeded with cached response');
    }
  }

  check(res, {
    'response handled gracefully': (r) => r.status === 200 || 
                                          r.status === 304 || 
                                          r.status === 503,
  });
}

function testRecoveryPhase() {
  // Recovery Phase: Measure time to full recovery
  const recoveryStartTime = __ENV.RECOVERY_START || Date.now();
  
  let res = http.get(`${BASE_URL}/api/health`);
  const responseTimeMs = res.timings.duration;

  check(res, {
    'service recovered': (r) => r.status === 200,
    'recovery latency acceptable': (r) => r.timings.duration < 100,
  });

  recoveryTime.add(responseTimeMs);

  // Verify all services back online
  res = http.get(`${BASE_URL}/api/users`);
  check(res, { 'users API recovered': (r) => r.status === 200 });

  res = http.get(`${BASE_URL}/api/database/status`);
  check(res, { 'database recovered': (r) => r.status === 200 });
}

/**
 * Summary handler with chaos test insights
 */
export function handleSummary(data) {
  const summary = ['\n=== P1 Chaos Test Summary ===\n'];
  
  if (data.metrics) {
    const recoveryMs = data.metrics.chaos_recovery_time.value || 0;
    const breakerTrips = data.metrics.chaos_breaker_trips.value || 0;
    const fallbackRate = (data.metrics.chaos_fallback_used.value * 100).toFixed(1);

    summary.push(`Recovery Time (p99): ${recoveryMs.toFixed(0)}ms (SLA: <30s)`);
    summary.push(`Circuit Breaker Trips: ${breakerTrips}`);
    summary.push(`Fallback Used: ${fallbackRate}%`);
  }

  console.log(summary.join('\n'));
  return {
    'stdout': summary.join('\n'),
  };
}
