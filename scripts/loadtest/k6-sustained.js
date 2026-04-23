import http from "k6/http";
import { check, sleep } from "k6";

const scaleProfile = (__ENV.SCALE_PROFILE || "sustained").toLowerCase();

function buildScenarios() {
  if (scaleProfile === "500x") {
    return {
      sustained_500x: {
        executor: "ramping-vus",
        stages: [
          { duration: "5m", target: 500 },    // ramp up to 500 users over 5 minutes
          { duration: "30m", target: 500 },   // sustain at 500 for 30 minutes
          { duration: "5m", target: 0 },      // ramp down to 0 over 5 minutes
        ],
        tags: { phase: "sustained_500x" },
      },
    };
  }

  if (scaleProfile === "100x") {
    return {
      sustained_100x: {
        executor: "ramping-vus",
        stages: [
          { duration: "5m", target: 250 },    // ramp up to 250 users over 5 minutes
          { duration: "20m", target: 250 },   // sustain at 250 for 20 minutes
          { duration: "5m", target: 0 },      // ramp down to 0 over 5 minutes
        ],
        tags: { phase: "sustained_100x" },
      },
    };
  }

  return {
    sustained_10x: {
      executor: "ramping-vus",
      stages: [
        { duration: "3m", target: 50 },     // ramp up to 50 users over 3 minutes
        { duration: "15m", target: 50 },    // sustain at 50 for 15 minutes
        { duration: "3m", target: 0 },      // ramp down to 0 over 3 minutes
      ],
      tags: { phase: "sustained_10x" },
    },
  };
}

export const options = {
  scenarios: buildScenarios(),
  thresholds: {
    http_req_failed: ["rate<0.001"],       // very strict - <0.1% failure over sustained load
    http_req_duration: ["p(50)<100", "p(95)<300", "p(99)<500"],  // strict latency requirements
  },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

export default function () {
  const res = http.get(`${BASE_URL}/healthz`);
  check(res, {
    "status is 200": (r) => r.status === 200,
    "response time < 1s": (r) => r.timings.duration < 1000,
  });
  
  // collect memory metrics at intervals
  const memRes = http.get(`${BASE_URL}/api/metrics`);
  check(memRes, {
    "metrics endpoint available": (r) => r.status === 200,
  });
  
  sleep(1);
}
