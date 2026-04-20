# Resilience Campaign Summary

Generated: 2026-04-20T00:03:21+00:00
Campaign profile: baseline
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 5} avg=0.23s min=0.023s max=1.051s
- ide-root: {'200': 5} avg=0.286s min=0.263s max=0.3s
- static-css: {'200': 5} avg=0.033s min=0.024s max=0.042s
- oauth-start: {'200': 5} avg=0.268s min=0.253s max=0.291s

## Soak-Lite

- portal-root: {'403': 15} avg=0.029s min=0.024s max=0.037s
- ide-root: {'200': 15} avg=0.275s min=0.25s max=0.312s
- static-css: {'200': 15} avg=0.03s min=0.024s max=0.036s
- oauth-start: {'200': 15} avg=0.25s min=0.207s max=0.295s

## Authenticated Smoke

- status: passed
- exit code: 0
- reason: n/a

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

- status: passed
- exit code: 0
- reason: n/a

## Notes

- This runner collects a repeatable surface baseline and a slightly heavier soak sample.
- It also provides an authenticated smoke path when the required environment is available.
- It includes a Puppeteer parity probe for critical login and root-path checks.
- It includes a profile-driven k6 loadtest for baseline and 100x campaign modes.
- Chaos/fault injection remains a separate follow-up step for the broader resilience campaign.
