# Live Surface Baseline

Generated: 2026-04-19T19:01:46+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 30
Parallelism: 10

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=30 | 0.045 | 0.027 | 0.058 |
| ide-root | https://ide.kushnir.cloud/ | 200=30 | 0.345 | 0.254 | 1.338 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=30 | 0.07 | 0.025 | 1.07 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=30 | 0.304 | 0.232 | 1.292 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
