#!/usr/bin/env bash
# @file        scripts/ops/security-scan-triage.sh
# @module      ops/security
# @description Route security scan findings from SARIF and npm audit outputs into GitHub Issues.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

GH_REPO="${GH_REPO:-kushin77/code-server}"
DRY_RUN="false"
TOOL_NAME="security-scan"
SARIF_FILE=""
NPM_AUDIT_FILE=""
AUDIT_JSONL_FILE=""
SECRET_JSONL_FILE=""
ZAP_JSON_FILE=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ops/security-scan-triage.sh --tool <name> --sarif <file> [--repo owner/repo]
  bash scripts/ops/security-scan-triage.sh --tool npm-audit --npm-audit <file> [--repo owner/repo]
  bash scripts/ops/security-scan-triage.sh --tool audit-log --audit-jsonl <file> [--repo owner/repo]
  bash scripts/ops/security-scan-triage.sh --tool zap --zap-json <file> [--repo owner/repo]

Options:
  --tool        Logical scan name used in issue titles and labels.
  --sarif       SARIF file to triage (Semgrep, Trivy, etc.).
  --npm-audit   npm audit JSON file to triage.
  --audit-jsonl  Structured audit JSONL file to triage.
  --secret-jsonl  TruffleHog JSONL file to triage.
  --zap-json     OWASP ZAP JSON report to triage.
  --repo        GitHub repository in owner/repo form.
  --dry-run     Print intended actions without creating issues.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      TOOL_NAME="${2:-}"
      shift 2
      ;;
    --sarif)
      SARIF_FILE="${2:-}"
      shift 2
      ;;
    --npm-audit)
      NPM_AUDIT_FILE="${2:-}"
      shift 2
      ;;
    --audit-jsonl)
      AUDIT_JSONL_FILE="${2:-}"
      shift 2
      ;;
    --secret-jsonl)
      SECRET_JSONL_FILE="${2:-}"
      shift 2
      ;;
    --zap-json)
      ZAP_JSON_FILE="${2:-}"
      shift 2
      ;;
    --repo)
      GH_REPO="${2:-}"
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

if [[ -z "${SARIF_FILE}" && -z "${NPM_AUDIT_FILE}" && -z "${AUDIT_JSONL_FILE}" && -z "${SECRET_JSONL_FILE}" && -z "${ZAP_JSON_FILE}" ]]; then
  log_fatal "Provide --sarif, --npm-audit, --audit-jsonl, --secret-jsonl, or --zap-json"
fi

if [[ -n "${SARIF_FILE}" && ! -f "${SARIF_FILE}" ]]; then
  log_fatal "SARIF file not found: ${SARIF_FILE}"
fi

if [[ -n "${NPM_AUDIT_FILE}" && ! -f "${NPM_AUDIT_FILE}" ]]; then
  log_fatal "npm audit file not found: ${NPM_AUDIT_FILE}"
fi

if [[ -n "${AUDIT_JSONL_FILE}" && ! -f "${AUDIT_JSONL_FILE}" ]]; then
  log_fatal "audit JSONL file not found: ${AUDIT_JSONL_FILE}"
fi

if [[ -n "${SECRET_JSONL_FILE}" && ! -f "${SECRET_JSONL_FILE}" ]]; then
  log_fatal "secret JSONL file not found: ${SECRET_JSONL_FILE}"
fi

if [[ -n "${ZAP_JSON_FILE}" && ! -f "${ZAP_JSON_FILE}" ]]; then
  log_fatal "ZAP JSON file not found: ${ZAP_JSON_FILE}"
fi

if [[ "${DRY_RUN}" != "true" ]] && ! command -v gh >/dev/null 2>&1; then
  log_fatal "gh CLI is required for issue routing"
fi

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  log_fatal "Either jq or python3 is required for scan parsing"
fi

if [[ "${DRY_RUN}" != "true" && -z "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
  log_fatal "GitHub token is required for issue routing"
fi

normalize_text() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[0-9a-f]{8,}/<hex>/g; s/[0-9]{2,}/<num>/g; s/[[:space:]]+/ /g; s/^ //; s/ $//'
}

issue_fingerprint() {
  printf '%s' "$1" | sha256sum | awk '{print substr($1, 1, 12)}'
}

extract_sarif_findings() {
  local sarif_file="$1"
  local scan_name="$2"

  if command -v jq >/dev/null 2>&1; then
    jq -r --arg scan "$scan_name" '
      .runs[]?.results[]? |
      select((.level // "warning") != "note" and (.level // "warning") != "none") |
      [
        $scan,
        (.ruleId // "unknown-rule"),
        (.level // "warning"),
        ((.message.text // .message // "Security finding") | gsub("\n"; " ")),
        (.locations[0].physicalLocation.artifactLocation.uri // "unknown"),
        ((.locations[0].physicalLocation.region.startLine // 0) | tostring)
      ] | @tsv
    ' "${sarif_file}"
    return 0
  fi

  python3 - "$sarif_file" "$scan_name" <<'PY'
import json
import sys

sarif_path = sys.argv[1]
scan_name = sys.argv[2]
with open(sarif_path, encoding='utf-8') as handle:
    data = json.load(handle)

for run in data.get('runs', []):
    for result in run.get('results', []) or []:
        level = (result.get('level') or 'warning')
        if level in {'note', 'none'}:
            continue
        rule_id = result.get('ruleId') or 'unknown-rule'
        message = result.get('message')
        if isinstance(message, dict):
            message = message.get('text') or str(message)
        else:
            message = str(message)
        locations = result.get('locations') or [{}]
        physical = (locations[0].get('physicalLocation') or {}) if locations else {}
        artifact = physical.get('artifactLocation') or {}
        region = physical.get('region') or {}
        uri = artifact.get('uri') or 'unknown'
        line = str(region.get('startLine') or 0)
        print("\t".join([scan_name, rule_id, level, message.replace('\n', ' '), uri, line]))
PY
}

extract_npm_audit_findings() {
  local audit_file="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -r '
      .vulnerabilities // {} |
      to_entries[] |
      select(.value.severity == "high" or .value.severity == "critical") |
      .value as $v |
      [
        (.key // $v.name // "unknown-package"),
        ($v.severity // "high"),
        ($v.range // "unknown range"),
        (($v.via | map(if type == "object" then (.title // (.source | tostring) // "advisory") else . end) | join("; ")) // "advisory"),
        (($v.fixAvailable | tostring) // "false")
      ] | @tsv
    ' "${audit_file}"
    return 0
  fi

  python3 - "$audit_file" <<'PY'
import json
import sys

audit_path = sys.argv[1]
with open(audit_path, encoding='utf-8') as handle:
    data = json.load(handle)

for package_name, payload in (data.get('vulnerabilities') or {}).items():
    severity = payload.get('severity') or 'high'
    if severity not in {'high', 'critical'}:
        continue
    range_value = payload.get('range') or 'unknown range'
    via_items = payload.get('via') or []
    advisories = []
    for item in via_items:
        if isinstance(item, dict):
            advisories.append(str(item.get('title') or item.get('source') or 'advisory'))
        else:
            advisories.append(str(item))
    if not advisories:
        advisories = ['advisory']
    fix_available = str(payload.get('fixAvailable') or 'false')
    print("\t".join([package_name, severity, range_value, '; '.join(advisories), fix_available]))
PY
}

extract_audit_findings() {
  local audit_file="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -r '
      select(
        .event_type == "SHELL_VIOLATION" or
        .event_type == "FILE_WRITE_ATTEMPT" or
        .event_type == "FILE_DELETE_ATTEMPT" or
        .event_type == "FILE_DOWNLOAD_ATTEMPT" or
        .event_type == "policy.denied" or
        .event_type == "SECURITY_POLICY_VIOLATION" or
        .status == "blocked" or
        .status == "denied"
      ) |
      [
        (.event_type // "audit-event"),
        (.component // "audit"),
        (.status // "unknown"),
        ((.timestamp // "unknown") + " | " + (.details | tostring)),
        (.developer_id // "unknown"),
        (.ip_address // "unknown")
      ] | @tsv
    ' "${audit_file}"
    return 0
  fi

  python3 - "$audit_file" <<'PY'
import json
import sys

audit_path = sys.argv[1]
target_events = {
    'SHELL_VIOLATION',
    'FILE_WRITE_ATTEMPT',
    'FILE_DELETE_ATTEMPT',
    'FILE_DOWNLOAD_ATTEMPT',
    'policy.denied',
    'SECURITY_POLICY_VIOLATION',
}

with open(audit_path, encoding='utf-8') as handle:
    for raw_line in handle:
        line = raw_line.strip()
        if not line:
            continue
        event = json.loads(line)
        event_type = event.get('event_type') or ''
        status = event.get('status') or ''
        if event_type not in target_events and status not in {'blocked', 'denied'}:
            continue
        timestamp = event.get('timestamp') or 'unknown'
        component = event.get('component') or 'audit'
        developer_id = event.get('developer_id') or 'unknown'
        ip_address = event.get('ip_address') or 'unknown'
        details = event.get('details')
        print("\t".join([
            event_type or 'audit-event',
            component,
            status or 'unknown',
            f"{timestamp} | {details}",
            developer_id,
            ip_address,
        ]))
PY
}

extract_trufflehog_findings() {
  local secret_file="$1"

  python3 - "$secret_file" <<'PY'
import json
import sys

secret_path = sys.argv[1]

def iter_objects(path):
  with open(path, encoding='utf-8') as handle:
    raw = handle.read().strip()

  if not raw:
    return

  if raw.startswith('['):
    try:
      payload = json.loads(raw)
    except Exception:
      payload = None
    if isinstance(payload, list):
      for item in payload:
        if isinstance(item, dict):
          yield item
      return
    if isinstance(payload, dict):
      for item in payload.get('results', []) or []:
        if isinstance(item, dict):
          yield item
      return

  for raw_line in raw.splitlines():
    line = raw_line.strip()
    if not line:
      continue
    try:
      payload = json.loads(line)
    except Exception:
      continue
    if isinstance(payload, dict):
      yield payload


def first_value(value, keys):
  if isinstance(value, dict):
    for key in keys:
      candidate = value.get(key)
      if candidate not in (None, '', [], {}):
        return candidate
    for nested in value.values():
      candidate = first_value(nested, keys)
      if candidate not in (None, '', [], {}):
        return candidate
  elif isinstance(value, list):
    for item in value:
      candidate = first_value(item, keys)
      if candidate not in (None, '', [], {}):
        return candidate
  return None


def to_text(value):
  if value is None:
    return ''
  if isinstance(value, (str, int, float, bool)):
    return str(value)
  try:
    return json.dumps(value, separators=(',', ':'), sort_keys=True)
  except Exception:
    return str(value)


for finding in iter_objects(secret_path):
  verified = finding.get('Verified')
  if verified is None:
    verified = finding.get('verified')
  verified_bool = str(verified).lower() == 'true'
  if not verified_bool:
    continue

  detector = to_text(finding.get('DetectorName') or finding.get('detector_name') or finding.get('detector') or 'trufflehog')
  source_metadata = finding.get('SourceMetadata') or finding.get('source_metadata') or {}
  location = first_value(source_metadata, ['Path', 'path', 'uri', 'file', 'filename', 'name'])
  if location is None:
    location = first_value(finding, ['Path', 'path', 'uri', 'file', 'filename', 'name'])
  line_value = first_value(source_metadata, ['Line', 'line', 'startLine'])
  if line_value is None:
    line_value = first_value(finding, ['Line', 'line', 'startLine'])
  if line_value is None:
    line_value = 0

  summary = finding.get('Reason') or finding.get('reason') or finding.get('Description') or finding.get('description')
  if not summary:
    summary = f'verified secret detected by {detector}' if verified else f'secret candidate detected by {detector}'

  redacted = finding.get('Redacted') or finding.get('redacted') or detector

  print("\t".join([
    detector,
    'P0',
    summary.replace('\n', ' '),
    to_text(location) or 'unknown',
    to_text(line_value),
    to_text(redacted),
  ]))
PY
}

find_existing_issue() {
  local marker="$1"
  if [[ "${DRY_RUN}" == "true" && -z "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
    echo ""
    return 0
  fi

  gh issue list --repo "${GH_REPO}" --state open --limit 200 --json number,body \
    | jq -r --arg marker "$marker" '.[] | select(.body | contains($marker)) | .number' \
    | head -1
}

route_issue() {
  local scan_name="$1"
  local severity="$2"
  local title_detail="$3"
  local body_detail="$4"
  local labels="$5"
  local evidence_file="$6"
  local fingerprint_source="$7"

  local fingerprint marker title body existing_issue
  fingerprint="$(issue_fingerprint "$(normalize_text "${fingerprint_source}")")"
  marker="<!-- security-scan-fingerprint:${fingerprint} -->"
  title="[SECURITY][${scan_name}] ${title_detail}"
  body=$(cat <<EOF
${marker}
## Security Scan Finding

**Scan**: ${scan_name}
**Severity**: ${severity}
**Fingerprint**: ${fingerprint}
**Evidence**: ${evidence_file}

### Finding
${body_detail}

### Triage
- [ ] Confirm whether this is a true positive
- [ ] Fix the issue or document a time-bounded suppression
- [ ] Link the remediation PR or suppression PR back here

### Evidence
\`\`\`
${fingerprint_source}
\`\`\`
EOF
)

  existing_issue="$(find_existing_issue "${marker}")"

  if [[ "${DRY_RUN}" == "true" ]]; then
    local preview_body
    preview_body=$(cat <<EOF
${marker}

Additional scan evidence:

${body_detail}
EOF
)
    if [[ -n "${existing_issue}" ]]; then
      log_info "[DRY-RUN] Would comment on issue #${existing_issue} for ${scan_name}: ${title_detail}"
    else
      log_info "[DRY-RUN] Would create issue for ${scan_name}: ${title_detail}"
    fi
    printf '%s\n' "${preview_body}" >/dev/null
    return 0
  fi

  if [[ -n "${existing_issue}" ]]; then
    gh issue comment "${existing_issue}" --repo "${GH_REPO}" --body "$(cat <<EOF
${marker}

Additional scan evidence:

${body_detail}
EOF
)" >/dev/null
    log_info "Updated existing security issue #${existing_issue} for ${scan_name}: ${title_detail}"
  else
    gh issue create --repo "${GH_REPO}" --title "${title}" --body "${body}" --label "${labels}" >/dev/null
    log_info "Created security issue for ${scan_name}: ${title_detail}"
  fi
}

triage_sarif() {
  local sarif_file="$1"
  local scan_name="$2"

  mapfile -t findings < <(extract_sarif_findings "${sarif_file}" "${scan_name}")

  if [[ ${#findings[@]} -eq 0 ]]; then
    log_info "No actionable SARIF findings in ${sarif_file}"
    return 0
  fi

  for finding in "${findings[@]}"; do
    IFS=$'\t' read -r scan_name rule_id level message uri line <<< "${finding}"
    severity="P2"
    if [[ "${level}" == "error" || "${level}" == "high" || "${level}" == "critical" ]]; then
      severity="P1"
    fi

    local detail_body
    detail_body=$(cat <<EOF
  Rule: ${rule_id}
  Location: ${uri}:${line}
  Level: ${level}
Message: ${message}
EOF
)

    route_issue \
      "${scan_name}" \
      "${severity}" \
      "${rule_id} in ${uri}:${line}" \
      "${detail_body}" \
      "security-scan,${scan_name},${severity}" \
      "${sarif_file}" \
      "${scan_name}|${rule_id}|${uri}|${line}|${message}"
  done
}

triage_npm_audit() {
  local audit_file="$1"

  mapfile -t findings < <(extract_npm_audit_findings "${audit_file}")

  if [[ ${#findings[@]} -eq 0 ]]; then
    log_info "No high/critical npm audit findings in ${audit_file}"
    return 0
  fi

  for finding in "${findings[@]}"; do
    IFS=$'\t' read -r package_name severity range advisories fix_available <<< "${finding}"

    local detail_body
    detail_body=$(cat <<EOF
  Package: ${package_name}
  Range: ${range}
Advisories: ${advisories}
  Fix available: ${fix_available}
EOF
)

    route_issue \
      "npm-audit" \
      "${severity^^}" \
      "${package_name} vulnerability" \
      "${detail_body}" \
      "security-scan,npm-audit,${severity}" \
      "${audit_file}" \
      "npm-audit|${package_name}|${range}|${advisories}"
  done
}

triage_trufflehog() {
  local secret_file="$1"

  mapfile -t findings < <(extract_trufflehog_findings "${secret_file}")

  if [[ ${#findings[@]} -eq 0 ]]; then
    log_info "No verified TruffleHog findings in ${secret_file}"
    return 0
  fi

  for finding in "${findings[@]}"; do
    IFS=$'\t' read -r detector severity summary uri line redacted <<< "${finding}"

    route_issue \
      "trufflehog" \
      "${severity}" \
      "${detector} secret in ${uri}:${line}" \
      "Detector: ${detector}
Location: ${uri}:${line}
Severity: ${severity}
Summary: ${summary}
Verified secret evidence: ${redacted}" \
      "security-scan,trufflehog,${severity}" \
      "${secret_file}" \
      "trufflehog|${detector}|${uri}|${line}|${severity}"
  done
}

extract_zap_findings() {
  local zap_file="$1"

  python3 - "$zap_file" <<'PY'
import json
import sys

zap_path = sys.argv[1]
with open(zap_path, encoding='utf-8') as handle:
    data = json.load(handle)

sites = data.get('site') or []
if isinstance(sites, dict):
    sites = [sites]

for site in sites:
    site_name = site.get('@name') or site.get('name') or site.get('@host') or 'unknown-site'
    alerts = site.get('alerts') or []
    for alert in alerts:
        risk_code = str(alert.get('riskcode') or alert.get('risk_code') or '')
        risk_desc = str(alert.get('riskdesc') or alert.get('risk_desc') or '')
        if risk_code not in {'2', '3'} and risk_desc.lower() not in {'medium', 'high'}:
            continue

        plugin_id = str(alert.get('pluginid') or alert.get('plugin_id') or 'unknown-plugin')
        alert_name = str(alert.get('alert') or alert.get('name') or 'DAST finding')
        description = str(alert.get('desc') or alert.get('description') or 'OWASP ZAP alert')
        solution = str(alert.get('solution') or alert.get('remediation') or '')
        confidence = str(alert.get('confidence') or alert.get('@confidence') or '')

        instances = alert.get('instances') or [{}]
        if isinstance(instances, dict):
            instances = [instances]

        for instance in instances:
            uri = str(instance.get('uri') or site_name or 'unknown')
            line_value = instance.get('line') or instance.get('lineNumber') or 0
            method = str(instance.get('method') or '')
            param = str(instance.get('param') or '')
            evidence = str(instance.get('evidence') or '')

            print("\t".join([
                plugin_id,
                risk_code,
                risk_desc,
                alert_name,
                description.replace('\n', ' '),
                solution.replace('\n', ' '),
                confidence,
                uri,
                str(line_value),
                method,
                param,
                evidence,
            ]))
PY
}

triage_zap() {
  local zap_file="$1"

  mapfile -t findings < <(extract_zap_findings "${zap_file}")

  if [[ ${#findings[@]} -eq 0 ]]; then
    log_info "No actionable ZAP findings in ${zap_file}"
    return 0
  fi

  for finding in "${findings[@]}"; do
    IFS=$'\t' read -r plugin_id risk_code risk_desc alert_name description solution confidence uri line method param evidence <<< "${finding}"

    severity="P2"
    if [[ "${risk_code}" == "3" || "${risk_desc,,}" == *"high"* ]]; then
      severity="P1"
    fi

    route_issue \
      "zap-dast" \
      "${severity}" \
      "${alert_name} in ${uri}:${line}" \
      "Plugin: ${plugin_id}
Risk code: ${risk_code}
Risk: ${risk_desc}
Confidence: ${confidence}
Location: ${uri}:${line}
Method: ${method}
Parameter: ${param}
Description: ${description}
Solution: ${solution}
Evidence: ${evidence}" \
      "security-scan,zap-dast,${severity}" \
      "${zap_file}" \
      "zap|${plugin_id}|${uri}|${line}|${method}|${alert_name}|${risk_code}|${param}|${evidence}"
  done
}

if [[ -n "${SARIF_FILE}" ]]; then
  triage_sarif "${SARIF_FILE}" "${TOOL_NAME}"
fi

if [[ -n "${NPM_AUDIT_FILE}" ]]; then
  triage_npm_audit "${NPM_AUDIT_FILE}"
fi

if [[ -n "${AUDIT_JSONL_FILE}" ]]; then
  mapfile -t findings < <(extract_audit_findings "${AUDIT_JSONL_FILE}")

  if [[ ${#findings[@]} -eq 0 ]]; then
    log_info "No actionable audit findings in ${AUDIT_JSONL_FILE}"
    exit 0
  fi

  for finding in "${findings[@]}"; do
    IFS=$'\t' read -r event_type component status details developer_id ip_address <<< "${finding}"
    severity="P2"
    if [[ "${event_type}" == "SHELL_VIOLATION" || "${event_type}" == "FILE_WRITE_ATTEMPT" || "${event_type}" == "FILE_DELETE_ATTEMPT" || "${event_type}" == "FILE_DOWNLOAD_ATTEMPT" || "${status}" == "blocked" || "${status}" == "denied" ]]; then
      severity="P1"
    fi

    route_issue \
      "audit-log" \
      "${severity}" \
      "${event_type} in ${component} (${status})" \
      "Event: ${event_type}
Component: ${component}
Status: ${status}
Developer: ${developer_id}
IP: ${ip_address}
Details: ${details}" \
      "security-scan,audit-log,${severity}" \
      "${AUDIT_JSONL_FILE}" \
      "audit-log|${event_type}|${component}|${status}|${developer_id}|${ip_address}|${details}"
  done
fi

if [[ -n "${SECRET_JSONL_FILE}" ]]; then
  triage_trufflehog "${SECRET_JSONL_FILE}"
fi

if [[ -n "${ZAP_JSON_FILE}" ]]; then
  triage_zap "${ZAP_JSON_FILE}"
fi
