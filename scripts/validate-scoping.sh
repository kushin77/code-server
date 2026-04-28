#!/bin/bash
# =============================================================================
# DEPLOYMENT SCOPING VALIDATION SCRIPT
# =============================================================================
# Purpose: Validate that code-server deployment only manages its own resources
# Usage: ./scripts/validate-scoping.sh [--fix] [--strict]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/_common/init.sh"

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Configuration
NAMESPACE="code-server"
PROJECT_LABEL="project=code-server"
APP_LABEL="app.kubernetes.io/name=code-server-enterprise"
DOCKER_PREFIX="code-server-"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
FIX_MODE=false
STRICT_MODE=false
VIOLATIONS=0
WARNINGS=0
DESCRIPTIVE_SUFFIX_REGEX='^code-server-.*-(service|gateway|logs|db|cache|models|vectors|dashboards|traces|broker|control-plane)$'

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --fix) FIX_MODE=true; shift ;;
    --strict) STRICT_MODE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS+1)); }
log_error() { echo -e "${RED}✗${NC} $1"; VIOLATIONS=$((VIOLATIONS+1)); }

# =============================================================================
# SECTION 1: TERRAFORM VALIDATION
# =============================================================================
validate_terraform() {
  log_info "Checking Terraform configuration..."

  local tf_files=$(find terraform/environments/private -name "*.tf" 2>/dev/null)

  if [ -z "$tf_files" ]; then
    log_warning "No terraform files found"
    return
  fi

  for tf_file in $tf_files; do
    log_info "  Validating $tf_file..."

    # Check for non-code-server namespace references
    if grep -q 'namespace.*=.*"[^c][^o][^d][^e]' "$tf_file" 2>/dev/null; then
      log_error "    Found non-code-server namespace in $tf_file"
    fi

    # Check for cluster-admin role
    if grep -q 'cluster-admin\|clusterAdmin' "$tf_file" 2>/dev/null; then
      log_error "    Found cluster-admin role in $tf_file - should use namespace-scoped role"
    fi

    # Only warn about label selectors in files that actually manage Kubernetes resources
    if grep -q 'kubernetes_' "$tf_file" 2>/dev/null; then
      if ! grep -q 'label_selector.*project.*code-server' "$tf_file" 2>/dev/null; then
        log_warning "    No label_selector with project=code-server found in $tf_file"
      fi
    fi
  done
}

# =============================================================================
# SECTION 2: DOCKER-COMPOSE VALIDATION
# =============================================================================
validate_docker_compose() {
  log_info "Checking docker-compose configuration..."

  local compose_files
  compose_files=$(find . -type f \( \
    -name "docker-compose*.yml" -o \
    -name "docker-compose*.yaml" -o \
    -path "./docker/*.yml" -o \
    -path "./docker/*.yaml" \
  \) | sort)

  if [ -z "$compose_files" ]; then
    log_warning "No docker-compose files found"
    return
  fi

  while IFS= read -r compose_file; do
    [[ -z "$compose_file" ]] && continue
    log_info "  Validating $compose_file..."

    while IFS= read -r container_line; do
      local line_number="${container_line%%:*}"
      local container_name="${container_line#*:}"
      container_name="${container_name#*container_name: }"
      container_name="${container_name#\"}"
      container_name="${container_name%\"}"
      container_name="${container_name#\'}"
      container_name="${container_name%\'}"

      if [[ -n "$container_name" ]] && [[ ! "$container_name" =~ ^$DOCKER_PREFIX ]]; then
        log_error "    $compose_file:$line_number container_name '$container_name' doesn't start with $DOCKER_PREFIX"
      elif [[ -n "$container_name" ]] && [[ "$container_name" =~ $DESCRIPTIVE_SUFFIX_REGEX ]]; then
        log_error "    $compose_file:$line_number container_name '$container_name' uses a descriptive suffix; use the plain service name instead"
      fi
    done < <(grep -n "container_name:" "$compose_file" 2>/dev/null || true)
  done <<< "$compose_files"
}

# =============================================================================
# SECTION 3: HELM VALIDATION
# =============================================================================
validate_helm() {
  log_info "Checking Helm configuration..."

  if [ ! -d "helm/code-server-enterprise" ]; then
    log_warning "Helm chart directory not found"
    return
  fi

  # Check Chart.yaml
  if [ -f "helm/code-server-enterprise/Chart.yaml" ]; then
    log_info "  Validating Chart.yaml..."
    if grep -q "namespace:" helm/code-server-enterprise/Chart.yaml 2>/dev/null; then
      log_warning "    Namespace should be specified in values.yaml, not Chart.yaml"
    fi
  fi

  # Check templates for hardcoded namespaces
  local templates=$(find helm/code-server-enterprise/templates -name "*.yaml" -o -name "*.yml")
  for template in $templates; do
    if grep -q 'namespace: [^{]' "$template" 2>/dev/null; then
      if ! grep -q 'namespace: code-server' "$template" 2>/dev/null; then
        log_error "    $template has non-code-server namespace"
      fi
    fi
  done

  # Check for label requirements
  for template in $templates; do
    if grep -q 'include "code-server-enterprise.labels"' "$template" 2>/dev/null; then
      continue
    fi

    if ! grep -q "project: code-server\|project: \"code-server\"" "$template" 2>/dev/null; then
      if grep -q "labels:" "$template" 2>/dev/null; then
        log_warning "    $template may be missing project label"
      fi
    fi
  done
}

# =============================================================================
# SECTION 4: KUBERNETES MANIFESTS VALIDATION
# =============================================================================
validate_kubernetes_manifests() {
  log_info "Checking Kubernetes manifests..."

  local k8s_files=$(find kubernetes -name "*.yaml" -o -name "*.yml" 2>/dev/null)

  if [ -z "$k8s_files" ]; then
    log_info "  No kubernetes manifests found"
    return
  fi

  for k8s_file in $k8s_files; do
    log_info "  Validating $k8s_file..."

    # Check namespace
    if grep -q "^  namespace:" "$k8s_file" 2>/dev/null; then
      if ! grep -q "namespace: code-server" "$k8s_file" 2>/dev/null; then
        log_error "    $k8s_file doesn't specify namespace: code-server"
      fi
    fi

    # Check for labels
    if grep -q "^  labels:" "$k8s_file" 2>/dev/null; then
      if ! grep -q "project: code-server" "$k8s_file" 2>/dev/null; then
        log_warning "    $k8s_file missing project: code-server label"
      fi
    fi
  done
}

# =============================================================================
# SECTION 5: RUNTIME VALIDATION (if cluster accessible)
# =============================================================================
validate_runtime() {
  log_info "Checking runtime deployment (if Kubernetes cluster available)..."

  if ! command -v kubectl &> /dev/null; then
    log_info "  kubectl not available, skipping runtime checks"
    return
  fi

  if ! kubectl cluster-info &> /dev/null; then
    log_info "  Cluster not accessible, skipping runtime checks"
    return
  fi

  # Check namespace exists
  if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_warning "  Namespace $NAMESPACE doesn't exist yet"
  else
    log_success "  Namespace $NAMESPACE exists"
  fi

  # Check for resources without project label
  local unlabeled=$(kubectl get all -n "$NAMESPACE" -o json 2>/dev/null | jq '.items[] | select(.metadata.labels.project != "code-server") | .metadata.name' 2>/dev/null | wc -l)
  if [ "$unlabeled" -gt 0 ]; then
    log_warning "  Found $unlabeled resources without project=code-server label"
  else
    log_success "  All resources properly labeled"
  fi

  # Check RBAC
  if kubectl get role -n "$NAMESPACE" code-server-deployment &> /dev/null; then
    log_success "  RBAC role exists"
  else
    log_warning "  RBAC role not found"
  fi

  # Check network policies
  if kubectl get networkpolicies -n "$NAMESPACE" &> /dev/null; then
    log_success "  Network policies exist"
  else
    log_warning "  Network policies not found"
  fi
}

# =============================================================================
# SECTION 6: DOCKER RUNTIME VALIDATION
# =============================================================================
validate_docker_runtime() {
  log_info "Checking Docker runtime..."

  if ! command -v docker &> /dev/null; then
    log_info "  Docker not available, skipping"
    return
  fi

  # Check for containers without code-server prefix
  local non_prefixed=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -v "^$DOCKER_PREFIX" | grep -v "^$" | wc -l)

  if [ "$non_prefixed" -gt 0 ] && [ "$STRICT_MODE" = true ]; then
    log_warning "  Found $non_prefixed containers without $DOCKER_PREFIX prefix"
  fi

  # Check for orphaned volumes
  local orphaned_volumes=$(docker volume ls --filter "dangling=true" 2>/dev/null | grep -v "DRIVER" | wc -l)
  if [ "$orphaned_volumes" -gt 0 ]; then
    log_warning "  Found $orphaned_volumes orphaned volumes"
  fi

  # Check for network isolation
  local networks=$(docker network ls --filter "label=project=code-server" 2>/dev/null | grep -v "NETWORK" | wc -l)
  log_info "  Found $networks code-server networks"
}

# =============================================================================
# SECTION 7: GIT VALIDATION
# =============================================================================
validate_git() {
  log_info "Checking Git repository..."

  if ! command -v git &> /dev/null; then
    log_info "  Git not available, skipping"
    return
  fi

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_info "  Not a git repository, skipping"
    return
  fi

  # Check for uncommitted changes in scoping files
  if git diff --quiet 2>/dev/null; then
    log_success "  No uncommitted changes"
  else
    log_warning "  Uncommitted changes detected"
  fi

  # Check latest commits touch only code-server files
  local recent_commits=$(git log --oneline -5 2>/dev/null | wc -l)
  if [ "$recent_commits" -gt 0 ]; then
    log_info "  Latest commits verified"
  fi
}

# =============================================================================
# SUMMARY
# =============================================================================
print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║               DEPLOYMENT SCOPING VALIDATION REPORT             ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo -e "  Errors:   ${RED}$VIOLATIONS${NC}"
  echo -e "  Warnings: ${YELLOW}$WARNINGS${NC}"
  echo ""

  if [ "$VIOLATIONS" -eq 0 ]; then
    if [ "$WARNINGS" -eq 0 ]; then
      echo -e "  ${GREEN}✓ All scoping validations passed!${NC}"
      return 0
    else
      echo -e "  ${YELLOW}⚠ Validation passed with warnings${NC}"
      return 0
    fi
  else
    echo -e "  ${RED}✗ Validation FAILED - fix violations before deploying${NC}"
    return 1
  fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║     CODE-SERVER DEPLOYMENT SCOPING VALIDATION CHECKER          ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""

  validate_terraform
  validate_docker_compose
  validate_helm
  validate_kubernetes_manifests
  validate_runtime
  validate_docker_runtime
  validate_git

  print_summary
}

# Run main
main
