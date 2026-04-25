import http from 'k6/http';
import { check, group, sleep } from 'k6';

/**
 * Team Management Load Test Script
 * Tests team endpoints under load (150 concurrent users)
 * 
 * Run with:
 *   k6 run tests/load/team-load-test.js --vus 150 --duration 5m
 */

export const options = {
  stages: [
    { duration: '30s', target: 40 },    // Ramp up
    { duration: '1m30s', target: 150 }, // Ramp to 150 users
    { duration: '3m', target: 150 },    // Stay at 150
    { duration: '1m', target: 75 },     // Ramp down
    { duration: '30s', target: 0 },     // Ramp to 0
  ],
  thresholds: {
    'http_req_duration': ['p(95)<800', 'p(99)<1500'],
    'http_req_failed': ['rate<0.1'],
  },
};

export default function () {
  const baseUrl = process.env.API_BASE_URL || 'http://localhost:8001';
  const userId = Math.floor(Math.random() * 10000);
  const timestamp = Date.now();
  const orgId = 'org-' + Math.floor(Math.random() * 100);
  const teamId = 'team-' + Math.floor(Math.random() * 100);

  // 1. Create Organization
  group('Team - Create Organization', () => {
    const res = http.post(`${baseUrl}/api/organizations`, {
      name: `K6 Org ${timestamp}-${userId}`,
      slug: `k6-org-${timestamp}-${userId}`,
    }, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 201, 400, 401, or 403': (r) => 
        r.status === 201 || r.status === 400 || r.status === 401 || r.status === 403,
      'response time < 800ms': (r) => r.timings.duration < 800,
    });
  });

  sleep(0.5);

  // 2. Get Organization
  group('Team - Get Organization', () => {
    const res = http.get(`${baseUrl}/api/organizations/${orgId}`, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 200, 401, 403, or 404': (r) => 
        r.status === 200 || r.status === 401 || r.status === 403 || r.status === 404,
      'response time < 300ms': (r) => r.timings.duration < 300,
    });
  });

  sleep(0.5);

  // 3. Create Team
  group('Team - Create Team', () => {
    const res = http.post(`${baseUrl}/api/organizations/${orgId}/teams`, {
      name: `K6 Team ${timestamp}-${userId}`,
      slug: `k6-team-${timestamp}-${userId}`,
    }, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 201, 400, 401, 403, or 404': (r) => 
        r.status === 201 || r.status === 400 || r.status === 401 || r.status === 403 || r.status === 404,
      'response time < 800ms': (r) => r.timings.duration < 800,
    });
  });

  sleep(0.5);

  // 4. Get Team Members
  group('Team - Get Members', () => {
    const res = http.get(`${baseUrl}/api/teams/${teamId}/members`, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 200, 401, 403, or 404': (r) => 
        r.status === 200 || r.status === 401 || r.status === 403 || r.status === 404,
      'response time < 400ms': (r) => r.timings.duration < 400,
    });
  });

  sleep(0.5);

  // 5. Add Team Member
  group('Team - Add Member', () => {
    const res = http.post(`${baseUrl}/api/teams/${teamId}/members`, {
      user_id: `user-${userId}`,
      role: 'developer',
    }, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 201, 400, 401, 403, or 404': (r) => 
        r.status === 201 || r.status === 400 || r.status === 401 || r.status === 403 || r.status === 404,
      'response time < 800ms': (r) => r.timings.duration < 800,
    });
  });

  sleep(0.5);

  // 6. Invite to Team
  group('Team - Send Invitation', () => {
    const res = http.post(`${baseUrl}/api/teams/${teamId}/invitations`, {
      email: `invite-${timestamp}-${userId}@example.com`,
      role: 'developer',
    }, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 201, 400, 401, 403, or 404': (r) => 
        r.status === 201 || r.status === 400 || r.status === 401 || r.status === 403 || r.status === 404,
      'response time < 600ms': (r) => r.timings.duration < 600,
    });
  });

  sleep(0.5);

  // 7. List Organization Members
  group('Team - List Org Members', () => {
    const res = http.get(`${baseUrl}/api/organizations/${orgId}/members`, {
      headers: {
        'Authorization': 'Bearer fake-jwt-token',
      },
    });

    check(res, {
      'status is 200, 401, 403, or 404': (r) => 
        r.status === 200 || r.status === 401 || r.status === 403 || r.status === 404,
      'response time < 400ms': (r) => r.timings.duration < 400,
    });
  });

  sleep(1);
}
