#!/usr/bin/env bash
# Sync persisted warning/error/critical log signals into grouped GitHub issues.

set -euo pipefail
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

export GITHUB_OWNER="${GITHUB_OWNER:-kushin77}"
export GITHUB_REPO="${GITHUB_REPO:-code-server}"

DRY_RUN="${SLOG_DRY_RUN:-0}"
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi
export SLOG_DRY_RUN="$DRY_RUN"

if [[ "$DRY_RUN" != "1" && -z "${GITHUB_TOKEN:-}" ]]; then
  echo "❌ GITHUB_TOKEN environment variable not set"
  echo "Run: bash sync-slog-now.sh"
  exit 1
fi

python3 - <<'PY'
import fnmatch
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

OWNER = os.environ.get("GITHUB_OWNER", "kushin77")
REPO = os.environ.get("GITHUB_REPO", "code-server")
TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
ROOT = Path.cwd()
DRY_RUN = os.environ.get("SLOG_DRY_RUN", "0") == "1"
PATH_FILTER = os.environ.get("SLOG_PATH_FILTER", "").strip()
MAX_CREATE = int(os.environ.get("SLOG_MAX_CREATE", "0") or "0")
SEVERITIES = {
    item.strip().lower()
    for item in os.environ.get("SLOG_SEVERITIES", "warning,error,critical,issue").split(",")
    if item.strip()
}
INCLUDE_MARKDOWN_LOGS = os.environ.get("SLOG_INCLUDE_MARKDOWN_LOGS", "1") == "1"
INCLUDE_PATTERNS = [
    item.strip()
    for item in os.environ.get(
        "SLOG_INCLUDE_PATTERNS",
        "logs/*.log,logs/**/*.log,*.log,artifacts/**/*.log",
    ).split(",")
    if item.strip()
]
LABEL_CACHE = None

ANSI_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
LOG_PATTERNS = (
    re.compile(r"^\[(?P<ts>[^\]]+)\]\s+\[(?P<level>INFO|WARN|WARNING|ERROR|CRITICAL|ISSUE|SUCCESS)\]\s+(?P<msg>.+)$", re.IGNORECASE),
    re.compile(r"^\[(?P<ts>[^\]]+)\]\s+(?P<level>INFO|WARN|WARNING|ERROR|CRITICAL|ISSUE|SUCCESS):\s+(?P<msg>.+)$", re.IGNORECASE),
    re.compile(r"^\[(?P<level>WARN|WARNING|ERROR|CRITICAL|ISSUE)\]\s+(?P<msg>.+)$", re.IGNORECASE),
    re.compile(r"^\*\*(?P<level>Error|Warning|Critical|Issue)\*\*:\s*(?P<msg>.+)$", re.IGNORECASE),
)


def github_request(method: str, url: str, payload=None, retries=4):
    if not TOKEN:
        raise RuntimeError("GitHub token is required for live sync")
    
    for attempt in range(retries):
        try:
            data = None
            headers = {
                "Authorization": f"token {TOKEN}",
                "Accept": "application/vnd.github+json",
                "User-Agent": "code-server-slog-sync",
            }
            if payload is not None:
                data = json.dumps(payload).encode()
                headers["Content-Type"] = "application/json"
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=30) as response:
                content = response.read().decode()
                return json.loads(content) if content else {}
        except urllib.error.HTTPError as e:
            if e.code == 403:
                error_body = e.read().decode()
                if "rate limit" in error_body.lower():
                    if attempt < retries - 1:
                        wait_time = (2 ** attempt) * 5
                        print(f"⏳ Rate limit (attempt {attempt+1}/{retries}), waiting {wait_time}s...", file=sys.stderr)
                        import time
                        time.sleep(wait_time)
                        continue
            raise


def repository_labels():
    global LABEL_CACHE
    if LABEL_CACHE is not None:
        return LABEL_CACHE
    if DRY_RUN or not TOKEN:
        LABEL_CACHE = set()
        return LABEL_CACHE

    labels = set()
    page = 1
    while True:
        items = github_request(
            "GET",
            f"https://api.github.com/repos/{OWNER}/{REPO}/labels?per_page=100&page={page}",
        )
        if not items:
            break
        labels.update(item.get("name", "") for item in items)
        page += 1
    LABEL_CACHE = labels
    return LABEL_CACHE


def iter_candidate_files():
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        rel_str = rel.as_posix()
        if any(part in {".git", "node_modules", ".backups", ".bootstrap-state", ".venv"} for part in rel.parts):
            continue
        if PATH_FILTER and PATH_FILTER not in rel_str:
            continue
        matches_runtime_pattern = any(fnmatch.fnmatch(rel_str, pattern) for pattern in INCLUDE_PATTERNS)
        if path.suffix.lower() == ".log":
            if matches_runtime_pattern:
                yield path
            continue
        if INCLUDE_MARKDOWN_LOGS and path.suffix.lower() == ".md" and "log" in path.name.lower():
            yield path


def normalize_severity(value: str):
    level = value.strip().lower()
    if level == "warn":
        return "warning"
    return level


def strip_ansi(text: str):
    return ANSI_RE.sub("", text)


def normalize_message(text: str):
    normalized = strip_ansi(text)
    normalized = normalized.replace("`", "")
    normalized = re.sub(r"https?://\S+", "<url>", normalized)
    normalized = re.sub(r"\b\d{4}-\d{2}-\d{2}[T ][^\s]+\b", "<timestamp>", normalized)
    normalized = re.sub(r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b", "<ip>", normalized)
    normalized = re.sub(r"\b[0-9a-f]{7,40}\b", "<hash>", normalized, flags=re.IGNORECASE)
    normalized = re.sub(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b", "<uuid>", normalized, flags=re.IGNORECASE)
    normalized = re.sub(r"\b\d{2,}\b", "<num>", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip(" .:-")
    return normalized


def extract_event(path: Path, line_no: int, raw_line: str):
    cleaned = strip_ansi(raw_line).strip()
    if not cleaned:
        return None
    for pattern in LOG_PATTERNS:
        match = pattern.match(cleaned)
        if not match:
            continue
        severity = normalize_severity(match.group("level"))
        if severity not in SEVERITIES:
            return None
        message = match.group("msg").strip()
        normalized = normalize_message(message)
        if not normalized:
            return None
        timestamp = match.groupdict().get("ts", "")
        return {
            "severity": severity,
            "message": message,
            "normalized": normalized,
            "timestamp": timestamp,
            "path": path.relative_to(ROOT).as_posix(),
            "line": line_no,
        }
    return None


def iter_events():
    for path in iter_candidate_files():
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except Exception:
            continue
        for index, raw_line in enumerate(lines, 1):
            event = extract_event(path, index, raw_line)
            if event:
                yield event


def severity_priority(severity: str):
    if severity == "critical":
        return "P1"
    if severity == "error":
        return "P2"
    return "P3"


def infer_family(source_paths, normalized_text: str):
    lowered = (" ".join(source_paths) + " " + normalized_text).lower()
    family_rules = (
        ("drift", ("drift", "gitops")),
        ("health-checks", ("health check", "health checks", "endpoint health")),
        ("deployment", ("deployment", "rollback", "phase 5", "deploy")),
        ("database", ("database", "postgres", "psql", "gitlabdb")),
        ("docker", ("docker", "compose daemon")),
        ("caddy", ("caddy",)),
    )
    for family, probes in family_rules:
        if any(probe in lowered for probe in probes):
            return family
    return "runtime-logs"


def derive_tags(source_paths, normalized_text: str):
    joined = " ".join(source_paths) + " " + normalized_text
    lowered = joined.lower()
    tags = []
    for key in ("audit", "docker", "terraform", "caddy", "github", "deployment", "cluster", "ci/cd"):
        probe = key.replace("/", "")
        if key in lowered or probe in lowered:
            tags.append(key)
    family = infer_family(source_paths, normalized_text)
    if family not in tags:
        tags.append(family)
    return tags[:5]


def resolve_labels(priority: str, severity: str, tags, family: str):
    available = repository_labels()
    desired = [
        "automation",
        "github",
        "area:github-sync",
        "epic:pmo-excellence",
        priority,
        severity,
        "triage",
        "logs",
        f"area:{family}",
    ]
    desired.extend(tags)
    labels = []
    if not available:
        return labels
    for label in desired:
        if label in available and label not in labels:
            labels.append(label)
    return labels


def build_groups():
    groups = {}
    for event in iter_events():
        signature_input = f"{event['severity']}::{event['normalized']}"
        signature = hashlib.sha1(signature_input.encode()).hexdigest()[:16]
        group = groups.setdefault(
            signature,
            {
                "signature": signature,
                "severity": event["severity"],
                "normalized": event["normalized"],
                "events": [],
                "sources": Counter(),
                "messages": Counter(),
                "first_seen": None,
                "last_seen": None,
            },
        )
        group["events"].append(event)
        group["sources"][event["path"]] += 1
        group["messages"][event["message"]] += 1
        if event["timestamp"]:
            if not group["first_seen"] or event["timestamp"] < group["first_seen"]:
                group["first_seen"] = event["timestamp"]
            if not group["last_seen"] or event["timestamp"] > group["last_seen"]:
                group["last_seen"] = event["timestamp"]
    return groups


def build_issue(group):
    severity = group["severity"]
    priority = severity_priority(severity)
    sources = sorted(group["sources"].items(), key=lambda item: (-item[1], item[0]))
    top_message = max(group["messages"].items(), key=lambda item: (item[1], item[0]))[0]
    pretty_title = re.sub(r"\s+", " ", top_message).strip()
    title = f"[slog][{severity}] {pretty_title}"
    if len(title) > 110:
        title = title[:107] + "..."
    marker = f"slog-sync-signature: {group['signature']}"
    tags = derive_tags([path for path, _ in sources], group["normalized"])
    family = infer_family([path for path, _ in sources], group["normalized"])
    recent_events = sorted(
        group["events"],
        key=lambda item: (item["timestamp"], item["path"], item["line"]),
    )[-5:]
    body_lines = [
        f"Severity: `{severity}`",
        f"Priority: `{priority}`",
        f"Family: `{family}`",
        f"Occurrences: `{len(group['events'])}`",
        f"Normalized signature: `{group['normalized']}`",
    ]
    if group["first_seen"]:
        body_lines.append(f"First seen: `{group['first_seen']}`")
    if group["last_seen"]:
        body_lines.append(f"Last seen: `{group['last_seen']}`")
    if tags:
        body_lines.append("Tags: " + ", ".join(f"`{tag}`" for tag in tags))
    body_lines.extend(["", "Top sources:"])
    for path, count in sources[:10]:
        body_lines.append(f"- `{path}`: `{count}` occurrence(s)")
    body_lines.extend(["", "Recent evidence:"])
    for event in recent_events:
        location = f"{event['path']}:{event['line']}"
        prefix = f"`{event['timestamp']}` " if event["timestamp"] else ""
        body_lines.append(f"- {prefix}`{location}` - {event['message']}")
    body_lines.extend(["", marker])
    return {
        "title": title,
        "body": "\n".join(body_lines),
        "labels": resolve_labels(priority, severity, tags, family),
        "marker": marker,
        "family": family,
    }


def find_existing_issue(marker: str):
    query = urllib.parse.quote(f'repo:{OWNER}/{REPO} type:issue "{marker}"')
    data = github_request("GET", f"https://api.github.com/search/issues?q={query}&per_page=10")
    for item in data.get("items", []):
        if marker in item.get("body", ""):
            return item
    return None


def print_plan(issues):
    if not issues:
        print("No warning/error/critical/issue log entries matched the configured sources.")
        return
    for issue in issues:
        print(
            f"[{issue['severity']}] {issue['title']} :: family={issue['family']} :: "
            f"occurrences={issue['occurrences']} :: marker={issue['marker']}"
        )


groups = build_groups()
planned = []
for signature in sorted(groups):
    group = groups[signature]
    issue = build_issue(group)
    planned.append({
        "severity": group["severity"],
        "family": issue["family"],
        "title": issue["title"],
        "body": issue["body"],
        "labels": issue["labels"],
        "marker": issue["marker"],
        "occurrences": len(group["events"]),
    })

print(f"Discovered {len(planned)} grouped slog issue candidate(s).")
if DRY_RUN:
    print_plan(planned)
    sys.exit(0)

created = 0
updated = 0
for issue in planned:
    existing = find_existing_issue(issue["marker"])
    payload = {
        "title": issue["title"],
        "body": issue["body"],
    }
    if issue["labels"]:
        payload["labels"] = issue["labels"]

    if existing:
        payload["state"] = "open"
        github_request("PATCH", existing["url"], payload)
        updated += 1
        print(f"Updated existing slog issue #{existing['number']}: {issue['title']}")
        continue

    if MAX_CREATE and created >= MAX_CREATE:
        print(f"Reached SLOG_MAX_CREATE={MAX_CREATE}; stopping new issue creation.")
        break

    created_issue = github_request(
        "POST",
        f"https://api.github.com/repos/{OWNER}/{REPO}/issues",
        payload,
    )
    created += 1
    print(f"Created slog issue #{created_issue['number']}: {issue['title']}")

print(f"SLOG sync complete. created={created} updated={updated} grouped={len(planned)}")
PY