# Resilience Campaign Summary

Generated: 2026-04-20T00:03:04+00:00
Campaign profile: 100x
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 50} avg=0.083s min=0.039s max=0.161s
- ide-root: {'200': 50} avg=0.323s min=0.246s max=1.32s
- static-css: {'200': 50} avg=0.068s min=0.028s max=1.065s
- oauth-start: {'200': 50} avg=0.276s min=0.215s max=1.283s

## Soak-Lite

- portal-root: {'403': 100} avg=0.069s min=0.032s max=1.037s
- ide-root: {'200': 100} avg=0.346s min=0.246s max=1.322s
- static-css: {'200': 100} avg=0.071s min=0.023s max=1.056s
- oauth-start: {'200': 100} avg=0.28s min=0.211s max=1.24s

## Authenticated Smoke

- status: skipped
- exit code: 0
- reason: not requested

## Loadtest

- status: skipped
- exit code: 0
- reason: not requested
- scale profile: 100x

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
