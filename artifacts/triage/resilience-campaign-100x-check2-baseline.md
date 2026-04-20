# Live Surface Baseline

Generated: 2026-04-20T00:02:51+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud
Requests per target: 50
Parallelism: 10

## Results

| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |
|---|---|---|---:|---:|---:|
| portal-root | https://kushnir.cloud/ | 403=50 | 0.083 | 0.039 | 0.161 |
| ide-root | https://ide.kushnir.cloud/ | 200=50 | 0.323 | 0.246 | 1.32 |
| static-css | https://kushnir.cloud/static/css/main.c5955fd3.css | 200=50 | 0.068 | 0.028 | 1.065 |
| oauth-start | https://ide.kushnir.cloud/oauth2/start?rd=%2F | 200=50 | 0.276 | 0.215 | 1.283 |

## Notes

- This report captures the current live surface, but it is a baseline only.
- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.
