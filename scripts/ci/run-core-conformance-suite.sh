#!/usr/bin/env bash
# @file        scripts/ci/run-core-conformance-suite.sh
# @module      ci/conformance
# @description Run core domain-managed conformance suites and emit consolidated JSON/markdown reports
#

set -euo pipefail

REPORT_DIR="${REPORT_DIR:-.github/reports/conformance}"
AUTH_REPORT="${AUTH_REPORT:-$REPORT_DIR/auth-conformance-report.json}"
VITEST_REPORT="${VITEST_REPORT:-$REPORT_DIR/core-conformance-vitest.json}"
SUMMARY_REPORT="${SUMMARY_REPORT:-$REPORT_DIR/core-conformance-summary.json}"
MARKDOWN_REPORT="${MARKDOWN_REPORT:-$REPORT_DIR/core-conformance-summary.md}"

mkdir -p "$REPORT_DIR"

auth_exit=0
vitest_exit=0

echo "[core-conformance] running auth/policy conformance"
set +e
bash scripts/ci/test-auth-conformance.sh --report "$AUTH_REPORT"
auth_exit=$?
set -e

echo "[core-conformance] running unit conformance matrix"
set +e
npx vitest run \
  tests/unit/policy-bundle-verifier/conformance.spec.ts \
  tests/unit/session-bootstrap-enforcer/bootstrap.spec.ts \
  tests/unit/revocation-broker/enforcement.spec.ts \
  tests/unit/shared-workspace-acl/conformance.spec.ts \
  tests/unit/ephemeral-workspace-lifecycle/conformance.spec.ts \
  --reporter=json \
  --outputFile="$VITEST_REPORT"
vitest_exit=$?
set -e

python3 - <<'PY' "$AUTH_REPORT" "$VITEST_REPORT" "$SUMMARY_REPORT" "$MARKDOWN_REPORT" "$auth_exit" "$vitest_exit"
import json
import os
import sys
from datetime import datetime, timezone

auth_path, vitest_path, summary_path, md_path, auth_exit_raw, vitest_exit_raw = sys.argv[1:]
auth_exit = int(auth_exit_raw or 0)
vitest_exit = int(vitest_exit_raw or 0)

def read_json(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

auth = read_json(auth_path) or {}
vitest = read_json(vitest_path) or {}

auth_total = int(auth.get("total", 0) or 0)
auth_passed = int(auth.get("passed", 0) or 0)
auth_failed = int(auth.get("failed", max(0, auth_total - auth_passed)) or 0)

test_files = vitest.get("testResults") or vitest.get("files") or []
vitest_total = 0
vitest_passed = 0
vitest_failed = 0

for f in test_files:
    assertion_results = f.get("assertionResults") or f.get("tests") or []
    for t in assertion_results:
        vitest_total += 1
        status = t.get("status")
        if status == "passed":
            vitest_passed += 1
        elif status == "failed":
            vitest_failed += 1

if vitest_total == 0:
    vitest_total = int(vitest.get("numTotalTests", 0) or 0)
    vitest_passed = int(vitest.get("numPassedTests", 0) or 0)
    vitest_failed = int(vitest.get("numFailedTests", max(0, vitest_total - vitest_passed)) or 0)

summary = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "suites": [
        {
            "name": "auth-policy-conformance",
            "report": auth_path,
            "exit_code": auth_exit,
            "total": auth_total,
            "passed": auth_passed,
            "failed": auth_failed,
            "status": "pass" if auth_exit == 0 else "fail",
        },
        {
            "name": "core-unit-conformance",
            "report": vitest_path,
            "exit_code": vitest_exit,
            "total": vitest_total,
            "passed": vitest_passed,
            "failed": vitest_failed,
            "status": "pass" if vitest_exit == 0 else "fail",
        },
    ],
}

summary["total"] = sum(s["total"] for s in summary["suites"])
summary["passed"] = sum(s["passed"] for s in summary["suites"])
summary["failed"] = sum(s["failed"] for s in summary["suites"])
summary["overall_status"] = "pass" if auth_exit == 0 and vitest_exit == 0 else "fail"

with open(summary_path, "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2)

md_lines = [
    "# Core Conformance Summary",
    "",
    f"Generated: {summary['generated_at']}",
    "",
    "| Suite | Status | Passed | Failed | Total | Exit |",
    "|---|---|---:|---:|---:|---:|",
]

for s in summary["suites"]:
    md_lines.append(f"| {s['name']} | {s['status']} | {s['passed']} | {s['failed']} | {s['total']} | {s['exit_code']} |")

md_lines += [
    "",
    f"Overall: **{summary['overall_status'].upper()}**",
    f"Totals: passed={summary['passed']}, failed={summary['failed']}, total={summary['total']}",
    "",
    f"Reports: {auth_path}, {vitest_path}, {summary_path}",
]

with open(md_path, "w", encoding="utf-8") as f:
    f.write("\n".join(md_lines) + "\n")
PY

cat "$MARKDOWN_REPORT"

if [[ "$auth_exit" -ne 0 || "$vitest_exit" -ne 0 ]]; then
  echo "[core-conformance] failed"
  exit 1
fi

echo "[core-conformance] passed"
