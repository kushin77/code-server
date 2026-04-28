#!/usr/bin/env bash
# @file scripts/process/generate-weekly-report.sh
# @description Generate the weekly review markdown report from GitHub state.
# Tracks GitHub issue #2413 (Weekly Review & Reporting Template).

set -euo pipefail

# Required error handling traps (pre-commit policy)
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../_common/init.sh"

REPO_SLUG="${REPO_SLUG:-kushin77/code-server}"
OUT_DIR="${REPO_ROOT}/artifacts/weekly"
mkdir -p "${OUT_DIR}"
WEEK_TAG="$(date -u +%G-W%V)"
OUT="${OUT_DIR}/${WEEK_TAG}.md"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_warning "GITHUB_TOKEN not set; report will fall back to git log only."
fi

log_info "=== Generating weekly report for ${WEEK_TAG} ==="

python3 - "${REPO_SLUG}" "${OUT}" <<'PY'
import json, os, subprocess, sys, urllib.request
from datetime import datetime, timedelta, timezone

slug, out_path = sys.argv[1], sys.argv[2]
tok = os.environ.get('GITHUB_TOKEN', '')
since = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
since_short = since[:10]

def gh(path, params=''):
    url = f'https://api.github.com{path}'
    if params:
        url += '?' + params
    req = urllib.request.Request(url, headers={'Accept':'application/vnd.github+json'})
    if tok:
        req.add_header('Authorization', f'Bearer {tok}')
    try:
        return json.load(urllib.request.urlopen(req))
    except Exception as e:
        return {'_error': str(e)}

def search(q):
    return gh('/search/issues', f'q={urllib.parse.quote(q)}&per_page=100') if tok else {'total_count': 'n/a', 'items': []}

import urllib.parse
prs_merged = search(f'repo:{slug} is:pr is:merged merged:>={since_short}')
issues_closed = search(f'repo:{slug} is:issue is:closed closed:>={since_short}')
issues_opened = search(f'repo:{slug} is:issue created:>={since_short}')
p0_open = search(f'repo:{slug} is:issue is:open label:P0')
p1_open = search(f'repo:{slug} is:issue is:open label:P1')

# Local commit count
git_count = subprocess.run(
    ['git', '-C', os.path.dirname(out_path) + '/../..', 'rev-list', '--count', f'--since={since}', 'HEAD'],
    capture_output=True, text=True
).stdout.strip() or '0'

def n(o): return o.get('total_count', 'n/a') if isinstance(o, dict) else 'n/a'

with open(out_path, 'w') as f:
    f.write(f"# Weekly Review — {datetime.now(timezone.utc).strftime('%G-W%V')}\n\n")
    f.write(f"_Window: last 7 days, generated {datetime.now(timezone.utc).isoformat()}_\n\n")
    f.write("## 1. KPIs\n\n| Metric | Value |\n|---|---|\n")
    f.write(f"| Local commits (HEAD)          | {git_count} |\n")
    f.write(f"| PRs merged                    | {n(prs_merged)} |\n")
    f.write(f"| Issues closed                 | {n(issues_closed)} |\n")
    f.write(f"| Issues opened                 | {n(issues_opened)} |\n")
    f.write(f"| P0 open                       | {n(p0_open)} |\n")
    f.write(f"| P1 open                       | {n(p1_open)} |\n\n")

    def list_items(label, blob, limit=15):
        f.write(f"## {label}\n\n")
        items = blob.get('items', []) if isinstance(blob, dict) else []
        if not items:
            f.write("_(none or unauthenticated)_\n\n")
            return
        for it in items[:limit]:
            f.write(f"- [#{it['number']}]({it['html_url']}) — {it['title']}\n")
        if len(items) > limit:
            f.write(f"- _… {len(items) - limit} more_\n")
        f.write("\n")

    list_items("2. PRs merged", prs_merged)
    list_items("3. Issues closed", issues_closed)
    list_items("4. Issues opened", issues_opened)
    list_items("5. P0 open (focus list)", p0_open, limit=50)

    f.write("## 6. Risks & blockers\n\n_Fill in by the facilitator._\n\n")
    f.write("## 7. Next week — top 3 outcomes\n\n_Fill in by the facilitator._\n\n")
    f.write("## 8. Decisions logged\n\n_Fill in by the facilitator._\n")
print('REPORT', out_path)
PY

log_success "Weekly report: ${OUT}"
exit 0
