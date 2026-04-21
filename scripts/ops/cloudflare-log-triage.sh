#!/usr/bin/env bash
# @file        scripts/ops/cloudflare-log-triage.sh
# @module      ops/incident
# @description Classify Cloudflare edge/auth/TLS/WAF/tunnel events and route deduplicated GitHub issues.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
CLOUDFLARE_JSONL=""
WINDOW_MINUTES="15"
SUSTAINED_THRESHOLD="3"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ops/cloudflare-log-triage.sh [options]

Options:
  --cloudflare-jsonl <file>   Cloudflare event file (JSONL, JSON array, or {events:[...]})
  --repo <owner/repo>         GitHub repository target
  --window-minutes <int>      Observation window metadata in issue body (default: 15)
  --sustained-threshold <n>   Non-critical recurrence threshold for filing/updating issues (default: 3)
  --dry-run                   Print actions without writing issues
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloudflare-jsonl)
      CLOUDFLARE_JSONL="${2:-}"
      shift 2
      ;;
    --repo)
      GH_REPO="${2:-}"
      shift 2
      ;;
    --window-minutes)
      WINDOW_MINUTES="${2:-15}"
      shift 2
      ;;
    --sustained-threshold)
      SUSTAINED_THRESHOLD="${2:-3}"
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

if [[ -z "$CLOUDFLARE_JSONL" && -n "${CLOUDFLARE_LOG_EVENTS_B64:-}" ]]; then
  CLOUDFLARE_JSONL="$(mktemp "${TMPDIR:-/tmp}/cloudflare-events.XXXXXX.jsonl")"
  printf '%s' "${CLOUDFLARE_LOG_EVENTS_B64}" | base64 --decode > "$CLOUDFLARE_JSONL"
fi

if [[ -z "$CLOUDFLARE_JSONL" ]]; then
  log_warn "No Cloudflare event file provided; skipping triage"
  exit 0
fi

if [[ ! -f "$CLOUDFLARE_JSONL" ]]; then
  log_fatal "Cloudflare event file not found: $CLOUDFLARE_JSONL"
fi

if [[ "$DRY_RUN" != "true" ]]; then
  require_command gh
  if [[ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    log_fatal "GH_TOKEN or GITHUB_TOKEN is required for issue routing"
  fi
fi

require_command python3

triage_output=$(python3 - "$CLOUDFLARE_JSONL" "$WINDOW_MINUTES" "$SUSTAINED_THRESHOLD" <<'PY'
import hashlib
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone

cloudflare_file = sys.argv[1]
window_minutes = int(sys.argv[2])
sustained_threshold = int(sys.argv[3])


def load_events(path):
    with open(path, encoding="utf-8") as handle:
        raw = handle.read().strip()
    if not raw:
        return []

    if raw.startswith("["):
        payload = json.loads(raw)
        return [item for item in payload if isinstance(item, dict)]

    if raw.startswith("{"):
        try:
            payload = json.loads(raw)
        except Exception:
            payload = None
        if isinstance(payload, dict):
            events = payload.get("events") or payload.get("result") or []
            if isinstance(events, list):
                return [item for item in events if isinstance(item, dict)]

    events = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except Exception:
            continue
        if isinstance(item, dict):
            events.append(item)
    return events


def first_value(obj, keys, default=""):
    for key in keys:
        value = obj.get(key)
        if value not in (None, "", [], {}):
            return str(value)
    return default


def normalize_message(message):
    text = str(message).lower().strip()
    text = re.sub(r"\b[0-9a-f]{12,}\b", "<hex>", text)
    text = re.sub(r"\b\d{2,}\b", "<num>", text)
    text = re.sub(r"\s+", " ", text)
    return text


def classify(event):
    fields = [
        first_value(event, ["event_type", "eventType", "type", "kind"]),
        first_value(event, ["service", "component", "source"]),
        first_value(event, ["action", "decision", "outcome"]),
        first_value(event, ["message", "msg", "description"]),
        first_value(event, ["http_status", "status", "edgeResponseStatus"]),
    ]
    blob = " ".join(fields).lower()

    rules = [
        (r"tls|ssl|certificate|handshake|x509|cert", "tls", "P1", "Validate certificate chain, expiration, and TLS mode on Cloudflare edge and origin."),
        (r"waf|firewall|managed challenge|bot|attack", "waf", "P2", "Review WAF rule/action, confirm expected traffic, and tune managed/custom rules."),
        (r"rate.?limit|429", "rate-limit", "P2", "Review rate-limit policy and client retry behavior to reduce false positives."),
        (r"access denied|zero trust|device posture|identity|mfa|forbidden|unauthorized|auth", "auth", "P1", "Validate Access policy, IdP claims, device posture rules, and audience settings."),
        (r"tunnel|argo|origin unreachable|connection refused|no route|dial tcp|521|522|523|524|525|526|530", "tunnel", "P1", "Check cloudflared health, connector reachability, and origin service readiness."),
        (r"edge|timeout|gateway|5\d\d", "edge", "P1", "Inspect edge/origin latency and upstream availability around the failure window."),
    ]

    for pattern, event_class, severity, remediation in rules:
        if re.search(pattern, blob):
            return event_class, severity, remediation
    return "unknown", "P2", "Classify event source and add explicit mapping when recurrence is confirmed."


events = load_events(cloudflare_file)
groups = defaultdict(list)
metadata = {}

for event in events:
    event_class, severity, remediation = classify(event)
    host = first_value(event, ["host", "hostname", "http_host", "zone", "zone_name"], "unknown-host")
    service = first_value(event, ["service", "component", "source"], "cloudflare")
    message = first_value(event, ["message", "msg", "description"], "cloudflare event")
    normalized = normalize_message(message)
    base = f"{event_class}|{host}|{service}|{normalized}"
    fingerprint = hashlib.sha256(base.encode("utf-8")).hexdigest()[:12]
    groups[fingerprint].append(event)
    metadata[fingerprint] = {
        "class": event_class,
        "severity": severity,
        "remediation": remediation,
        "host": host,
        "service": service,
        "normalized": normalized,
    }

now_iso = datetime.now(timezone.utc).isoformat(timespec="seconds")
outputs = []

for fingerprint, group in groups.items():
    info = metadata[fingerprint]
    count = len(group)
    severity = info["severity"]
    actionable = severity == "P1" or count >= sustained_threshold
    if not actionable:
        continue

    timestamps = []
    ray_ids = []
    sample_messages = []
    for event in group[:5]:
        ts = first_value(event, ["timestamp", "datetime", "occurred_at", "time"])
        if ts:
            timestamps.append(ts)
        ray = first_value(event, ["ray_id", "rayId", "cf_ray", "request_id"])
        if ray:
            ray_ids.append(ray)
        msg = first_value(event, ["message", "msg", "description"], "cloudflare event")
        sample_messages.append(msg)

    short_fp = fingerprint[:8]
    title = f"[cf-{short_fp}] {severity}: Cloudflare {info['class']} signal on {info['host']}"
    marker = f"<!-- cloudflare-fingerprint:{fingerprint} -->"

    first_seen = timestamps[0] if timestamps else "unknown"
    last_seen = timestamps[-1] if timestamps else "unknown"
    sample_block = "\n".join(f"- {line[:220]}" for line in sample_messages)
    ray_block = ", ".join(ray_ids[:5]) if ray_ids else "n/a"

    body = f"""## Cloudflare Log Triage

{marker}
- Severity: {severity}
- Event class: {info['class']}
- Host/zone: {info['host']}
- Service/source: {info['service']}
- Occurrences in window: {count}
- Window (minutes): {window_minutes}
- First seen: {first_seen}
- Last seen: {last_seen}
- Correlation IDs (ray/request): {ray_block}

### Evidence Samples
{sample_block}

### Remediation Hint
{info['remediation']}

### Acceptance Checks
- [ ] Validate signal class and affected scope (edge/auth/tls/waf/tunnel)
- [ ] Confirm root cause and rollback/mitigation path
- [ ] Link runbook update or suppression rule if noise is expected

Auto-generated at {now_iso} by scripts/ops/cloudflare-log-triage.sh
"""

    outputs.append({
        "fingerprint": fingerprint,
        "short": short_fp,
        "title": title,
        "body": body,
        "severity": severity,
        "count": count,
        "event_class": info["class"],
    })

print(json.dumps(outputs))
PY
)

total=$(python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())))' <<<"$triage_output")
if [[ "$total" == "0" ]]; then
  log_info "No actionable Cloudflare signals matched thresholds"
  exit 0
fi

log_info "Actionable Cloudflare fingerprints: $total"

for idx in $(seq 0 $((total - 1))); do
  entry=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(json.dumps(data[int(sys.argv[1])]))' "$idx" <<<"$triage_output")
  fingerprint=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["fingerprint"])' <<<"$entry")
  short_fp=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["short"])' <<<"$entry")
  title=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["title"])' <<<"$entry")
  body=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["body"])' <<<"$entry")
  severity=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["severity"])' <<<"$entry")
  count=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["count"])' <<<"$entry")
  event_class=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["event_class"])' <<<"$entry")

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] ${severity} ${event_class} fingerprint ${short_fp} count=${count}"
    log_info "[DRY RUN] Title: ${title}"
    continue
  fi

  existing=$(gh issue list --repo "$GH_REPO" --state open --limit 200 --json number,title,body \
    --jq ".[] | select((.title | contains(\"[cf-${short_fp}]\")) or (.body | contains(\"cloudflare-fingerprint:${fingerprint}\"))) | .number" | head -n 1)

  if [[ -n "$existing" ]]; then
    gh issue comment "$existing" --repo "$GH_REPO" --body "Cloudflare recurrence detected for fingerprint \`${fingerprint}\`.

- Class: ${event_class}
- Severity: ${severity}
- New occurrences in window: ${count}
- Updated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    log_info "Updated existing Cloudflare issue #$existing (${short_fp})"
  else
  if created=$(gh issue create --repo "$GH_REPO" --title "$title" --body "$body" --label "$severity"); then
    log_info "Created Cloudflare issue for fingerprint ${short_fp}: ${created}"
  else
    log_error "Failed to create Cloudflare issue for fingerprint ${short_fp}"
    exit 1
  fi
  fi
done
