#!/usr/bin/env bash
# @file        scripts/ops/triage-issues-autonomous.sh
# @module      ops/governance
# @description Idempotent GitHub issue triage: assign missing priorities and post autonomous agent execution briefs.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

GH_OWNER="kushin77"
GH_REPO="code-server"
API_BASE="https://api.github.com/repos/${GH_OWNER}/${GH_REPO}"
MARKER="[agent-autonomy-ready-v1]"
AGENT_READY_LABEL="agent-ready"

resolve_token() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "${GITHUB_TOKEN}"
        return
    fi
    if [[ -n "${GH_TOKEN:-}" ]]; then
        echo "${GH_TOKEN}"
        return
    fi

    local token
    token=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p' | head -1 || true)
    if [[ -z "${token}" ]]; then
        log_fatal "Unable to resolve GitHub token from env or git credential helper"
    fi
    echo "${token}"
}

api_get() {
    local token="$1"
    local url="$2"
    curl --max-time 30 -fsSL \
        -H "Authorization: token ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: code-server-agent" \
        "${url}"
}

api_post() {
    local token="$1"
    local url="$2"
    local payload_file="$3"
    curl --max-time 30 -fsSL \
        -X POST \
        -H "Authorization: token ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -H "User-Agent: code-server-agent" \
        "${url}" \
        --data @"${payload_file}"
}

ensure_label_exists() {
    local token="$1"
    local name="$2"
    local color="$3"
    local description="$4"

    local labels
    labels=$(api_get "${token}" "${API_BASE}/labels?per_page=100")
    if echo "${labels}" | grep -F -q "\"name\":\"${name}\""; then
        log_info "Label ${name} already exists"
        return
    fi

    NAME_VALUE="${name}" COLOR_VALUE="${color}" DESCRIPTION_VALUE="${description}" python3 - <<'PY' > /tmp/triage-create-label.json
import json
import os

name = os.environ["NAME_VALUE"]
color = os.environ["COLOR_VALUE"]
description = os.environ["DESCRIPTION_VALUE"]
print(json.dumps({"name": name, "color": color, "description": description}))
PY

    api_post "${token}" "${API_BASE}/labels" "/tmp/triage-create-label.json" >/dev/null
    log_info "Created label ${name}"
}

label_needs_priority() {
    local token="$1"
    local number="$2"
    local title="$3"

    local priority="P2"
    case "${number}" in
        623) priority="P0" ;;
        650|652|653|655|657) priority="P1" ;;
        651|654|613) priority="P2" ;;
    esac

    cat > /tmp/triage-label.json <<EOF2
{"labels":["${priority}"]}
EOF2
    api_post "${token}" "${API_BASE}/issues/${number}/labels" "/tmp/triage-label.json" >/dev/null
    log_info "Applied ${priority} to #${number} (${title})"
}

apply_agent_ready_label() {
    local token="$1"
    local number="$2"
    local title="$3"

    cat > /tmp/triage-agent-ready-label.json <<EOF2
{"labels":["${AGENT_READY_LABEL}"]}
EOF2
    api_post "${token}" "${API_BASE}/issues/${number}/labels" "/tmp/triage-agent-ready-label.json" >/dev/null
    log_info "Applied ${AGENT_READY_LABEL} to #${number} (${title})"
}

post_agent_ready_comment() {
    local token="$1"
    local number="$2"
    local title="$3"

    local comments
    comments=$(api_get "${token}" "${API_BASE}/issues/${number}/comments?per_page=100")
    if echo "${comments}" | grep -F -q "${MARKER}"; then
        log_info "Agent-ready comment already present on #${number}"
        return
    fi

    MARKER_VALUE="${MARKER}" ISSUE_NUMBER="${number}" python3 - <<'PY' > /tmp/triage-comment.json
import json
import os

marker = os.environ["MARKER_VALUE"]
issue_number = os.environ["ISSUE_NUMBER"]
body = (
    f"{marker}\n"
    "Autonomous execution brief for agents:\n\n"
    "1. Reproduce current behavior and capture evidence in PR description.\n"
    "2. Implement minimal, immutable, idempotent change in canonical files only (no duplication).\n"
    "3. Add/adjust tests and CI checks for regression coverage.\n"
    "4. Update docs/config only where required by behavior changes.\n"
    f"5. Open PR with `Fixes #{issue_number}` (or `Relates to #{issue_number}` for epic/meta issues), include rollout/rollback notes and verification commands.\n\n"
    "Definition of done:\n"
    "- CI green for touched scopes\n"
    "- No config drift or hardcoded secret regressions\n"
    "- IaC/deployment paths remain deterministic and reproducible\n"
    "- Evidence posted in issue and PR links back here"
)

print(json.dumps({"body": body}))
PY

    if ! api_post "${token}" "${API_BASE}/issues/${number}/comments" "/tmp/triage-comment.json" >/dev/null; then
        log_warn "Unable to post agent-ready brief on #${number} (${title}); continuing"
        return
    fi
    log_info "Posted agent-ready brief on #${number} (${title})"
}

main() {
    local token
    token=$(resolve_token)

    log_info "Fetching open issues"
    ensure_label_exists "${token}" "${AGENT_READY_LABEL}" "0e8a16" "Issue has autonomous execution brief and is ready for agent implementation"
    local issues_file="/tmp/open-issues.json"
    api_get "${token}" "${API_BASE}/issues?state=open&per_page=100" > "${issues_file}"

    python3 - <<'PY' > /tmp/open-issues.tsv
import json
from pathlib import Path
issues = json.loads(Path('/tmp/open-issues.json').read_text(encoding='utf-8'))
for i in issues:
    if 'pull_request' in i:
        continue
    labels = [l['name'] for l in i.get('labels', [])]
    print(f"{i['number']}\t{i['title'].replace(chr(9), ' ')}\t{','.join(labels)}")
PY

    local total=0
    while IFS=$'\t' read -r number title labels; do
        total=$((total + 1))

        if [[ "${labels}" == *"needs-priority"* ]]; then
            label_needs_priority "${token}" "${number}" "${title}"
        fi

        if [[ "${labels}" != *"${AGENT_READY_LABEL}"* ]]; then
            apply_agent_ready_label "${token}" "${number}" "${title}"
        fi

        # Keep issue #291 as persistent tracker but still prepare autonomous brief.
        post_agent_ready_comment "${token}" "${number}" "${title}"
    done < /tmp/open-issues.tsv

    log_info "Autonomous triage completed for ${total} open issues"
}

main "$@"
