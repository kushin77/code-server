#!/usr/bin/env bash
# @file        scripts/governance/reconcile-org-rulesets.sh
# @module      governance/github
# @description Idempotently reconcile repository branch protection against org baseline
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || {
  echo "FATAL: Cannot load _common/init.sh from $SCRIPT_DIR" >&2
  exit 1
}

ORG=""
BASELINE_FILE=""
TARGET_REPO=""
DRY_RUN="false"
WAIVER_REPO="${GOVERNANCE_WAIVER_REPO:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/reconcile-org-rulesets.sh --org <org> --baseline <path> [--repo <name>] [--dry-run]

Examples:
  scripts/governance/reconcile-org-rulesets.sh --org kushin77 --baseline config/github-org-ruleset-baseline.json
  scripts/governance/reconcile-org-rulesets.sh --org kushin77 --baseline config/github-org-ruleset-baseline.json --repo code-server
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      ORG="$2"
      shift 2
      ;;
    --baseline)
      BASELINE_FILE="$2"
      shift 2
      ;;
    --repo)
      TARGET_REPO="$2"
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
      log_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$ORG" || -z "$BASELINE_FILE" ]]; then
  log_error "--org and --baseline are required"
  usage
  exit 1
fi

if [[ -z "$WAIVER_REPO" ]]; then
  WAIVER_REPO="${ORG}/code-server"
fi

require_command "gh" "GitHub CLI required"
require_command "jq" "jq required"

GH_BIN="gh"
if ! command -v "$GH_BIN" >/dev/null 2>&1; then
  if command -v gh.exe >/dev/null 2>&1; then
    GH_BIN="gh.exe"
  else
    log_fatal "GitHub CLI required: gh (or gh.exe) not found"
  fi
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  log_error "Baseline not found: $BASELINE_FILE"
  exit 1
fi

required_checks_json="$(jq -c '.required_status_checks' "$BASELINE_FILE")"
required_reviews="$(jq -r '.required_approving_review_count' "$BASELINE_FILE")"
enforce_admins="$(jq -r '.enforce_admins' "$BASELINE_FILE")"
conv_resolution="$(jq -r '.required_conversation_resolution' "$BASELINE_FILE")"
now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

is_blank_approval_field() {
  local value="$1"
  local compact="${value//[[:space:]]/}"
  local trimmed="$value"
  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [[ -z "$compact" || "$trimmed" == \<*\> || "$trimmed" =~ ^[Tt][Bb][Dd]$ || "$trimmed" =~ ^[Pp]ending$ ]]
}

is_valid_waiver_exception() {
  local repo="$1"
  local exception_json
  local waiver_issue
  local expires_at
  local issue_json
  local state
  local labels
  local body
  local approved_by
  local approval_date
  local approval_signature

  exception_json="$(jq -c --arg repo "$repo" '.exceptions[]? | select(.repo == $repo)' "$BASELINE_FILE" | head -n 1)"
  [[ -z "$exception_json" ]] && return 1

  waiver_issue="$(jq -r '.waiver_issue // 0' <<<"$exception_json")"
  expires_at="$(jq -r '.expires_at // ""' <<<"$exception_json")"

  if [[ "$waiver_issue" -le 0 || -z "$expires_at" || "$expires_at" < "$now_utc" ]]; then
    log_warn "Exception rejected for $repo: waiver_issue/expires_at invalid"
    return 1
  fi

  issue_json="$("$GH_BIN" api repos/"$WAIVER_REPO"/issues/"$waiver_issue" 2>/dev/null || true)"
  if [[ -z "$issue_json" ]]; then
    log_warn "Exception rejected for $repo: waiver issue #$waiver_issue not found in $WAIVER_REPO"
    return 1
  fi

  state="$(jq -r '.state // ""' <<<"$issue_json")"
  labels="$(jq -r '[.labels[].name] | join(",")' <<<"$issue_json")"
  body="$(jq -r '.body // ""' <<<"$issue_json")"
  approved_by="$(printf '%s\n' "$body" | awk 'index($0, "- Approved by: ") == 1 { print substr($0, 16); exit }')"
  approval_date="$(printf '%s\n' "$body" | awk 'index($0, "- Approval date (YYYY-MM-DD): ") == 1 { print substr($0, 31); exit }')"
  approval_signature="$(printf '%s\n' "$body" | awk 'index($0, "- Approval signature (sha256:<64-hex>): ") == 1 { print substr($0, 42); exit }')"

  if [[ "$state" != "open" ]]; then
    log_warn "Exception rejected for $repo: waiver issue #$waiver_issue is not open"
    return 1
  fi

  if [[ ",$labels," != *",waiver,"* || ",$labels," != *",governance,"* ]]; then
    log_warn "Exception rejected for $repo: waiver issue #$waiver_issue missing governance/waiver labels"
    return 1
  fi

  if is_blank_approval_field "$approved_by" || is_blank_approval_field "$approval_date"; then
    log_warn "Exception rejected for $repo: waiver issue #$waiver_issue missing approval metadata"
    return 1
  fi

  if [[ ! "$approval_signature" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
    log_warn "Exception rejected for $repo: waiver issue #$waiver_issue signature is invalid"
    return 1
  fi

  return 0
}

if [[ -n "$TARGET_REPO" ]]; then
  repos="$TARGET_REPO"
else
  repos="$("$GH_BIN" api orgs/"$ORG"/repos --paginate --jq '.[].name')"
fi

processed=0
updated=0
skipped=0

while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  processed=$((processed + 1))

  if jq -e --arg repo "$repo" '.exceptions[]? | select(.repo == $repo)' "$BASELINE_FILE" >/dev/null; then
    if is_valid_waiver_exception "$repo"; then
      log_warn "Skipping exception repo with approved waiver: $repo"
      skipped=$((skipped + 1))
      continue
    fi
    log_warn "Exception present but invalid; enforcing baseline for repo: $repo"
  fi

  default_branch="$("$GH_BIN" api repos/"$ORG"/"$repo" --jq '.default_branch' 2>/dev/null || true)"
  if [[ -z "$default_branch" || "$default_branch" == "null" ]]; then
    log_warn "Unable to resolve default branch for $repo"
    skipped=$((skipped + 1))
    continue
  fi

  protection_payload="$(jq -n \
    --argjson checks "$required_checks_json" \
    --argjson reviews "$required_reviews" \
    --argjson enforce "$enforce_admins" \
    --argjson conv "$conv_resolution" \
    '{
      required_status_checks: { strict: true, contexts: $checks },
      required_pull_request_reviews: { required_approving_review_count: $reviews, dismiss_stale_reviews: true, require_code_owner_reviews: false },
      enforce_admins: $enforce,
      allow_force_pushes: false,
      allow_deletions: false,
      required_conversation_resolution: $conv
    }')"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would reconcile $ORG/$repo@$default_branch"
    continue
  fi

  if "$GH_BIN" api -X PUT repos/"$ORG"/"$repo"/branches/"$default_branch"/protection --input <(printf '%s' "$protection_payload") >/dev/null; then
    log_info "Reconciled: $ORG/$repo@$default_branch"
    updated=$((updated + 1))
  else
    log_warn "Failed to reconcile: $ORG/$repo@$default_branch"
  fi
done <<< "$repos"

log_info "Reconcile summary: processed=$processed updated=$updated skipped=$skipped"
