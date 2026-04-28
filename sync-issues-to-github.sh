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

EXCLUDED_FILES = {
    "SYNC_ISSUES_README.md",
    "TASK_COMPLETION_VERIFICATION.md",
    "FINAL_ACCEPTANCE_CHECKLIST.md",
    "READY_FOR_EXECUTION.md",
    "START_HERE.md",
    "INDEX.md",
    "EXECUTE_NOW.txt",
}
CODE_EXTS = {".sh", ".py", ".js", ".jsx", ".ts", ".tsx"}


def github_request(method: str, url: str, payload=None):
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


def scan_markdown_tasks(path: Path):
    tasks = []
    if path.name in EXCLUDED_FILES:
        return tasks
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        return tasks
    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        checkbox = re.match(r"^- \[ \] (.+)$", stripped)
        todo_heading = re.match(r"^#+ .*TODO:?\s*(.+)?$", stripped, re.IGNORECASE)
        if checkbox:
            tasks.append((idx, checkbox.group(1).strip(), "markdown-checkbox"))
        elif todo_heading:
            text = todo_heading.group(1).strip() if todo_heading.group(1) else stripped
            text = re.sub(r"^#+\s*", "", text)
            text = re.sub(r"^TODO:?\s*", "", text, flags=re.IGNORECASE)
            tasks.append((idx, text.strip() or stripped, "markdown-todo"))
    return tasks


def scan_code_tasks(path: Path):
    tasks = []
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
    clean = re.sub(r"\s+", " ", text).strip()
    title = f"[{path.name}] {clean}"
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
    }


def issue_exists(marker: str) -> bool:
    query = urllib.parse.quote(f'repo:{OWNER}/{REPO} "{marker}" in:body')
    url = f"https://api.github.com/search/issues?q={query}&per_page=1"
    data = github_request("GET", url)
    return data.get("total_count", 0) > 0


def create_issue(issue):
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/issues"
    return github_request("POST", url, {"title": issue["title"], "body": issue["body"]})


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
