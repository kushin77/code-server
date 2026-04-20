# Resilience Campaign Summary

Generated: 2026-04-20T00:02:31+00:00
Campaign profile: baseline
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 5} avg=0.032s min=0.029s max=0.034s
- ide-root: {'200': 5} avg=0.25s min=0.239s max=0.276s
- static-css: {'200': 5} avg=0.033s min=0.026s max=0.038s
- oauth-start: {'200': 5} avg=0.248s min=0.221s max=0.277s

## Soak-Lite

- portal-root: {'403': 15} avg=0.026s min=0.019s max=0.033s
- ide-root: {'200': 15} avg=0.321s min=0.228s max=1.28s
- static-css: {'200': 15} avg=0.029s min=0.022s max=0.034s
- oauth-start: {'200': 15} avg=0.236s min=0.207s max=0.294s

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

- status: skipped
- exit code: 0
- reason: not requested

## Notes

- This runner collects a repeatable surface baseline and a slightly heavier soak sample.
- It also provides an authenticated smoke path when the required environment is available.
- It includes a Puppeteer parity probe for critical login and root-path checks.
- It includes a profile-driven k6 loadtest for baseline and 100x campaign modes.
- Chaos/fault injection remains a separate follow-up step for the broader resilience campaign.
