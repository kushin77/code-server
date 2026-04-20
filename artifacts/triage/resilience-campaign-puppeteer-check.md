# Resilience Campaign Summary

Generated: 2026-04-19T23:59:46+00:00
Campaign profile: baseline
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 5} avg=0.029s min=0.028s max=0.031s
- ide-root: {'200': 5} avg=0.491s min=0.276s max=1.299s
- static-css: {'200': 5} avg=0.032s min=0.026s max=0.036s
- oauth-start: {'200': 5} avg=0.253s min=0.233s max=0.302s

## Soak-Lite

- portal-root: {'403': 15} avg=0.031s min=0.019s max=0.038s
- ide-root: {'200': 15} avg=0.354s min=0.246s max=1.269s
- static-css: {'200': 15} avg=0.032s min=0.028s max=0.037s
- oauth-start: {'200': 15} avg=0.254s min=0.227s max=0.291s

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
