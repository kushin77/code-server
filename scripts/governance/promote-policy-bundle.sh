#!/usr/bin/env bash
# @file        scripts/governance/promote-policy-bundle.sh
# @module      governance/policy-bundle
# @description Promote a policy bundle through channels: canary → stable (or roll back to rollback channel)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

CATALOG_FILE="config/policy-bundles/bundle-catalog.json"
FROM_CHANNEL=""
TO_CHANNEL=""
DRY_RUN="false"
FORCE="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/promote-policy-bundle.sh --from <channel> --to <channel> [--catalog <path>] [--dry-run] [--force]

Channels:
  canary   → stable    : promote canary to stable (normal rollout path)
  stable   → rollback  : capture stable as rollback snapshot before a new deploy
  stable   → canary    : demote (unusual; use --force)
  rollback → stable    : rollback: restore rollback snapshot to stable

Examples:
  # Capture current stable as rollback before deploying new canary
  scripts/governance/promote-policy-bundle.sh --from stable --to rollback

  # Promote canary to stable after validation
  scripts/governance/promote-policy-bundle.sh --from canary --to stable

  # Roll back: restore rollback snapshot to stable
  scripts/governance/promote-policy-bundle.sh --from rollback --to stable

  # Dry run (no file changes)
  scripts/governance/promote-policy-bundle.sh --from canary --to stable --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM_CHANNEL="$2"; shift 2 ;;
    --to) TO_CHANNEL="$2"; shift 2 ;;
    --catalog) CATALOG_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --force) FORCE="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$FROM_CHANNEL" || -z "$TO_CHANNEL" ]]; then
  log_error "--from and --to are required"
  usage
  exit 1
fi

require_command "jq" "jq is required"

VALID_CHANNELS=("stable" "canary" "rollback")
is_valid_channel() {
  local c="$1"
  for v in "${VALID_CHANNELS[@]}"; do
    [[ "$c" == "$v" ]] && return 0
  done
  return 1
}

if ! is_valid_channel "$FROM_CHANNEL"; then
  log_fatal "Invalid from-channel: $FROM_CHANNEL (valid: ${VALID_CHANNELS[*]})"
fi
if ! is_valid_channel "$TO_CHANNEL"; then
  log_fatal "Invalid to-channel: $TO_CHANNEL (valid: ${VALID_CHANNELS[*]})"
fi
if [[ "$FROM_CHANNEL" == "$TO_CHANNEL" ]]; then
  log_fatal "from-channel and to-channel must be different"
fi

# Guard against unusual/risky promotions without --force
if [[ "$FORCE" != "true" ]]; then
  case "${FROM_CHANNEL}->${TO_CHANNEL}" in
    canary->stable|stable->rollback|rollback->stable)
      # Valid promotion paths
      ;;
    *)
      log_fatal "Non-standard promotion path ${FROM_CHANNEL} -> ${TO_CHANNEL}. Use --force to override."
      ;;
  esac
fi

if [[ ! -f "$CATALOG_FILE" ]]; then
  log_fatal "Bundle catalog not found: $CATALOG_FILE"
fi

catalog="$(cat "$CATALOG_FILE")"
from_version="$(jq -r --arg ch "$FROM_CHANNEL" '.channels[$ch].version // empty' <<<"$catalog")"
from_manifest="$(jq -r --arg ch "$FROM_CHANNEL" '.channels[$ch].bundle_manifest // empty' <<<"$catalog")"

if [[ -z "$from_version" || -z "$from_manifest" ]]; then
  log_fatal "Channel $FROM_CHANNEL not found or incomplete in catalog: $CATALOG_FILE"
fi

log_info "Promoting: ${FROM_CHANNEL} v${from_version} → ${TO_CHANNEL}"
log_info "Manifest: $from_manifest"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY RUN] Would update $CATALOG_FILE: channels.${TO_CHANNEL}.version = ${from_version}, channels.${TO_CHANNEL}.bundle_manifest = ${from_manifest}"
  exit 0
fi

now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
updated_catalog="$(jq \
  --arg ch "$TO_CHANNEL" \
  --arg ver "$from_version" \
  --arg mf "$from_manifest" \
  --arg ts "$now_utc" \
  '.channels[$ch].version = $ver
  | .channels[$ch].bundle_manifest = $mf
  | .updated_at = $ts' \
  <<<"$catalog")"

tmp_catalog="$(mktemp)"
trap 'rm -f "$tmp_catalog"' EXIT

printf '%s\n' "$updated_catalog" > "$tmp_catalog"
mv "$tmp_catalog" "$CATALOG_FILE"

log_info "Catalog updated: ${TO_CHANNEL} → v${from_version}"

# Append promotion event to audit log
AUDIT_LOG="artifacts/policy-bundles/promotion-audit.jsonl"
mkdir -p "$(dirname "$AUDIT_LOG")"
jq -nc \
  --arg ts "$now_utc" \
  --arg from "$FROM_CHANNEL" \
  --arg to "$TO_CHANNEL" \
  --arg ver "$from_version" \
  --arg mf "$from_manifest" \
  '{timestamp: $ts, action: "promote", from_channel: $from, to_channel: $to, version: $ver, manifest: $mf}' \
  >> "$AUDIT_LOG"

log_info "Promotion audit logged: $AUDIT_LOG"
log_info "Done: ${FROM_CHANNEL} v${from_version} promoted to ${TO_CHANNEL}"
