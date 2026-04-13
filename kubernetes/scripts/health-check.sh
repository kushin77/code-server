#!/usr/bin/env bash

# kubernetes/scripts/health-check.sh
# Monitor Kubernetes deployment health status
# Usage: ./health-check.sh [-n namespace] [--watch] [--interval 10]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
NAMESPACE="code-server"
WATCH_MODE=false
INTERVAL=10

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_header() { echo ""; echo -e "${BLUE}=== $1 ===${NC}"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Namespace '$NAMESPACE' not found"
    exit 1
fi

# Main health check function
run_health_check() {
    clear
    
    log_header "Kubernetes Cluster Health"
    
    # 1. Node Status
    log_header "Node Status"
    kubectl get nodes -o wide 2>/dev/null || log_error "Failed to fetch nodes"
    
    # 2. Namespace Status
    log_header "Namespace: $NAMESPACE"
    kubectl describe namespace "$NAMESPACE" 2>/dev/null | grep -E "Name:|Labels:|Annotations:" || true
    
    # 3. Pod Status
    log_header "Pod Status"
    if kubectl get pods -n "$NAMESPACE" &>/dev/null; then
        kubectl get pods -n "$NAMESPACE" -o wide
        
        # Count pod states
        RUNNING=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c "Running" || echo "0")
        PENDING=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c "Pending" || echo "0")
        FAILED=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c "Failed" || echo "0")
        TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        
        echo ""
        log_success "Running: $RUNNING / Pending: $PENDING / Failed: $FAILED / Total: $TOTAL"
        
        if [[ $FAILED -gt 0 ]]; then
            log_warn "Failed pods detected!"
            kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[?(@.status.phase=="Failed")]}{.metadata.name}{"\n"}{end}'
        fi
    else
        log_error "Failed to fetch pods"
    fi
    
    # 4. Deployment Status
    log_header "Deployment Status"
    if kubectl get deployments -n "$NAMESPACE" &>/dev/null; then
        kubectl rollout status deployments -n "$NAMESPACE" --timeout=10s 2>/dev/null || log_warn "Some deployments not fully rolled out"
        echo ""
        kubectl get deployments -n "$NAMESPACE" -o wide
    else
        log_error "No deployments found"
    fi
    
    # 5. StatefulSet Status
    log_header "StatefulSet Status"
    if kubectl get statefulsets -n "$NAMESPACE" &>/dev/null; then
        kubectl get statefulsets -n "$NAMESPACE" -o wide
    else
        log_info "No StatefulSets found"
    fi
    
    # 6. Service Status
    log_header "Service Status"
    kubectl get services -n "$NAMESPACE" -o wide
    
    # 7. Endpoint Status
    log_header "Endpoint Status"
    kubectl get endpoints -n "$NAMESPACE" -o wide
    
    # 8. PVC Status
    log_header "PersistentVolumeClaim Status"
    if kubectl get pvc -n "$NAMESPACE" &>/dev/null; then
        kubectl get pvc -n "$NAMESPACE" -o wide
    else
        log_info "No PersistentVolumeClaims found"
    fi
    
    # 9. HPA Status
    log_header "HorizontalPodAutoscaler Status"
    if kubectl get hpa -n "$NAMESPACE" &>/dev/null; then
        kubectl get hpa -n "$NAMESPACE" -o wide
        echo ""
        # Detailed HPA status
        for hpa in $(kubectl get hpa -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
            echo "HPA: $hpa"
            kubectl describe hpa "$hpa" -n "$NAMESPACE" | grep -A 5 "Status:"
        done
    else
        log_info "No HorizontalPodAutoscalers configured"
    fi
    
    # 10. Resource Usage
    log_header "Resource Usage"
    if kubectl top nodes &>/dev/null; then
        echo "Nodes:"
        kubectl top nodes
        echo ""
        echo "Pods (Top 10):"
        kubectl top pods -n "$NAMESPACE" --sort-by=memory | head -11
    else
        log_warn "Metrics Server not available (HPA may not work)"
    fi
    
    # 11. Recent Events
    log_header "Recent Events (In $NAMESPACE Namespace)"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20
    
    # 12. Service Health Checks
    log_header "Service Connectivity Checks"
    
    # Check Code Server
    if kubectl get svc code-server -n "$NAMESPACE" &>/dev/null; then
        log_info "Testing code-server service..."
        if kubectl exec -n "$NAMESPACE" deployment/code-server -- curl -s http://localhost:8443/health >/dev/null 2>&1; then
            log_success "code-server health check passed"
        else
            log_warn "code-server health check failed"
        fi
    fi
    
    # Check Agent API
    if kubectl get svc agent-api -n "$NAMESPACE" &>/dev/null; then
        log_info "Testing agent-api service..."
        if kubectl exec -n "$NAMESPACE" deployment/agent-api -- curl -s http://localhost:3000/health >/dev/null 2>&1; then
            log_success "agent-api health check passed"
        else
            log_warn "agent-api health check failed"
        fi
    fi
    
    # Check Redis
    if kubectl get svc redis -n "$NAMESPACE" &>/dev/null; then
        log_info "Testing redis service..."
        if kubectl exec -n "$NAMESPACE" statefulset/redis -- redis-cli ping &>/dev/null; then
            log_success "redis health check passed"
        else
            log_warn "redis health check failed"
        fi
    fi
    
    # 13. Logs Preview
    log_header "Recent Logs (Last 5 lines from each pod)"
    
    for pod in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        echo ""
        log_info "Pod: $pod"
        kubectl logs -n "$NAMESPACE" "$pod" --tail=5 2>/dev/null || echo "  (no logs available)"
    done
    
    # 14. Summary
    log_header "Health Check Summary"
    log_success "Cluster: $(kubectl config current-context)"
    log_success "Namespace: $NAMESPACE"
    log_success "Check Time: $(date)"
    
    if [[ $WATCH_MODE == false ]]; then
        echo ""
        log_info "Use --watch flag to continuously monitor health"
    fi
}

# Watch mode
if [[ $WATCH_MODE == true ]]; then
    log_info "Starting health check in watch mode (interval: ${INTERVAL}s)"
    log_info "Press Ctrl+C to exit"
    
    while true; do
        run_health_check
        echo ""
        log_info "Next check in $INTERVAL seconds... (Press Ctrl+C to exit)"
        sleep "$INTERVAL"
    done
else
    run_health_check
fi
