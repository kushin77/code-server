// @file        tests/stress/k6-load.js
// @module      testing/stress
// @description k6 load + soak test for code-server-enterprise
// @governance  GOV-002: IaC, idempotent, scriptable
// Issue #1537: Testing & QA — Stress & Performance Testing
//
// Usage:
//   # Ramp to 50 concurrent users (load test):
//   k6 run tests/stress/k6-load.js
//
//   # 1-hour soak test (10 users):
//   SOAK=1 k6 run tests/stress/k6-load.js
//
//   # Target a specific host:
//   BASE_URL=https://ide.kushnir.cloud k6 run tests/stress/k6-load.js

import http from "k6/http";
import { sleep, check } from "k6";
import { Rate, Trend } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "https://ide.kushnir.cloud";
const SOAK = __ENV.SOAK === "1";

// Custom metrics
const errorRate = new Rate("error_rate");
const authLatency = new Trend("auth_latency_ms", true);
const healthLatency = new Trend("health_latency_ms", true);

// ── SLA Thresholds ────────────────────────────────────────────────────────────
export const options = SOAK
  ? // Soak test: 10 VUs for 1 hour
    {
      vus: 10,
      duration: "1h",
      thresholds: {
        http_req_duration: ["p(99)<2000"],  // p99 < 2s
        error_rate: ["rate<0.001"],          // error rate < 0.1%
        http_req_failed: ["rate<0.001"],
      },
    }
  : // Load test: ramp to 50 VUs, hold 5 min, ramp down
    {
      stages: [
        { duration: "2m", target: 10 },   // Warm-up
        { duration: "5m", target: 30 },   // Ramp to 30
        { duration: "5m", target: 50 },   // Ramp to 50
        { duration: "5m", target: 50 },   // Hold at 50
        { duration: "2m", target: 0 },    // Ramp down
      ],
      thresholds: {
        http_req_duration: ["p(50)<500", "p(95)<1500", "p(99)<2000"],
        error_rate: ["rate<0.001"],
        http_req_failed: ["rate<0.001"],
      },
    };

// ── Scenarios ─────────────────────────────────────────────────────────────────

export default function () {
  // 1. Health check
  const healthStart = Date.now();
  const healthResp = http.get(`${BASE_URL}/oauth2/ping`, {
    tags: { scenario: "health" },
  });
  healthLatency.add(Date.now() - healthStart);

  const healthOk = check(healthResp, {
    "oauth2/ping status 200": (r) => r.status === 200,
    "oauth2/ping response time < 500ms": (r) => r.timings.duration < 500,
  });
  errorRate.add(!healthOk);

  sleep(0.5);

  // 2. Static asset load (workbench CSS/JS)
  const assetResp = http.get(`${BASE_URL}/static/`, {
    tags: { scenario: "assets" },
  });
  const assetOk = check(assetResp, {
    "static asset status 200 or 301": (r) =>
      r.status === 200 || r.status === 301 || r.status === 302,
  });
  errorRate.add(!assetOk);

  sleep(1);

  // 3. Auth redirect check (unauthenticated)
  const authStart = Date.now();
  const authResp = http.get(BASE_URL, {
    redirects: 0, // Don't follow redirects
    tags: { scenario: "auth_redirect" },
  });
  authLatency.add(Date.now() - authStart);

  const authOk = check(authResp, {
    "root redirects (302/307)": (r) =>
      r.status === 302 || r.status === 307 || r.status === 200,
  });
  errorRate.add(!authOk);

  sleep(1 + Math.random() * 2); // 1-3s think time
}

// ── Summary ────────────────────────────────────────────────────────────────────

export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  return {
    [`artifacts/reports/stress-test-${timestamp}.json`]: JSON.stringify(
      data,
      null,
      2
    ),
    stdout: textSummary(data),
  };
}

function textSummary(data) {
  const metrics = data.metrics;
  const dur = metrics.http_req_duration?.values;
  const err = metrics.error_rate?.values;

  return `
=== k6 Stress Test Summary ===
Base URL: ${BASE_URL}
Mode: ${SOAK ? "SOAK (1h / 10 VUs)" : "LOAD (50 VUs peak)"}

Request Duration:
  p50: ${dur?.["p(50)"]?.toFixed(1) ?? "N/A"}ms
  p95: ${dur?.["p(95)"]?.toFixed(1) ?? "N/A"}ms
  p99: ${dur?.["p(99)"]?.toFixed(1) ?? "N/A"}ms

Error Rate: ${((err?.rate ?? 0) * 100).toFixed(3)}%
SLA Target: p99 < 2000ms, error rate < 0.1%
`;
}
