#!/usr/bin/env bash
# @file        scripts/ops/triage-issues-autonomous.sh
# @module      ops/governance
# @description Idempotent GitHub issue triage: assign missing priorities and post autonomous agent execution briefs.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"
source "${REPO_ROOT}/scripts/lib/automation-policy-gate.sh"

GH_OWNER="kushin77"
GH_REPO="code-server"
API_BASE="https://api.github.com/repos/${GH_OWNER}/${GH_REPO}"
MARKER="[agent-autonomy-ready-v2]"
AGENT_READY_LABEL="agent-ready"
AUTO_CLOSE_MARKER="[auto-close-by-linkage-v1]"
MANIFEST_HELPER="${REPO_ROOT}/scripts/ops/issue_execution_manifest.py"

RESOLVED_IDS_FILE="/tmp/triage-resolved-issue-ids.txt"

manifest_get_field() {
    local number="$1"
    local field="$2"

    python3 "${MANIFEST_HELPER}" get --number "${number}" --field "${field}" 2>/dev/null || true
}

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

api_patch() {
    local token="$1"
    local url="$2"
    local payload_file="$3"
    curl --max-time 30 -fsSL \
        -X PATCH \
        -H "Authorization: token ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -H "User-Agent: code-server-agent" \
        "${url}" \
        --data @"${payload_file}"
}

api_delete() {
    local token="$1"
    local url="$2"
    curl --max-time 30 -fsSL \
        -X DELETE \
        -H "Authorization: token ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: code-server-agent" \
        "${url}" >/dev/null
}

prepare_resolved_issue_ids() {
    cd "${REPO_ROOT}"

    if ! command -v git >/dev/null 2>&1; then
        : > "${RESOLVED_IDS_FILE}"
        log_warn "git unavailable; skipping auto-close linkage resolution"
        return
    fi

    git log --format='%s%n%b' \
        | grep -Eoi '(Fixes|Closes|Resolves) #[0-9]+' \
        | grep -Eo '#[0-9]+' \
        | tr -d '#' \
        | sort -u > "${RESOLVED_IDS_FILE}" || true

    local resolved_count
    resolved_count=$(wc -l < "${RESOLVED_IDS_FILE}" | tr -d ' ')
    log_info "Prepared ${resolved_count} resolved issue id(s) from git history"
}

is_resolved_by_git_history() {
    local number="$1"
    [[ -f "${RESOLVED_IDS_FILE}" ]] || return 1
    grep -Fxq "${number}" "${RESOLVED_IDS_FILE}"
}

is_epic_issue() {
    local title="$1"
    local labels_csv="$2"

    if [[ "${title}" =~ ^EPIC: ]]; then
        return 0
    fi
    if [[ "${labels_csv}" == *"epic"* ]]; then
        return 0
    fi
    return 1
}

auto_close_resolved_issue() {
    local token="$1"
    local number="$2"
    local title="$3"
    local labels="$4"

    if ! is_resolved_by_git_history "${number}"; then
        return 1
    fi

    local close_policy
    close_policy="$(manifest_get_field "${number}" closePolicy)"

    if [[ "${close_policy}" == "never" ]] || [[ "${number}" == "291" ]]; then
        log_info "Skipping auto-close for persistent tracker #291"
        return 1
    fi

    if [[ "${close_policy}" == "children-only" ]]; then
        log_info "Skipping auto-close for parent issue #${number} (${title})"
        return 1
    fi

    if is_epic_issue "${title}" "${labels}"; then
        log_info "Skipping auto-close for epic issue #${number} (${title})"
        return 1
    fi

    local comments
    comments=$(api_get "${token}" "${API_BASE}/issues/${number}/comments?per_page=100")
    if ! echo "${comments}" | grep -F -q "${AUTO_CLOSE_MARKER}"; then
        ISSUE_NUMBER="${number}" MARKER_VALUE="${AUTO_CLOSE_MARKER}" python3 - <<'PY' > /tmp/triage-auto-close-comment.json
import json
import os

issue_number = os.environ["ISSUE_NUMBER"]
marker = os.environ["MARKER_VALUE"]
body = (
    f"{marker}\n"
    f"Auto-closing as resolved: merged default-branch history already contains "
    f"Fixes/Closes/Resolves linkage for #{issue_number}. "
    "Reopen if additional scope remains."
)
print(json.dumps({"body": body}))
PY
        api_post "${token}" "${API_BASE}/issues/${number}/comments" "/tmp/triage-auto-close-comment.json" >/dev/null
    fi

    cat > /tmp/triage-close-issue.json <<EOF2
{"state":"closed"}
EOF2
    api_patch "${token}" "${API_BASE}/issues/${number}" "/tmp/triage-close-issue.json" >/dev/null
    log_info "Auto-closed resolved issue #${number} (${title})"
    return 0
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
    local labels="$4"

    local priority
    priority="$(manifest_get_field "${number}" priority)"

    if [[ -z "${priority}" ]]; then
        priority="P2"
    fi

    if [[ "${priority}" == "Persistent" ]]; then
        log_info "Skipping priority label for persistent tracker #${number} (${title})"
        return
    fi

    # Preserve explicit critical-path signal from issue metadata.
    if [[ "${labels}" == *"critical-path"* ]] && [[ "${priority}" != "P0" ]]; then
        priority="P1"
    fi

    cat > /tmp/triage-label.json <<EOF2
{"labels":["${priority}"]}
EOF2
    api_post "${token}" "${API_BASE}/issues/${number}/labels" "/tmp/triage-label.json" >/dev/null

    # Clear temporary queue label once a concrete priority is set.
    if [[ "${labels}" == *"needs-priority"* ]]; then
        api_delete "${token}" "${API_BASE}/issues/${number}/labels/needs-priority" || true
    fi

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

    local comment_body
    comment_body="$(python3 "${MANIFEST_HELPER}" comment --number "${number}" 2>/dev/null || true)"
    if [[ -z "${comment_body}" ]]; then
        comment_body=$(
            cat <<EOF2
Autonomous execution brief for agents:

1. Reproduce current behavior and capture evidence in PR description.
2. Implement minimal, immutable, idempotent change in canonical files only (no duplication).
3. Add or adjust tests and CI checks for regression coverage.
4. Update docs and config only where required by behavior changes.
5. Open PR with Fixes #${number} (or Relates to #${number} for epic or meta issues), include rollout and rollback notes and verification commands.

Definition of done:
- CI green for touched scopes
- No config drift or hardcoded secret regressions
- IaC and deployment paths remain deterministic and reproducible
- Evidence posted in issue and PR links back here
EOF2
        )
    fi

    MARKER_VALUE="${MARKER}" COMMENT_BODY="${comment_body}" python3 - <<'PY' > /tmp/triage-comment.json
import json
import os

marker = os.environ["MARKER_VALUE"]
body = f"{marker}\n" + os.environ["COMMENT_BODY"]

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

    python3 "${MANIFEST_HELPER}" validate >/dev/null

    prepare_resolved_issue_ids

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

        if auto_close_resolved_issue "${token}" "${number}" "${title}" "${labels}"; then
            continue
        fi

        if [[ "${labels}" == *"needs-priority"* ]]; then
            label_needs_priority "${token}" "${number}" "${title}" "${labels}"
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
