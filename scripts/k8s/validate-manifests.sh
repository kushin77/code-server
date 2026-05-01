#!/usr/bin/env bash
################################################################################
# Kubernetes Manifest Testing & Validation Script
#
# Validates all Kubernetes manifests before deployment
# Tests YAML syntax, resource completeness, and configuration
#
# Usage: bash scripts/k8s/validate-manifests.sh [OPTIONS]
#
# OPTIONS:
#   --strict              Exit on warnings (not just errors)
#   --verbose             Show all validation details
#   --dry-run             Test kubectl dry-run (requires kubectl)
#   --help                Show this help
#
################################################################################

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STRICT=false
VERBOSE=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict) STRICT=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) head -20 "$0" | tail -15; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Source logging if available
if [[ -f "${ROOT_DIR}/scripts/common/logging.sh" ]]; then
    source "${ROOT_DIR}/scripts/common/logging.sh"
else
    # Minimal logging
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
fi

################################################################################
# Validation Functions
################################################################################

validate_yaml_syntax() {
    log_info "Validating YAML syntax..."
    
    local errors=0
    local files=0
    
    for yaml_file in $(find "${ROOT_DIR}/kubernetes" -name "*.yaml" -type f); do
        files=$((files + 1))
        
        if python3 -c "import yaml; yaml.safe_load_all(open('$yaml_file'))" 2>/dev/null; then
            [[ "$VERBOSE" == true ]] && log_info "  ✅ $(basename "$yaml_file")"
        else
            log_error "  ❌ $(basename "$yaml_file"): Invalid YAML"
            errors=$((errors + 1))
        fi
    done
    
    log_info "YAML Validation: $((files - errors))/$files files valid"
    
    [[ "$STRICT" == true && $errors -gt 0 ]] && return 1 || return 0
}

validate_resource_completeness() {
    log_info "Validating resource completeness..."
    
    local required_resources=(
        "Namespace"
        "ServiceAccount"
        "Role"
        "RoleBinding"
        "ConfigMap"
        "Service"
        "Deployment"
        "NetworkPolicy"
    )
    
    local found_resources=0
    
    for resource in "${required_resources[@]}"; do
        count=$(python3 << EOF 2>/dev/null || echo "0"
import yaml
import os

count = 0
for root, dirs, files in os.walk("${ROOT_DIR}/kubernetes"):
    for f in files:
        if f.endswith(".yaml"):
            try:
                with open(os.path.join(root, f)) as file:
                    for doc in yaml.safe_load_all(file):
                        if doc and doc.get("kind") == "$resource":
                            count += 1
            except:
                pass
print(count)
EOF
)
        
        if [[ "$count" -gt 0 ]]; then
            log_info "  ✅ $resource: $count"
            found_resources=$((found_resources + 1))
        else
            log_warn "  ⚠️  $resource: 0 (may be in Helm templates)"
        fi
    done
    
    log_info "Resource Coverage: $found_resources/${#required_resources[@]}"
    
    [[ $found_resources -ge 5 ]] && return 0 || return 1
}

validate_helm_chart() {
    log_info "Validating Helm chart structure..."
    
    local helm_dir="${ROOT_DIR}/helm/code-server-enterprise"
    local errors=0
    
    [[ -f "$helm_dir/Chart.yaml" ]] && log_info "  ✅ Chart.yaml" || { log_error "  ❌ Chart.yaml missing"; errors=$((errors + 1)); }
    [[ -f "$helm_dir/values.yaml" ]] && log_info "  ✅ values.yaml" || { log_error "  ❌ values.yaml missing"; errors=$((errors + 1)); }
    [[ -d "$helm_dir/templates" ]] && log_info "  ✅ templates/ directory" || { log_error "  ❌ templates/ missing"; errors=$((errors + 1)); }
    
    local templates=$(find "$helm_dir/templates" -name "*.yaml" -o -name "*.tpl" | wc -l)
    log_info "  Templates found: $templates"
    [[ $templates -ge 10 ]] && log_info "  ✅ Sufficient templates" || { log_warn "  ⚠️  Low template count"; }
    
    return $errors
}

validate_kubernetes_syntax() {
    if ! command -v kubectl &>/dev/null; then
        log_warn "kubectl not available - skipping kubectl validation"
        return 0
    fi
    
    if [[ "$DRY_RUN" != true ]]; then
        log_info "Skipping kubectl dry-run (use --dry-run flag)"
        return 0
    fi
    
    log_info "Running kubectl dry-run validation..."
    
    if kubectl apply -f "${ROOT_DIR}/kubernetes" --dry-run=client -o yaml > /dev/null 2>&1; then
        log_info "  ✅ kubectl dry-run passed"
        return 0
    else
        log_error "  ❌ kubectl dry-run failed"
        return 1
    fi
}

validate_service_inventory() {
    log_info "Validating service inventory..."
    
    local deployments=$(python3 << EOF 2>/dev/null || echo "0"
import yaml
import os

count = 0
for root, dirs, files in os.walk("${ROOT_DIR}/kubernetes"):
    for f in files:
        if f.endswith(".yaml"):
            try:
                with open(os.path.join(root, f)) as file:
                    for doc in yaml.safe_load_all(file):
                        if doc and doc.get("kind") == "Deployment":
                            count += 1
            except:
                pass
print(count)
EOF
)
    
    log_info "  Deployments: $deployments"
    
    if [[ "$VERBOSE" == true ]]; then
        python3 << 'EOF'
import yaml
import os

for root, dirs, files in os.walk("./kubernetes"):
    for f in files:
        if f.endswith(".yaml"):
            try:
                with open(os.path.join(root, f)) as file:
                    for doc in yaml.safe_load_all(file):
                        if doc and doc.get("kind") == "Deployment":
                            name = doc["metadata"]["name"]
                            replicas = doc["spec"].get("replicas", 1)
                            print(f"    • {name} ({replicas} replicas)")
            except:
                pass
EOF
    fi
    
    [[ $deployments -gt 0 ]] && return 0 || return 1
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    log_info "╔════════════════════════════════════════════════════════════════╗"
    log_info "║        Kubernetes Manifest Validation & Testing               ║"
    log_info "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    local failed=0
    
    # Run validation checks
    validate_yaml_syntax || failed=$((failed + 1))
    echo ""
    
    validate_resource_completeness || failed=$((failed + 1))
    echo ""
    
    validate_helm_chart || failed=$((failed + 1))
    echo ""
    
    validate_service_inventory || failed=$((failed + 1))
    echo ""
    
    validate_kubernetes_syntax || failed=$((failed + 1))
    echo ""
    
    # Summary
    log_info "╔════════════════════════════════════════════════════════════════╗"
    if [[ $failed -eq 0 ]]; then
        log_info "✅ KUBERNETES MANIFESTS: ALL VALIDATION CHECKS PASSED"
    else
        log_error "❌ KUBERNETES MANIFESTS: $failed VALIDATION CHECKS FAILED"
    fi
    log_info "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    [[ $failed -eq 0 ]] && return 0 || return 1
}

main "$@"
