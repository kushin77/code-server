#!/usr/bin/env bash
# @file        scripts/setup-cloudflare-access.sh
# @module      operations/cloudflare
# @description configure Cloudflare Access policies for portal and IDE domains in an idempotent way
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
IDE_DOMAIN="${IDE_DOMAIN:-ide.kushnir.cloud}"
PORTAL_DOMAIN="${PORTAL_DOMAIN:-kushnir.cloud}"
SESSION_DURATION="${SESSION_DURATION:-24h}"

API_BASE="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}"

require_runtime() {
  if [[ -z "$CLOUDFLARE_ACCOUNT_ID" || -z "$CLOUDFLARE_API_TOKEN" ]]; then
    log_warn "Skipping Cloudflare Access setup: CLOUDFLARE_ACCOUNT_ID/CLOUDFLARE_API_TOKEN not set"
    return 1
  fi
  return 0
}

api_get() {
  local path="$1"
  curl -fsS -X GET "${API_BASE}${path}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json"
}

api_post() {
  local path="$1"
  local payload="$2"
  curl -fsS -X POST "${API_BASE}${path}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload"
}

api_put() {
  local path="$1"
  local payload="$2"
  curl -fsS -X PUT "${API_BASE}${path}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$payload"
}

find_app_id_by_domain() {
  local domain="$1"
  api_get "/access/apps" | jq -r --arg d "$domain" '.result[] | select(.domain == $d) | .id' | head -n1
}

ensure_access_app() {
  local domain="$1"
  local app_name="$2"
  local app_id

  app_id="$(find_app_id_by_domain "$domain")"
  if [[ -n "$app_id" ]]; then
    log_info "Access app exists for ${domain}: ${app_id}"
    return 0
  fi

  local payload
  payload="$(jq -n \
    --arg name "$app_name" \
    --arg domain "$domain" \
    --arg session "$SESSION_DURATION" \
    '{name:$name, domain:$domain, type:"self_hosted", session_duration:$session}')"

  api_post "/access/apps" "$payload" >/dev/null
  log_info "Created Access app for ${domain}"
}

ensure_default_allow_policy() {
  local domain="$1"
  local app_id
  app_id="$(find_app_id_by_domain "$domain")"

  if [[ -z "$app_id" ]]; then
    log_warn "Cannot create Access policy, app not found for ${domain}"
    return 0
  fi

  local existing
  existing="$(api_get "/access/apps/${app_id}/policies" | jq -r '.result[]? | select(.name=="Allow Authenticated Emails") | .id' | head -n1)"

  local payload
  payload='{"name":"Allow Authenticated Emails","precedence":1,"decision":"allow","include":[{"email_domain":{"domain":"*"}}]}'

  if [[ -n "$existing" ]]; then
    api_put "/access/apps/${app_id}/policies/${existing}" "$payload" >/dev/null
    log_info "Updated Access policy for ${domain}"
  else
    api_post "/access/apps/${app_id}/policies" "$payload" >/dev/null
    log_info "Created Access policy for ${domain}"
  fi
}

main() {
  require_command curl
  require_command jq

  if ! require_runtime; then
    exit 0
  fi

  log_info "Reconciling Cloudflare Access apps and baseline policies"
  ensure_access_app "$IDE_DOMAIN" "Code Server IDE"
  ensure_access_app "$PORTAL_DOMAIN" "Code Server Portal"

  ensure_default_allow_policy "$IDE_DOMAIN"
  ensure_default_allow_policy "$PORTAL_DOMAIN"

  log_info "Cloudflare Access setup completed"
}

main "$@"
