import http from "k6/http";
import { check, sleep } from "k6";

const scaleProfile = (__ENV.SCALE_PROFILE || "spike").toLowerCase();

function buildScenarios() {
  if (scaleProfile === "1000x") {
    return {
      spike_1000x: {
        executor: "ramping-vus",
        stages: [
          { duration: "30s", target: 1000 },  // ramp up to 1000 users in 30s
          { duration: "5m", target: 1000 },   // stay at 1000 for 5 minutes
          { duration: "30s", target: 0 },     // ramp down to 0
        ],
        tags: { phase: "spike_1000x" },
      },
    };
  }

  if (scaleProfile === "100x") {
    return {
      spike_100x: {
        executor: "ramping-vus",
        stages: [
          { duration: "30s", target: 250 },   // ramp up to 250 users in 30s
          { duration: "3m", target: 250 },    // stay at 250 for 3 minutes
          { duration: "30s", target: 0 },     // ramp down to 0
        ],
        tags: { phase: "spike_100x" },
      },
    };
  }

  return {
    spike_10x: {
      executor: "ramping-vus",
      stages: [
        { duration: "30s", target: 50 },    // ramp up to 50 users in 30s
        { duration: "2m", target: 50 },     // stay at 50 for 2 minutes
        { duration: "30s", target: 0 },     // ramp down to 0
      ],
      tags: { phase: "spike_10x" },
    },
  };
}

export const options = {
  scenarios: buildScenarios(),
  thresholds: {
    http_req_failed: ["rate<0.01"],       // allow up to 1% failure during spike
    http_req_duration: ["p(95)<500", "p(99)<1500"],  // relaxed thresholds for spike
  },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

export default function () {
  const res = http.get(`${BASE_URL}/healthz`);
  check(res, {
    "status is 200": (r) => r.status === 200,
    "response time < 2s": (r) => r.timings.duration < 2000,
  });
  sleep(0.5);
}
