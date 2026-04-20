# Resilience Campaign Summary

Generated: 2026-04-20T00:01:21+00:00
Campaign profile: baseline
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 5} avg=0.048s min=0.036s max=0.058s
- ide-root: {'200': 5} avg=0.42s min=0.241s max=1.012s
- static-css: {'200': 5} avg=0.045s min=0.027s max=0.058s
- oauth-start: {'200': 5} avg=0.266s min=0.218s max=0.304s

## Soak-Lite

- portal-root: {'403': 15} avg=0.042s min=0.026s max=0.072s
- ide-root: {'200': 15} avg=0.534s min=0.379s max=1.427s
- static-css: {'200': 15} avg=0.09s min=0.026s max=0.143s
- oauth-start: {'200': 15} avg=0.547s min=0.366s max=1.682s

## Authenticated Smoke

- status: skipped
- exit code: 0
- reason: not requested

## Loadtest

- status: skipped
- exit code: 0
- reason: not requested
- scale profile: baseline

## Failover Continuity

- status: skipped
- exit code: 0
- reason: not requested

## Puppeteer Parity

- status: failed
- exit code: 1
- reason: exit code 1

## Notes

- This runner collects a repeatable surface baseline and a slightly heavier soak sample.
- It also provides an authenticated smoke path when the required environment is available.
- It includes a Puppeteer parity probe for critical login and root-path checks.
- It includes a profile-driven k6 loadtest for baseline and 100x campaign modes.
- Chaos/fault injection remains a separate follow-up step for the broader resilience campaign.
