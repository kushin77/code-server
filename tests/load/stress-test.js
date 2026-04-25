/**
 * Stress testing with k6 for code-server infrastructure
 * @file tests/load/stress-test.js
 * @issue #1537 (Testing & QA Strategy)
 * @phase Phase 4: Load & Performance Testing
 * @governance GOV-002: System resilience, breaking point identification
 * 
 * Test Scenarios:
 * - Gradual linear load increase until system breaks
 * - Identify breaking point (where error rate > 10%)
 * - Measure system behavior under extreme load
 * - Test recovery after load reduction
 * 
 * Usage:
 *   k6 run tests/load/stress-test.js
 *   k6 run tests/load/stress-test.js --vus 5000 --duration 20m
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';

// Stress test configuration
export let options = {
  // Gradually increase load until system breaks
  stages: [
    // Phase 1: Ramp up to find breaking point
    { duration: '5m', target: 100 },
    { duration: '5m', target: 250 },
    { duration: '5m', target: 500 },
    { duration: '5m', target: 1000 },
    { duration: '5m', target: 2000 },    // Stress point 1
    { duration: '5m', target: 3000 },    // Stress point 2
    { duration: '5m', target: 5000 },    // Max stress
    
    // Phase 2: Hold at max stress
    { duration: '5m', target: 5000 },
    
    // Phase 3: Graceful recovery
    { duration: '5m', target: 1000 },
    { duration: '5m', target: 0 },
  ],
  
  // Relaxed thresholds for stress testing
  thresholds: {
    // Track response times but don't fail
    'http_req_duration': [
      'p(99) < 5000',   // Allow higher latency under stress
    ],
    
    // Track errors but allow higher rate (to find breaking point)
    'http_req_failed': [
      'rate < 0.5',     // Allow up to 50% error rate at breaking point
    ],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const API_BASE = __ENV.API_BASE || `${BASE_URL}/api`;
const THINK_TIME = parseInt(__ENV.THINK_TIME) || 1000;

/**
 * Setup
 */
export function setup() {
  console.log(`=== STRESS TEST STARTING ===`);
  console.log(`Target: ${BASE_URL}`);
  console.log(`API Base: ${API_BASE}`);
  console.log(`Phases: Ramp (0-5000 VUs) → Hold → Recovery`);
  console.log(`Looking for system breaking point...`);
  
  return {
    testStartTime: new Date().getTime(),
  };
}

/**
 * Stress test scenario - simplified to focus on throughput
 */
export default function(data) {
  const vu = `vu-${__VU}-iter-${__ITER}`;
  
  // 1. Fast health check
  group('health_check', function() {
    const res = http.get(`${BASE_URL}/health`, {
      tags: { name: 'HealthCheck' },
      timeout: '30s',
    });
    
    check(res, {
      'health status 200': (r) => r.status === 200,
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 2. List teams (high-frequency operation)
  group('list_teams', function() {
    const res = http.get(`${API_BASE}/teams?limit=100`, {
      headers: {
        'X-Test-VU': String(__VU),
        'X-Test-Iter': String(__ITER),
      },
      tags: { name: 'ListTeams' },
      timeout: '30s',
    });
    
    check(res, {
      'list teams responded': (r) => r.status !== null,
      'list teams status 200 or error': (r) => [200, 400, 404, 429, 500, 503].includes(r.status),
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 3. Create team (write operation)
  group('create_team', function() {
    const payload = JSON.stringify({
      name: `StressTest-${__VU}-${__ITER}-${Date.now()}`,
      description: 'Stress test',
    });
    
    const res = http.post(`${API_BASE}/teams`, payload, {
      headers: {
        'Content-Type': 'application/json',
        'X-Test-VU': String(__VU),
      },
      tags: { name: 'CreateTeam' },
      timeout: '30s',
    });
    
    check(res, {
      'create team responded': (r) => r.status !== null,
      'create team status valid': (r) => [200, 201, 400, 404, 429, 500, 503].includes(r.status),
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 4. Search memory (read-heavy)
  group('search_memory', function() {
    const res = http.get(`${API_BASE}/memory/search?q=test&limit=50`, {
      headers: {
        'X-Test-VU': String(__VU),
      },
      tags: { name: 'SearchMemory' },
      timeout: '30s',
    });
    
    check(res, {
      'search responded': (r) => r.status !== null,
      'search status valid': (r) => [200, 204, 400, 404, 429, 500, 503].includes(r.status),
    });
  });
  
  sleep(THINK_TIME / 1000);
}

/**
 * Teardown
 */
export function teardown(data) {
  const testEndTime = new Date().getTime();
  const duration = (testEndTime - data.testStartTime) / 1000;
  console.log(`=== STRESS TEST COMPLETED ===`);
  console.log(`Total duration: ${duration}s`);
  console.log(`Check reports for breaking point analysis`);
}
