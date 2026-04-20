# Resilience Campaign Summary

Generated: 2026-04-20T00:02:19+00:00
Campaign profile: baseline
Portal base URL: https://kushnir.cloud
IDE base URL: https://ide.kushnir.cloud

## Baseline

- portal-root: {'403': 5} avg=0.047s min=0.038s max=0.056s
- ide-root: {'200': 5} avg=0.305s min=0.276s max=0.342s
- static-css: {'200': 5} avg=0.043s min=0.028s max=0.05s
- oauth-start: {'200': 5} avg=0.26s min=0.235s max=0.282s

## Soak-Lite

- portal-root: {'403': 15} avg=0.041s min=0.022s max=0.086s
- ide-root: {'200': 15} avg=0.291s min=0.242s max=0.351s
- static-css: {'200': 15} avg=0.047s min=0.03s max=0.082s
- oauth-start: {'200': 15} avg=0.267s min=0.225s max=0.311s

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

- status: passed
- exit code: 0
- reason: n/a

## Notes

- This runner collects a repeatable surface baseline and a slightly heavier soak sample.
- It also provides an authenticated smoke path when the required environment is available.
- It includes a Puppeteer parity probe for critical login and root-path checks.
- It includes a profile-driven k6 loadtest for baseline and 100x campaign modes.
- Chaos/fault injection remains a separate follow-up step for the broader resilience campaign.
