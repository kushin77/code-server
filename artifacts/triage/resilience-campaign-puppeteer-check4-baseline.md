# Live Surface Baseline

Generated: 2026-04-20T00:02:14+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 5
Parallelism: 5

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=5 | 0.047 | 0.038 | 0.056 |
| ide-root | https://ide.kushnir.cloud/ | 200=5 | 0.305 | 0.276 | 0.342 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=5 | 0.043 | 0.028 | 0.05 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=5 | 0.26 | 0.235 | 0.282 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
