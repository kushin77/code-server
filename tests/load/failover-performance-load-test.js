import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const endpoint = __ENV.ENDPOINT || __ENV.BASE_URL || 'https://ide.kushnir.cloud';
const dryRun = (__ENV.DRY_RUN || '1') === '1';
const vus = Number(__ENV.VUS || '10');
const duration = __ENV.DURATION || '60s';
const failoverTriggerDelay = Number(__ENV.FAILOVER_TRIGGER_DELAY || '15');
const requestInterval = Number(__ENV.REQUEST_INTERVAL || '0.5');
const testStartTime = Number(__ENV.TEST_START_MS || Date.now());

const failoverRequestErrors = new Rate('failover_request_errors');
const failoverRequestLatency = new Trend('failover_request_latency');
const failoverDetectionTime = new Trend('failover_detection_time');
const failoverRequestsBefore = new Counter('failover_requests_before');
const failoverRequestsAfter = new Counter('failover_requests_after');

export const options = {
  vus,
  duration,
  thresholds: {
    failover_request_errors: ['rate<0.15'],
    failover_request_latency: ['p(95)<1000'],
  },
};

export default function () {
  const now = Date.now();
  const elapsed = now - testStartTime;
  const failoverWindowMs = failoverTriggerDelay * 1000;
  const inFailoverWindow = elapsed >= failoverWindowMs && elapsed <= failoverWindowMs + 15000;

  const startedAt = Date.now();
  const response = http.get(`${endpoint}/health`, {
    headers: {
      Authorization: `Bearer ${__ENV.JWT_TOKEN || 'test-token'}`,
    },
  });
  const latency = Date.now() - startedAt;

  failoverRequestLatency.add(latency);
  failoverRequestErrors.add(response.status >= 400);

  if (elapsed < failoverWindowMs) {
    failoverRequestsBefore.add(1);
  } else {
    failoverRequestsAfter.add(1);
  }

  if (inFailoverWindow && response.status === 200) {
    failoverDetectionTime.add(Math.max(0, elapsed - failoverWindowMs));
  }

  check(response, {
    'request succeeded': (r) => r.status === 200,
    'service reports healthy': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.status === 'healthy';
      } catch {
        return false;
      }
    },
  });

  sleep(requestInterval);
}

export function handleSummary(data) {
  return {
    stdout: JSON.stringify(data, null, 2),
    'artifacts/load-tests/failover-performance-summary.json': JSON.stringify(data, null, 2),
  };
}
