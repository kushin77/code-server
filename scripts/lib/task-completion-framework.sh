#!/usr/bin/env bash
# @file        scripts/lib/task-completion-framework.sh
# @module      task-management/completion-validation
# @description Definition of Done (DoD) validation framework to prevent task_complete hook blockers
#
# This framework provides structured Definition of Done registration, tracking, validation,
# and diagnosis to ensure clarity before marking tasks complete. Prevents repeated task_complete
# rejections by validating completion status upfront.
#
# USAGE:
#   source scripts/lib/task-completion-framework.sh
#   register_dod_item "step-1" "Implement feature" "agent"
#   do_work
#   mark_dod_complete "step-1"
#   validate_definition_of_done && safe_task_complete 1234 || diagnose_completion_blockers
#
# @owner       kushin77
# @status      production
#

set -euo pipefail

# ============================================================================
# INTERNAL STATE (do not modify directly)
# ============================================================================

declare -gA _DOD_REGISTRY=()        # { "step-id" -> "description|blocker_type|notes|command" }
declare -gA _DOD_COMPLETION=()      # { "step-id" -> "completed|blocked|pending" }
declare -gA _DOD_BLOCKERS=()        # { "step-id" -> "reason" }
declare -gA _DOD_TIMESTAMPS=()      # { "step-id:event" -> "epoch_seconds" }
declare -g  _DOD_INITIALIZED=0
declare -g  _COMPLETION_VERBOSE=0
declare -g  _DOD_AUDIT_LOG=""       # Path to audit log file (empty = disabled)
declare -g  _DOD_GITHUB_REPO=""     # "owner/repo" for GitHub integration

# ============================================================================
# CORE API
# ============================================================================

##
# register_dod_item(id, description, blocker_type, [notes])
#
# Register a Definition of Done item that must be completed before task_complete.
#
# PARAMETERS:
#   id             - Unique identifier (e.g., "step-1", "deploy-prod")
#   description    - Human-readable description of the item
#   blocker_type   - One of: "agent", "credentials", "manual", "external"
#   notes          - Optional additional context
#
# BLOCKER TYPES:
#   agent         - Agent must complete this step
#   credentials   - Needs credentials (GCP, SSH, API keys, passwords)
#   manual        - Needs human judgment (browser testing, approval)
#   external      - Blocked by external system (waiting for webhook, etc)
#
function register_dod_item() {
  local id="${1:?missing id}"
  local description="${2:?missing description}"
  local blocker_type="${3:?missing blocker_type}"
  local notes="${4:-}"
  local command="${5:-}"

  # Validate blocker type
  case "$blocker_type" in
    agent|credentials|manual|external) ;;
    *)
      echo "ERROR: Invalid blocker_type '$blocker_type'. Must be: agent|credentials|manual|external" >&2
      return 1
      ;;
  esac

  _DOD_REGISTRY["$id"]="$description|$blocker_type|$notes|$command"
  _DOD_COMPLETION["$id"]="pending"
  _DOD_TIMESTAMPS["${id}:registered"]="$(date +%s)"
  _DOD_INITIALIZED=1
  _dod_audit "$id" "REGISTERED" "$blocker_type"
}

##
# mark_dod_complete(id)
#
# Mark a Definition of Done item as complete.
#
function mark_dod_complete() {
  local id="${1:?missing id}"

  if [[ -z "${_DOD_REGISTRY[$id]:-}" ]]; then
    echo "ERROR: DoD item '$id' not registered" >&2
    return 1
  fi

  # shellcheck disable=SC2034
  local prev="${_DOD_COMPLETION[$id]}"
  _DOD_COMPLETION["$id"]="completed"
  _DOD_TIMESTAMPS["${id}:completed"]="$(date +%s)"
  unset "_DOD_BLOCKERS[$id]" 2>/dev/null || true

  local duration=""
  if [[ -n "${_DOD_TIMESTAMPS[${id}:registered]:-}" ]]; then
    duration=$(( $(date +%s) - _DOD_TIMESTAMPS["${id}:registered"] ))
  fi
  _dod_audit "$id" "COMPLETED" "${duration:+duration=${duration}s}"
}

##
# mark_dod_blocked(id, reason)
#
# Mark a Definition of Done item as blocked with explanation.
#
function mark_dod_blocked() {
  local id="${1:?missing id}"
  local reason="${2:?missing reason}"

  if [[ -z "${_DOD_REGISTRY[$id]:-}" ]]; then
    echo "ERROR: DoD item '$id' not registered" >&2
    return 1
  fi

  _DOD_COMPLETION["$id"]="blocked"
  _DOD_BLOCKERS["$id"]="$reason"
  _DOD_TIMESTAMPS["${id}:blocked"]="$(date +%s)"
  _dod_audit "$id" "BLOCKED" "$reason"
}

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

# _dod_audit(id, event, detail) — append to audit log if enabled
function _dod_audit() {
  [[ -z "$_DOD_AUDIT_LOG" ]] && return 0
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"
  printf "%s\t%-12s\t%-25s\t%s\n" "$ts" "${2:-}" "${1:-}" "${3:-}" >> "$_DOD_AUDIT_LOG"
}

# _dod_elapsed(id) — seconds since item was registered
function _dod_elapsed() {
  local id="${1:?}"
  local reg="${_DOD_TIMESTAMPS[${id}:registered]:-}"
  [[ -z "$reg" ]] && echo "0" && return
  echo $(( $(date +%s) - reg ))
}

# _dod_duration(id) — seconds from registered to completed
function _dod_duration() {
  local id="${1:?}"
  local reg="${_DOD_TIMESTAMPS[${id}:registered]:-}"
  local done="${_DOD_TIMESTAMPS[${id}:completed]:-}"
  [[ -z "$reg" || -z "$done" ]] && echo "" && return
  echo $(( done - reg ))
}

# _dod_parse_field(registry_value, field_index) — extract pipe-delimited field
# Fields: 0=description, 1=blocker_type, 2=notes, 3=command
function _dod_parse_field() {
  local value="$1"
  local idx="${2:-0}"
  # shellcheck disable=SC2034
  local i=0
  local IFS='|'
  local parts
  read -ra parts <<< "$value"
  echo "${parts[$idx]:-}"
}

# ============================================================================
# VALIDATION & DIAGNOSIS
# ============================================================================

##
# validate_definition_of_done()
#
# Check if all Definition of Done items are complete.
# Returns 0 if all complete, 1 if any blocked/pending.
#
function validate_definition_of_done() {
  if [[ $_DOD_INITIALIZED -eq 0 ]]; then
    [[ $_COMPLETION_VERBOSE -eq 1 ]] && echo "ℹ️  No DoD items registered"
    return 0  # No DoD defined = validation passes
  fi

  local total=0
  local completed=0

  for id in "${!_DOD_COMPLETION[@]}"; do
    ((total++))
    if [[ "${_DOD_COMPLETION[$id]}" == "completed" ]]; then
      ((completed++))
    fi
  done

  if [[ $completed -eq $total && $total -gt 0 ]]; then
    [[ $_COMPLETION_VERBOSE -eq 1 ]] && echo "✅ Definition of Done: $completed/$total complete"
    return 0
  else
    [[ $_COMPLETION_VERBOSE -eq 1 ]] && echo "❌ Definition of Done: $completed/$total complete"
    return 1
  fi
}

##
# get_completion_status([format])
#
# Get current completion status. Format: text (default), json, markdown
#
function get_completion_status() {
  local format="${1:-text}"

  local total=0
  local completed=0
  local blocked=0
  local pending=0

  for id in "${!_DOD_COMPLETION[@]}"; do
    ((total++))
    case "${_DOD_COMPLETION[$id]}" in
      completed) ((completed++)) ;;
      blocked) ((blocked++)) ;;
      pending) ((pending++)) ;;
    esac
  done

  case "$format" in
    text)
      cat <<EOF
Definition of Done Status
═════════════════════════════════════════
Total Items:    $total
Completed:      $completed ✅
Blocked:        $blocked ⚠️
Pending:        $pending 🔄
────────────────────────────────────────
Status:         $(validate_definition_of_done >/dev/null 2>&1 && echo "READY ✅" || echo "NOT READY ❌")
EOF
      ;;
    json)
      echo "{"
      echo "  \"total\": $total,"
      echo "  \"completed\": $completed,"
      echo "  \"blocked\": $blocked,"
      echo "  \"pending\": $pending,"
      echo "  \"ready\": $(validate_definition_of_done >/dev/null 2>&1 && echo "true" || echo "false"),"
      echo "  \"items\": {"
      local first=1
      for id in "${!_DOD_REGISTRY[@]}"; do
        local reg="${_DOD_REGISTRY[$id]}"
        local desc;       desc="$(_dod_parse_field "$reg" 0)"
        local btype;      btype="$(_dod_parse_field "$reg" 1)"
        local status="${_DOD_COMPLETION[$id]}"
        local dur;        dur="$(_dod_duration "$id")"
        local elapsed;    elapsed="$(_dod_elapsed "$id")"
        local registered="${_DOD_TIMESTAMPS[${id}:registered]:-}"
        local completed_ts="${_DOD_TIMESTAMPS[${id}:completed]:-}"
        [[ $first -eq 0 ]] && echo ","
        printf '    "%s": {"status":"%s","type":"%s","description":"%s","registered":%s,"completed":%s,"duration_secs":%s,"age_secs":%s}' \
          "$id" "$status" "$btype" "$desc" \
          "${registered:-null}" \
          "${completed_ts:-null}" \
          "${dur:-null}" \
          "$elapsed"
        first=0
      done
      echo ""
      echo "  }"
      echo "}"
      ;;
    markdown)
      cat <<EOF
## Definition of Done Status

| Metric | Count |
|--------|-------|
| Total Items | $total |
| Completed | $completed ✅ |
| Blocked | $blocked ⚠️ |
| Pending | $pending 🔄 |

**Overall Status**: $(validate_definition_of_done >/dev/null 2>&1 && echo "**READY ✅**" || echo "**NOT READY ❌**")
EOF
      ;;
    *)
      echo "ERROR: Unknown format '$format'" >&2
      return 1
      ;;
  esac
}

##
# diagnose_completion_blockers([show_solutions])
#
# Detailed diagnosis of what's blocking completion and recommended paths forward.
# If show_solutions=1, displays resolution options.
#
function diagnose_completion_blockers() {
  local show_solutions="${1:-1}"

  if [[ $_DOD_INITIALIZED -eq 0 ]]; then
    echo "ℹ️  No DoD items registered - nothing to diagnose"
    return 0
  fi

  local has_blockers=0
  declare -A blocker_by_type

  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "COMPLETION BLOCKER DIAGNOSIS"
  echo "════════════════════════════════════════════════════════════════"
  echo ""

  for id in "${!_DOD_COMPLETION[@]}"; do
    local status="${_DOD_COMPLETION[$id]}"
    if [[ "$status" != "completed" ]]; then
      has_blockers=1
      local registry="${_DOD_REGISTRY[$id]}"
      local desc="${registry%%|*}"
      local blocker_type="${registry#*|}"
      blocker_type="${blocker_type%%|*}"

      echo "❌ BLOCKED: $id"
      echo "   Description: $desc"
      echo "   Type: $blocker_type"

      if [[ -n "${_DOD_BLOCKERS[$id]:-}" ]]; then
        echo "   Reason: ${_DOD_BLOCKERS[$id]}"
      fi
      echo ""

      blocker_by_type["$blocker_type"]=$((${blocker_by_type[$blocker_type]:-0} + 1))
    fi
  done

  if [[ $has_blockers -eq 0 ]]; then
    echo "✅ No blockers detected - all DoD items complete!"
    echo ""
    return 0
  fi

  if [[ $show_solutions -eq 1 ]]; then
    echo "════════════════════════════════════════════════════════════════"
    echo "RESOLUTION PATHS"
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    if [[ -n "${blocker_by_type[credentials]:-}" ]]; then
      cat <<EOF
🔴 PATH A (HIGH RISK): Provide credentials to agent
   ├─ Requires: SSH keys, API passwords, GCP service accounts
   ├─ Risk: Storing secrets in logs/scripts
   ├─ Recommended: NO - Only if absolutely necessary and temporary
   └─ Command: Provide credentials, agent will execute steps

🟢 PATH B (RECOMMENDED): Operations team handles credential steps
   ├─ Requires: Human execution with proper secrets management
   ├─ Risk: LOW - Credentials stay with ops team
   ├─ Next: Report issue with this diagnosis, ops team takes over
   └─ Timeline: Immediate handoff to ops

EOF
    fi

    if [[ -n "${blocker_by_type[manual]:-}" ]]; then
      cat <<EOF
🟡 PATH C (DEPENDENT): Manual verification needed
   ├─ Requires: Human judgment, browser testing, approval
   ├─ Risk: MEDIUM - Can be delegated post-deployment
   ├─ Next: Complete agent work, hand to QA for verification
   └─ Timeline: Can proceed after automated steps complete

EOF
    fi

    if [[ -n "${blocker_by_type[external]:-}" ]]; then
      cat <<EOF
🔵 PATH D (WAITING): External system dependency
   ├─ Requires: Webhook response, deployment completion, etc
   ├─ Risk: MEDIUM - Depends on external system reliability
   ├─ Next: Verify external system status, retry or escalate
   └─ Timeline: Monitor external system

EOF
    fi

    cat <<EOF
════════════════════════════════════════════════════════════════
RECOMMENDED ACTION:
  1. Document all blocker types above
  2. For credentials blockers → Assign to ops team (PATH B)
  3. For manual blockers → Assign to QA (PATH C)
  4. For external blockers → Verify system status (PATH D)
  5. Comment on issue with this diagnosis + recommended path
════════════════════════════════════════════════════════════════

EOF
  fi

  return 1  # Return 1 because there are blockers
}

##
# safe_task_complete(issue_id, [force])
#
# Safely call task_complete after validating Definition of Done.
# If force=1, skips validation and calls task_complete anyway.
#
# USAGE:
#   safe_task_complete 1234           # Validate first
#   safe_task_complete 1234 1         # Skip validation (dangerous!)
#
function safe_task_complete() {
  local issue_id="${1:?missing issue_id}"
  local force="${2:-0}"

  if [[ $force -eq 0 ]]; then
    if ! validate_definition_of_done; then
      echo ""
      echo "❌ Cannot complete task: Definition of Done not satisfied"
      echo "Run: diagnose_completion_blockers"
      echo ""
      return 1
    fi
  fi

  echo "✅ Calling task_complete for issue #$issue_id..."
  echo ""

  # This would call the actual task_complete tool in a real scenario
  # For now, we just indicate readiness
  return 0
}

##
# get_completion_report([format])
#
# Generate detailed completion report in specified format.
#
function get_completion_report() {
  local format="${1:-text}"

  case "$format" in
    text|json|markdown)
      get_completion_status "$format"
      ;;
    *)
      echo "ERROR: Unknown format '$format'" >&2
      return 1
      ;;
  esac
}

##
# list_dod_items([status_filter])
#
# List all DoD items, optionally filtered by status.
# status_filter: all (default), completed, pending, blocked
#
function list_dod_items() {
  local filter="${1:-all}"

  if [[ $_DOD_INITIALIZED -eq 0 ]]; then
    echo "No DoD items registered"
    return 0
  fi

  printf "%-20s %-50s %-15s %-10s\n" "ID" "DESCRIPTION" "TYPE" "STATUS"
  printf "%-20s %-50s %-15s %-10s\n" "---" "---" "---" "---"

  for id in "${!_DOD_REGISTRY[@]}"; do
    local registry="${_DOD_REGISTRY[$id]}"
    local desc="${registry%%|*}"
    local blocker_type="${registry#*|}"
    blocker_type="${blocker_type%%|*}"
    local status="${_DOD_COMPLETION[$id]}"

    # Apply filter
    if [[ "$filter" != "all" && "$status" != "$filter" ]]; then
      continue
    fi

    # Truncate description if needed
    if [[ ${#desc} -gt 48 ]]; then
      desc="${desc:0:45}..."
    fi

    printf "%-20s %-50s %-15s %-10s\n" "$id" "$desc" "$blocker_type" "$status"
  done
}

##
# reset_dod()
#
# Clear all Definition of Done items (useful for testing).
#
function reset_dod() {
  _DOD_REGISTRY=()
  _DOD_COMPLETION=()
  _DOD_BLOCKERS=()
  _DOD_INITIALIZED=0
}

##
# enable_dod_verbose()
#
# Enable verbose output for validation checks.
#
function enable_dod_verbose() {
  _COMPLETION_VERBOSE=1
}

##
# disable_dod_verbose()
#
# Disable verbose output for validation checks.
#
function disable_dod_verbose() {
  _COMPLETION_VERBOSE=0
}

##
# enable_dod_audit(log_file)
#
# Enable append-only audit log. Every state transition is timestamped.
# Log format: ISO8601_UTC  EVENT  ITEM_ID  DETAIL
#
function enable_dod_audit() {
  _DOD_AUDIT_LOG="${1:?missing log_file}"
  printf "# dod-audit-log started %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$_DOD_AUDIT_LOG"
}

##
# set_dod_github_repo(owner/repo)
#
# Configure GitHub repo for post_dod_to_issue.
#
function set_dod_github_repo() {
  _DOD_GITHUB_REPO="${1:?missing owner/repo}"
}

##
# run_dod_item(id)
#
# Execute the command attached to an agent-type DoD item (registered with a 5th argument).
# Auto-marks complete on success, blocked on failure.
#
# USAGE:
#   register_dod_item "check-email" "Email in whitelist" "agent" "" \
#     "grep -q qa@kushnir.cloud allowed-emails.txt"
#   run_dod_item "check-email"
#
function run_dod_item() {
  local id="${1:?missing id}"

  if [[ -z "${_DOD_REGISTRY[$id]:-}" ]]; then
    echo "ERROR: DoD item '$id' not registered" >&2
    return 1
  fi

  local reg="${_DOD_REGISTRY[$id]}"
  local cmd; cmd="$(_dod_parse_field "$reg" 3)"
  local desc; desc="$(_dod_parse_field "$reg" 0)"
  local btype; btype="$(_dod_parse_field "$reg" 1)"

  if [[ -z "$cmd" ]]; then
    echo "ERROR: DoD item '$id' has no command attached (5th argument of register_dod_item)" >&2
    return 1
  fi

  if [[ "$btype" != "agent" ]]; then
    echo "WARN: run_dod_item is intended for 'agent' type items (got '$btype')" >&2
  fi

  echo "⏳ Running: $id — $desc"
  echo "   Command: $cmd"

  # Run in a subshell to prevent 'exit N' inside the command from killing the
  # parent shell. Capture exit code explicitly.
  local exit_code=0
  ( eval "$cmd" ) || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    mark_dod_complete "$id"
    echo "   ✅ Succeeded"
    return 0
  else
    mark_dod_blocked "$id" "Command exited with code $exit_code"
    echo "   ❌ Failed (exit $exit_code)" >&2
    return 1
  fi
}

##
# save_dod_state(file_path)
#
# Serialize current DoD state to a JSON file.
# Enables resuming across script runs and sessions.
#
# USAGE:
#   save_dod_state .dod-state.json
#
function save_dod_state() {
  local file="${1:?missing file_path}"

  {
    echo "{"
    echo "  \"saved_at\": $(date +%s),"
    echo "  \"registry\": {"
    local first_r=1
    for id in "${!_DOD_REGISTRY[@]}"; do
      [[ $first_r -eq 0 ]] && echo ","
      local reg="${_DOD_REGISTRY[$id]}"
      local desc; desc="$(_dod_parse_field "$reg" 0)"
      local btype; btype="$(_dod_parse_field "$reg" 1)"
      local notes; notes="$(_dod_parse_field "$reg" 2)"
      local cmd; cmd="$(_dod_parse_field "$reg" 3)"
      # Escape double quotes in values
      desc="${desc//\"/\\\"}"
      notes="${notes//\"/\\\"}"
      cmd="${cmd//\"/\\\"}"
      printf '    "%s": {"description":"%s","blocker_type":"%s","notes":"%s","command":"%s"}' \
        "$id" "$desc" "$btype" "$notes" "$cmd"
      first_r=0
    done
    echo ""
    echo "  },"
    echo "  \"completion\": {"
    local first_c=1
    for id in "${!_DOD_COMPLETION[@]}"; do
      [[ $first_c -eq 0 ]] && echo ","
      printf '    "%s": "%s"' "$id" "${_DOD_COMPLETION[$id]}"
      first_c=0
    done
    echo ""
    echo "  },"
    echo "  \"blockers\": {"
    local first_b=1
    for id in "${!_DOD_BLOCKERS[@]}"; do
      [[ $first_b -eq 0 ]] && echo ","
      local reason="${_DOD_BLOCKERS[$id]//\"/\\\"}"
      printf '    "%s": "%s"' "$id" "$reason"
      first_b=0
    done
    echo ""
    echo "  },"
    echo "  \"timestamps\": {"
    local first_t=1
    for key in "${!_DOD_TIMESTAMPS[@]}"; do
      [[ $first_t -eq 0 ]] && echo ","
      printf '    "%s": %s' "$key" "${_DOD_TIMESTAMPS[$key]}"
      first_t=0
    done
    echo ""
    echo "  }"
    echo "}"
  } > "$file"

  echo "💾 DoD state saved to: $file"
}

##
# load_dod_state(file_path)
#
# Restore DoD state from a previously saved JSON file.
# Requires bash 4+ with associative arrays.
#
# USAGE:
#   load_dod_state .dod-state.json
#
function load_dod_state() {
  local file="${1:?missing file_path}"

  if [[ ! -f "$file" ]]; then
    echo "ERROR: State file not found: $file" >&2
    return 1
  fi

  reset_dod

  # Parse with python3 if available (reliable), else fallback to awk
  if command -v python3 &>/dev/null; then
    local parsed
    parsed="$(python3 - "$file" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    state = json.load(f)

reg   = state.get("registry", {})
comp  = state.get("completion", {})
block = state.get("blockers", {})
ts    = state.get("timestamps", {})

for id, v in reg.items():
    print(f"REG\t{id}\t{v['description']}\t{v['blocker_type']}\t{v.get('notes','')}\t{v.get('command','')}")

for id, status in comp.items():
    print(f"COMP\t{id}\t{status}")

for id, reason in block.items():
    print(f"BLOCK\t{id}\t{reason}")

for key, val in ts.items():
    print(f"TS\t{key}\t{val}")
PYEOF
)"
    while IFS=$'\t' read -r kind rest; do
      case "$kind" in
        REG)
          IFS=$'\t' read -r id desc btype notes cmd <<< "$rest"
          _DOD_REGISTRY["$id"]="$desc|$btype|$notes|$cmd"
          _DOD_INITIALIZED=1
          ;;
        COMP)
          IFS=$'\t' read -r id status <<< "$rest"
          _DOD_COMPLETION["$id"]="$status"
          ;;
        BLOCK)
          IFS=$'\t' read -r id reason <<< "$rest"
          _DOD_BLOCKERS["$id"]="$reason"
          ;;
        TS)
          IFS=$'\t' read -r key val <<< "$rest"
          _DOD_TIMESTAMPS["$key"]="$val"
          ;;
      esac
    done <<< "$parsed"
  else
    echo "WARN: python3 not found; state file loaded read-only (display only)" >&2
    echo "Install python3 for full load_dod_state support." >&2
    return 1
  fi

  local item_count=${#_DOD_REGISTRY[@]}
  echo "📂 DoD state loaded from: $file ($item_count items)"
}

##
# post_dod_to_issue(issue_number, [repo])
#
# Post current DoD status as a formatted GitHub issue comment.
# Uses _DOD_GITHUB_REPO if repo not specified.
# Requires: gh CLI authenticated.
#
# USAGE:
#   set_dod_github_repo "kushin77/code-server"
#   post_dod_to_issue 984
#   # — or inline —
#   post_dod_to_issue 984 "kushin77/code-server"
#
function post_dod_to_issue() {
  local issue="${1:?missing issue_number}"
  local repo="${2:-$_DOD_GITHUB_REPO}"

  if [[ -z "$repo" ]]; then
    echo "ERROR: No GitHub repo set. Call set_dod_github_repo owner/repo first." >&2
    return 1
  fi

  if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not found. Install from https://cli.github.com" >&2
    return 1
  fi

  # Build markdown body
  local body
  body="$(cat <<MDEOF
## Definition of Done Status

$(get_completion_status markdown)

### Item Details

| ID | Description | Type | Status | Age |
|----|-------------|------|--------|-----|
MDEOF
)"
  for id in "${!_DOD_REGISTRY[@]}"; do
    local reg="${_DOD_REGISTRY[$id]}"
    local desc; desc="$(_dod_parse_field "$reg" 0)"
    local btype; btype="$(_dod_parse_field "$reg" 1)"
    local status="${_DOD_COMPLETION[$id]}"
    local elapsed; elapsed="$(_dod_elapsed "$id")"
    local status_icon
    case "$status" in
      completed) status_icon="✅ completed" ;;
      blocked)   status_icon="❌ blocked" ;;
      pending)   status_icon="🔄 pending" ;;
      *)         status_icon="$status" ;;
    esac
    local age_str
    if (( elapsed >= 3600 )); then
      age_str="$(( elapsed / 3600 ))h $(( (elapsed % 3600) / 60 ))m"
    elif (( elapsed >= 60 )); then
      age_str="$(( elapsed / 60 ))m"
    else
      age_str="${elapsed}s"
    fi
    body+=$'\n'"| \`$id\` | $desc | $btype | $status_icon | $age_str |"
  done

  # Append blocker diagnosis if any items are blocked
  if ! validate_definition_of_done >/dev/null 2>&1; then
    body+=$'\n\n'
    body+="### Blockers & Resolution Paths"$'\n\n'
    for id in "${!_DOD_COMPLETION[@]}"; do
      if [[ "${_DOD_COMPLETION[$id]}" != "completed" ]]; then
        local reg="${_DOD_REGISTRY[$id]}"
        local btype; btype="$(_dod_parse_field "$reg" 1)"
        local blocker_reason="${_DOD_BLOCKERS[$id]:-}"
        body+="**\`$id\`** ($btype)"
        [[ -n "$blocker_reason" ]] && body+=": $blocker_reason"
        case "$btype" in
          credentials) body+=$'\n'"→ **PATH B**: Assign to ops team — credentials must not be given to agent"$'\n' ;;
          manual)      body+=$'\n'"→ **PATH C**: Assign to QA — requires human verification"$'\n' ;;
          external)    body+=$'\n'"→ **PATH D**: Monitor external system, retry when ready"$'\n' ;;
        esac
        body+=$'\n'
      fi
    done
  fi

  body+=$'\n'"---"$'\n'"_Posted by task-completion-framework · $(date -u +%Y-%m-%dT%H:%M:%SZ)_"

  echo "$body" | gh issue comment "$issue" --repo "$repo" --body-file -
  echo "📬 DoD status posted to issue #$issue in $repo"
}

# ============================================================================
# EXPORT PUBLIC API
# ============================================================================

export -f register_dod_item
export -f mark_dod_complete
export -f mark_dod_blocked
export -f validate_definition_of_done
export -f get_completion_status
export -f diagnose_completion_blockers
export -f safe_task_complete
export -f get_completion_report
export -f list_dod_items
export -f reset_dod
export -f enable_dod_verbose
export -f disable_dod_verbose
# Elite enhancements
export -f enable_dod_audit
export -f set_dod_github_repo
export -f run_dod_item
export -f save_dod_state
export -f load_dod_state
export -f post_dod_to_issue
# Internal helpers (exported for subshell access)
export -f _dod_audit
export -f _dod_elapsed
export -f _dod_duration
export -f _dod_parse_field
# Elite enhancements
export -f enable_dod_audit
export -f set_dod_github_repo
export -f run_dod_item
export -f save_dod_state
export -f load_dod_state
export -f post_dod_to_issue
# Internal helpers (exported for subshell access)
export -f _dod_audit
export -f _dod_elapsed
export -f _dod_duration
export -f _dod_parse_field
