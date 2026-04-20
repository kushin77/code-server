# Live Surface Baseline

Generated: 2026-04-20T00:02:57+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 100
Parallelism: 20

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=100 | 0.069 | 0.032 | 1.037 |
| ide-root | https://ide.kushnir.cloud/ | 200=100 | 0.346 | 0.246 | 1.322 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=100 | 0.071 | 0.023 | 1.056 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=100 | 0.28 | 0.211 | 1.24 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
