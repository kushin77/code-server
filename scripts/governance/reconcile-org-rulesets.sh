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

require_command "gh" "GitHub CLI required"
require_command "jq" "jq required"

if [[ ! -f "$BASELINE_FILE" ]]; then
  log_error "Baseline not found: $BASELINE_FILE"
  exit 1
fi

required_checks_json="$(jq -c '.required_status_checks' "$BASELINE_FILE")"
required_reviews="$(jq -r '.required_approving_review_count' "$BASELINE_FILE")"
enforce_admins="$(jq -r '.enforce_admins' "$BASELINE_FILE")"
conv_resolution="$(jq -r '.required_conversation_resolution' "$BASELINE_FILE")"

if [[ -n "$TARGET_REPO" ]]; then
  repos="$TARGET_REPO"
else
  repos="$(gh api orgs/"$ORG"/repos --paginate --jq '.[].name')"
fi

processed=0
updated=0
skipped=0

while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue
  processed=$((processed + 1))

  if jq -e --arg repo "$repo" '.exceptions[]? | select(.repo == $repo)' "$BASELINE_FILE" >/dev/null; then
    log_warn "Skipping exception repo: $repo"
    skipped=$((skipped + 1))
    continue
  fi

  default_branch="$(gh api repos/"$ORG"/"$repo" --jq '.default_branch' 2>/dev/null || true)"
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

  if gh api -X PUT repos/"$ORG"/"$repo"/branches/"$default_branch"/protection --input <(printf '%s' "$protection_payload") >/dev/null; then
    log_info "Reconciled: $ORG/$repo@$default_branch"
    updated=$((updated + 1))
  else
    log_warn "Failed to reconcile: $ORG/$repo@$default_branch"
  fi
done <<< "$repos"

log_info "Reconcile summary: processed=$processed updated=$updated skipped=$skipped"
