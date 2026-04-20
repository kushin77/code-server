# Live Surface Baseline

Generated: 2026-04-20T00:00:37+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 5
Parallelism: 5

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=5 | 0.043 | 0.034 | 0.047 |
| ide-root | https://ide.kushnir.cloud/ | 200=5 | 0.288 | 0.282 | 0.298 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=5 | 0.03 | 0.025 | 0.035 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=5 | 0.453 | 0.239 | 1.265 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
