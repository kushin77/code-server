#!/usr/bin/env bash
# @file        scripts/ops/test-failure-triage.sh
# @module      ops/incident
# @description Route failed unit/integration/E2E test results into deduplicated GitHub issues.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

TOOL_NAME="test-failure"
SUITE_NAME="unknown-suite"
WORKFLOW_NAME="unknown-workflow"
RUN_URL=""
GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
PLAYWRIGHT_JSON=""
FLAKE_JSON=""
EXIT_CODE="1"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ops/test-failure-triage.sh [options]

Options:
  --tool <name>             Logical test tool name (vitest|playwright|integration|etc.)
  --suite <name>            Suite identifier used for dedupe grouping.
  --workflow <name>         Workflow/job name for reporting context.
  --run-url <url>           CI run URL for drill-down.
  --repo <owner/repo>       GitHub repository target.
  --playwright-json <file>  Playwright JSON report path.
  --flake-json <file>       Deterministic flake report JSON path.
  --exit-code <int>         Exit code from the failed command (default: 1).
  --dry-run                 Print routed issue payload without creating/updating issues.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      TOOL_NAME="${2:-}"
      shift 2
      ;;
    --suite)
      SUITE_NAME="${2:-}"
      shift 2
      ;;
    --workflow)
      WORKFLOW_NAME="${2:-}"
      shift 2
      ;;
    --run-url)
      RUN_URL="${2:-}"
      shift 2
      ;;
    --repo)
      GH_REPO="${2:-}"
      shift 2
      ;;
    --playwright-json)
      PLAYWRIGHT_JSON="${2:-}"
      shift 2
      ;;
    --flake-json)
      FLAKE_JSON="${2:-}"
      shift 2
      ;;
    --exit-code)
      EXIT_CODE="${2:-1}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_fatal "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$GH_REPO" ]]; then
  log_fatal "--repo (or GH_REPO/GITHUB_REPOSITORY) is required"
fi

if [[ "$DRY_RUN" != "true" ]]; then
  require_command gh
  if [[ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    log_fatal "GH_TOKEN or GITHUB_TOKEN is required for issue routing"
  fi
fi

if [[ -n "$PLAYWRIGHT_JSON" && ! -f "$PLAYWRIGHT_JSON" ]]; then
  log_fatal "Playwright JSON report not found: $PLAYWRIGHT_JSON"
fi

if [[ -n "$FLAKE_JSON" && ! -f "$FLAKE_JSON" ]]; then
  log_fatal "Flake JSON report not found: $FLAKE_JSON"
fi

require_command python3

parse_output=$(python3 - "$TOOL_NAME" "$SUITE_NAME" "$WORKFLOW_NAME" "$RUN_URL" "$PLAYWRIGHT_JSON" "$FLAKE_JSON" "$EXIT_CODE" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

tool = sys.argv[1]
suite = sys.argv[2]
workflow = sys.argv[3]
run_url = sys.argv[4]
playwright_path = sys.argv[5]
flake_path = sys.argv[6]
exit_code = int(sys.argv[7])

severity = "P2"
if any(token in suite.lower() for token in ["auth", "login", "failover", "continuity"]):
    severity = "P1"

details = {
    "tool": tool,
    "suite": suite,
    "workflow": workflow,
    "exitCode": exit_code,
    "runUrl": run_url,
    "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
}

summary = f"{tool} suite '{suite}' failed"
failure_signature = ""
playwright_block = ""
flake_block = ""

if flake_path:
    data = json.loads(Path(flake_path).read_text(encoding="utf-8"))
    details["flake"] = {
        "finalStatus": data.get("finalStatus"),
        "finalClassification": data.get("finalClassification"),
        "finalExitCode": data.get("finalExitCode"),
    }
    attempts = data.get("attempts") or []
    if attempts:
        last = attempts[-1]
        failure_signature = str(last.get("classification") or data.get("finalClassification") or "unknown")
    if data.get("finalClassification") == "critical":
        severity = "P1"
    flake_block = json.dumps(data, indent=2)[:3500]

if playwright_path:
    report = json.loads(Path(playwright_path).read_text(encoding="utf-8"))
    stats = report.get("stats") or {}
    details["playwrightStats"] = {
        "expected": stats.get("expected"),
        "unexpected": stats.get("unexpected"),
        "flaky": stats.get("flaky"),
        "skipped": stats.get("skipped"),
    }
    unexpected = int(stats.get("unexpected") or 0)
    if unexpected > 0 and severity != "P1":
        severity = "P2"
    errors = report.get("errors") or []
    if errors:
        failure_signature = failure_signature or str(errors[0].get("message") or "playwright-error")[:120]
    suites = report.get("suites") or []
    failed_titles = []
    for suite_node in suites:
        for spec in suite_node.get("specs") or []:
            for test in spec.get("tests") or []:
                outcomes = {r.get("status") for r in (test.get("results") or [])}
                if "failed" in outcomes:
                    failed_titles.append(spec.get("title") or test.get("title") or "unknown-test")
    if failed_titles:
        details["failedTests"] = failed_titles[:20]
        failure_signature = failure_signature or failed_titles[0]
    playwright_block = json.dumps({
        "stats": details.get("playwrightStats"),
        "failedTests": details.get("failedTests", []),
        "errors": errors[:5],
    }, indent=2)[:3500]

if not failure_signature:
    failure_signature = f"exit-{exit_code}"

fingerprint_source = f"{tool}|{suite}|{workflow}|{failure_signature}"
fingerprint = hashlib.sha256(fingerprint_source.encode("utf-8")).hexdigest()[:12]
title = f"[{fingerprint}] {severity}: {tool} failure in {suite}"

issue_body_lines = [
    f"## Test Failure Routing",
    "",
    f"- Tool: `{tool}`",
    f"- Suite: `{suite}`",
    f"- Workflow: `{workflow}`",
    f"- Exit code: `{exit_code}`",
    f"- Severity: `{severity}`",
]

if run_url:
    issue_body_lines.append(f"- Run URL: {run_url}")

issue_body_lines += [
    "",
    "### Summary",
    summary,
    "",
]

if flake_block:
    issue_body_lines += [
        "### Deterministic Flake Report (trimmed)",
        "```json",
        flake_block,
        "```",
        "",
    ]

if playwright_block:
    issue_body_lines += [
        "### Playwright Report Summary (trimmed)",
        "```json",
        playwright_block,
        "```",
        "",
    ]

issue_body_lines += [
    "### Triage Checklist",
    "- [ ] Confirm reproducibility and classify deterministic vs flaky",
    "- [ ] Link failing test/spec and remediation PR",
    "- [ ] Add suppression only with explicit expiry if signal is noisy",
    "",
    f"<!-- test-failure-fingerprint:{fingerprint} -->",
]

payload = {
    "severity": severity,
    "fingerprint": fingerprint,
    "title": title,
    "summary": summary,
    "body": "\n".join(issue_body_lines),
}

print(json.dumps(payload))
PY
)

severity=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["severity"])' <<<"$parse_output")
fingerprint=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["fingerprint"])' <<<"$parse_output")
title=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["title"])' <<<"$parse_output")
body=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["body"])' <<<"$parse_output")
summary=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["summary"])' <<<"$parse_output")

existing_issue=""
if [[ "$DRY_RUN" != "true" ]]; then
  existing_issue=$(gh issue list --repo "$GH_REPO" --state open --limit 200 --json number,title,body \
    --jq ".[] | select((.title | contains(\"[$fingerprint]\")) or (.body | contains(\"test-failure-fingerprint:$fingerprint\"))) | .number" | head -n 1)
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY RUN] Severity: $severity"
  log_info "[DRY RUN] Fingerprint: $fingerprint"
  log_info "[DRY RUN] Title: $title"
  log_info "[DRY RUN] Summary: $summary"
  exit 0
fi

if [[ -n "$existing_issue" ]]; then
  gh issue comment "$existing_issue" --repo "$GH_REPO" --body "Re-occurrence detected for fingerprint \\`$fingerprint\\`.

- Summary: $summary
- Run URL: ${RUN_URL:-n/a}
- Exit code: $EXIT_CODE
- Updated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  log_info "Updated existing test-failure issue #$existing_issue"
else
  gh issue create --repo "$GH_REPO" --title "$title" --body "$body" --label "$severity" >/dev/null
  log_info "Created test-failure issue for fingerprint $fingerprint"
fi
