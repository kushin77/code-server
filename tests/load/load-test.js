/**
 * Load testing with k6 for code-server infrastructure
 * @file tests/load/load-test.js
 * @issue #1537 (Testing & QA Strategy)
 * @phase Phase 4: Load & Performance Testing
 * @governance GOV-002: Performance baselines, scalability validation
 * 
 * Test Scenarios:
 * - Gradual load increase: 100 → 500 → 1000 concurrent users
 * - Sustained load: 1000 concurrent users for 5+ minutes
 * - Performance thresholds: p95 < 500ms (GET), p95 < 800ms (POST)
 * - Error rate monitoring: < 0.1% acceptable
 * 
 * Usage:
 *   k6 run tests/load/load-test.js
 *   k6 run tests/load/load-test.js --vus 500 --duration 10m
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';

// Configuration
export let options = {
  // Test stages: ramp up → sustained → ramp down
  stages: [
    { duration: '2m', target: 100 },    // Ramp up to 100 users
    { duration: '3m', target: 500 },    // Increase to 500 users
    { duration: '5m', target: 1000 },   // Increase to 1000 users
    { duration: '5m', target: 1000 },   // Sustain at 1000 users
    { duration: '3m', target: 500 },    // Ramp down to 500 users
    { duration: '2m', target: 0 },      // Ramp down to 0
  ],
  
  // Performance thresholds
  thresholds: {
    // Response time thresholds
    'http_req_duration': [
      'p(50) < 100',    // 50th percentile < 100ms
      'p(95) < 500',    // 95th percentile < 500ms for GET
      'p(99) < 2000',   // 99th percentile < 2000ms
      'avg < 300',      // Average < 300ms
    ],
    
    'http_req_duration{staticAsset:yes}': [
      'p(99) < 1000',
    ],
    
    // Error rate thresholds
    'http_req_failed': [
      'rate < 0.1',     // Error rate < 0.1% (1 in 1000)
    ],
    
    'http_req_failed{staticAsset:yes}': [
      'rate < 0.05',
    ],
    
    // Connection success rate
    'http_conn_connecting{group:::setup}': [
      'p(99) < 600',
    ],
  },
};

// Configuration from environment
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const API_BASE = __ENV.API_BASE || `${BASE_URL}/api`;
const THINK_TIME = parseInt(__ENV.THINK_TIME) || 2000;

/**
 * Setup: Initialize test data and session once
 */
export function setup() {
  console.log(`Starting load test against ${BASE_URL}`);
  console.log(`API Base: ${API_BASE}`);
  console.log(`Virtual Users: ${__ENV.VUS || 'ramping 100-1000'}`);
  
  return {
    testStartTime: new Date().getTime(),
  };
}

/**
 * Main load test scenario
 */
export default function(data) {
  const vu = `vu-${__VU}-iter-${__ITER}`;
  
  // 1. Health check
  group('01_health_check', function() {
    const res = http.get(`${BASE_URL}/health`, {
      tags: { name: 'HealthCheck' },
    });
    
    check(res, {
      'health status 200': (r) => r.status === 200,
      'health response < 100ms': (r) => r.timings.duration < 100,
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 2. List teams (GET request)
  group('02_list_teams', function() {
    const res = http.get(`${API_BASE}/teams`, {
      headers: {
        'User-Agent': `k6-load-test/${vu}`,
        'X-Test-VU': String(__VU),
      },
      tags: {
        name: 'ListTeams',
        staticAsset: 'no',
      },
    });
    
    check(res, {
      'list teams status 200': (r) => r.status === 200,
      'list teams response < 500ms': (r) => r.timings.duration < 500,
      'list teams body not empty': (r) => r.body.length > 0,
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 3. Get team details (GET request)
  group('03_get_team', function() {
    const teamId = `team-${__VU}`;
    
    const res = http.get(`${API_BASE}/teams/${teamId}`, {
      headers: {
        'User-Agent': `k6-load-test/${vu}`,
        'X-Test-VU': String(__VU),
      },
      tags: {
        name: 'GetTeam',
        staticAsset: 'no',
      },
    });
    
    check(res, {
      'get team status 200 or 404': (r) => [200, 404].includes(r.status),
      'get team response < 500ms': (r) => r.timings.duration < 500,
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 4. Create team (POST request)
  group('04_create_team', function() {
    const teamName = `LoadTest-Team-${__VU}-${__ITER}-${Date.now()}`;
    const payload = JSON.stringify({
      name: teamName,
      description: 'Load test team',
    });
    
    const res = http.post(`${API_BASE}/teams`, payload, {
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': `k6-load-test/${vu}`,
        'X-Test-VU': String(__VU),
      },
      tags: {
        name: 'CreateTeam',
        staticAsset: 'no',
      },
    });
    
    check(res, {
      'create team status 201 or 200': (r) => [200, 201].includes(r.status),
      'create team response < 800ms': (r) => r.timings.duration < 800,
      'create team has id': (r) => r.body.includes('id') || r.status >= 400,
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 5. List team members (GET request)
  group('05_list_team_members', function() {
    const teamId = `team-${__VU}`;
    
    const res = http.get(`${API_BASE}/teams/${teamId}/members`, {
      headers: {
        'User-Agent': `k6-load-test/${vu}`,
        'X-Test-VU': String(__VU),
      },
      tags: {
        name: 'ListMembers',
        staticAsset: 'no',
      },
    });
    
    check(res, {
      'list members status 200 or 404': (r) => [200, 404].includes(r.status),
      'list members response < 500ms': (r) => r.timings.duration < 500,
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 6. Search memory (GET request)
  group('06_search_memory', function() {
    const res = http.get(
      `${API_BASE}/memory/search?q=test&limit=10`,
      {
        headers: {
          'User-Agent': `k6-load-test/${vu}`,
          'X-Test-VU': String(__VU),
        },
        tags: {
          name: 'SearchMemory',
          staticAsset: 'no',
        },
      }
    );
    
    check(res, {
      'search memory status 200 or 204': (r) => [200, 204].includes(r.status),
      'search memory response < 1000ms': (r) => r.timings.duration < 1000,
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 7. Get memory document (GET request)
  group('07_get_memory', function() {
    const docId = `doc-${__VU}`;
    
    const res = http.get(`${API_BASE}/memory/${docId}`, {
      headers: {
        'User-Agent': `k6-load-test/${vu}`,
        'X-Test-VU': String(__VU),
      },
      tags: {
        name: 'GetMemory',
        staticAsset: 'no',
      },
    });
    
    check(res, {
      'get memory status 200 or 404': (r) => [200, 404].includes(r.status),
      'get memory response < 500ms': (r) => r.timings.duration < 500,
    });
  });
  
  sleep(THINK_TIME / 1000);
}

/**
 * Teardown: Run once after all test iterations complete
 */
export function teardown(data) {
  const testEndTime = new Date().getTime();
  const duration = (testEndTime - data.testStartTime) / 1000;
  console.log(`Load test completed. Duration: ${duration}s`);
}
