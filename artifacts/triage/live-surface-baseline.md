# Live Surface Baseline

Generated: 2026-04-19T18:22:52+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 2
Parallelism: 2

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=2 | 0.026 | 0.025 | 0.026 |
| ide-root | https://ide.kushnir.cloud/ | 200=2 | 0.239 | 0.235 | 0.244 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=2 | 0.036 | 0.036 | 0.036 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=2 | 0.273 | 0.245 | 0.302 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
