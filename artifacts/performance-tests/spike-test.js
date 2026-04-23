import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: { duration: '2s', target: 5 }, { duration: '6s', target: 5 },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function() {
  const res = http.get('https://ide.kushnir.cloud' + '/health');
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  sleep(1);
}
