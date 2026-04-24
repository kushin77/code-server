#!/usr/bin/env bash
# @file        scripts/lib/automation-policy-gate.sh
# @module      policy/gate
# @description Cross-repo policy gate library — source this in automation scripts to enforce
#              repo allowlist, action gates, dry-run first-run, and break-glass audit logging.
#
# Usage:
#   source scripts/lib/automation-policy-gate.sh
#   policy_gate_check <repo> <action_category>
#   policy_gate_audit <repo> <action> <detail>

POLICY_FILE="${AUTOMATION_POLICY_FILE:-$(dirname "${BASH_SOURCE[0]}")/../../config/automation-policy.yml}"
AUDIT_LOG="${AUTOMATION_AUDIT_LOG:-/tmp/automation-audit.log}"
BREAK_GLASS="${AUTOMATION_POLICY_BREAK_GLASS:-0}"
BREAK_GLASS_REASON="${BREAK_GLASS_REASON:-}"
DRY_RUN="${DRY_RUN:-0}"

_policy_log()  { echo "[policy-gate] $*"; }
_policy_warn() { echo "[policy-gate] WARN: $*" >&2; }
_policy_fail() { echo "[policy-gate] BLOCKED: $*" >&2; return 1; }

# Append one line to the audit log
policy_gate_audit() {
  local repo="${1:-unknown}"
  local action="${2:-unknown}"
  local detail="${3:-}"
  local actor="${GITHUB_ACTOR:-${USER:-unknown}}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local line="$ts | actor=$actor | repo=$repo | action=$action | detail=$detail"
  if [[ "$BREAK_GLASS" == "1" ]]; then
    line="$line | BREAK_GLASS=1 | reason=${BREAK_GLASS_REASON:-unspecified}"
  fi
  echo "$line" >> "$AUDIT_LOG"
}

# Determine if a repo is in the allowlist
_repo_allowed() {
  local repo="$1"
  if [[ ! -f "$POLICY_FILE" ]]; then
    _policy_warn "policy file not found: $POLICY_FILE — defaulting to dry-run"
    return 1
  fi
  # Simple grep-based check (avoids yq dependency)
  grep -qF "  ${repo}:" "$POLICY_FILE" 2>/dev/null
}

# Main gate check — call before any mutating action
# Returns 0 (proceed), 1 (blocked)
policy_gate_check() {
  local repo="${1:?policy_gate_check requires repo argument}"
  local action="${2:-mutating}"

  # Break-glass bypass with mandatory reason
  if [[ "$BREAK_GLASS" == "1" ]]; then
    if [[ -z "$BREAK_GLASS_REASON" ]]; then
      _policy_fail "BREAK_GLASS=1 but BREAK_GLASS_REASON is empty — refusing bypass"
      return 1
    fi
    _policy_warn "BREAK_GLASS override for $repo/$action — reason: $BREAK_GLASS_REASON"
    policy_gate_audit "$repo" "$action" "break_glass_bypass"
    return 0
  fi

  # Read-only actions always pass
  if [[ "$action" == "read" ]]; then
    return 0
  fi

  # Dry-run mode: log and skip mutations
  if [[ "$DRY_RUN" == "1" ]]; then
    _policy_log "DRY_RUN: would execute $action on $repo (not applied)"
    policy_gate_audit "$repo" "$action" "dry_run_skip"
    return 1
  fi

  # Check allowlist
  if ! _repo_allowed "$repo"; then
    _policy_warn "$repo is not in the automation allowlist"
    _policy_log "Set AUTOMATION_POLICY_BREAK_GLASS=1 with BREAK_GLASS_REASON to override"
    _policy_log "Or add $repo to config/automation-policy.yml and commit"
    policy_gate_audit "$repo" "$action" "blocked_not_in_allowlist"
    return 1
  fi

  # Allowed — audit and proceed
  policy_gate_audit "$repo" "$action" "allowed"
  return 0
}

# Convenience: enforce gate or exit
policy_gate_require() {
  policy_gate_check "$@" || {
    _policy_fail "action blocked by policy gate — aborting"
    exit 1
  }
}
