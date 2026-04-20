# Live Surface Baseline

Generated: 2026-04-20T00:00:39+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 15
Parallelism: 5

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=15 | 0.034 | 0.024 | 0.045 |
| ide-root | https://ide.kushnir.cloud/ | 200=15 | 0.285 | 0.261 | 0.311 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=15 | 0.032 | 0.026 | 0.041 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=15 | 0.324 | 0.232 | 1.262 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
