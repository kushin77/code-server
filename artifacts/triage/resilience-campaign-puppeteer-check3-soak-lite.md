# Live Surface Baseline

Generated: 2026-04-20T00:01:16+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 15
Parallelism: 5

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=15 | 0.042 | 0.026 | 0.072 |
| ide-root | https://ide.kushnir.cloud/ | 200=15 | 0.534 | 0.379 | 1.427 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=15 | 0.09 | 0.026 | 0.143 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=15 | 0.547 | 0.366 | 1.682 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
