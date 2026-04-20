# Resilience Campaign Summary

Generated: 2026-04-19T23:59:34+00:00
Campaign profile: baseline
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 5} avg=0.041s min=0.037s max=0.045s
- ide-root: {'200': 5} avg=0.311s min=0.296s max=0.329s
- static-css: {'200': 5} avg=0.032s min=0.028s max=0.036s
- oauth-start: {'200': 5} avg=0.263s min=0.249s max=0.287s

## Soak-Lite

- portal-root: {'403': 15} avg=0.029s min=0.021s max=0.038s
- ide-root: {'200': 15} avg=0.349s min=0.247s max=1.298s
- static-css: {'200': 15} avg=0.048s min=0.025s max=0.07s
- oauth-start: {'200': 15} avg=0.269s min=0.236s max=0.298s

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
