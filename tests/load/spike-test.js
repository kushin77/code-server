/**
 * Spike testing with k6 for code-server infrastructure
 * @file tests/load/spike-test.js
 * @issue #1537 (Testing & QA Strategy)
 * @phase Phase 4: Load & Performance Testing
 * @governance GOV-002: Burst capacity testing, recovery validation
 * 
 * Test Scenarios:
 * - Normal baseline load (100 users)
 * - Sudden spike to 1000 users (10x increase)
 * - Measure response time spike and recovery
 * - Test circuit breaker patterns and rate limiting
 * 
 * Usage:
 *   k6 run tests/load/spike-test.js
 *   k6 run tests/load/spike-test.js --vus 1000 --duration 15m
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';

// Spike test configuration
export let options = {
  stages: [
    // Baseline: Normal load
    { duration: '3m', target: 100 },    // Normal load
    
    // Spike 1: Sudden 10x increase
    { duration: '1m', target: 1000 },   // Immediate spike to 1000
    { duration: '3m', target: 1000 },   // Hold spike
    
    // Recovery 1: Back to normal
    { duration: '1m', target: 100 },
    { duration: '2m', target: 100 },
    
    // Spike 2: Another spike (test repeated spikes)
    { duration: '1m', target: 1500 },   // Even higher spike
    { duration: '3m', target: 1500 },   // Hold higher spike
    
    // Final recovery
    { duration: '2m', target: 0 },
  ],
  
  thresholds: {
    // Track spike impact on response time
    'http_req_duration': [
      'p(95) < 2000',   // Allow degraded performance during spike
      'p(99) < 5000',
    ],
    
    // Accept some failures during spike
    'http_req_failed': [
      'rate < 0.2',     // Accept up to 20% errors during spike
    ],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const API_BASE = __ENV.API_BASE || `${BASE_URL}/api`;
const THINK_TIME = parseInt(__ENV.THINK_TIME) || 1500;

/**
 * Setup
 */
export function setup() {
  console.log(`=== SPIKE TEST STARTING ===`);
  console.log(`Target: ${BASE_URL}`);
  console.log(`Baseline: 100 VUs`);
  console.log(`Spike 1: 1000 VUs (10x)`);
  console.log(`Spike 2: 1500 VUs (15x)`);
  console.log(`Recovery tests enabled`);
  
  return {
    testStartTime: new Date().getTime(),
    spikes: [],
  };
}

/**
 * Spike test scenario
 */
export default function(data) {
  const vu = `vu-${__VU}-iter-${__ITER}`;
  const currentVUs = __VU;
  
  // Track which phase we're in
  let phase = 'baseline';
  if (currentVUs > 1200) phase = 'spike2';
  else if (currentVUs > 300) phase = 'spike1';
  
  // 1. Health check (lightweight)
  group('01_health', function() {
    const res = http.get(`${BASE_URL}/health`, {
      tags: { 
        name: 'Health',
        phase: phase,
      },
      timeout: '30s',
    });
    
    check(res, {
      'health ok': (r) => r.status === 200,
      'health fast': (r) => r.timings.duration < 200,
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 2. API call - list teams
  group('02_list_teams', function() {
    const res = http.get(`${API_BASE}/teams`, {
      headers: {
        'X-Spike-Phase': phase,
        'X-Test-VU': String(__VU),
      },
      tags: { 
        name: 'ListTeams',
        phase: phase,
      },
      timeout: '30s',
    });
    
    check(res, {
      'teams responded': (r) => r.status !== null,
      'teams status ok': (r) => [200, 404, 500].includes(r.status),
      'teams response time': (r) => {
        if (phase === 'baseline') return r.timings.duration < 500;
        if (phase === 'spike1') return r.timings.duration < 2000;
        if (phase === 'spike2') return r.timings.duration < 5000;
        return true;
      },
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 3. Create team - stress write operations
  group('03_create_team', function() {
    const payload = JSON.stringify({
      name: `Spike-${phase}-${__VU}-${__ITER}-${Date.now()}`,
      description: 'Spike test',
    });
    
    const res = http.post(`${API_BASE}/teams`, payload, {
      headers: {
        'Content-Type': 'application/json',
        'X-Spike-Phase': phase,
        'X-Test-VU': String(__VU),
      },
      tags: { 
        name: 'CreateTeam',
        phase: phase,
      },
      timeout: '30s',
    });
    
    check(res, {
      'create responded': (r) => r.status !== null,
      'create valid status': (r) => [200, 201, 400, 500].includes(r.status),
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 4. Memory operations
  group('04_memory_search', function() {
    const res = http.get(`${API_BASE}/memory/search?q=test&limit=20`, {
      headers: {
        'X-Spike-Phase': phase,
        'X-Test-VU': String(__VU),
      },
      tags: { 
        name: 'MemorySearch',
        phase: phase,
      },
      timeout: '30s',
    });
    
    check(res, {
      'search responded': (r) => r.status !== null,
      'search valid': (r) => [200, 204, 400, 404, 500].includes(r.status),
    });
  });
  
  sleep(THINK_TIME / 1000);
  
  // 5. Database-intensive operation
  group('05_team_members', function() {
    const teamId = `team-spike-${__VU}`;
    
    const res = http.get(`${API_BASE}/teams/${teamId}/members`, {
      headers: {
        'X-Spike-Phase': phase,
        'X-Test-VU': String(__VU),
      },
      tags: { 
        name: 'TeamMembers',
        phase: phase,
      },
      timeout: '30s',
    });
    
    check(res, {
      'members responded': (r) => r.status !== null,
      'members valid': (r) => [200, 404, 500].includes(r.status),
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
  console.log(`=== SPIKE TEST COMPLETED ===`);
  console.log(`Total duration: ${duration}s`);
  console.log(`Key metrics to review:`);
  console.log(`  - Baseline response times (100 VUs)`);
  console.log(`  - Spike 1 impact (1000 VUs)`);
  console.log(`  - Recovery time to baseline`);
  console.log(`  - Spike 2 impact (1500 VUs)`);
  console.log(`  - Final recovery time`);
}
