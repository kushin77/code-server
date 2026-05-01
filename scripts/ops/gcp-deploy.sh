#!/bin/bash

################################################################################
# GCP Infrastructure Deployment via REST API
#
# Purpose: Deploy code-server infrastructure to Google Cloud Platform using
#          curl-based REST API calls (no gcloud CLI dependency)
#
# Usage:
#   export GCP_PROJECT_ID="my-project-id"
#   export GCP_CREDENTIALS_JSON="/path/to/service-account.json"
#   export GCP_ZONE="us-central1-a"
#   export GCP_MACHINE_TYPE="e2-standard-4"
#   bash scripts/ops/gcp-deploy.sh [list|create|delete|status|validate]
#
# Requirements:
#   - curl
#   - jq
#   - GCP service account with Compute, Storage permissions
#   - GCP_PROJECT_ID, GCP_CREDENTIALS_JSON environment variables
#
################################################################################

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"
readonly TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# GCP Configuration
readonly GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
readonly GCP_CREDENTIALS_JSON="${GCP_CREDENTIALS_JSON:-}"
readonly GCP_ZONE="${GCP_ZONE:-us-central1-a}"
readonly GCP_REGION="${GCP_ZONE%-*}"
readonly GCP_MACHINE_TYPE="${GCP_MACHINE_TYPE:-e2-standard-4}"
readonly GCP_IMAGE_FAMILY="${GCP_IMAGE_FAMILY:-ubuntu-2204-lts}"
readonly GCP_IMAGE_PROJECT="${GCP_IMAGE_PROJECT:-ubuntu-os-cloud}"

# Code-server configuration
readonly INSTANCE_NAME_PREFIX="code-server"
readonly INSTANCE_PRIMARY="${INSTANCE_NAME_PREFIX}-primary"
readonly INSTANCE_REPLICA="${INSTANCE_NAME_PREFIX}-replica"
readonly DISK_SIZE_GB="${DISK_SIZE_GB:-100}"
readonly NETWORK_NAME="code-server-network"
readonly FIREWALL_RULE="code-server-firewall"

# API endpoints
readonly GCP_API_ENDPOINT="https://compute.googleapis.com/compute/v1/projects"
readonly GCP_STORAGE_ENDPOINT="https://storage.googleapis.com/storage/v1/b"

# Temporary files
readonly TEMP_DIR="/tmp/gcp-deploy-$$"
readonly ACCESS_TOKEN_FILE="${TEMP_DIR}/access-token.txt"
readonly OPERATION_STATUS_FILE="${TEMP_DIR}/operation-status.json"

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo "[${TIMESTAMP}] [INFO] $*" >&2
}

log_warn() {
    echo "[${TIMESTAMP}] [WARN] $*" >&2
}

log_error() {
    echo "[${TIMESTAMP}] [ERROR] $*" >&2
}

log_success() {
    echo "[${TIMESTAMP}] [SUCCESS] $*" >&2
}

################################################################################
# Cleanup & Error Handling
################################################################################

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed at line $LINENO with exit code $exit_code"
    fi
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
    return $exit_code
}

trap 'cleanup' EXIT
trap 'log_error "Script interrupted"; exit 130' INT TERM

################################################################################
# Validation Functions
################################################################################

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    for cmd in curl jq base64; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    
    # Check required environment variables
    if [[ -z "$GCP_PROJECT_ID" ]]; then
        log_error "GCP_PROJECT_ID environment variable not set"
        return 1
    fi
    
    if [[ -z "$GCP_CREDENTIALS_JSON" ]]; then
        log_error "GCP_CREDENTIALS_JSON environment variable not set"
        return 1
    fi
    
    if [[ ! -f "$GCP_CREDENTIALS_JSON" ]]; then
        log_error "Service account credentials file not found: $GCP_CREDENTIALS_JSON"
        return 1
    fi
    
    log_success "All prerequisites validated"
    return 0
}

################################################################################
# GCP Authentication
################################################################################

get_access_token() {
    log_info "Obtaining GCP access token..."
    
    mkdir -p "${TEMP_DIR}"
    
    # Extract service account details
    local client_email
    local private_key
    local private_key_id
    
    client_email=$(jq -r '.client_email' "$GCP_CREDENTIALS_JSON")
    private_key=$(jq -r '.private_key' "$GCP_CREDENTIALS_JSON")
    private_key_id=$(jq -r '.private_key_id' "$GCP_CREDENTIALS_JSON")
    
    # Create JWT header and payload
    local now
    now=$(date +%s)
    local expiry=$((now + 3600))
    
    local header
    header=$(echo '{"alg":"RS256","typ":"JWT","kid":"'"$private_key_id"'"}' | base64 -w0 | tr '+/' '-_' | tr -d '=')
    
    local payload
    payload=$(echo "{
        \"iss\":\"$client_email\",
        \"scope\":\"https://www.googleapis.com/auth/cloud-platform\",
        \"aud\":\"https://oauth2.googleapis.com/token\",
        \"exp\":$expiry,
        \"iat\":$now
    }" | base64 -w0 | tr '+/' '-_' | tr -d '=')
    
    # Create JWT signature
    local message="${header}.${payload}"
    local signature
    signature=$(echo -n "$message" | \
        openssl dgst -sha256 -sign <(echo "$private_key") | \
        base64 -w0 | tr '+/' '-_' | tr -d '=')
    
    local jwt="${message}.${signature}"
    
    # Exchange JWT for access token
    local response
    response=$(curl -s -X POST https://oauth2.googleapis.com/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt")
    
    local access_token
    access_token=$(echo "$response" | jq -r '.access_token')
    
    if [[ -z "$access_token" ]] || [[ "$access_token" == "null" ]]; then
        log_error "Failed to obtain access token: $response"
        return 1
    fi
    
    echo "$access_token" > "$ACCESS_TOKEN_FILE"
    log_success "Access token obtained (expires in 1 hour)"
    return 0
}

get_current_access_token() {
    if [[ ! -f "$ACCESS_TOKEN_FILE" ]]; then
        get_access_token || return 1
    fi
    cat "$ACCESS_TOKEN_FILE"
}

################################################################################
# GCP API Functions
################################################################################

gcp_api_call() {
    local method=$1
    local api_path=$2
    local data=${3:-}
    
    local access_token
    access_token=$(get_current_access_token) || return 1
    
    local url="${GCP_API_ENDPOINT}/${GCP_PROJECT_ID}${api_path}"
    local curl_opts=(
        -s
        -X "$method"
        -H "Authorization: Bearer $access_token"
        -H "Content-Type: application/json"
    )
    
    if [[ -n "$data" ]]; then
        curl_opts+=(-d "$data")
    fi
    
    curl "${curl_opts[@]}" "$url"
}

gcp_storage_api_call() {
    local method=$1
    local bucket=$2
    local object=${3:-}
    
    local access_token
    access_token=$(get_current_access_token) || return 1
    
    local url="${GCP_STORAGE_ENDPOINT}/${GCP_PROJECT_ID}-${bucket}"
    if [[ -n "$object" ]]; then
        url="${url}/o/${object}"
    fi
    
    local curl_opts=(
        -s
        -X "$method"
        -H "Authorization: Bearer $access_token"
        -H "Content-Type: application/json"
    )
    
    curl "${curl_opts[@]}" "$url"
}

################################################################################
# Instance Management
################################################################################

get_image_id() {
    log_info "Looking up GCP image ID for $GCP_IMAGE_FAMILY..."
    
    local response
    response=$(curl -s "https://compute.googleapis.com/compute/v1/projects/${GCP_IMAGE_PROJECT}/global/images" \
        -H "Authorization: Bearer $(get_current_access_token)")
    
    local image_id
    image_id=$(echo "$response" | jq -r \
        ".images[] | select(.name | startswith(\"${GCP_IMAGE_FAMILY}\")) | .selfLink" | \
        head -1)
    
    if [[ -z "$image_id" ]]; then
        log_error "Image not found: $GCP_IMAGE_FAMILY in $GCP_IMAGE_PROJECT"
        return 1
    fi
    
    echo "$image_id"
}

create_network() {
    log_info "Creating VPC network: $NETWORK_NAME..."
    
    local payload
    payload=$(cat <<EOF
{
  "name": "$NETWORK_NAME",
  "autoCreateSubnetworks": true,
  "description": "Network for code-server cluster"
}
EOF
)
    
    local response
    response=$(gcp_api_call POST "/global/networks" "$payload")
    
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        log_warn "Network creation error (may already exist): $(echo "$response" | jq -r '.error.message')"
        return 0
    fi
    
    log_success "Network created: $NETWORK_NAME"
    return 0
}

create_firewall_rule() {
    log_info "Creating firewall rule: $FIREWALL_RULE..."
    
    local payload
    payload=$(cat <<EOF
{
  "name": "$FIREWALL_RULE",
  "network": "projects/$GCP_PROJECT_ID/global/networks/$NETWORK_NAME",
  "priority": 1000,
  "sourceRanges": ["0.0.0.0/0"],
  "allowed": [
    {"IPProtocol": "tcp", "ports": ["22", "80", "443", "8101", "8004", "8040", "8060"]},
    {"IPProtocol": "udp", "ports": ["53"]}
  ],
  "description": "Allow code-server services and SSH"
}
EOF
)
    
    local response
    response=$(gcp_api_call POST "/global/firewalls" "$payload")
    
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        log_warn "Firewall rule creation error (may already exist): $(echo "$response" | jq -r '.error.message')"
        return 0
    fi
    
    log_success "Firewall rule created: $FIREWALL_RULE"
    return 0
}

create_instance() {
    local instance_name=$1
    local zone=${2:-$GCP_ZONE}
    
    log_info "Creating instance: $instance_name in zone $zone..."
    
    local image_link
    image_link=$(get_image_id) || return 1
    
    local payload
    payload=$(cat <<EOF
{
  "name": "$instance_name",
  "machineType": "projects/$GCP_PROJECT_ID/zones/$zone/machineTypes/$GCP_MACHINE_TYPE",
  "zone": "projects/$GCP_PROJECT_ID/zones/$zone",
  "disks": [
    {
      "boot": true,
      "initializeParams": {
        "sourceImage": "$image_link",
        "diskSizeGb": $DISK_SIZE_GB,
        "diskType": "projects/$GCP_PROJECT_ID/zones/$zone/diskTypes/pd-standard"
      },
      "autoDelete": true
    }
  ],
  "networkInterfaces": [
    {
      "network": "projects/$GCP_PROJECT_ID/global/networks/$NETWORK_NAME",
      "accessConfigs": [{"type": "ONE_TO_ONE_NAT"}]
    }
  ],
  "tags": {"items": ["code-server", "http-server", "https-server"]},
  "metadata": {
    "items": [
      {"key": "enable-oslogin", "value": "TRUE"},
      {"key": "block-project-ssh-keys", "value": "FALSE"}
    ]
  },
  "serviceAccounts": [
    {
      "email": "default@appspot.gserviceaccount.com",
      "scopes": ["https://www.googleapis.com/auth/cloud-platform"]
    }
  ]
}
EOF
)
    
    local response
    response=$(gcp_api_call POST "/zones/$zone/instances" "$payload")
    
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        log_error "Instance creation failed: $(echo "$response" | jq -r '.error.message')"
        return 1
    fi
    
    local operation_name
    operation_name=$(echo "$response" | jq -r '.name')
    
    log_info "Instance creation initiated: $operation_name"
    wait_for_operation "$operation_name" "$zone" || return 1
    
    log_success "Instance created: $instance_name"
    return 0
}

delete_instance() {
    local instance_name=$1
    local zone=${2:-$GCP_ZONE}
    
    log_info "Deleting instance: $instance_name..."
    
    local response
    response=$(gcp_api_call DELETE "/zones/$zone/instances/$instance_name")
    
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        log_error "Instance deletion failed: $(echo "$response" | jq -r '.error.message')"
        return 1
    fi
    
    local operation_name
    operation_name=$(echo "$response" | jq -r '.name')
    
    wait_for_operation "$operation_name" "$zone" || return 1
    
    log_success "Instance deleted: $instance_name"
    return 0
}

get_instance_info() {
    local instance_name=$1
    local zone=${2:-$GCP_ZONE}
    
    local response
    response=$(gcp_api_call GET "/zones/$zone/instances/$instance_name")
    
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        log_error "Failed to get instance info: $(echo "$response" | jq -r '.error.message')"
        return 1
    fi
    
    echo "$response"
}

list_instances() {
    log_info "Listing instances in zone $GCP_ZONE..."
    
    local response
    response=$(gcp_api_call GET "/zones/$GCP_ZONE/instances")
    
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        log_error "Failed to list instances: $(echo "$response" | jq -r '.error.message')"
        return 1
    fi
    
    echo "$response" | jq -r '.items[] | "\(.name)\t\(.status)\t\(.machineType | split("/") | .[-1])\t\(.networkInterfaces[0].accessConfigs[0].natIP // "INTERNAL")"'
    return 0
}

################################################################################
# Operation Monitoring
################################################################################

wait_for_operation() {
    local operation_name=$1
    local zone=$2
    local max_wait=300  # 5 minutes
    local elapsed=0
    local interval=5
    
    log_info "Waiting for operation: $operation_name (max ${max_wait}s)..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        local response
        response=$(curl -s \
            -H "Authorization: Bearer $(get_current_access_token)" \
            "${GCP_API_ENDPOINT}/${GCP_PROJECT_ID}/zones/${zone}/operations/${operation_name}")
        
        local status
        status=$(echo "$response" | jq -r '.status')
        
        if [[ "$status" == "DONE" ]]; then
            local error_code
            error_code=$(echo "$response" | jq -r '.error.errors[0].code // "NONE"')
            
            if [[ "$error_code" != "NONE" ]]; then
                log_error "Operation failed with code $error_code"
                return 1
            fi
            
            log_success "Operation completed successfully"
            return 0
        fi
        
        log_info "Operation status: $status (elapsed: ${elapsed}s)"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    log_error "Operation timed out after ${max_wait}s"
    return 1
}

################################################################################
# Storage Functions
################################################################################

create_bucket() {
    local bucket_name="${GCP_PROJECT_ID}-code-server-artifacts"
    
    log_info "Creating storage bucket: $bucket_name..."
    
    local payload
    payload=$(cat <<EOF
{
  "name": "$bucket_name",
  "location": "$GCP_REGION",
  "storageClass": "STANDARD"
}
EOF
)
    
    local response
    response=$(gcp_storage_api_call POST "$bucket_name" "")
    
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        log_warn "Bucket creation error (may already exist): $(echo "$response" | jq -r '.error.message')"
        return 0
    fi
    
    log_success "Bucket created: $bucket_name"
    return 0
}

################################################################################
# Main Operations
################################################################################

cmd_list() {
    log_info "Listing code-server instances..."
    list_instances || return 1
}

cmd_create() {
    log_info "Creating code-server infrastructure on GCP..."
    
    validate_prerequisites || return 1
    create_network || return 1
    create_firewall_rule || return 1
    create_bucket || return 1
    
    log_info "Creating PRIMARY instance..."
    create_instance "$INSTANCE_PRIMARY" "$GCP_ZONE" || return 1
    
    log_info "Creating REPLICA instance..."
    create_instance "$INSTANCE_REPLICA" "$GCP_ZONE" || return 1
    
    log_success "All infrastructure created successfully"
    list_instances || return 1
}

cmd_delete() {
    log_warn "Deleting code-server infrastructure on GCP..."
    
    validate_prerequisites || return 1
    
    delete_instance "$INSTANCE_PRIMARY" "$GCP_ZONE" || return 1
    delete_instance "$INSTANCE_REPLICA" "$GCP_ZONE" || return 1
    
    log_success "All instances deleted"
}

cmd_status() {
    log_info "Getting code-server instance status..."
    
    validate_prerequisites || return 1
    
    echo "=== PRIMARY Instance ==="
    get_instance_info "$INSTANCE_PRIMARY" "$GCP_ZONE" | jq '{name, status, machineType, zone, externalIP: .networkInterfaces[0].accessConfigs[0].natIP}' || return 1
    
    echo ""
    echo "=== REPLICA Instance ==="
    get_instance_info "$INSTANCE_REPLICA" "$GCP_ZONE" | jq '{name, status, machineType, zone, externalIP: .networkInterfaces[0].accessConfigs[0].natIP}' || return 1
}

cmd_validate() {
    log_info "Validating GCP deployment configuration..."
    
    validate_prerequisites || return 1
    
    log_success "All validations passed"
    echo ""
    echo "Configuration:"
    echo "  Project ID: $GCP_PROJECT_ID"
    echo "  Zone: $GCP_ZONE"
    echo "  Machine Type: $GCP_MACHINE_TYPE"
    echo "  Image Family: $GCP_IMAGE_FAMILY"
    echo "  Network: $NETWORK_NAME"
    echo "  Firewall Rule: $FIREWALL_RULE"
}

################################################################################
# Main Entry Point
################################################################################

main() {
    local command=${1:-list}
    
    case "$command" in
        list)
            cmd_list
            ;;
        create)
            cmd_create
            ;;
        delete)
            cmd_delete
            ;;
        status)
            cmd_status
            ;;
        validate)
            cmd_validate
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Usage: $SCRIPT_NAME [list|create|delete|status|validate]"
            return 1
            ;;
    esac
}

main "$@"
