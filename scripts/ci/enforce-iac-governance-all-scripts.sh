#!/usr/bin/env bash
# @file        scripts/ci/enforce-iac-governance-all-scripts.sh
# @module      ci/governance
# @description Apply IaC governance headers to all scripts missing them
#
# IaC Principles:
# - Immutable: Script templates frozen for consistent application
# - Idempotent: Re-running adds no duplicate headers
# - Versioned: All scripts get versioning headers for audit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

log_info "Enforcing IaC governance headers on all scripts..."

# Add headers to CI scripts
add_governance_header_to_script() {
    local script_file=$1
    local module_path=$2
    local description=$3
    
    # Check if header already exists
    if head -5 "$script_file" | grep -q "@file"; then
        log_debug "Skipping $script_file (header already present)"
        return 0
    fi
    
    # Create temp file with new header
    local temp_file="${script_file}.tmp"
    {
        echo "#!/usr/bin/env bash"
        echo "# @file        $script_file"
        echo "# @module      $module_path"
        echo "# @description $description"
        echo "#"
        tail -n +2 "$script_file"
    } > "$temp_file"
    
    mv "$temp_file" "$script_file"
    chmod +x "$script_file"
    log_info "✅ Added header to $script_file"
}

# CI Scripts
log_info "Processing CI scripts..."
add_governance_header_to_script "${SCRIPT_DIR}/scripts/ci/check-code-smells.sh" "ci/quality" "Code smell detection and reporting"
add_governance_header_to_script "${SCRIPT_DIR}/scripts/ci/check-copilot-session-compliance.sh" "ci/governance" "Verify Copilot session initialization compliance"
add_governance_header_to_script "${SCRIPT_DIR}/scripts/ci/check-metadata-headers.sh" "ci/governance" "Verify all scripts have proper metadata headers"
add_governance_header_to_script "${SCRIPT_DIR}/scripts/ci/check-no-hardcoded-credentials.sh" "ci/security" "Detect hardcoded secrets and credentials"
add_governance_header_to_script "${SCRIPT_DIR}/scripts/ci/check-image-immutability.sh" "ci/images" "Verify Docker images use SHA256 digests"
add_governance_header_to_script "${SCRIPT_DIR}/scripts/ci/check-policy-ssot.sh" "ci/policy" "Validate configuration single source of truth"
add_governance_header_to_script "${SCRIPT_DIR}/scripts/ci/enforce-global-dedup.sh" "ci/dedup" "Enforce no-duplication rule across codebase"

log_info "✅ IaC governance header enforcement complete"
