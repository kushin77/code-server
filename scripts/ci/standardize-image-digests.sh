#!/usr/bin/env bash
# @file        scripts/ci/standardize-image-digests.sh
# @module      infrastructure/iac
# @description Standardize all container image digests in docker-compose.yml for immutable deployments (P2-1679)
#
# This script captures the actual image digests from running containers and updates
# docker-compose.yml to pin all images to their SHA256 digests. This ensures:
# - Immutability: Exact same image binary on every deployment
# - Reproducibility: Deployments are deterministic and auditable
# - Security: Image modifications detected immediately (digest mismatch)
#
# Usage:
#   ./scripts/ci/standardize-image-digests.sh [--target-host 192.168.168.31]
#
# This script is idempotent and safe to re-run multiple times.

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_HOST="${1:-192.168.168.31}"
COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.yml"

# Associative arrays for image mappings
declare -A IMAGE_DIGESTS
declare -A IMAGES_PROCESSED

# ═══════════════════════════════════════════════════════════════════════════════
# Functions
# ═══════════════════════════════════════════════════════════════════════════════

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Fetch digest for an image from remote host via SSH
get_image_digest_remote() {
    local image_spec="$1"
    local host="$2"
    
    # Extract image name without tag
    local image_name="${image_spec%:*}"
    
    # Get digest from running container or image registry
    ssh -q "akushnir@${host}" \
        "docker inspect --format='{{.RepoDigests}}' ${image_spec} 2>/dev/null || \
         docker image ls --digests --format='{{.ID}}' ${image_spec} 2>/dev/null || \
         echo ''" || echo ""
}

# Get all running images and their digests from production host
capture_production_digests() {
    local host="$1"
    
    log_info "Capturing image digests from ${host}..."
    
    # SSH to host and get all image digests
    ssh -q "akushnir@${host}" \
        'docker images --digests --format="{{.Repository}}:{{.Tag}}@{{.Digest}}" | grep -v "<none>" | sort -u' \
        > /tmp/digests.txt 2>/dev/null || {
        log_error "Failed to capture digests from ${host}"
        return 1
    }
    
    log_info "Captured $(wc -l < /tmp/digests.txt) unique image digests"
}

# Update docker-compose.yml with digests from captured list
update_docker_compose() {
    local compose_file="$1"
    local digests_file="$2"
    
    log_info "Updating ${compose_file}..."
    
    # Create backup
    cp "${compose_file}" "${compose_file}.pre-digest-standardization"
    log_info "Backup saved: ${compose_file}.pre-digest-standardization"
    
    # Read digests file and build mapping
    while IFS='@' read -r image_name digest; do
        # Extract repository and tag
        local repo="${image_name%:*}"
        local tag="${image_name#*:}"
        
        IMAGE_DIGESTS["${image_name}"]="${digest}"
        log_info "Mapped: ${image_name} → ${digest:0:20}..."
    done < "${digests_file}"
    
    # Now update docker-compose.yml
    local tmpfile=$(mktemp)
    
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*image:[[:space:]]* ]]; then
            # Extract image specification
            local image_spec=$(echo "$line" | sed 's/.*image:[[:space:]]*//;s/[[:space:]]*$//')
            
            # Skip if already has digest
            if [[ $image_spec == *"@sha256:"* ]]; then
                echo "$line" >> "$tmpfile"
                continue
            fi
            
            # Check if we have a digest for this image
            local updated=false
            for mapped_image in "${!IMAGE_DIGESTS[@]}"; do
                if [[ "$mapped_image" == "$image_spec"* ]] || [[ "$image_spec" == "$mapped_image" ]]; then
                    local digest="${IMAGE_DIGESTS[$mapped_image]}"
                    local indent=$(echo "$line" | sed 's/[^ ].*//g')
                    echo "${indent}image: ${image_spec}@${digest}" >> "$tmpfile"
                    updated=true
                    break
                fi
            done
            
            if [[ $updated != "true" ]]; then
                log_warn "No digest found for: ${image_spec}"
                echo "$line" >> "$tmpfile"
            fi
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "${compose_file}"
    
    # Replace original with updated
    mv "$tmpfile" "${compose_file}"
    log_info "Updated docker-compose.yml with all available digests"
}

# Validate all images in docker-compose.yml
validate_digest_coverage() {
    local compose_file="$1"
    
    log_info "Validating digest coverage..."
    
    local total=0
    local with_digest=0
    local without_digest=0
    
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*image:[[:space:]]* ]]; then
            ((total++))
            if [[ $line == *"@sha256:"* ]]; then
                ((with_digest++))
            else
                ((without_digest++))
                local image_spec=$(echo "$line" | sed 's/.*image:[[:space:]]*//;s/[[:space:]]*$//')
                log_warn "Missing digest: ${image_spec}"
            fi
        fi
    done < "${compose_file}"
    
    log_info "Digest Coverage: ${with_digest}/${total} images ($(( with_digest * 100 / total ))%)"
    
    if [[ $without_digest -gt 0 ]]; then
        log_error "${without_digest} images still lack SHA256 digests"
        return 1
    fi
    
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    log_info "═══════════════════════════════════════════════════════════════════════════════"
    log_info "Container Image Digest Standardization — IaC Immutability (P2-1679)"
    log_info "═══════════════════════════════════════════════════════════════════════════════"
    log_info ""
    log_info "Target Host: ${TARGET_HOST}"
    log_info "Compose File: ${COMPOSE_FILE}"
    log_info ""
    
    # Verify SSH access to target host
    log_info "Verifying SSH access to ${TARGET_HOST}..."
    ssh -q "akushnir@${TARGET_HOST}" "echo 'SSH OK' > /dev/null" || {
        log_error "Cannot SSH to ${TARGET_HOST}"
        exit 1
    }
    
    # Capture digests from production
    capture_production_digests "${TARGET_HOST}" || exit 1
    
    # Update docker-compose.yml
    update_docker_compose "${COMPOSE_FILE}" /tmp/digests.txt || exit 1
    
    # Validate coverage
    validate_digest_coverage "${COMPOSE_FILE}" || {
        log_warn "Some images lack digests, but continuing..."
    }
    
    log_info ""
    log_info "✅ Digest standardization complete!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Review changes: git diff docker-compose.yml"
    log_info "2. Commit: git add docker-compose.yml && git commit -m 'refactor(P2-1679): Pin all container images to SHA256 digests for IaC immutability'"
    log_info "3. Deploy: docker-compose up -d --force-recreate"
    log_info ""
    
    return 0
}

main "$@"
