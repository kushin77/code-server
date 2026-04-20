# Live Surface Baseline

Generated: 2026-04-20T00:03:14+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 15
Parallelism: 5

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=15 | 0.029 | 0.024 | 0.037 |
| ide-root | https://ide.kushnir.cloud/ | 200=15 | 0.275 | 0.25 | 0.312 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=15 | 0.03 | 0.024 | 0.036 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=15 | 0.25 | 0.207 | 0.295 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
