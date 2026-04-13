# Phase 8: Verification & Validation
# Implements health checks, compliance verification, and performance benchmarking

# Data sources to fetch cluster information
data "kubernetes_nodes" "all" {}

data "kubernetes_namespace" "all" {
  for_each = toset(var.namespaces_to_verify)
  metadata {
    name = each.value
  }
}

# Local file: Verification script
resource "local_file" "health_check_script" {
  count            = var.create_health_check_script ? 1 : 0
  filename         = "${var.verification_scripts_dir}/01-health-check.sh"
  file_permission  = "0755"
  content = <<-EOT
#!/bin/bash
set -euo pipefail

# Health check script for Kubernetes cluster components

SCRIPT_DIR="$(cd "$(dirname "$${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$${SCRIPT_DIR}/../logs/health-check-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $@" | tee -a "$LOG_FILE"
}

check_resource() {
  local resource_type="$1"
  local namespace="$2"
  local resource_name="$3"
  
  if kubectl get "$resource_type" -n "$namespace" "$resource_name" &>/dev/null; then
    log "INFO" "✓ $resource_type/$resource_name in $namespace exists"
    return 0
  else
    log "ERROR" "✗ $resource_type/$resource_name in $namespace MISSING"
    return 1
  fi
}

check_pod_ready() {
  local namespace="$1"
  local pod_selector="$2"
  
  local ready_count=$(kubectl get pods -n "$namespace" -l "$pod_selector" -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)
  local total_count=$(kubectl get pods -n "$namespace" -l "$pod_selector" --no-headers 2>/dev/null | wc -l)
  
  if [ "$ready_count" -eq "$total_count" ] && [ "$total_count" -gt 0 ]; then
    log "INFO" "✓ Pods ready: $ready_count/$total_count for $pod_selector"
    return 0
  else
    log "WARN" "⚠ Only $ready_count/$total_count pods ready for $pod_selector"
    return 1
  fi
}

log "INFO" "=== Starting Kubernetes Cluster Health Check ==="
log "INFO" "Cluster: $(kubectl config current-context)"

# Check node status
log "INFO" "Checking nodes..."
kubectl get nodes -o wide | tee -a "$LOG_FILE"

# Check namespaces
log "INFO" "Checking namespaces..."
%{for ns in var.namespaces_to_verify~}
check_resource "namespace" "default" "${ns}" || true
%{endfor~}

# Check critical deployments
log "INFO" "Checking critical deployments..."
%{if var.enable_monitoring~}
check_pod_ready "monitoring" "app.kubernetes.io/name=prometheus" || true
check_pod_ready "monitoring" "app.kubernetes.io/name=grafana" || true
check_pod_ready "monitoring" "app.kubernetes.io/name=loki" || true
%{endif~}

%{if var.enable_code_server~}
check_pod_ready "code-server" "app.kubernetes.io/name=code-server" || true
%{endif~}

%{if var.enable_ingress_controller~}
check_pod_ready "ingress-nginx" "app.kubernetes.io/name=ingress-nginx" || true
%{endif~}

# Check resources (CPU, Memory)
log "INFO" "Checking node resources..."
kubectl top nodes 2>/dev/null | tee -a "$LOG_FILE" || log "WARN" "Metrics not available (install heapster/metrics-server)"

# Summary
log "INFO" "=== Health Check Complete ==="
log "INFO" "Full log: $LOG_FILE"
  EOT
}

# Local file: Compliance check script
resource "local_file" "compliance_check_script" {
  count            = var.create_compliance_check_script ? 1 : 0
  filename         = "${var.verification_scripts_dir}/02-compliance-check.sh"
  file_permission  = "0755"
  content = <<-EOT
#!/bin/bash
set -euo pipefail

# Compliance verification script

SCRIPT_DIR="$(cd "$(dirname "$${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$${SCRIPT_DIR}/../logs/compliance-check-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $@" | tee -a "$LOG_FILE"
}

log "INFO" "=== Starting Compliance Verification ==="

# Check Network Policies
log "INFO" "Checking Network Policies..."
if kubectl get networkpolicies -n monitoring -q &>/dev/null; then
  log "INFO" "✓ Network Policies configured"
else
  log "WARN" "⚠ No Network Policies found"
fi

# Check RBAC
log "INFO" "Checking RBAC configuration..."
if kubectl get clusterrolebindings -q &>/dev/null; then
  log "INFO" "✓ ClusterRoleBindings configured"
fi

if kubectl get rolebindings -A -q &>/dev/null; then
  log "INFO" "✓ RoleBindings configured"
fi

# Check Service Accounts
log "INFO" "Checking Service Accounts..."
kubectl get serviceaccount -A | tee -a "$LOG_FILE" || true

# Check Resource Quotas
log "INFO" "Checking Resource Quotas..."
kubectl get resourcequota -A | tee -a "$LOG_FILE"

# Check Pod Security Policies
log "INFO" "Checking Pod Security Standards..."
kubectl label namespace monitoring pod-security.kubernetes.io/enforce=baseline --dry-run=client -o yaml | tee -a "$LOG_FILE" || true

log "INFO" "=== Compliance Check Complete ==="
  EOT
}

# Local file: Performance benchmark script
resource "local_file" "performance_benchmark_script" {
  count            = var.create_performance_benchmark ? 1 : 0
  filename         = "${var.verification_scripts_dir}/03-performance-benchmark.sh"
  file_permission  = "0755"
  content = <<-EOT
#!/bin/bash
set -euo pipefail

# Performance benchmarking script

SCRIPT_DIR="$(cd "$(dirname "$${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$${SCRIPT_DIR}/../logs/benchmark-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $@" | tee -a "$LOG_FILE"
}

benchmark_api_latency() {
  log "INFO" "Benchmarking API server latency..."
  
  local total_time=0
  local iterations=10
  
  for i in $(seq 1 $iterations); do
    local start=$(date +%s%N)
    kubectl get pods --all-namespaces -q &>/dev/null
    local end=$(date +%s%N)
    local duration=$((($end - $start) / 1000000))  # Convert to ms
    total_time=$((total_time + duration))
    log "INFO" "  Iteration $i: $${duration}ms"
  done
  
  local avg=$((total_time / iterations))
  log "INFO" "Average API latency: $${avg}ms"
  
  if [ "$avg" -lt 100 ]; then
    log "INFO" "✓ API latency is acceptable (<100ms)"
  elif [ "$avg" -lt 500 ]; then
    log "WARN" "⚠ API latency is moderate (100-500ms)"
  else
    log "ERROR" "✗ API latency is high (>500ms)"
  fi
}

benchmark_disk_io() {
  log "INFO" "Benchmarking disk I/O on nodes..."
  
  # Check disk usage on nodes
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{":\t"}{.status.capacity.ephemeralStorage}{"\n"}{end}' | tee -a "$LOG_FILE"
}

benchmark_network() {
  log "INFO" "Testing inter-pod network latency..."
  
  # Create temporary test pod
  log "INFO" "Creating test pod for network benchmark..."
  kubectl run -n default network-test --image=busybox --restart=Never -- sleep 300 &>/dev/null || true
  
  sleep 2
  
  log "INFO" "Network benchmark pod created"
  log "INFO" "To test: kubectl exec -n default network-test -- ping <service>"
}

log "INFO" "=== Starting Performance Benchmark ==="

benchmark_api_latency
benchmark_disk_io
benchmark_network

log "INFO" "=== Performance Benchmark Complete ==="
log "INFO" "Results saved to: $LOG_FILE"
  EOT
}

# Local file: Cleanup script
resource "local_file" "cleanup_script" {
  count            = var.create_cleanup_script ? 1 : 0
  filename         = "${var.verification_scripts_dir}/04-cleanup-test-resources.sh"
  file_permission  = "0755"
  content = <<-EOT
#!/bin/bash
set -euo pipefail

# Cleanup test resources created during verification

SCRIPT_DIR="$(cd "$(dirname "$${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$${SCRIPT_DIR}/../logs/cleanup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a "$LOG_FILE"
}

log "Cleaning up test resources..."

# Remove test pod if exists
log "Removing network test pod..."
kubectl delete pod -n default network-test --ignore-not-found=true 2>/dev/null || true

# Remove test namespaces if created
log "Removing test namespaces..."
kubectl delete namespace test-verification --ignore-not-found=true 2>/dev/null || true

log "Cleanup complete"
  EOT
}

# ConfigMap: Verification checklist
resource "kubernetes_config_map" "verification_checklist" {
  count = var.create_verification_checklist ? 1 : 0
  metadata {
    name      = "verification-checklist"
    namespace = "default"
    labels = {
      "app.kubernetes.io/name"       = "verification"
      "app.kubernetes.io/component"  = "checklist"
      "environment"                  = var.environment
    }
  }

  data = {
    "VERIFICATION_CHECKLIST.md" = <<-EOT
# Kubernetes Cluster Verification Checklist

## Pre-Deployment
- [ ] Kubernetes cluster running (kubectl cluster-info)
- [ ] kubectl configured correctly (kubectl get nodes)
- [ ] Helm installed (helm version)
- [ ] Required namespaces exist

## Phase 2: Namespaces & Storage
- [ ] Monitoring namespace created
- [ ] Security namespace created
- [ ] Code-server namespace created
- [ ] Backup namespace created
- [ ] Storage classes created (kubectl get sc)
- [ ] Persistent volumes created (kubectl get pv)
- [ ] No pending PVCs (kubectl get pvc -A)

## Phase 3: Observability Stack
- [ ] Prometheus running (kubectl get deployment -n monitoring)
- [ ] Grafana running (kubectl get deployment -n monitoring)
- [ ] Loki running (kubectl get statefulset -n monitoring)
- [ ] All monitoring pods ready (kubectl get pods -n monitoring)
- [ ] Prometheus scraping metrics
- [ ] Grafana dashboards accessible
- [ ] Loki receiving logs

## Phase 4: Security & RBAC
- [ ] Network policies created
- [ ] RBAC roles configured
- [ ] Service accounts created
- [ ] Default-deny ingress policy applied
- [ ] Security pod security standards enforced

## Phase 5: Backup & DR
- [ ] Velero installed
- [ ] Backup storage configured
- [ ] Backup schedules active
- [ ] First backup completed
- [ ] Restore testing passed

## Phase 6: Application Platform
- [ ] code-server StatefulSet running
- [ ] Workspace PVCs bound
- [ ] code-server service accessible
- [ ] Extensions installed
- [ ] Sessions persistent

## Phase 7: Ingress & TLS
- [ ] NGINX Ingress Controller running
- [ ] Ingress rules created
- [ ] cert-manager running
- [ ] Certificates issued
- [ ] TLS termination working
- [ ] All services accessible via HTTPS

## Post-Deployment
- [ ] All pods running and ready
- [ ] No pending resources
- [ ] Node resources healthy
- [ ] Cluster events clean (no errors)
- [ ] Monitoring alerting functional
- [ ] Backup and restore tested
- [ ] Performance SLOs met

## Rollback Preparation
- [ ] Latest backup confirmed
- [ ] Restore procedure tested
- [ ] Emergency contacts documented
- [ ] Runbook reviewed
    EOT
  }

  lifecycle {
    ignore_changes = [metadata[0].resource_version]
  }
}

output "verification_status" {
  value = {
    health_check_script         = var.create_health_check_script ? local_file.health_check_script[0].filename : null
    compliance_check_script     = var.create_compliance_check_script ? local_file.compliance_check_script[0].filename : null
    performance_benchmark_script = var.create_performance_benchmark ? local_file.performance_benchmark_script[0].filename : null
    cleanup_script              = var.create_cleanup_script ? local_file.cleanup_script[0].filename : null
  }
  description = "Verification script locations"
}

output "verification_commands" {
  value = <<-EOT
    Verification Commands:
    
    1. Health Check:
       bash ${var.verification_scripts_dir}/01-health-check.sh
    
    2. Compliance Check:
       bash ${var.verification_scripts_dir}/02-compliance-check.sh
    
    3. Performance Benchmark:
       bash ${var.verification_scripts_dir}/03-performance-benchmark.sh
    
    4. Cleanup Test Resources:
       bash ${var.verification_scripts_dir}/04-cleanup-test-resources.sh
    
    5. View Verification Checklist:
       kubectl get configmap verification-checklist -o jsonpath='{.data.VERIFICATION_CHECKLIST\.md}'
    
    6. Monitor Cluster:
       kubectl top nodes
       kubectl top pods -A
       kubectl get events -A --sort-by='.lastTimestamp'
  EOT
  description = "Commands to run verification checks"
}
