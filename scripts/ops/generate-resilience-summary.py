#!/usr/bin/env python3
# @file        scripts/ops/generate-resilience-summary.py
# @module      ops/resilience
# @description Generate JSON and Markdown summaries for resilience campaigns
#

import json
import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="Generate resilience campaign summaries")
    parser.add_argument("--baseline-json", type=Path, required=True)
    parser.add_argument("--soak-json", type=Path, required=True)
    parser.add_argument("--summary-json", type=Path, required=True)
    parser.add_argument("--summary-md", type=Path, required=True)
    parser.add_argument("--auth-status", required=True)
    parser.add_argument("--auth-exit-code", type=int, required=True)
    parser.add_argument("--auth-reason", default="")
    parser.add_argument("--loadtest-status", required=True)
    parser.add_argument("--loadtest-exit-code", type=int, required=True)
    parser.add_argument("--loadtest-reason", default="")
    parser.add_argument("--failover-status", required=True)
    parser.add_argument("--failover-exit-code", type=int, required=True)
    parser.add_argument("--failover-reason", default="")
    parser.add_argument("--puppeteer-status", required=True)
    parser.add_argument("--puppeteer-exit-code", type=int, required=True)
    parser.add_argument("--puppeteer-reason", default="")
    parser.add_argument("--portal-base-url", required=True)
    parser.add_argument("--ide-base-url", required=True)
    parser.add_argument("--scale-profile", required=True)

    args = parser.parse_args()

    with args.baseline_json.open(encoding='utf-8') as handle:
        baseline = json.load(handle)

    with args.soak_json.open(encoding='utf-8') as handle:
        soak = json.load(handle)

    generated_at = datetime.now(timezone.utc).isoformat(timespec='seconds')

    summary = {
        'generated_at': generated_at,
        'portal_base_url': args.portal_base_url,
        'ide_base_url': args.ide_base_url,
        'baseline': baseline,
        'soak_lite': soak,
        'authenticated_smoke': {
            'status': args.auth_status,
            'exit_code': args.auth_exit_code,
            'reason': args.auth_reason,
            'log_file': str(args.summary_json.parent / f"{args.summary_json.stem}-authenticated-smoke.log"),
        },
        'loadtest': {
            'status': args.loadtest_status,
            'exit_code': args.loadtest_exit_code,
            'reason': args.loadtest_reason,
            'log_file': str(args.summary_json.parent / f"{args.summary_json.stem}-k6.log"),
            'summary_file': str(args.summary_json.parent / f"{args.summary_json.stem}-k6.json"),
            'scale_profile': args.scale_profile,
        },
        'failover_continuity': {
            'status': args.failover_status,
            'exit_code': args.failover_exit_code,
            'reason': args.failover_reason,
            'log_file': str(args.summary_json.parent / f"{args.summary_json.stem}-failover-continuity.log"),
        },
        'puppeteer_parity': {
            'status': args.puppeteer_status,
            'exit_code': args.puppeteer_exit_code,
            'reason': args.puppeteer_reason,
            'log_file': str(args.summary_json.parent / f"{args.summary_json.stem}-puppeteer-parity.log"),
        },
        'campaign_status': 'degraded' if any(s == 'failed' for s in [args.auth_status, args.loadtest_status, args.failover_status, args.puppeteer_status]) else 'in-progress',
    }

    args.summary_json.write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')

    lines = [
        '# Resilience Campaign Summary',
        '',
        f'Generated: {generated_at}',
        f'Campaign profile: {args.scale_profile}',
        f'Portal base URL: {args.portal_base_url}',
        f'IDE base URL: {args.ide_base_url}',
        '',
        '## Baseline',
        '',
    ]

    for report in baseline['reports']:
        lines.append(
            f"- {report['name']}: {report['status_counts']} avg={report['average_seconds']}s min={report['min_seconds']}s max={report['max_seconds']}s"
        )

    lines += [
        '',
        '## Soak',
        '',
    ]

    for report in soak['reports']:
        lines.append(
            f"- {report['name']}: {report['status_counts']} avg={report['average_seconds']}s min={report['min_seconds']}s max={report['max_seconds']}s"
        )

    lines += [
        '',
        '## Authenticated Smoke',
        '',
        f'- status: {args.auth_status}',
        f'- exit code: {args.auth_exit_code}',
        f'- reason: {args.auth_reason or "n/a"}',
        '',
        '## Loadtest (k6)',
        '',
        f'- status: {args.loadtest_status}',
        f'- exit code: {args.loadtest_exit_code}',
        f'- reason: {args.loadtest_reason or "n/a"}',
        '',
        '## Failover Continuity',
        '',
        f'- status: {args.failover_status}',
        f'- exit code: {args.failover_exit_code}',
        f'- reason: {args.failover_reason or "n/a"}',
        '',
        '## Puppeteer Parity',
        '',
        f'- status: {args.puppeteer_status}',
        f'- exit code: {args.puppeteer_exit_code}',
        f'- reason: {args.puppeteer_reason or "n/a"}',
        '',
        '## Notes',
        '',
        '- This runner collects a repeatable surface baseline and a slightly heavier soak sample.',
        '- It also provides an authenticated smoke path when the required environment is available.',
        '- It includes a Puppeteer parity probe for critical login and root-path checks.',
        '- It includes a profile-driven k6 loadtest for baseline and 100x campaign modes.',
        '- Chaos/fault injection remains a separate follow-up step for the broader resilience campaign.',
    ]

    args.summary_md.write_text('\n'.join(lines) + '\n', encoding='utf-8')

if __name__ == "__main__":
    main()
