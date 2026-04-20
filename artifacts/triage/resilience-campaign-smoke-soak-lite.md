# Live Surface Baseline

Generated: 2026-04-19T23:59:31+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 15
Parallelism: 5

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=15 | 0.029 | 0.021 | 0.038 |
| ide-root | https://ide.kushnir.cloud/ | 200=15 | 0.349 | 0.247 | 1.298 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=15 | 0.048 | 0.025 | 0.07 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=15 | 0.269 | 0.236 | 0.298 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
