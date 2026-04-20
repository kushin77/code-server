# Resilience Campaign Summary

Generated: 2026-04-20T00:00:41+00:00
Campaign profile: baseline
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 5} avg=0.043s min=0.034s max=0.047s
- ide-root: {'200': 5} avg=0.288s min=0.282s max=0.298s
- static-css: {'200': 5} avg=0.03s min=0.025s max=0.035s
- oauth-start: {'200': 5} avg=0.453s min=0.239s max=1.265s

## Soak-Lite

- portal-root: {'403': 15} avg=0.034s min=0.024s max=0.045s
- ide-root: {'200': 15} avg=0.285s min=0.261s max=0.311s
- static-css: {'200': 15} avg=0.032s min=0.026s max=0.041s
- oauth-start: {'200': 15} avg=0.324s min=0.232s max=1.262s

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
- exit code: 2
- reason: exit code 2

## Notes

- This runner collects a repeatable surface baseline and a slightly heavier soak sample.
- It also provides an authenticated smoke path when the required environment is available.
- It includes a Puppeteer parity probe for critical login and root-path checks.
- It includes a profile-driven k6 loadtest for baseline and 100x campaign modes.
- Chaos/fault injection remains a separate follow-up step for the broader resilience campaign.
