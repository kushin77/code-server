import http from 'k6/http';
import { check, sleep } from 'k6';
export const options = { stages: [{ duration: '1m', target: 100 }] };
export default function () {
  let res = http.get('http://localhost:8080/health');
  check(res, { status: r => r.status === 200 });
  sleep(1);
}
