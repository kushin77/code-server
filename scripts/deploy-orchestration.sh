#!/bin/bash
# MASTER DEPLOYMENT ORCHESTRATION SCRIPT
# Enterprise Kubernetes Platform Deployment
# Date: April 13, 2026
# This script orchestrates an 8-phase deployment of the enterprise platform

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DEPLOYMENT_LOG="/tmp/deployment-$(date +%Y%m%d-%H%M%S).log"
PHASES=("1" "2" "3" "4" "5" "6" "7" "8")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
log_banner() { echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"; echo -e "${CYAN}║ $1 ${NC}"; echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n" | tee -a "$DEPLOYMENT_LOG"; }

# Argument parsing
PHASE_START=${1:-"1"}
PHASE_END=${2:-"8"}
DRY_RUN=${DRY_RUN:-"false"}

# Validation
if ! [[ "$PHASE_START" =~ ^[1-8]$ ]]; then
    log_error "Invalid start phase: $PHASE_START (must be 1-8)"
    exit 1
fi

if ! [[ "$PHASE_END" =~ ^[1-8]$ ]]; then
    log_error "Invalid end phase: $PHASE_END (must be 1-8)"
    exit 1
fi

if [ "$PHASE_START" -gt "$PHASE_END" ]; then
    log_error "Start phase ($PHASE_START) cannot be greater than end phase ($PHASE_END)"
    exit 1
fi

# Main Banner
clear
log_banner "ENTERPRISE KUBERNETES DEPLOYMENT ORCHESTRATOR"
echo "Start Time: $(date)" | tee -a "$DEPLOYMENT_LOG"
echo "Deployment Log: $DEPLOYMENT_LOG" | tee -a "$DEPLOYMENT_LOG"
echo "Phases to Execute: $PHASE_START to $PHASE_END" | tee -a "$DEPLOYMENT_LOG"
echo "Dry Run Mode: $DRY_RUN" | tee -a "$DEPLOYMENT_LOG"
echo "" | tee -a "$DEPLOYMENT_LOG"

# Pre-flight Checks
log_banner "PRE-FLIGHT CHECKS"

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl"
    exit 1
fi
log_success "kubectl: $(kubectl version --client --short 2>/dev/null | head -1)"

if ! command -v docker &> /dev/null; then
    log_warning "docker not found (may not be required)"
else
    log_success "docker: $(docker --version)"
fi

if ! command -v bash &> /dev/null; then
    log_error "bash not found"
    exit 1
fi
log_success "bash: $(bash --version | head -1)"

# Check cluster connectivity
log_info "Checking cluster connectivity..."
if kubectl cluster-info &>/dev/null; then
    log_success "Cluster connectivity: OK"
    CLUSTER_INFO=$(kubectl cluster-info | head -1)
    log_info "  $CLUSTER_INFO"
else
    log_warning "Cluster not currently accessible"
fi

# Check disk space
log_info "Checking disk space..."
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    log_success "Disk space: ${DISK_USAGE}% used (OK)"
else
    log_warning "Disk space: ${DISK_USAGE}% used (approaching limit)"
fi

echo "" | tee -a "$DEPLOYMENT_LOG"

# Phase Execution
log_banner "EXECUTING DEPLOYMENT PHASES"

TOTAL_PHASES=$((PHASE_END - PHASE_START + 1))
CURRENT_PHASE=0

for PHASE in $(seq "$PHASE_START" "$PHASE_END"); do
    ((CURRENT_PHASE++))
    PERCENTAGE=$((CURRENT_PHASE * 100 / TOTAL_PHASES))
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}" | tee -a "$DEPLOYMENT_LOG"
    echo -e "${YELLOW}[${CURRENT_PHASE}/${TOTAL_PHASES}]${NC} Phase $PHASE - Progress: ${PERCENTAGE}%" | tee -a "$DEPLOYMENT_LOG"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}" | tee -a "$DEPLOYMENT_LOG"
    
    PHASE_SCRIPT="$SCRIPT_DIR/phase-$PHASE-*.sh"
    PHASE_FILE=$(ls $PHASE_SCRIPT 2>/dev/null | head -1 || echo "")
    
    if [ -z "$PHASE_FILE" ]; then
        log_error "Phase $PHASE script not found: $PHASE_SCRIPT"
        exit 1
    fi
    
    log_info "Executing: $(basename $PHASE_FILE)"
    log_info "Phase Start Time: $(date)"
    
    if [ "$DRY_RUN" == "true" ]; then
        log_warning "DRY RUN - Would execute: $PHASE_FILE"
        log_info "Script preview (first 20 lines):"
        head -20 "$PHASE_FILE" | sed 's/^/  /' | tee -a "$DEPLOYMENT_LOG"
    else
        # Execute phase script
        if bash "$PHASE_FILE" 2>&1 | tee -a "$DEPLOYMENT_LOG"; then
            log_success "Phase $PHASE completed successfully"
            echo "Phase Completion Time: $(date)" | tee -a "$DEPLOYMENT_LOG"
        else
            log_error "Phase $PHASE failed"
            log_info "Check log file: $DEPLOYMENT_LOG"
            exit 1
        fi
    fi
    
    # Add pause between phases for stability
    if [ "$PHASE" -lt "$PHASE_END" ] && [ "$DRY_RUN" != "true" ]; then
        log_info "Waiting 10 seconds before next phase..."
        sleep 10
    fi
done

# Final Summary
log_banner "DEPLOYMENT SUMMARY"

echo "Deployment Information:" | tee -a "$DEPLOYMENT_LOG"
echo "  Start Time: $(date +%s)" | tee -a "$DEPLOYMENT_LOG"
echo "  End Time: $(date)" | tee -a "$DEPLOYMENT_LOG"
echo "  Phases Executed: $PHASE_START to $PHASE_END" | tee -a "$DEPLOYMENT_LOG"
echo "" | tee -a "$DEPLOYMENT_LOG"

echo "Cluster Status:" | tee -a "$DEPLOYMENT_LOG"
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "unknown")
READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
echo "  Nodes: $READY_COUNT/$NODE_COUNT Ready" | tee -a "$DEPLOYMENT_LOG"

POD_COUNT=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l || echo "unknown")
RUNNING_COUNT=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo "0")
echo "  Pods: $RUNNING_COUNT/$POD_COUNT Running" | tee -a "$DEPLOYMENT_LOG"

echo "" | tee -a "$DEPLOYMENT_LOG"

if [ "$DRY_RUN" != "true" ]; then
    echo "Post-Deployment Verification:" | tee -a "$DEPLOYMENT_LOG"
    
    # Check API Server
    if kubectl cluster-info &>/dev/null; then
        log_success "API Server: Healthy"
    else
        log_warning "API Server: Not responding"
    fi
    
    # Check nodes
    if [ "$READY_COUNT" -gt 0 ]; then
        log_success "Nodes: $READY_COUNT Ready"
    else
        log_warning "Nodes: 0 Ready"
    fi
    
    # Check critical namespaces
    NAMESPACES=("monitoring" "code-server" "ingress-nginx" "kube-system")
    echo "" | tee -a "$DEPLOYMENT_LOG"
    echo "Namespace Status:" | tee -a "$DEPLOYMENT_LOG"
    for NS in "${NAMESPACES[@]}"; do
        POD_COUNT=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | wc -l || echo "0")
        RUNNING=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        printf "  %-20s %d/%d Running\n" "$NS:" "$RUNNING" "$POD_COUNT" | tee -a "$DEPLOYMENT_LOG"
    done
    
    echo "" | tee -a "$DEPLOYMENT_LOG"
    echo "Service Access Points:" | tee -a "$DEPLOYMENT_LOG"
    
    # Get LoadBalancer IPs
    SERVICES=$(kubectl get svc -A 2>/dev/null | grep LoadBalancer | head -5 || echo "")
    if [ -n "$SERVICES" ]; then
        echo "$SERVICES" | while read line; do
            NS=$(echo $line | awk '{print $1}')
            NAME=$(echo $line | awk '{print $2}')
            IP=$(echo $line | awk '{print $NF}')
            if [ "$IP" != "<pending>" ] && [ -n "$IP" ]; then
                printf "  %-20s %-20s %s\n" "$NAME:" "$NS" "$IP" | tee -a "$DEPLOYMENT_LOG"
            fi
        done
    fi
fi

echo "" | tee -a "$DEPLOYMENT_LOG"

# Final Status Banner
if [ "$DRY_RUN" == "true" ]; then
    log_banner "DRY RUN COMPLETE - NO CHANGES MADE"
    echo "To execute the actual deployment, run:" | tee -a "$DEPLOYMENT_LOG"
    echo "  bash $0" | tee -a "$DEPLOYMENT_LOG"
else
    log_banner "DEPLOYMENT COMPLETE"
fi

echo "" | tee -a "$DEPLOYMENT_LOG"
echo "Log file saved to: $DEPLOYMENT_LOG" | tee -a "$DEPLOYMENT_LOG"
echo "Review any errors above and verify deployment with: kubectl get all -a" | tee -a "$DEPLOYMENT_LOG"
echo "" | tee -a "$DEPLOYMENT_LOG"

# Display important next steps
if [ "$DRY_RUN" != "true" ] && [ "$PHASE_END" -ge "8" ]; then
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}" | tee -a "$DEPLOYMENT_LOG"
    echo -e "${CYAN}║              CRITICAL POST-DEPLOYMENT TASKS                 ║${NC}" | tee -a "$DEPLOYMENT_LOG"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}" | tee -a "$DEPLOYMENT_LOG"
    echo "" | tee -a "$DEPLOYMENT_LOG"
    echo "1. CHANGE ALL DEFAULT PASSWORDS IMMEDIATELY" | tee -a "$DEPLOYMENT_LOG"
    echo "   - code-server: Set via CODER_PASSWORD environment variable" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Grafana: admin / ChanGedDefaultPassword123! (CHANGE NOW!)" | tee -a "$DEPLOYMENT_LOG"
    echo "" | tee -a "$DEPLOYMENT_LOG"
    echo "2. CONFIGURE DNS" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Get LoadBalancer IP: kubectl get svc ingress-nginx -n ingress-nginx" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Point domains to this IP" | tee -a "$DEPLOYMENT_LOG"
    echo "" | tee -a "$DEPLOYMENT_LOG"
    echo "3. VERIFY FUNCTIONALITY" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Test code-server access" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Verify Prometheus metrics collection" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Check Grafana dashboard" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Confirm backup execution" | tee -a "$DEPLOYMENT_LOG"
    echo "" | tee -a "$DEPLOYMENT_LOG"
    echo "4. TEAM TRAINING" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Operational procedures documentation" | tee -a "$DEPLOYMENT_LOG"
    echo "   - Troubleshooting runbooks" | tee -a "$DEPLOYMENT_LOG"
    echo "   - On-call support setup" | tee -a "$DEPLOYMENT_LOG"
    echo "" | tee -a "$DEPLOYMENT_LOG"
fi

echo -e "\n${GREEN}✅ Deployment orchestration complete!${NC}\n" | tee -a "$DEPLOYMENT_LOG"
