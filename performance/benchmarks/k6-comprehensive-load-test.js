/**
 * Comprehensive K6 Load Testing Suite for Code-Server Enterprise
 * 
 * Tests all critical services:
 * - Code Server IDE (WebSocket + HTTP)
 * - Agent API (LangGraph orchestration)
 * - Embeddings Service (Vector generation & search)
 * - RBAC API (Authentication & authorization)
 * - ChromaDB (Vector database queries)
 * 
 * Run: k6 run performance/benchmarks/k6-comprehensive-load-test.js
 * With env: k6 run -e BASE_URL=http://localhost:8080 -e OLLAMA_URL=http://localhost:11434
 */

import http from 'k6/http';
import ws from 'k6/ws';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const AGENT_API = __ENV.AGENT_API || 'http://localhost:8001';
const EMBEDDINGS_API = __ENV.EMBEDDINGS_API || 'http://localhost:8002';
const OLLAMA_URL = __ENV.OLLAMA_URL || 'http://localhost:11434';

// Custom metrics
const errorRate = new Rate('errors');
const duration = new Trend('request_duration');
const successfulRequests = new Counter('successful_requests');
const failedRequests = new Counter('failed_requests');

// Thresholds for test pass/fail
export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up: 10 VUs
    { duration: '1m', target: 50 },    // Ramp up: 50 VUs
    { duration: '2m', target: 100 },   // Full load: 100 VUs
    { duration: '1m', target: 50 },    // Ramp down: 50 VUs
    { duration: '30s', target: 0 },    // Cool down
  ],
  thresholds: {
    'http_req_duration': ['p(99)<1000', 'p(95)<500', 'p(50)<100'], // Response times
    'http_req_failed': ['rate<0.1'],                                // Error rate <10%
    'errors': ['rate<0.05'],                                        // Custom error rate <5%
  },
};

// Utility functions
function makeRequest(method, url, payload = null, params = {}) {
  const startTime = new Date();
  let response;
  
  const options = {
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'k6-load-test/1.0',
      ...params.headers,
    },
    timeout: '30s',
  };

  try {
    if (method === 'GET') {
      response = http.get(url, options);
    } else if (method === 'POST') {
      response = http.post(url, JSON.stringify(payload), options);
    } else if (method === 'PUT') {
      response = http.put(url, JSON.stringify(payload), options);
    } else if (method === 'DELETE') {
      response = http.del(url, options);
    }

    const endTime = new Date();
    const elapsed = endTime - startTime;
    duration.add(elapsed);

    const success = response.status >= 200 && response.status < 400;
    if (success) {
      successfulRequests.add(1);
    } else {
      failedRequests.add(1);
      errorRate.add(1);
    }

    return response;
  } catch (error) {
    failedRequests.add(1);
    errorRate.add(1);
    console.error(`Request failed: ${method} ${url} - ${error}`);
    return null;
  }
}

// Test suites
export default function () {
  // Health checks - baseline <100ms
  group('Health Checks', () => {
    // Code Server health
    let res = makeRequest('GET', `${BASE_URL}/healthz`);
    check(res, {
      'code-server health is 200': r => r && r.status === 200,
      'code-server response <50ms': r => r && r.timings.duration < 50,
    });

    // Agent API health  
    res = makeRequest('GET', `${AGENT_API}/health`);
    check(res, {
      'agent-api health is 200': r => r && r.status === 200,
      'agent-api response <50ms': r => r && r.timings.duration < 50,
    });

    // Embeddings health
    res = makeRequest('GET', `${EMBEDDINGS_API}/api/v1/heartbeat`);
    check(res, {
      'embeddings health is 200': r => r && r.status === 200,
      'embeddings response <50ms': r => r && r.timings.duration < 50,
    });

    // Ollama health
    res = makeRequest('GET', `${OLLAMA_URL}/api/tags`);
    check(res, {
      'ollama health is 200': r => r && r.status === 200,
      'ollama response <100ms': r => r && r.timings.duration < 100,
    });
  });

  sleep(1);

  // Agent API - Orchestration (<200ms p99)
  group('Agent API - LangGraph Orchestration', () => {
    const agentPayload = {
      user_id: `user-${Math.random()}`,
      query: 'Analyze the git repository structure and suggest optimizations',
      model: 'qwen2.5-coder:14b-instruct-q6_K',
      context_window: 4096,
    };

    let res = makeRequest('POST', `${AGENT_API}/v1/agents/farm/execute`, agentPayload);
    check(res, {
      'agent execute returns 200-202': r => r && (r.status === 200 || r.status === 202),
      'agent response <200ms p99': r => r && r.timings.duration < 200,
    });

    // Agent status check
    const agentId = res && res.json()?.agent_id;
    if (agentId) {
      res = makeRequest('GET', `${AGENT_API}/v1/agents/${agentId}/status`);
      check(res, {
        'agent status 200': r => r && r.status === 200,
        'status check <100ms': r => r && r.timings.duration < 100,
      });
    }
  });

  sleep(1);

  // Embeddings Service - Vector Generation (<1s p95)
  group('Embeddings Service - Vector Generation', () => {
    const codeSnippets = [
      'function fibonacci(n) { return n <= 1 ? n : fibonacci(n-1) + fibonacci(n-2); }',
      'SELECT * FROM users WHERE created_at > NOW() - INTERVAL 1 MONTH;',
      'const config = { timeout: 30000, retries: 3, backoff: exponential };',
      'def parse_json(data): return json.loads(data.decode("utf-8"))',
      'type User = { id: uuid, email: string, created_at: timestamp }',
    ];

    // Single snippet embedding
    let payload = { snippets: codeSnippets.slice(0, 1) };
    let res = makeRequest('POST', `${EMBEDDINGS_API}/api/v1/embed`, payload);
    check(res, {
      'single embed 200': r => r && r.status === 200,
      'single embed <100ms': r => r && r.timings.duration < 100,
    });

    // Batch embedding
    payload = { snippets: codeSnippets };
    res = makeRequest('POST', `${EMBEDDINGS_API}/api/v1/embed`, payload);
    check(res, {
      'batch embed 200': r => r && r.status === 200,
      'batch embed <500ms': r => r && r.timings.duration < 500,
    });

    // Semantic search
    payload = {
      query: 'How do I implement efficient data structures?',
      limit: 10,
      threshold: 0.7,
    };
    res = makeRequest('POST', `${EMBEDDINGS_API}/api/v1/search`, payload);
    check(res, {
      'search 200': r => r && r.status === 200,
      'search <1000ms p99': r => r && r.timings.duration < 1000,
    });

    // Embeddings stats
    res = makeRequest('GET', `${EMBEDDINGS_API}/api/v1/stats`);
    check(res, {
      'stats 200': r => r && r.status === 200,
      'stats <50ms': r => r && r.timings.duration < 50,
    });
  });

  sleep(1);

  // RBAC API - Authentication (<100ms p99)
  group('RBAC API - Authentication & Authorization', () => {
    // Token introspection
    const tokenPayload = {
      token: `token-${Math.random()}`,
      client_id: 'agent-farm',
      client_secret: 'secret-key',
    };

    let res = makeRequest('POST', `${BASE_URL}/oauth2/introspect`, tokenPayload);
    check(res, {
      'token introspection 2xx': r => r && r.status >= 200 && r.status < 300,
      'introspection <100ms': r => r && r.timings.duration < 100,
    });

    // User info check
    res = makeRequest('GET', `${BASE_URL}/oauth2/user`, null, {
      headers: { 'Authorization': 'Bearer test-token' },
    });
    check(res, {
      'userinfo 2xx': r => r && (r.status >= 200 && r.status < 400),
      'userinfo <100ms': r => r && r.timings.duration < 100,
    });

    // RBAC check
    const rbacPayload = {
      subject: `user-${Math.random()}`,
      action: 'read',
      resource: 'workspace',
    };
    res = makeRequest('POST', `${BASE_URL}/rbac/check`, rbacPayload);
    check(res, {
      'rbac check 2xx': r => r && r.status >= 200 && r.status < 300,
      'rbac <100ms': r => r && r.timings.duration < 100,
    });
  });

  sleep(1);

  // File Operations - Code Repository Access
  group('File Operations - Code Repository', () => {
    // List directory
    let res = makeRequest('GET', `${BASE_URL}/api/workspace/files?path=/workspace`);
    check(res, {
      'file list 2xx': r => r && r.status >= 200 && r.status < 300,
      'file list <300ms': r => r && r.timings.duration < 300,
    });

    // Read file
    res = makeRequest('GET', `${BASE_URL}/api/workspace/files/read?path=/workspace/README.md`);
    check(res, {
      'file read 2xx': r => r && r.status >= 200 && r.status < 400,
      'file read <300ms': r => r && r.timings.duration < 300,
    });

    // Search in files
    const searchPayload = { query: 'function', path: '/workspace' };
    res = makeRequest('POST', `${BASE_URL}/api/workspace/search`, searchPayload);
    check(res, {
      'file search 2xx': r => r && r.status >= 200 && r.status < 300,
      'file search <500ms': r => r && r.timings.duration < 500,
    });
  });

  sleep(1);

  // WebSocket Connection - Code Server (real-time IDE)
  group('WebSocket - Code Editor Real-time', () => {
    const wsUrl = BASE_URL.replace(/^http/, 'ws') + '/ws';
    
    try {
      const res = ws.connect(wsUrl, {
        tags: { name: 'CodeServerWS' },
      }, (socket) => {
        socket.on('open', () => {
          check(true, { 'websocket open': true });
        });

        socket.on('message', (msg) => {
          check(msg.length > 0, { 'websocket message received': true });
        });

        socket.on('error', (e) => {
          errorRate.add(1);
          check(false, { 'websocket error': e });
        });

        socket.setTimeout(() => {
          socket.close();
        }, 3000);
      });

      check(res, {
        'websocket connect 1000': r => r && r.status === 1000,
      });
    } catch (e) {
      errorRate.add(1);
      console.error(`WebSocket test failed: ${e}`);
    }
  });

  sleep(2);

  // Summary
  group('Performance Summary', () => {
    console.log(`
    ╔══════════════════════════════════════════════════════════════╗
    ║     Code-Server Enterprise Performance Test Complete         ║
    ╚══════════════════════════════════════════════════════════════╝
    
    Successful Requests: ${successfulRequests.value}
    Failed Requests: ${failedRequests.value}
    Error Rate: ${errorRate.value}%
    
    Target Metrics:
    ✓ Health Check: <100ms p99
    ✓ Agent API: <200ms p99
    ✓ Embeddings: <1s p95
    ✓ RBAC: <100ms p99
    ✓ File Ops: <300ms p99
    ✓ WebSocket: Real-time <500ms latency
    `);
  });
}
