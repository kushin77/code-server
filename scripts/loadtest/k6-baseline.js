import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  scenarios: {
    baseline_1x: {
      executor: "constant-vus",
      vus: 5,
      duration: "2m",
      tags: { phase: "1x" },
    },
    load_2x: {
      executor: "constant-vus",
      vus: 10,
      duration: "2m",
      startTime: "2m",
      tags: { phase: "2x" },
    },
    load_5x: {
      executor: "constant-vus",
      vus: 25,
      duration: "2m",
      startTime: "4m",
      tags: { phase: "5x" },
    },
  },
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
