#!/usr/bin/env bash
# @file        scripts/ops/kubernetes-log-triage.sh
# @module      ops/incident
# @description Classify Kubernetes/container runtime signals and route deduplicated GitHub issues.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
KUBERNETES_JSONL=""
WINDOW_MINUTES="15"
SUSTAINED_THRESHOLD="3"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ops/kubernetes-log-triage.sh [options]

Options:
  --kubernetes-jsonl <file>   Kubernetes event file (JSONL, JSON array, or {events:[...]})
  --repo <owner/repo>         GitHub repository target
  --window-minutes <int>      Observation window metadata in issue body (default: 15)
  --sustained-threshold <n>   Non-critical recurrence threshold for filing/updating issues (default: 3)
  --dry-run                   Print actions without writing issues
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubernetes-jsonl)
      KUBERNETES_JSONL="${2:-}"
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

if [[ -z "$KUBERNETES_JSONL" && -n "${KUBERNETES_LOG_EVENTS_B64:-}" ]]; then
  KUBERNETES_JSONL="$(mktemp "${TMPDIR:-/tmp}/kubernetes-events.XXXXXX.jsonl")"
  printf '%s' "${KUBERNETES_LOG_EVENTS_B64}" | base64 --decode > "$KUBERNETES_JSONL"
fi

if [[ -z "$KUBERNETES_JSONL" ]]; then
  log_warn "No Kubernetes event file provided; skipping triage"
  exit 0
fi

if [[ ! -f "$KUBERNETES_JSONL" ]]; then
  log_fatal "Kubernetes event file not found: $KUBERNETES_JSONL"
fi

if [[ "$DRY_RUN" != "true" ]]; then
  require_command gh
  if [[ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    log_fatal "GH_TOKEN or GITHUB_TOKEN is required for issue routing"
  fi
fi

require_command python3

triage_output=$(python3 - "$KUBERNETES_JSONL" "$WINDOW_MINUTES" "$SUSTAINED_THRESHOLD" <<'PY'
import hashlib
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone

kubernetes_file = sys.argv[1]
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
        first_value(event, ["event_type", "eventType", "type", "kind", "reason"]),
        first_value(event, ["service", "component", "source", "controller"]),
        first_value(event, ["action", "decision", "outcome"]),
        first_value(event, ["message", "msg", "description"]),
        first_value(event, ["namespace", "ns"]),
        first_value(event, ["pod", "pod_name"]),
        first_value(event, ["container", "container_name"]),
    ]
    blob = " ".join(fields).lower()

    rules = [
        (r"crashloopbackoff|back-off restarting failed container|oomkilled|segmentation fault|panic", "runtime", "P1", "Inspect pod/container restart history, memory limits, and runtime logs for crash root cause."),
        (r"failed scheduling|insufficient cpu|insufficient memory|taint|evicted|preempt", "scheduling", "P1", "Review node capacity, taints/tolerations, affinity, and scheduling constraints."),
        (r"readiness probe failed|liveness probe failed|startup probe failed|unhealthy", "health", "P2", "Validate probe endpoints/timeouts and compare against deployment startup profile."),
        (r"imagepullbackoff|errimagepull|failed to pull image|image pull", "image-pull", "P1", "Verify registry auth, image tag digest, and pull policy consistency with last-known-good image."),
        (r"seccomp|apparmor|admission denied|podsecurity|forbidden", "runtime-policy", "P1", "Check security policy enforcement (PSA/admission/runtime profiles) and required workload permissions."),
    ]

    for pattern, signal_class, severity, remediation in rules:
        if re.search(pattern, blob):
            return signal_class, severity, remediation
    return "unclassified", "P2", "Classify Kubernetes signal and add explicit mapping if recurrence is confirmed."


events = load_events(kubernetes_file)
groups = defaultdict(list)
metadata = {}

for event in events:
    signal_class, severity, remediation = classify(event)
    namespace = first_value(event, ["namespace", "ns"], "unknown-namespace")
    service = first_value(event, ["service", "app", "deployment"], "unknown-service")
    pod = first_value(event, ["pod", "pod_name"], "unknown-pod")
    container = first_value(event, ["container", "container_name"], "unknown-container")
    image = first_value(event, ["image", "image_ref", "container_image"], "unknown-image")
    message = first_value(event, ["message", "msg", "description"], "kubernetes event")
    normalized = normalize_message(message)

    base = f"{signal_class}|{namespace}|{service}|{pod}|{container}|{normalized}"
    fingerprint = hashlib.sha256(base.encode("utf-8")).hexdigest()[:12]
    groups[fingerprint].append(event)
    metadata[fingerprint] = {
        "class": signal_class,
        "severity": severity,
        "remediation": remediation,
        "namespace": namespace,
        "service": service,
        "pod": pod,
        "container": container,
        "image": image,
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
    corr_ids = []
    sample_messages = []
    for event in group[:5]:
        ts = first_value(event, ["timestamp", "datetime", "occurred_at", "time"])
        if ts:
            timestamps.append(ts)
        corr = first_value(event, ["trace_id", "request_id", "event_id", "uid"])
        if corr:
            corr_ids.append(corr)
        msg = first_value(event, ["message", "msg", "description"], "kubernetes event")
        sample_messages.append(msg)

    short_fp = fingerprint[:8]
    title = f"[k8s-{short_fp}] {severity}: {info['class']} signal in {info['namespace']}/{info['service']}"
    marker = f"<!-- kubernetes-fingerprint:{fingerprint} -->"

    first_seen = timestamps[0] if timestamps else "unknown"
    last_seen = timestamps[-1] if timestamps else "unknown"
    sample_block = "\n".join(f"- {line[:220]}" for line in sample_messages)
    corr_block = ", ".join(corr_ids[:5]) if corr_ids else "n/a"

    body = f"""## Kubernetes/Container Log Triage

{marker}
- Severity: {severity}
- Signal class: {info['class']}
- Namespace: {info['namespace']}
- Service: {info['service']}
- Pod: {info['pod']}
- Container: {info['container']}
- Last known image: {info['image']}
- Occurrences in window: {count}
- Window (minutes): {window_minutes}
- First seen: {first_seen}
- Last seen: {last_seen}
- Correlation IDs (trace/request/event): {corr_block}

### Evidence Samples
{sample_block}

### Remediation Hint
{info['remediation']}

### Acceptance Checks
- [ ] Validate class mapping (runtime/scheduling/health/image-pull/runtime-policy)
- [ ] Confirm affected workload and blast radius
- [ ] Link remediation PR/rollback and verification evidence

Auto-generated at {now_iso} by scripts/ops/kubernetes-log-triage.sh
"""

    outputs.append({
        "fingerprint": fingerprint,
        "short": short_fp,
        "title": title,
        "body": body,
        "severity": severity,
        "count": count,
        "signal_class": info["class"],
        "namespace": info["namespace"],
        "service": info["service"],
    })

print(json.dumps(outputs))
PY
)

total=$(python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())))' <<<"$triage_output")
if [[ "$total" == "0" ]]; then
  log_info "No actionable Kubernetes signals matched thresholds"
  exit 0
fi

log_info "Actionable Kubernetes fingerprints: $total"

for idx in $(seq 0 $((total - 1))); do
  entry=$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(json.dumps(data[int(sys.argv[1])]))' "$idx" <<<"$triage_output")
  fingerprint=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["fingerprint"])' <<<"$entry")
  short_fp=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["short"])' <<<"$entry")
  title=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["title"])' <<<"$entry")
  body=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["body"])' <<<"$entry")
  severity=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["severity"])' <<<"$entry")
  count=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["count"])' <<<"$entry")
  signal_class=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["signal_class"])' <<<"$entry")
  namespace=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["namespace"])' <<<"$entry")
  service=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["service"])' <<<"$entry")

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] ${severity} ${signal_class} fingerprint ${short_fp} count=${count}"
    log_info "[DRY RUN] Scope: ${namespace}/${service}"
    log_info "[DRY RUN] Title: ${title}"
    continue
  fi

  existing=$(gh issue list --repo "$GH_REPO" --state open --limit 200 --json number,title,body \
    --jq ".[] | select((.title | contains(\"[k8s-${short_fp}]\")) or (.body | contains(\"kubernetes-fingerprint:${fingerprint}\"))) | .number" | head -n 1)

  if [[ -n "$existing" ]]; then
    gh issue comment "$existing" --repo "$GH_REPO" --body "Kubernetes recurrence detected for fingerprint \`${fingerprint}\`.

- Signal class: ${signal_class}
- Severity: ${severity}
- Scope: ${namespace}/${service}
- New occurrences in window: ${count}
- Updated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    log_info "Updated existing Kubernetes issue #$existing (${short_fp})"
  else
  if created=$(gh issue create --repo "$GH_REPO" --title "$title" --body "$body" --label "$severity"); then
    log_info "Created Kubernetes issue for fingerprint ${short_fp}: ${created}"
  else
    log_error "Failed to create Kubernetes issue for fingerprint ${short_fp}"
    exit 1
  fi
  fi
done
