import http from "k6/http";
import { check, sleep } from "k6";

const scaleProfile = (__ENV.SCALE_PROFILE || "baseline").toLowerCase();

function buildScenarios() {
  if (scaleProfile === "100x") {
    return {
      baseline_100x: {
        executor: "constant-vus",
        vus: 250,
        duration: "3m",
        tags: { phase: "100x" },
      },
    };
  }

  if (scaleProfile === "10x") {
    return {
      baseline_10x: {
        executor: "constant-vus",
        vus: 50,
        duration: "2m",
        tags: { phase: "10x" },
      },
    };
  }

  return {
    baseline_1x: {
      executor: "constant-vus",
      vus: 5,
      duration: "2m",
      tags: { phase: "1x" },
    },
  };
}

export const options = {
  scenarios: buildScenarios(),
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500", "p(99)<1000"],
  },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

export default function () {
  const res = http.get(`${BASE_URL}/healthz`);
  check(res, {
    "status is 200": (r) => r.status === 200,
  });
  sleep(1);
}
