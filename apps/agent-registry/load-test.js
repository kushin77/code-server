import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10,
  duration: '10s',
  thresholds: {
    http_req_failed: ['rate<0.01'], 
    http_req_duration: ['p(95)<500'], 
  },
};

const BASE_URL = 'http://localhost:8000';

export default function () {
  // 1. Search for agents (Internal endpoint)
  let searchRes = http.get(`${BASE_URL}/registry/search?q=security`);
  check(searchRes, {
    'status is 200': (r) => r.status === 200,
  });

  // 2. Heavy work: Get all packages and simulate an install check
  let listRes = http.get(`${BASE_URL}/registry/agents`);
  if (listRes.status === 200 && listRes.json().length > 0) {
    const agents = listRes.json();
    const agentId = agents[0].id;
    
    // 3. Increment usage (Writing state)
    let usageBody = JSON.stringify({
      tokens: 42,
      user_id: 'load-test-runner'
    });
    
    let usageRes = http.post(`${BASE_URL}/registry/usage/${agentId}`, usageBody, {
       headers: { 'Content-Type': 'application/json' }
    });
    
    check(usageRes, {
        'usage update success': (r) => r.status === 200,
    });
  }
  
  sleep(0.1);
}
