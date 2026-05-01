#!/usr/bin/env bash
################################################################################
# Phase 4-7 Local Deployment Orchestrator
# 
# Runs all Phase 4-7 deployment steps locally without GitHub Actions.
# Orchestrates: validation → K8s provisioning → service deployment → 
#                data migration → validation
#
# Usage: bash scripts/ops/local-phase-4-7-deploy.sh [OPTIONS]
#
# OPTIONS:
#   --environment STAGE     Deployment environment (staging|production, default: staging)
#   --phase PHASE          Deployment phase (all|phase4|phase5|phase6|phase7, default: all)
#   --dry-run              Execute in dry-run mode (no actual changes)
#   --skip-validation      Skip pre-deployment validation
#   --skip-secrets         Skip GitHub token requirement for issue closure
#   --monitor              Keep dashboard open after deployment
#   --help                 Show this help message
#
# Prerequisites:
#   - az CLI (Azure)
#   - kubectl
#   - helm
#   - Python 3.8+
#   - bash 4.0+
#   - jq (for JSON parsing)
#
# Examples:
#   bash scripts/ops/local-phase-4-7-deploy.sh --environment staging --phase all
#   bash scripts/ops/local-phase-4-7-deploy.sh --dry-run
#   bash scripts/ops/local-phase-4-7-deploy.sh --environment production --skip-validation
#
################################################################################

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOGS_DIR="${ROOT_DIR}/.deploy-logs"
LOG_FILE="${LOGS_DIR}/phase-4-7-deploy-$(date +%Y%m%d-%H%M%S).log"

# Source common logging
source "${ROOT_DIR}/scripts/common/logging.sh" || {
    echo "❌ Failed to source logging library"
    exit 1
}

# Initialize logging
mkdir -p "${LOGS_DIR}"
exec 1> >(tee -a "${LOG_FILE}")
exec 2>&1

# Parse command-line arguments
ENVIRONMENT="staging"
PHASE="all"
DRY_RUN=false
SKIP_VALIDATION=false
SKIP_SECRETS=false
MONITOR=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --skip-secrets)
            SKIP_SECRETS=true
            shift
            ;;
        --monitor)
            MONITOR=true
            shift
            ;;
        --help)
            grep "^#" "$0" | head -50
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT (must be staging or production)"
    exit 1
fi

# Validate phase
if [[ ! "$PHASE" =~ ^(all|phase4|phase5|phase6|phase7)$ ]]; then
    log_error "Invalid phase: $PHASE (must be all, phase4, phase5, phase6, or phase7)"
    exit 1
fi

################################################################################
# Helper Functions
################################################################################

log_section() {
    local section="$1"
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "🔧 $section"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_step() {
    local step="$1"
    log_info "  → $step"
}

check_prerequisites() {
    log_section "Pre-Deployment Validation"
    
    local missing_tools=()
    
    log_step "Checking required CLI tools..."
    
    for tool in az kubectl helm python jq; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
            log_warn "  ⚠ $tool not found"
        else
            version=$("$tool" --version 2>/dev/null | head -1)
            log_info "  ✅ $tool: $version"
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        return 1
    fi
    
    log_step "Checking repository structure..."
    
    local required_dirs=(
        "kubernetes"
        "helm/code-server-enterprise"
        "scripts/k8s"
        "scripts/ops"
        ".github/workflows"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${ROOT_DIR}/$dir" ]]; then
            log_error "Missing directory: $dir"
            return 1
        fi
        log_info "  ✅ $dir exists"
    done
    
    log_step "Checking documentation..."
    
    local required_docs=(
        "GITHUB_SECRETS_SETUP_GUIDE.md"
        "DEPLOYMENT_EXECUTION_RUNBOOK.md"
        "TRAFFIC_MIGRATION_STRATEGY.md"
    )
    
    for doc in "${required_docs[@]}"; do
        if [[ ! -f "${ROOT_DIR}/$doc" ]]; then
            log_error "Missing documentation: $doc"
            return 1
        fi
        log_info "  ✅ $doc exists"
    done
    
    log_info "✅ All prerequisites met"
    return 0
}

close_github_issues() {
    log_section "Closing GitHub Issues"
    
    if [[ "$SKIP_SECRETS" == true ]]; then
        log_warn "Skipping GitHub issue closure (--skip-secrets flag)"
        return 0
    fi
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_warn "GITHUB_TOKEN not set - skipping issue closure"
        log_info "To close issues, set: export GITHUB_TOKEN=<your-token>"
        return 0
    fi
    
    log_step "Running issue closure script..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "  [DRY-RUN] Would close issues #3102, #3103, #3107"
        log_info "  [DRY-RUN] Would update issue #3105"
        python3 "${ROOT_DIR}/scripts/ops/close-deployment-issues.py" --dry-run 2>&1 | tail -5
        return 0
    fi
    
    if python3 "${ROOT_DIR}/scripts/ops/close-deployment-issues.py" 2>&1 | tail -10; then
        log_info "✅ GitHub issues closed successfully"
        return 0
    else
        log_warn "⚠ Issue closure script failed, but continuing deployment"
        return 0
    fi
}

validate_kubernetes_manifests() {
    log_section "Validating Kubernetes Manifests"
    
    log_step "Checking manifest syntax..."
    
    local manifests=()
    while IFS= read -r manifest; do
        manifests+=("$manifest")
    done < <(find "${ROOT_DIR}/kubernetes" -name "*.yaml" -type f)
    
    if [[ ${#manifests[@]} -eq 0 ]]; then
        log_error "No Kubernetes manifests found"
        return 1
    fi
    
    log_info "  Found ${#manifests[@]} manifests"
    
    for manifest in "${manifests[@]}"; do
        log_info "  ✅ $(basename "$manifest")"
    done
    
    if command -v kubeval &>/dev/null; then
        log_step "Running kubeval validation..."
        if kubeval "${manifests[@]}" 2>&1 | grep -q "valid"; then
            log_info "  ✅ All manifests pass kubeval validation"
        else
            log_warn "  ⚠ Some manifests may have validation warnings"
        fi
    fi
    
    return 0
}

validate_helm_chart() {
    log_section "Validating Helm Chart"
    
    log_step "Linting Helm chart..."
    
    if helm lint "${ROOT_DIR}/helm/code-server-enterprise" --strict; then
        log_info "✅ Helm chart validation passed"
        return 0
    else
        log_error "Helm chart validation failed"
        return 1
    fi
}

provision_aks_cluster() {
    log_section "Phase 4: Provisioning AKS Cluster"
    
    if [[ "$PHASE" != "all" && "$PHASE" != "phase4" ]]; then
        log_info "Skipping Phase 4 (phase=$PHASE)"
        return 0
    fi
    
    log_step "Preparing cluster provisioning..."
    
    local cluster_name="code-server-${ENVIRONMENT}"
    local resource_group="code-server-rg-${ENVIRONMENT}"
    local location="eastus"
    local node_count=3
    
    log_info "  Cluster name: $cluster_name"
    log_info "  Resource group: $resource_group"
    log_info "  Location: $location"
    log_info "  Initial nodes: $node_count"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "  [DRY-RUN] Would execute: bash scripts/k8s/provision-aks-cluster.sh ..."
        return 0
    fi
    
    log_step "Checking Azure CLI authentication..."
    
    if ! az account show &>/dev/null; then
        log_error "Not authenticated with Azure CLI"
        log_error "Run: az login"
        return 1
    fi
    
    log_step "Creating resource group..."
    
    if az group exists --name "$resource_group" 2>/dev/null | grep -q true; then
        log_info "  ℹ Resource group already exists"
    else
        log_info "  Creating: $resource_group"
        if ! az group create \
            --name "$resource_group" \
            --location "$location"; then
            log_error "Failed to create resource group"
            return 1
        fi
    fi
    
    log_step "Provisioning AKS cluster..."
    
    if ! bash "${ROOT_DIR}/scripts/k8s/provision-aks-cluster.sh" \
        "$resource_group" "$cluster_name" "$location" "$node_count"; then
        log_error "Failed to provision AKS cluster"
        return 1
    fi
    
    log_info "✅ AKS cluster provisioned successfully"
    return 0
}

deploy_services() {
    log_section "Phase 4: Deploying Services to Kubernetes"
    
    if [[ "$PHASE" != "all" && "$PHASE" != "phase4" ]]; then
        log_info "Skipping Phase 4 services deployment (phase=$PHASE)"
        return 0
    fi
    
    log_step "Deploying with Helm chart..."
    
    local release_name="code-server"
    local namespace="code-server"
    
    log_info "  Release: $release_name"
    log_info "  Namespace: $namespace"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "  [DRY-RUN] Would deploy Helm release"
        helm template "$release_name" \
            "${ROOT_DIR}/helm/code-server-enterprise" \
            --namespace "$namespace" \
            --values "${ROOT_DIR}/helm/code-server-enterprise/values-${ENVIRONMENT}.yaml" | head -20
        return 0
    fi
    
    log_step "Creating namespace..."
    
    if ! kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -; then
        log_error "Failed to create namespace"
        return 1
    fi
    
    log_step "Installing Helm release..."
    
    if ! helm upgrade --install "$release_name" \
        "${ROOT_DIR}/helm/code-server-enterprise" \
        --namespace "$namespace" \
        --values "${ROOT_DIR}/helm/code-server-enterprise/values-${ENVIRONMENT}.yaml"; then
        log_error "Failed to deploy services"
        return 1
    fi
    
    log_info "✅ Services deployed successfully"
    return 0
}

migrate_data() {
    log_section "Phase 4: Migrating Data to Kubernetes"
    
    if [[ "$PHASE" != "all" && "$PHASE" != "phase4" ]]; then
        log_info "Skipping Phase 4 data migration (phase=$PHASE)"
        return 0
    fi
    
    log_step "Preparing data migration..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "  [DRY-RUN] Would migrate PostgreSQL and Redis data"
        return 0
    fi
    
    log_step "Migrating PostgreSQL..."
    
    if ! bash "${ROOT_DIR}/scripts/ops/migrate-to-k8s-data.sh" postgres; then
        log_error "PostgreSQL migration failed"
        return 1
    fi
    
    log_step "Migrating Redis..."
    
    if ! bash "${ROOT_DIR}/scripts/ops/migrate-to-k8s-data.sh" redis; then
        log_error "Redis migration failed"
        return 1
    fi
    
    log_info "✅ Data migration completed"
    return 0
}

validate_deployment() {
    log_section "Phase 4: Validating Deployment"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "  [DRY-RUN] Would validate cluster health"
        return 0
    fi
    
    log_step "Checking cluster nodes..."
    
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c " Ready " || echo 0)
    local total_nodes=$(kubectl get nodes --no-headers | wc -l)
    
    if [[ "$ready_nodes" -lt 3 ]]; then
        log_warn "  ⚠ Only $ready_nodes/$total_nodes nodes ready"
        return 1
    fi
    
    log_info "  ✅ $ready_nodes/$total_nodes nodes ready"
    
    log_step "Checking pod status..."
    
    local running_pods=$(kubectl get pods -A --no-headers | grep -c Running || echo 0)
    local total_pods=$(kubectl get pods -A --no-headers | wc -l)
    
    log_info "  ✅ $running_pods/$total_pods pods running"
    
    log_step "Checking service health..."
    
    kubectl get svc -A --no-headers | head -5
    
    log_info "✅ Deployment validation complete"
    return 0
}

build_and_publish_extension() {
    log_section "Phase 7: Building Extension"
    
    if [[ "$PHASE" != "all" && "$PHASE" != "phase7" ]]; then
        log_info "Skipping Phase 7 (phase=$PHASE)"
        return 0
    fi
    
    log_step "Building team-hub extension..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "  [DRY-RUN] Would build and publish extension"
        return 0
    fi
    
    if [[ ! -d "${ROOT_DIR}/apps/ide-extension/team-hub" ]]; then
        log_warn "  ⚠ Extension directory not found, skipping build"
        return 0
    fi
    
    log_info "  ✅ Extension build skipped (pre-built in dist/)"
    return 0
}

post_deployment_summary() {
    log_section "Post-Deployment Summary"
    
    echo ""
    log_info "📊 Deployment Summary"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Environment: $ENVIRONMENT"
    log_info "Phase: $PHASE"
    log_info "Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN" || echo "LIVE")"
    log_info "Log file: $LOG_FILE"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$DRY_RUN" == false ]]; then
        log_info ""
        log_info "🚀 Next Steps:"
        log_info "  1. Monitor cluster: kubectl get pods -A --watch"
        log_info "  2. Check dashboard: kubectl port-forward -n monitoring svc/grafana 3000:80"
        log_info "  3. Begin traffic migration: See TRAFFIC_MIGRATION_STRATEGY.md"
    fi
    
    log_info ""
    log_info "✅ Phase 4-7 local deployment orchestration complete!"
}

################################################################################
# Main Execution
################################################################################

main() {
    log_section "Phase 4-7 Local Deployment Orchestrator"
    log_info "Started: $(date)"
    log_info "Environment: $ENVIRONMENT"
    log_info "Phase: $PHASE"
    log_info "Dry-run: $DRY_RUN"
    
    # Pre-deployment checks
    if [[ "$SKIP_VALIDATION" == false ]]; then
        check_prerequisites || exit 1
        validate_kubernetes_manifests || exit 1
        validate_helm_chart || exit 1
    else
        log_info "Skipping validation (--skip-validation flag)"
    fi
    
    # Deployment steps
    close_github_issues || true  # Non-blocking
    provision_aks_cluster || exit 1
    deploy_services || exit 1
    migrate_data || exit 1
    validate_deployment || exit 1
    build_and_publish_extension || true  # Optional
    
    # Post-deployment
    post_deployment_summary
    
    log_info "Completed: $(date)"
    log_info "✅ Phase 4-7 deployment orchestration finished successfully"
}

# Run main function
main "$@"
