#!/usr/bin/env bash
# @file        scripts/governance/distribute-policy-bundle.sh
# @module      governance/policy-bundle
# @description Distribute a versioned OPA policy bundle to configured agent endpoints
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

CATALOG_FILE="config/policy-bundles/bundle-catalog.json"
CHANNEL="stable"
DRY_RUN="false"
ENDPOINTS_FILE="config/policy-bundles/distribution-endpoints.json"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/distribute-policy-bundle.sh [--channel <channel>] [--catalog <path>] [--endpoints <path>] [--dry-run]

Environment variables (alternative to endpoints file):
  POLICY_BUNDLE_OPA_URL    - OPA agent base URL (e.g. http://localhost:8181)
  POLICY_BUNDLE_OPA_TOKEN  - Bearer token for OPA agent (optional)

Examples:
  # Distribute stable bundle to all configured endpoints
  scripts/governance/distribute-policy-bundle.sh --channel stable

  # Dry run: show what would be distributed without sending
  scripts/governance/distribute-policy-bundle.sh --channel canary --dry-run

  # Distribute to explicit OPA endpoint
  POLICY_BUNDLE_OPA_URL=http://192.168.168.31:8181 \
    scripts/governance/distribute-policy-bundle.sh --channel stable
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --catalog) CATALOG_FILE="$2"; shift 2 ;;
    --endpoints) ENDPOINTS_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

require_command "jq" "jq is required"
require_command "curl" "curl is required"

if [[ ! -f "$CATALOG_FILE" ]]; then
  log_fatal "Bundle catalog not found: $CATALOG_FILE"
fi

catalog="$(cat "$CATALOG_FILE")"
version="$(jq -r --arg ch "$CHANNEL" '.channels[$ch].version // empty' <<<"$catalog")"
manifest_path="$(jq -r --arg ch "$CHANNEL" '.channels[$ch].bundle_manifest // empty' <<<"$catalog")"

if [[ -z "$version" || -z "$manifest_path" ]]; then
  log_fatal "Channel $CHANNEL not found or incomplete in catalog"
fi

if [[ ! -f "$manifest_path" ]]; then
  log_warn "Bundle manifest not found: $manifest_path (bundle may need to be built first)"
  log_warn "Run: bash scripts/governance/build-policy-bundle.sh --version $version --channel $CHANNEL"
fi

archive_path=""
if [[ -f "$manifest_path" ]]; then
  archive_path="$(jq -r '.archive // empty' <"$manifest_path")"
fi

log_info "Distributing: channel=$CHANNEL version=$version"

# Collect target endpoints
declare -a endpoints=()

# From environment variable (highest precedence)
if [[ -n "${POLICY_BUNDLE_OPA_URL:-}" ]]; then
  endpoints+=("$POLICY_BUNDLE_OPA_URL")
fi

# From endpoints file
if [[ -f "$ENDPOINTS_FILE" ]]; then
  while IFS= read -r ep; do
    endpoints+=("$ep")
  done < <(jq -r --arg ch "$CHANNEL" '.endpoints[]? | select(.channels == null or (.channels | index($ch) != null)) | .url' "$ENDPOINTS_FILE")
fi

if [[ ${#endpoints[@]} -eq 0 ]]; then
  log_warn "No distribution endpoints configured."
  log_warn "Set POLICY_BUNDLE_OPA_URL or create $ENDPOINTS_FILE to configure endpoints."
  log_info "Distribution target model for this deployment:"
  log_info "  On-prem OPA agent: http://\${DEPLOY_HOST:-192.168.168.31}:8181"
  log_info "  Bundle is available as a file artifact at: $manifest_path"
  log_info "  OPA bundle server: mount $archive_path or serve via nginx/Caddy"
  exit 0
fi

success=0
failed=0
now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
AUDIT_LOG="artifacts/policy-bundles/distribution-audit.jsonl"
mkdir -p "$(dirname "$AUDIT_LOG")"

for ep in "${endpoints[@]}"; do
  log_info "Distributing to: $ep"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would POST bundle manifest to ${ep}/v1/data/policy_bundle"
    continue
  fi

  # Build auth header if token provided
  auth_header=""
  if [[ -n "${POLICY_BUNDLE_OPA_TOKEN:-}" ]]; then
    auth_header="Authorization: Bearer ${POLICY_BUNDLE_OPA_TOKEN}"
  fi

  # Distribute manifest metadata to OPA data API
  manifest_json=""
  if [[ -f "$manifest_path" ]]; then
    manifest_json="$(cat "$manifest_path")"
  else
    manifest_json="{\"version\":\"$version\",\"channel\":\"$CHANNEL\",\"distributed_at\":\"$now_utc\"}"
  fi

  http_status=0
  if [[ -n "$auth_header" ]]; then
    http_status="$(curl -s -o /dev/null -w '%{http_code}' \
      -X PUT "${ep}/v1/data/policy_bundle" \
      -H "Content-Type: application/json" \
      -H "$auth_header" \
      --data-raw "{\"result\": $manifest_json}" \
      --max-time 10 || echo "0")"
  else
    http_status="$(curl -s -o /dev/null -w '%{http_code}' \
      -X PUT "${ep}/v1/data/policy_bundle" \
      -H "Content-Type: application/json" \
      --data-raw "{\"result\": $manifest_json}" \
      --max-time 10 || echo "0")"
  fi

  if [[ "$http_status" =~ ^2 ]]; then
    log_info "Distributed to $ep: HTTP $http_status"
    success=$((success + 1))
    jq -nc --arg ts "$now_utc" --arg ep "$ep" --arg ch "$CHANNEL" --arg ver "$version" --arg status "$http_status" \
      '{timestamp: $ts, action: "distribute", endpoint: $ep, channel: $ch, version: $ver, http_status: $status, result: "ok"}' \
      >> "$AUDIT_LOG"
  else
    log_warn "Distribution failed for $ep: HTTP $http_status"
    failed=$((failed + 1))
    jq -nc --arg ts "$now_utc" --arg ep "$ep" --arg ch "$CHANNEL" --arg ver "$version" --arg status "$http_status" \
      '{timestamp: $ts, action: "distribute", endpoint: $ep, channel: $ch, version: $ver, http_status: $status, result: "fail"}' \
      >> "$AUDIT_LOG"
  fi
done

log_info "Distribution summary: success=$success failed=$failed"

if [[ $failed -gt 0 ]]; then
  log_error "Distribution failed for $failed endpoint(s). See $AUDIT_LOG"
  exit 2
fi
