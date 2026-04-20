# Resilience Campaign Summary

Generated: 2026-04-19T19:01:58+00:00
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 15} avg=0.059s min=0.043s max=0.07s
- ide-root: {'200': 15} avg=0.297s min=0.255s max=0.342s
- static-css: {'200': 15} avg=0.056s min=0.035s max=0.071s
- oauth-start: {'200': 15} avg=0.347s min=0.231s max=1.292s

## Soak-Lite

- portal-root: {'403': 30} avg=0.045s min=0.027s max=0.058s
- ide-root: {'200': 30} avg=0.345s min=0.254s max=1.338s
- static-css: {'200': 30} avg=0.07s min=0.025s max=1.07s
- oauth-start: {'200': 30} avg=0.304s min=0.232s max=1.292s

## Authenticated Smoke

- status: passed
- exit code: 0
- reason: n/a

## Failover Continuity

- status: skipped
- exit code: 0
- reason: not requested

## Notes

- This runner collects a repeatable surface baseline and a slightly heavier soak sample.
- It also provides an authenticated smoke path when the required environment is available.
- Chaos/fault injection remains a separate follow-up step for the broader resilience campaign.
