# Live Surface Baseline

Generated: 2026-04-19T19:01:44+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 15
Parallelism: 10

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=15 | 0.059 | 0.043 | 0.07 |
| ide-root | https://ide.kushnir.cloud/ | 200=15 | 0.297 | 0.255 | 0.342 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=15 | 0.056 | 0.035 | 0.071 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=15 | 0.347 | 0.231 | 1.292 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
