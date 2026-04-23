#!/usr/bin/env bash
# @file        scripts/ops/dast-scan.sh
# @module      ops/security
# @description Run a lightweight DAST check and emit ZAP-compatible JSON for issue routing.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$REPO_ROOT/scripts/_common/init.sh"

TARGET_URL="${TARGET_URL:-${DAST_TARGET_URL:-${PORTAL_BASE_URL:-${IDE_BASE_URL:-}}}}"
OUTPUT_JSON="${OUTPUT_JSON:-artifacts/triage/dast-zap-report.json}"
OUTPUT_MD="${OUTPUT_MD:-artifacts/triage/dast-zap-report.md}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-15}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ops/dast-scan.sh [--target-url <url>] [--output-json <file>] [--output-md <file>] [--timeout <seconds>]

Options:
  --target-url    Target application URL to probe. Defaults to DAST_TARGET_URL, PORTAL_BASE_URL, then IDE_BASE_URL.
  --output-json    ZAP-compatible JSON report path.
  --output-md      Human-readable report path.
  --timeout        Request timeout in seconds.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-url)
      TARGET_URL="${2:-}"
      shift 2
      ;;
    --output-json)
      OUTPUT_JSON="${2:-}"
      shift 2
      ;;
    --output-md)
      OUTPUT_MD="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
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

if [[ -z "$TARGET_URL" ]]; then
  log_warn "No DAST target configured; skipping DAST scan"
  exit 0
fi

# Guard: skip loopback/private targets unreachable from CI runners
# 127.x, 192.168.x, 10.x, ::1 cannot be scanned from GitHub Actions
if echo "$TARGET_URL" | grep -qE '^https?://(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|localhost|\[::1\])'; then
  log_warn "DAST target '$TARGET_URL' is a loopback/private address — not scannable from CI. Set PORTAL_BASE_URL or IDE_BASE_URL to a publicly reachable URL."
  log_warn "Skipping DAST scan to prevent false-positive findings."
  exit 0
fi

require_command python3

mkdir -p "$(dirname "$OUTPUT_JSON")" "$(dirname "$OUTPUT_MD")"

python3 - "$TARGET_URL" "$OUTPUT_JSON" "$OUTPUT_MD" "$TIMEOUT_SECONDS" <<'PY'
import html
import json
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

target_url = sys.argv[1].strip()
output_json = Path(sys.argv[2])
output_md = Path(sys.argv[3])
timeout_seconds = int(sys.argv[4])

sql_probe = "1' OR '1'='1"
xss_probe = "<script>alert('xss')</script>"

alerts = []

def normalize_target(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    if not parsed.scheme:
        raise ValueError(f"Target URL must include a scheme: {url}")
    path = parsed.path or "/"
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, path, parsed.query, parsed.fragment))

def build_url(base_url: str, **query_params: str) -> str:
    parsed = urllib.parse.urlsplit(base_url)
    query = list(urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))
    query.extend((key, value) for key, value in query_params.items())
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urllib.parse.urlencode(query), parsed.fragment))

def fetch(url: str, method: str = "GET"):
    request = urllib.request.Request(url, method=method, headers={"User-Agent": "code-server-dast/1.0"})
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    with urllib.request.urlopen(request, timeout=timeout_seconds, context=context) as response:
        body = response.read().decode("utf-8", errors="replace")
        headers = {key.lower(): value for key, value in response.headers.items()}
        status = int(getattr(response, "status", 200))
        return status, headers, body

def add_alert(plugin_id, alert_name, description, solution, risk_code, risk_desc, confidence, uri, method, param, evidence, severity="P2"):
    alerts.append({
        "pluginid": plugin_id,
        "alert": alert_name,
        "desc": description,
        "solution": solution,
        "riskcode": str(risk_code),
        "riskdesc": risk_desc,
        "confidence": confidence,
        "instances": [
            {
                "uri": uri,
                "line": 0,
                "method": method,
                "param": param,
                "evidence": evidence,
            }
        ],
        "severity": severity,
    })

def looks_like_login_form(body: str) -> bool:
    # Login forms are pre-auth credential submissions; they do not carry the
    # same CSRF marker expectations as authenticated state-changing forms.
    return bool(
        re.search(r'<input[^>]+type=["\']password["\']', body, re.IGNORECASE)
        or re.search(r'\b(?:sign\s*in|log\s*in|login)\b', body, re.IGNORECASE)
        or re.search(r'/auth/login\b', body, re.IGNORECASE)
    )

try:
    target = normalize_target(target_url)
except ValueError as exc:
    add_alert(
        "dast-target-invalid",
        "Invalid DAST target",
        str(exc),
        "Provide a fully qualified https:// or http:// target URL.",
        3,
        "High",
        "High",
        target_url,
        "GET",
        "",
        str(exc),
        severity="P1",
    )
else:
    parsed_target = urllib.parse.urlsplit(target)
    if parsed_target.scheme == "https":
        try:
            fetch(target)
        except Exception as exc:
            add_alert(
                "dast-target-unreachable",
                "DAST target unreachable",
                f"Unable to reach {target}: {exc}",
                "Verify the target URL and network access before rerunning the scan.",
                3,
                "High",
                "High",
                target,
                "GET",
                "",
                str(exc),
                severity="P1",
            )
    else:
        try:
            fetch(target)
        except Exception as exc:
            add_alert(
                "dast-target-unreachable",
                "DAST target unreachable",
                f"Unable to reach {target}: {exc}",
                "Verify the target URL and network access before rerunning the scan.",
                3,
                "High",
                "High",
                target,
                "GET",
                "",
                str(exc),
                severity="P1",
            )

    try:
        root_status, root_headers, root_body = fetch(target)
    except Exception as exc:
        if not alerts:
            add_alert(
                "dast-root-fetch",
                "DAST root fetch failed",
                f"Unable to fetch the root page for {target}: {exc}",
                "Verify the application is reachable before rerunning the scan.",
                3,
                "High",
                "High",
                target,
                "GET",
                "",
                str(exc),
                severity="P1",
            )
    else:
        body_lower = root_body.lower()
        headers_lower = {k.lower(): v for k, v in root_headers.items()}

        sql_url = build_url(target, id=sql_probe)
        try:
            _, _, sql_body = fetch(sql_url)
            sql_body_lower = sql_body.lower()
            if sql_probe.lower() in sql_body_lower or re.search(r"sql syntax|mysql|postgres|sqlite|odbc|ora-\d+|syntax error", sql_body_lower):
                add_alert(
                    "dast-sql-injection",
                    "Potential SQL injection reflection",
                    "The application reflected an SQL probe or emitted a database error pattern.",
                    "Parameterize database queries and validate all input before it reaches SQL execution paths.",
                    3,
                    "High",
                    "Medium",
                    sql_url,
                    "GET",
                    "id",
                    sql_probe,
                    sql_body[:500],
                    severity="P1",
                )
        except Exception as exc:
            add_alert(
                "dast-sql-probe-error",
                "SQL probe failed",
                f"The SQL injection probe could not be executed: {exc}",
                "Verify that the target remains reachable during DAST scanning.",
                2,
                "Medium",
                "Medium",
                sql_url,
                "GET",
                "id",
                str(exc),
            )

        xss_url = build_url(target, search=xss_probe)
        try:
            _, _, xss_body = fetch(xss_url)
            xss_body_lower = xss_body.lower()
            if xss_probe.lower() in xss_body_lower or "<script>alert('xss')</script>" in xss_body_lower:
                add_alert(
                    "dast-xss-reflection",
                    "Potential cross-site scripting reflection",
                    "The application reflected an XSS probe without escaping it.",
                    "Escape user-controlled content in HTML output and validate all templated fields.",
                    3,
                    "High",
                    "Medium",
                    xss_url,
                    "GET",
                    "search",
                    xss_probe,
                    xss_body[:500],
                    severity="P1",
                )
        except Exception as exc:
            add_alert(
                "dast-xss-probe-error",
                "XSS probe failed",
                f"The XSS probe could not be executed: {exc}",
                "Verify that the target remains reachable during DAST scanning.",
                2,
                "Medium",
                "Medium",
                xss_url,
                "GET",
                "search",
                str(exc),
            )

        if re.search(r"<form\b", root_body, re.IGNORECASE):
            if not re.search(r"csrf|xsrf|anti-forgery|authenticity_token", body_lower):
                if not looks_like_login_form(root_body):
                    add_alert(
                        "dast-csrf-token-missing",
                        "Missing CSRF token markers",
                        "A form was detected but no CSRF-style token markers were present in the response.",
                        "Add per-request CSRF tokens or equivalent anti-forgery validation on all state-changing forms.",
                        2,
                        "Medium",
                        "Low",
                        target,
                        "GET",
                        "",
                        "Form present without obvious CSRF token markers.",
                    )

        header_checks = {
            "x-content-type-options": "nosniff",
            "x-frame-options": None,
            "strict-transport-security": None,
        }
        for header_name, expected_value in header_checks.items():
            actual_value = headers_lower.get(header_name)
            if actual_value is None:
                add_alert(
                    f"dast-header-missing-{header_name}",
                    f"Missing security header: {header_name}",
                    f"The response did not include the {header_name} header.",
                    "Configure the reverse proxy or application server to emit the missing security header.",
                    2,
                    "Medium",
                    "High",
                    target,
                    "GET",
                    "",
                    f"Header missing: {header_name}",
                )
            elif expected_value and actual_value.lower() != expected_value:
                add_alert(
                    f"dast-header-invalid-{header_name}",
                    f"Unexpected security header value: {header_name}",
                    f"The {header_name} header was present but did not match the expected value.",
                    "Update the header policy to the canonical expected value.",
                    2,
                    "Medium",
                    "Medium",
                    target,
                    "GET",
                    "",
                    f"{header_name}: {actual_value}",
                )

        if parsed_target.scheme == "https":
            try:
                context = ssl.create_default_context()
                context.minimum_version = ssl.TLSVersion.TLSv1_2
                request = urllib.request.Request(target, method="HEAD", headers={"User-Agent": "code-server-dast/1.0"})
                with urllib.request.urlopen(request, timeout=timeout_seconds, context=context):
                    pass
            except Exception as exc:
                add_alert(
                    "dast-tls-version",
                    "TLS 1.2+ validation failed",
                    f"The target could not be validated with a TLS 1.2+ client context: {exc}",
                    "Enable TLS 1.2 or newer on the target endpoint.",
                    3,
                    "High",
                    "High",
                    target,
                    "HEAD",
                    "",
                    str(exc),
                    severity="P1",
                )

report = {
    "site": [
        {
            "@name": parsed_target.netloc if 'parsed_target' in locals() else target,
            "@host": parsed_target.hostname if 'parsed_target' in locals() else target,
            "alerts": alerts,
        }
    ]
}

output_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

summary_lines = [
    "DAST Security Scan Report",
    "==========================",
    f"Target: {target_url}",
    f"Alerts: {len(alerts)}",
    "",
]

for alert in alerts:
    instance = alert["instances"][0]
    summary_lines.extend([
        f"- {alert['riskdesc']} {alert['alert']}",
        f"  - URI: {instance['uri']}",
        f"  - Evidence: {instance['evidence']}",
    ])

if not alerts:
    summary_lines.append("No actionable DAST findings detected.")

output_md.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

if alerts:
    high_count = sum(1 for alert in alerts if alert.get("riskcode") == "3" or alert.get("severity") == "P1")
    medium_count = sum(1 for alert in alerts if alert.get("riskcode") == "2")
    print(f"DAST findings detected: high={high_count} medium={medium_count}")
    raise SystemExit(1)

print("DAST scan complete: no actionable findings")
PY
