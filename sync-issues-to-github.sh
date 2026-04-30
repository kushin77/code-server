#!/usr/bin/env bash
# Sync local task markers to GitHub Issues without requiring gh, curl, or jq.

set -euo pipefail
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

export GITHUB_OWNER="${GITHUB_OWNER:-kushin77}"
export GITHUB_REPO="${GITHUB_REPO:-code-server}"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "❌ GITHUB_TOKEN environment variable not set"
  echo "Run: bash sync-issues-now.sh"
  exit 1
fi

python3 - <<'PY'
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

OWNER = os.environ.get("GITHUB_OWNER", "kushin77")
REPO = os.environ.get("GITHUB_REPO", "code-server")
TOKEN = os.environ["GITHUB_TOKEN"].strip()
ROOT = Path.cwd()
PATH_FILTER = os.environ.get("SYNC_PATH_FILTER", "").strip()
START_AFTER = os.environ.get("SYNC_START_AFTER", "").strip()
MAX_CREATE = int(os.environ.get("SYNC_MAX_CREATE", "0") or "0")
INCLUDE_CODE_TASKS = os.environ.get("SYNC_INCLUDE_CODE_TASKS", "0") == "1"

EXCLUDED_FILES = {
    "SYNC_ISSUES_README.md",
    "TASK_COMPLETION_VERIFICATION.md",
    "FINAL_ACCEPTANCE_CHECKLIST.md",
    "READY_FOR_EXECUTION.md",
    "START_HERE.md",
    "INDEX.md",
    "EXECUTE_NOW.txt",
    # Exclude operational checklists and deployment guides (internal reference docs)
    # These contain 5000+ task markers but are not GitHub-trackable issues
    "MASTER_DEPLOYMENT_EXECUTION_CHECKLIST.md",
    "IaC-DEPLOYMENT-CHECKLIST.md",
    "MASTER_DEPLOYMENT_INDEX.md",
}
EXCLUDED_NAME_TOKENS = {
    "STATUS",
    "PROGRESS",
    "COMPLETE",
    "COMPLETION",
    "REPORT",
    "SUMMARY",
    "HANDOFF",
    "CERTIFICATE",
    "VERIFICATION",
    "EVIDENCE",
    # Operational guides (deployment checklists, phase runbooks, etc)
    # These are internal reference docs with 5000+ task markers, not GitHub issues
    "PHASE",
    "DEPLOYMENT",
    "OPERATIONS",
    "CHECKLIST",
    "RUNBOOK",
    "GUIDE",
    "PACKAGE",
}
APPROVED_MARKDOWN_PREFIXES = (
    "artifacts/",
    "terraform/",
    "docs/testing/",
    "docs/operations/",
    "docs/sso/",
)
APPROVED_MARKDOWN_NAME_TOKENS = {
    "ROADMAP",
    "CHECKLIST",
    "PLAN",
    "GAP-ANALYSIS",
    "MIGRATION",
}
CODE_EXTS = {".sh", ".py", ".js", ".jsx", ".ts", ".tsx"}
LABEL_CACHE = None


def strip_markdown_emphasis(text: str) -> str:
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"__([^_]+)__", r"\1", text)
    return text.strip()


def is_parent_checkbox_label(text: str) -> bool:
    clean = strip_markdown_emphasis(text)
    return bool(re.fullmatch(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9_-]+", clean))


def normalize_todo_heading(stripped: str) -> str:
    text = re.sub(r"^#+\s*", "", stripped).strip()
    text = re.sub(r"\s*\((?:TODO|FIXME|HACK)[^)]*\)\s*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r"^(?:TODO|FIXME|HACK):?\s*", "", text, flags=re.IGNORECASE)
    return text.strip()


def github_request(method: str, url: str, payload=None, retries=4):
    for attempt in range(retries):
        try:
            data = None
            headers = {
                "Authorization": f"token {TOKEN}",
                "Accept": "application/vnd.github+json",
                "User-Agent": "code-server-local-task-sync",
            }
            if payload is not None:
                data = json.dumps(payload).encode()
                headers["Content-Type"] = "application/json"
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            if e.code == 403:
                error_body = e.read().decode()
                if "rate limit" in error_body.lower():
                    if attempt < retries - 1:
                        wait_time = (2 ** attempt) * 5
                        print(f"⏳ Rate limit (attempt {attempt+1}/{retries}), waiting {wait_time}s...", file=sys.stderr)
                        time.sleep(wait_time)
                        continue
            raise


def repository_labels():
    global LABEL_CACHE
    if LABEL_CACHE is not None:
        return LABEL_CACHE

    labels = set()
    page = 1
    while True:
        data = github_request("GET", f"https://api.github.com/repos/{OWNER}/{REPO}/labels?per_page=100&page={page}")
        if not data:
            break
        labels.update(item.get("name", "") for item in data)
        page += 1

    LABEL_CACHE = labels
    return LABEL_CACHE


def iter_files():
    for path in sorted(ROOT.rglob("*")):
        rel = path.relative_to(ROOT)
        rel_str = rel.as_posix()
        if any(part in {".git", "node_modules", ".backups", ".bootstrap-state"} for part in rel.parts):
            continue
        if rel_str.startswith("docs/archive/"):
            continue
        if path.is_file():
            yield path


def classify_priority(text: str) -> str:
    text_l = text.lower()
    if any(word in text_l for word in ("security", "auth", "credential", "secret", "failover", "dr", "backup")):
        return "P1"
    if any(word in text_l for word in ("deploy", "staging", "production", "monitor", "alarm", "migration", "validate")):
        return "P2"
    return "P3"


def derive_tags(path: Path, text: str):
    joined = f"{path.as_posix()} {text}".lower()
    tags = []
    for key in ("terraform", "database", "deployment", "cluster", "audit", "ssl", "docker", "kubernetes", "ci/cd"):
        probe = key.replace("/", "")
        if probe in joined or key in joined:
            tags.append(key)
    return tags[:4]


def should_skip_markdown_file(path: Path) -> bool:
    if path.name in EXCLUDED_FILES:
        return True

    upper_name = path.name.upper()
    if any(token in upper_name for token in EXCLUDED_NAME_TOKENS):
        return True

    path_str = path.as_posix()
    if any(path_str.startswith(prefix) for prefix in APPROVED_MARKDOWN_PREFIXES):
        return False

    return not any(token in upper_name for token in APPROVED_MARKDOWN_NAME_TOKENS)


def resolve_labels(priority: str, tags):
    available = repository_labels()
    desired = [
        "automation",
        "github",
        "area:github-sync",
        "epic:pmo-excellence",
        priority,
    ]
    desired.extend(tags)

    labels = []
    for label in desired:
        if label in available and label not in labels:
            labels.append(label)
    return labels


def scan_markdown_tasks(path: Path):
    tasks = []
    if should_skip_markdown_file(path):
        return tasks
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        return tasks
    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        checkbox = re.match(r"^- \[ \] (.+)$", stripped)
        todo_heading = re.search(r"^#+ .*\b(TODO|FIXME|HACK)\b", stripped, re.IGNORECASE)
        if checkbox:
            text = checkbox.group(1).strip()
            if is_parent_checkbox_label(text):
                continue
            tasks.append((idx, text, "markdown-checkbox"))
        elif todo_heading:
            text = normalize_todo_heading(stripped)
            tasks.append((idx, text or stripped, "markdown-todo"))
    return tasks


def scan_code_tasks(path: Path):
    tasks = []
    if not INCLUDE_CODE_TASKS:
        return tasks
    if path.suffix.lower() not in CODE_EXTS or path.name == "pmo-todo-scanner.sh":
        return tasks
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        return tasks
    for idx, line in enumerate(lines, 1):
        match = re.search(r"\b(TODO|FIXME|HACK)\b[:\- ]*(.+)", line)
        if match:
            kind = match.group(1)
            text = match.group(2).strip() or kind
            tasks.append((idx, f"[{kind}] {text}", "code-marker"))
    return tasks


def build_issue(path: Path, line_no: int, text: str, task_type: str):
    clean = strip_markdown_emphasis(re.sub(r"\s+", " ", text).strip())
    display_source = path.as_posix() if path.name.lower() in {"readme.md", "index.md", "start_here.md"} else path.name
    title = f"[{display_source}] {clean}"
    if len(title) > 110:
        title = title[:107] + "..."
    marker = f"task-sync-source: {path.as_posix()}:{line_no}"
    priority = classify_priority(clean)
    tags = derive_tags(path, clean)
    body_lines = [
        f"Source file: `{path.as_posix()}:{line_no}`",
        f"Task type: `{task_type}`",
        f"Priority: `{priority}`",
    ]
    if tags:
        body_lines.append("Tags: " + ", ".join(f"`{tag}`" for tag in tags))
    body_lines += ["", clean, "", marker]
    return {
        "title": title,
        "body": "\n".join(body_lines),
        "marker": marker,
        "source": path.as_posix(),
        "line": line_no,
        "labels": resolve_labels(priority, tags),
    }


def issue_exists(marker: str) -> bool:
    query = urllib.parse.quote(f'repo:{OWNER}/{REPO} "{marker}" in:body')
    url = f"https://api.github.com/search/issues?q={query}&per_page=1"
    data = github_request("GET", url)
    return data.get("total_count", 0) > 0


def create_issue(issue):
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/issues"
    payload = {"title": issue["title"], "body": issue["body"]}
    if issue.get("labels"):
        payload["labels"] = issue["labels"]
    return github_request("POST", url, payload)


def is_rate_limited(http_error: urllib.error.HTTPError, details: str) -> bool:
    return http_error.code == 403 and "rate limit exceeded" in details.lower()


def matches_filter(issue, pattern: str) -> bool:
    if not pattern:
        return True
    probe = pattern.lower()
    return (
        probe in issue["source"].lower()
        or probe in issue["title"].lower()
        or probe in issue["marker"].lower()
    )


def main():
    try:
        github_request("GET", f"https://api.github.com/repos/{OWNER}/{REPO}")
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            print("❌ GitHub token is invalid or unauthorized", file=sys.stderr)
            return 2
        raise

    seen = set()
    issues = []
    for path in iter_files():
        rel = path.relative_to(ROOT)
        found = scan_markdown_tasks(rel) if path.suffix.lower() == ".md" else scan_code_tasks(rel)
        for line_no, text, task_type in found:
            key = (rel.as_posix(), line_no, text)
            if not text or key in seen:
                continue
            seen.add(key)
            issues.append(build_issue(rel, line_no, text, task_type))

    if PATH_FILTER:
        issues = [issue for issue in issues if matches_filter(issue, PATH_FILTER)]

    if START_AFTER:
        matched = False
        resumed = []
        for issue in issues:
            if matched:
                resumed.append(issue)
                continue
            if matches_filter(issue, START_AFTER):
                matched = True
        if not matched:
            print(f"❌ SYNC_START_AFTER did not match any task: {START_AFTER}", file=sys.stderr)
            return 2
        issues = resumed

    print(f"Discovered {len(issues)} local tasks")
    created = 0
    skipped = 0
    failed = 0
    for issue in issues:
        if MAX_CREATE and created >= MAX_CREATE:
            print(f"STOP  Reached SYNC_MAX_CREATE={MAX_CREATE}; ending batch")
            break
        try:
            if issue_exists(issue["marker"]):
                print(f"SKIP  {issue['title']}")
                skipped += 1
                continue
            created_issue = create_issue(issue)
            print(f"CREATE #{created_issue.get('number')} {issue['title']}")
            created += 1
        except urllib.error.HTTPError as exc:
            details = exc.read().decode(errors="ignore")
            print(f"FAIL  {issue['title']} :: HTTP {exc.code} {details[:200]}")
            failed += 1
            if is_rate_limited(exc, details):
                print("STOP  GitHub API rate limit exceeded; aborting remaining issue creation")
                break
            if exc.code == 401:
                break
        except Exception as exc:
            print(f"FAIL  {issue['title']} :: {exc}")
            failed += 1

    print(f"Summary: created={created} skipped={skipped} failed={failed}")
    return 0 if failed == 0 else 1


raise SystemExit(main())
PY
