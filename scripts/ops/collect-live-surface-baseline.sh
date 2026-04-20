#!/usr/bin/env bash
# @file        scripts/ops/collect-live-surface-baseline.sh
# @module      ops/monitoring
# @description Collect live surface latency and status evidence for portal, IDE, and auth paths.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

APEX_DOMAIN="${APEX_DOMAIN:-${DOMAIN#ide.}}"
PORTAL_DOMAIN="${PORTAL_DOMAIN:-${APEX_DOMAIN}}"
IDE_DOMAIN="${IDE_DOMAIN:-ide.${APEX_DOMAIN}}"
PORTAL_BASE_URL="${PORTAL_BASE_URL:-https://${PORTAL_DOMAIN}}"
IDE_BASE_URL="${IDE_BASE_URL:-https://${IDE_DOMAIN}}"
STATIC_ASSET_PATH="${STATIC_ASSET_PATH:-/static/css/main.c5955fd3.css}"
OAUTH_START_PATH="${OAUTH_START_PATH:-/oauth2/start?rd=%2F}"
REQUEST_COUNT="${REQUEST_COUNT:-5}"
THROTTLE_LIMIT="${THROTTLE_LIMIT:-5}"
OUTPUT_DIR="${OUTPUT_DIR:-artifacts/triage}"
REPORT_BASENAME="${REPORT_BASENAME:-live-surface-baseline}"

require_command python3

mkdir -p "$OUTPUT_DIR"

python3 - "$PORTAL_BASE_URL" "$IDE_BASE_URL" "$STATIC_ASSET_PATH" "$OAUTH_START_PATH" "$REQUEST_COUNT" "$THROTTLE_LIMIT" "$OUTPUT_DIR" "$REPORT_BASENAME" <<'PY'
import concurrent.futures as futures
import json
import ssl
import statistics
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

portal_base_url, ide_base_url, static_asset_path, oauth_start_path, request_count, throttle_limit, output_dir, report_basename = sys.argv[1:9]
request_count = int(request_count)
throttle_limit = int(throttle_limit)
output_dir = Path(output_dir)
generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")

context = ssl._create_unverified_context()

targets = [
    {"name": "portal-root", "url": f"{portal_base_url}/"},
    {"name": "ide-root", "url": f"{ide_base_url}/"},
    {"name": "static-css", "url": f"{portal_base_url}{static_asset_path}"},
    {"name": "oauth-start", "url": f"{ide_base_url}{oauth_start_path}"},
]


def probe(url: str) -> dict:
    started = time.perf_counter()
    status = None
    content_type = None
    error = None
    try:
        request = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(request, timeout=20, context=context) as response:
            status = response.getcode()
            content_type = response.headers.get("Content-Type")
    except urllib.error.HTTPError as exc:
        status = exc.code
        content_type = exc.headers.get("Content-Type") if exc.headers else None
        error = str(exc)
    except Exception as exc:  # pragma: no cover - network/runtime dependent
        error = str(exc)
    finished = time.perf_counter()
    return {
        "status": status,
        "content_type": content_type,
        "seconds": round(finished - started, 3),
        "error": error,
    }


def run_target(target: dict) -> dict:
    with futures.ThreadPoolExecutor(max_workers=throttle_limit) as executor:
        attempts = list(executor.map(lambda _: probe(target["url"]), range(request_count)))

    statuses = Counter(str(item["status"]) if item["status"] is not None else "error" for item in attempts)
    seconds = [item["seconds"] for item in attempts]
    errors = [item["error"] for item in attempts if item["error"]]

    return {
        "name": target["name"],
        "url": target["url"],
        "request_count": request_count,
        "status_counts": dict(sorted(statuses.items())),
        "average_seconds": round(statistics.fmean(seconds), 3) if seconds else None,
        "min_seconds": round(min(seconds), 3) if seconds else None,
        "max_seconds": round(max(seconds), 3) if seconds else None,
        "results": attempts,
        "errors": errors,
    }


reports = [run_target(target) for target in targets]
summary = {
    "total_requests": sum(item["request_count"] for item in reports),
    "success_statuses": {report["name"]: report["status_counts"] for report in reports},
}

json_report = {
    "generated_at": generated_at,
    "portal_base_url": portal_base_url,
    "ide_base_url": ide_base_url,
    "static_asset_path": static_asset_path,
    "oauth_start_path": oauth_start_path,
    "request_count": request_count,
    "throttle_limit": throttle_limit,
    "summary": summary,
    "reports": reports,
}

report_json = output_dir / f"{report_basename}.json"
report_md = output_dir / f"{report_basename}.md"
report_json.write_text(json.dumps(json_report, indent=2) + "\n", encoding="utf-8")

lines = [
    "# Live Surface Baseline",
    "",
    f"Generated: {generated_at}",
    f"Portal base URL: {portal_base_url}",
    f"IDE base URL: {ide_base_url}",
    f"Requests per target: {request_count}",
    f"Parallelism: {throttle_limit}",
    "",
    "## Results",
    "",
    "| Target | URL | Status counts | Avg (s) | Min (s) | Max (s) |",
    "|---|---|---|---:|---:|---:|",
]

for report in reports:
    lines.append(
        f"| {report['name']} | {report['url']} | {', '.join(f'{k}={v}' for k, v in report['status_counts'].items())} | {report['average_seconds']} | {report['min_seconds']} | {report['max_seconds']} |"
    )

lines += [
    "",
    "## Notes",
    "",
    "- This report captures the current live surface, but it is a baseline only.",
    "- It does not replace authenticated soak, chaos, or higher-concurrency campaigns.",
]

report_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

for report in reports:
    print(f"{report['name']}: {report['status_counts']} avg={report['average_seconds']}s min={report['min_seconds']}s max={report['max_seconds']}s")

print(f"JSON report: {report_json}")
print(f"Markdown report: {report_md}")
PY

log_info "Live surface baseline collected in $OUTPUT_DIR"