#!/usr/bin/env bash
# @file        scripts/register-google-workspace-domain.sh
# @module      workspace/domain-setup
# @description Register kushnir.cloud domain in Google Workspace with DNS verification

set -euo pipefail

readonly GODADDY_API="https://api.godaddy.com/v1"
readonly DOMAIN="${DOMAIN:-kushnir.cloud}"

VERIFICATION_VALUE=""
DRY_RUN=0

log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "✓ $*" >&2
}

validate_credentials() {
    if [[ -z "${GODADDY_KEY:-}" ]]; then
        log_error "GODADDY_KEY not set. Run: source scripts/fetch-gsm-secrets.sh"
        return 1
    fi
    
    if [[ -z "${GODADDY_SECRET:-}" ]]; then
        log_error "GODADDY_SECRET not set. Run: source scripts/fetch-gsm-secrets.sh"
        return 1
    fi
    
    log_success "GoDaddy credentials loaded"
    return 0
}

add_txt_record() {
    local domain="$1"
    local txt_value="$2"
    local ttl="${3:-3600}"
    local auth="sso-key ${GODADDY_KEY}:${GODADDY_SECRET}"
    
    log_info "Adding TXT record for Google Workspace domain verification..."
    log_info "Domain: ${domain}"
    log_info "Value: ${txt_value}"
    log_info "TTL: ${ttl}"
    
    if [[ "${DRY_RUN}" == "1" ]]; then
        log_info "DRY RUN: Would add TXT record"
        return 0
    fi
    
    local payload=$(cat <<EOF
[
  {
    "name": "@",
    "type": "TXT",
    "data": "${txt_value}",
    "ttl": ${ttl}
  }
]
EOF
)
    
    log_info "Sending to GoDaddy API..."
    curl -sf -X PUT \
        -H "Authorization: ${auth}" \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        "${GODADDY_API}/domains/${domain}/records/TXT" || {
        log_error "Failed to add TXT record"
        return 1
    }
    
    log_success "TXT record added successfully"
    return 0
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verification-value) VERIFICATION_VALUE="$2"; shift 2 ;;
            --dry-run) DRY_RUN=1; shift ;;
            --help) echo "Usage: $0 --verification-value VALUE"; exit 0 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    log_info "Google Workspace Domain Registration Script"
    
    if ! validate_credentials; then
        exit 1
    fi
    
    if [[ -z "${VERIFICATION_VALUE}" ]]; then
        log_info "No verification value provided. Get one from Google Workspace Admin Console then run:"
        log_info "$0 --verification-value \"google-site-verification=VALUE\""
        exit 0
    fi
    
    if add_txt_record "${DOMAIN}" "${VERIFICATION_VALUE}" 3600; then
        log_success "DNS configuration complete"
        log_info "Next: Go to admin.google.com and click 'Verify' to complete domain registration"
        return 0
    else
        log_error "Failed to add TXT record"
        exit 1
    fi
}

main "$@"
