#!/usr/bin/env bash
# @file        scripts/vscode-crash-diagnostics.sh
# @module      vscode-stability
# @description vscode crash diagnostics — on-prem code-server
# @owner       platform
# @status      active
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

WINDOW_MINUTES="${WINDOW_MINUTES:-30}"
GH_REPO_TARGET="${GH_REPO_TARGET:-kushin77/code-server}"
RELATES_ISSUE="${RELATES_ISSUE:-291}"
MAX_EVIDENCE_LINES="${MAX_EVIDENCE_LINES:-120}"
AUTO_CREATE_ISSUE=false
AUTO_COMMENT_TRACKER=true
DRY_RUN=false

OUT_DIR="/tmp/vscode-crash-rca"
mkdir -p "$OUT_DIR"
TS_UTC="$(date -u +'%Y%m%dT%H%M%SZ')"
RAW_EVIDENCE="$OUT_DIR/evidence-${TS_UTC}.log"
SUMMARY_MD="$OUT_DIR/rca-${TS_UTC}.md"

usage() {
    cat <<'EOF'
Usage: bash scripts/vscode-crash-diagnostics.sh [options]

Options:
    --window-minutes N      Lookback window in minutes (default: 30)
    --repo OWNER/REPO       GitHub repository (default: kushin77/code-server)
    --relates-issue N       Canonical tracker issue number (default: 291)
    --auto-create-issue     Create a GitHub issue when crash signals are detected
    --no-comment-tracker    Do not comment on tracker issue (#291 by default)
    --dry-run               Print intended GitHub actions without writing
    -h, --help              Show this help

Notes:
    - If gh is not authenticated, the script still generates a complete markdown draft.
    - This script classifies crashes to quickly determine whether they are likely similar
        to the persistent VSCode/code-server crash tracker (#291).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --window-minutes)
            WINDOW_MINUTES="$2"
            shift 2
            ;;
        --repo)
            GH_REPO_TARGET="$2"
            shift 2
            ;;
        --relates-issue)
            RELATES_ISSUE="$2"
            shift 2
            ;;
        --auto-create-issue)
            AUTO_CREATE_ISSUE=true
            shift
            ;;
        --no-comment-tracker)
            AUTO_COMMENT_TRACKER=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_fatal "Unknown option: $1"
            ;;
    esac
done

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

classify_line() {
    local l="$1"
    local lc
    lc="$(echo "$l" | tr '[:upper:]' '[:lower:]')"

    if echo "$lc" | grep -Eq 'extension host terminated|exthost.*(crash|exit)|extension host.*(died|stopped)'; then
        echo "extension-host"
        return
    fi
    if echo "$lc" | grep -Eq 'extensionhostprocess\.js|\$invokeagent'; then
        echo "extension-host"
        return
    fi
    if echo "$lc" | grep -Eq 'renderer process crashed|webview.*crash|gpu process crashed|window.*crash'; then
        echo "renderer"
        return
    fi
    if echo "$lc" | grep -Eq 'out of memory|oom|cannot allocate memory|killed process.*code-server'; then
        echo "memory"
        return
    fi
    if echo "$lc" | grep -Eq 'enospc|inotify|max_user_watches|file watcher'; then
        echo "file-watcher"
        return
    fi
    if echo "$lc" | grep -Eq 'segmentation fault|sigsegv|fatal error|core dumped'; then
        echo "process-crash"
        return
    fi
    if echo "$lc" | grep -Eq 'econnreset|epipe|socket hang up|connection reset'; then
        echo "transport"
        return
    fi
    echo "unknown"
}

normalize_line() {
    sed \
        -e 's/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9:.+-Z]*/ /g' \
        -e 's/0x[0-9A-Fa-f][0-9A-Fa-f]*/ADDR/g' \
        -e 's/pid[=: ][0-9][0-9]*/pid=N/g' \
        -e 's/:[0-9][0-9]*/:N/g' \
        -e 's/[[:space:]][[:space:]]*/ /g' \
        -e 's/^ *//g' \
        -e 's/ *$//g'
}

emit_source_hits() {
    local source_name="$1"
    local text="$2"
    [[ -z "$text" ]] && return 0
    while IFS= read -r line; do
        if echo "$line" | grep -qi 'Error from tool run_in_terminal'; then
            continue
        fi
        if [[ ${#line} -gt 600 ]]; then
            line="${line:0:600}..."
        fi
        printf '[%s] %s\n' "$source_name" "$line" >> "$RAW_EVIDENCE"
    done < <(
        echo "$text" | grep -Ein 'crash|fatal|panic|segfault|sigsegv|out of memory|oom|enospc|inotify|extension host terminated|renderer process crashed|webview.*crash|code-server.*(exited|stopped)' 2>/dev/null | head -n "$MAX_EVIDENCE_LINES" || true
    )
}

collect_file_logs() {
    local dirs=(
        "$HOME/.local/share/code-server/coder-logs"
        "$HOME/.local/share/code-server/logs"
        "$HOME/.config/code-server"
    )

    for d in "${dirs[@]}"; do
        [[ ! -d "$d" ]] && continue
        while IFS= read -r f; do
            local lines
            lines="$(tail -n 250 "$f" 2>/dev/null || true)"
            emit_source_hits "$f" "$lines"
        done < <(find "$d" -type f -mmin "-${WINDOW_MINUTES}" 2>/dev/null)
    done
}

collect_journal_logs() {
    if has_cmd journalctl; then
        emit_source_hits "journalctl-code-server" "$(journalctl --no-pager --since "-${WINDOW_MINUTES} min" -u code-server 2>/dev/null || true)"
        emit_source_hits "journalctl-kernel" "$(journalctl --no-pager --since "-${WINDOW_MINUTES} min" -k 2>/dev/null | grep -Ei 'oom|killed process|segfault|code-server' || true)"
    fi
}

collect_docker_logs() {
    if ! has_cmd docker; then
        log_warn "docker not found; skipping container log collection"
        return 0
    fi

    local names
    names="$(docker ps --format '{{.Names}}' 2>/dev/null || true)"
    [[ -z "$names" ]] && return 0

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        emit_source_hits "docker:${name}" "$(docker logs --since "${WINDOW_MINUTES}m" "$name" 2>&1 || true)"
    done <<< "$names"
}

log_info "Collecting crash evidence for last ${WINDOW_MINUTES} minute(s)"
rm -f "$RAW_EVIDENCE"
touch "$RAW_EVIDENCE"

collect_file_logs
collect_journal_logs
collect_docker_logs

if [[ ! -s "$RAW_EVIDENCE" ]]; then
    log_warn "No crash evidence found in the selected window"
    log_info "Hint: rerun with a larger window, e.g. --window-minutes 180"
    exit 0
fi

declare -A FP_COUNT
declare -A FP_CATEGORY
declare -A FP_SAMPLE

while IFS= read -r ev; do
    [[ -z "$ev" ]] && continue
    payload="$ev"
    if [[ "$payload" == \[*\]* ]]; then
        payload="${payload#*] }"
    fi
    norm="$(echo "$payload" | normalize_line)"
    [[ -z "$norm" ]] && continue
    fp="$(printf '%s' "$norm" | sha256sum | awk '{print substr($1,1,10)}')"
    category="$(classify_line "$payload")"

    FP_COUNT["$fp"]=$(( ${FP_COUNT["$fp"]:-0} + 1 ))
    FP_CATEGORY["$fp"]="${FP_CATEGORY["$fp"]:-$category}"
    if [[ -z "${FP_SAMPLE[$fp]:-}" ]]; then
        FP_SAMPLE["$fp"]="$payload"
    fi
done < "$RAW_EVIDENCE"

total_hits=$(wc -l < "$RAW_EVIDENCE" | tr -d ' ')
unique_fps=${#FP_COUNT[@]}

similar_to_291="unknown"
if grep -Eq 'extension-host|renderer|memory|file-watcher' <(printf '%s\n' "${FP_CATEGORY[@]}"); then
    similar_to_291="likely-similar"
else
    similar_to_291="inconclusive"
fi

{
    echo "## VSCode/code-server Crash RCA"
    echo
    echo "- Generated (UTC): $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "- Window: last ${WINDOW_MINUTES} minutes"
    echo "- Total crash signals: ${total_hits}"
    echo "- Unique fingerprints: ${unique_fps}"
    echo "- Similarity to #${RELATES_ISSUE}: ${similar_to_291}"
    echo
    echo "### Top Fingerprints"
    for fp in "${!FP_COUNT[@]}"; do
        printf '%s|%s|%s|%s\n' "${FP_COUNT[$fp]}" "$fp" "${FP_CATEGORY[$fp]}" "${FP_SAMPLE[$fp]}"
    done | sort -t'|' -k1,1nr | while IFS='|' read -r cnt fp cat sample; do
        echo "- [${fp}] count=${cnt} category=${cat}"
        echo "  sample: ${sample}"
    done
    echo
    echo "### Raw Evidence"
    echo '```'
    head -n 120 "$RAW_EVIDENCE"
    echo '```'
} > "$SUMMARY_MD"

log_info "RCA summary written: ${SUMMARY_MD}"
log_info "Raw evidence written: ${RAW_EVIDENCE}"
log_info "Similarity verdict vs #${RELATES_ISSUE}: ${similar_to_291}"

if [[ "$AUTO_CREATE_ISSUE" != "true" ]]; then
    log_info "Issue creation disabled (pass --auto-create-issue to enable)."
    exit 0
fi

if ! has_cmd gh; then
    log_warn "gh CLI not found; cannot auto-create issue"
    exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
    log_warn "gh is not authenticated; cannot auto-create issue"
    exit 0
fi

title="Crash RCA: ${total_hits} crash signals in ${WINDOW_MINUTES}m (similarity: ${similar_to_291})"
body_file="$OUT_DIR/issue-body-${TS_UTC}.md"

{
    echo "Relates to #${RELATES_ISSUE}"
    echo
    cat "$SUMMARY_MD"
} > "$body_file"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create issue in ${GH_REPO_TARGET}: ${title}"
    if [[ "$AUTO_COMMENT_TRACKER" == "true" ]]; then
        log_info "[DRY-RUN] Would comment on #${RELATES_ISSUE} with issue link"
    fi
    exit 0
fi

issue_url="$(gh issue create --repo "$GH_REPO_TARGET" --title "$title" --body-file "$body_file" --label P1 --label incident --label crash 2>/dev/null || true)"
if [[ -z "$issue_url" ]]; then
    log_warn "Failed to create GitHub issue"
    exit 1
fi

log_info "Created issue: ${issue_url}"

if [[ "$AUTO_COMMENT_TRACKER" == "true" ]]; then
    gh issue comment "$RELATES_ISSUE" --repo "$GH_REPO_TARGET" \
        --body "New crash RCA incident filed: ${issue_url}\n\nSimilarity verdict: ${similar_to_291}\nWindow: ${WINDOW_MINUTES}m\nSignals: ${total_hits}" >/dev/null 2>&1 || \
        log_warn "Failed to comment on tracker issue #${RELATES_ISSUE}"
fi
