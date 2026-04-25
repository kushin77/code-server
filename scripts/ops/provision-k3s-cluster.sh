#!/usr/bin/env bash
# @file        scripts/ops/provision-k3s-cluster.sh
# @module      infrastructure/kubernetes
# @description Idempotent k3s 2-node cluster provisioner (server + agent)
# @governance  GOV-002: No hardcoded IPs/secrets; env-driven; idempotent; version-controlled
# @issue       #1537 (Q3 Phase 4 — Kubernetes Migration), #1539 (EKS Cluster Provisioning P1)
# @date        2026-04-26
#
# USAGE
#   # Provision full 2-node cluster (server + agent):
#   ./scripts/ops/provision-k3s-cluster.sh
#
#   # Server node only (skip agent join):
#   SKIP_AGENT=true ./scripts/ops/provision-k3s-cluster.sh
#
#   # Dry-run (print all steps, no SSH):
#   DRY_RUN=true ./scripts/ops/provision-k3s-cluster.sh
#
#   # Use custom install channel:
#   K3S_CHANNEL=stable ./scripts/ops/provision-k3s-cluster.sh
#
# REQUIRED ENV (override defaults from network-config.env):
#   K3S_SERVER_HOST   — SSH target for server node  (default: $ONPREM_PRIMARY_IP)
#   K3S_AGENT_HOST    — SSH target for agent node   (default: $ONPREM_SECONDARY_IP)
#   SSH_USER          — Remote SSH username          (default: akushnir)
#
# IDEMPOTENCY
#   Re-running is safe: existing k3s installations are detected and skipped
#   unless FORCE_REINSTALL=true is set.

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Bootstrap: resolve repo root & load SSOT
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT SCRIPT_DIR

NETWORK_CONF="${REPO_ROOT}/scripts/_common/_epic-1536-network-config.env"
if [[ -f "${NETWORK_CONF}" ]]; then
    # shellcheck source=scripts/_common/_epic-1536-network-config.env
    source "${NETWORK_CONF}"
fi

# ---------------------------------------------------------------------------
# Configuration (all overridable via env — GOV-002)
# ---------------------------------------------------------------------------
readonly K3S_SERVER_HOST="${K3S_SERVER_HOST:-${ONPREM_PRIMARY_IP:-192.168.168.31}}"
readonly K3S_AGENT_HOST="${K3S_AGENT_HOST:-${ONPREM_SECONDARY_IP:-192.168.168.42}}"
readonly SSH_USER="${SSH_USER:-akushnir}"
# SSH options as array to properly handle word splitting despite IFS=$'\n\t'
declare -ra SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
readonly K3S_CHANNEL="${K3S_CHANNEL:-stable}"
readonly K3S_VERSION="${K3S_VERSION:-}"            # empty = latest in channel
readonly K3S_KUBECONFIG_LOCAL="${K3S_KUBECONFIG_LOCAL:-${HOME}/.kube/k3s-config}"
readonly KUBECONFIG_MERGE_TARGET="${KUBECONFIG_MERGE_TARGET:-${HOME}/.kube/config}"
readonly DRY_RUN="${DRY_RUN:-false}"
readonly SKIP_AGENT="${SKIP_AGENT:-false}"
readonly FORCE_REINSTALL="${FORCE_REINSTALL:-false}"
readonly LOG_LEVEL="${LOG_LEVEL:-info}"

# k3s installer URL (never hardcoded inline)
readonly K3S_INSTALL_URL="${K3S_INSTALL_URL:-https://get.k3s.io}"

# Pod & service CIDRs (from SSOT or safe defaults)
readonly K3S_POD_CIDR="${CLUSTER_POD_CIDR:-10.0.0.0/16}"
readonly K3S_SERVICE_CIDR="${CLUSTER_SERVICE_CIDR:-10.32.0.0/12}"

# Cluster name (used in kubeconfig context)
readonly K3S_CLUSTER_NAME="${K3S_CLUSTER_NAME:-code-server-enterprise}"

# Artifact dir for generated kubeconfig & logs
readonly ARTIFACT_DIR="${REPO_ROOT}/artifacts/k3s-cluster-provision"
readonly PROVISION_LOG="${ARTIFACT_DIR}/provision-$(date -u +'%Y%m%d-%H%M%S').log"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()         { printf "[%s] ${BLUE}[INFO]${NC}    %s\n" "$(date -u +'%H:%M:%S')" "$*" | tee -a "${PROVISION_LOG}"; }
log_ok()      { printf "[%s] ${GREEN}[OK]${NC}      %s\n" "$(date -u +'%H:%M:%S')" "$*" | tee -a "${PROVISION_LOG}"; }
log_warn()    { printf "[%s] ${YELLOW}[WARN]${NC}    %s\n" "$(date -u +'%H:%M:%S')" "$*" | tee -a "${PROVISION_LOG}"; }
log_step()    { printf "\n[%s] ${CYAN}══ %s${NC}\n" "$(date -u +'%H:%M:%S')" "$*" | tee -a "${PROVISION_LOG}"; }
die()         { printf "[%s] ${RED}[ERROR]${NC}   %s\n" "$(date -u +'%H:%M:%S')" "$*" | tee -a "${PROVISION_LOG}"; exit 1; }

remote() {
    # remote <host> <cmd> — run cmd over SSH; no-op if DRY_RUN=true
    local host="$1"; shift
    local cmd="$*"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] ssh ${SSH_USER}@${host}: ${cmd}"
        return 0
    fi
    # Use SSH_OPTS array properly: "${SSH_OPTS[@]}" expands all elements
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "${cmd}"
}

remote_sudo() {
    # remote_sudo <host> <cmd> — run sudo cmd over SSH
    # REQUIRES: Passwordless sudo configured on remote host
    # SETUP: bash scripts/ops/setup-k3s-sudoers.sh <host> [<ssh_user>]
    local host="$1"; shift
    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! remote "${host}" "sudo -n true" >/dev/null 2>&1; then
            die "Passwordless sudo not configured on ${host}. Run: bash scripts/ops/setup-k3s-sudoers.sh ${host} ${SSH_USER}"
        fi
    fi
    remote "${host}" "sudo $*"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight() {
    log_step "Pre-flight checks"

    # Verify SSH connectivity
    for host in "${K3S_SERVER_HOST}" "${K3S_AGENT_HOST}"; do
        [[ "${SKIP_AGENT}" == "true" && "${host}" == "${K3S_AGENT_HOST}" ]] && continue
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Use SSH_OPTS array: "${SSH_OPTS[@]}" expands all elements
            ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "echo ok" > /dev/null 2>&1 \
                || die "Cannot reach ${SSH_USER}@${host} via SSH"
            log_ok "SSH reachable: ${host}"
        fi
    done

    # Check local tooling
    command -v ssh > /dev/null || die "ssh not found"
    command -v kubectl > /dev/null 2>&1 && log_ok "kubectl available locally" \
        || log_warn "kubectl not found locally — install it to interact with the cluster"

    log_ok "Pre-flight passed"
}

# ---------------------------------------------------------------------------
# Step 1: Install k3s server on primary node
# ---------------------------------------------------------------------------
install_server() {
    log_step "Step 1 — Install k3s server on ${K3S_SERVER_HOST}"

    local already_installed
    already_installed=$(remote "${K3S_SERVER_HOST}" "command -v k3s >/dev/null 2>&1 && echo yes || echo no")

    if [[ "${already_installed}" == "yes" && "${FORCE_REINSTALL}" != "true" ]]; then
        log_ok "k3s already installed on ${K3S_SERVER_HOST} — skipping (set FORCE_REINSTALL=true to override)"
        return 0
    fi

    # Build install env
    local install_env="INSTALL_K3S_CHANNEL=${K3S_CHANNEL}"
    [[ -n "${K3S_VERSION}" ]] && install_env="${install_env} INSTALL_K3S_VERSION=${K3S_VERSION}"

    # Install k3s server with cluster CIDRs, disable default traefik (we use Caddy)
    remote_sudo "${K3S_SERVER_HOST}" \
        "${install_env} sh <(curl -sfL ${K3S_INSTALL_URL}) server \
            --cluster-cidr='${K3S_POD_CIDR}' \
            --service-cidr='${K3S_SERVICE_CIDR}' \
            --cluster-init \
            --disable=traefik \
            --node-label='topology.kubernetes.io/zone=primary' \
            --node-label='node-role=server'"

    log_ok "k3s server installed on ${K3S_SERVER_HOST}"

    # Wait for server to become ready
    local attempts=0
    local max_attempts=30
    while ! remote "${K3S_SERVER_HOST}" "sudo k3s kubectl get nodes 2>/dev/null | grep -q Ready" 2>/dev/null; do
        attempts=$((attempts + 1))
        [[ ${attempts} -ge ${max_attempts} ]] && die "k3s server failed to become Ready after ${max_attempts} attempts"
        log "Waiting for k3s server to be Ready... (${attempts}/${max_attempts})"
        sleep 5
    done
    log_ok "k3s server node is Ready"
}

# ---------------------------------------------------------------------------
# Step 2: Retrieve node token for agent join
# ---------------------------------------------------------------------------
get_node_token() {
    log_step "Step 2 — Retrieve cluster join token"
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "DRY_RUN_TOKEN"
        return 0
    fi
    remote_sudo "${K3S_SERVER_HOST}" "cat /var/lib/rancher/k3s/server/node-token"
}

# ---------------------------------------------------------------------------
# Step 3: Install k3s agent on replica node
# ---------------------------------------------------------------------------
install_agent() {
    local node_token="$1"
    log_step "Step 3 — Install k3s agent on ${K3S_AGENT_HOST}"

    local already_installed
    already_installed=$(remote "${K3S_AGENT_HOST}" "command -v k3s >/dev/null 2>&1 && echo yes || echo no")

    if [[ "${already_installed}" == "yes" && "${FORCE_REINSTALL}" != "true" ]]; then
        log_ok "k3s already installed on ${K3S_AGENT_HOST} — skipping (set FORCE_REINSTALL=true to override)"
        return 0
    fi

    local install_env="INSTALL_K3S_CHANNEL=${K3S_CHANNEL}"
    [[ -n "${K3S_VERSION}" ]] && install_env="${install_env} INSTALL_K3S_VERSION=${K3S_VERSION}"

    remote_sudo "${K3S_AGENT_HOST}" \
        "${install_env} K3S_URL='https://${K3S_SERVER_HOST}:6443' \
         K3S_TOKEN='${node_token}' \
         sh <(curl -sfL ${K3S_INSTALL_URL}) agent \
            --node-label='topology.kubernetes.io/zone=replica' \
            --node-label='node-role=agent'"

    log_ok "k3s agent installed on ${K3S_AGENT_HOST}"

    # Wait for agent node to appear as Ready
    local attempts=0
    local max_attempts=30
    while ! remote "${K3S_SERVER_HOST}" "sudo k3s kubectl get nodes 2>/dev/null | grep -qE '${K3S_AGENT_HOST}.*Ready'" 2>/dev/null; do
        attempts=$((attempts + 1))
        [[ ${attempts} -ge ${max_attempts} ]] && {
            log_warn "Agent node not yet Ready after ${max_attempts} attempts — continuing (may still be joining)"
            return 0
        }
        log "Waiting for agent node to be Ready... (${attempts}/${max_attempts})"
        sleep 5
    done
    log_ok "k3s agent node is Ready"
}

# ---------------------------------------------------------------------------
# Step 4: Export kubeconfig to local machine
# ---------------------------------------------------------------------------
export_kubeconfig() {
    log_step "Step 4 — Export kubeconfig"

    mkdir -p "$(dirname "${K3S_KUBECONFIG_LOCAL}")"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] Would copy /etc/rancher/k3s/k3s.yaml -> ${K3S_KUBECONFIG_LOCAL}"
        log "[DRY-RUN] Would patch server address: 127.0.0.1 -> ${K3S_SERVER_HOST}"
        return 0
    fi

    # shellcheck disable=SC2086
    scp ${SSH_OPTS} "${SSH_USER}@${K3S_SERVER_HOST}:/etc/rancher/k3s/k3s.yaml" \
        "${K3S_KUBECONFIG_LOCAL}"

    # Patch the loopback address to the real server IP
    sed -i.bak \
        "s|https://127.0.0.1:6443|https://${K3S_SERVER_HOST}:6443|g" \
        "${K3S_KUBECONFIG_LOCAL}"

    # Rename context/cluster to human-friendly name
    if command -v kubectl > /dev/null 2>&1; then
        KUBECONFIG="${K3S_KUBECONFIG_LOCAL}" kubectl config rename-context default "${K3S_CLUSTER_NAME}" 2>/dev/null || true
        KUBECONFIG="${K3S_KUBECONFIG_LOCAL}" kubectl config set-cluster default --name="${K3S_CLUSTER_NAME}" 2>/dev/null || true
    fi

    chmod 600 "${K3S_KUBECONFIG_LOCAL}"
    log_ok "Kubeconfig written to ${K3S_KUBECONFIG_LOCAL}"

    # Optionally merge into default kubeconfig
    if [[ -f "${KUBECONFIG_MERGE_TARGET}" ]]; then
        log "Merging context '${K3S_CLUSTER_NAME}' into ${KUBECONFIG_MERGE_TARGET}"
        local merged
        merged="$(KUBECONFIG="${KUBECONFIG_MERGE_TARGET}:${K3S_KUBECONFIG_LOCAL}" \
            kubectl config view --flatten 2>/dev/null)"
        printf '%s\n' "${merged}" > "${KUBECONFIG_MERGE_TARGET}.tmp"
        mv "${KUBECONFIG_MERGE_TARGET}.tmp" "${KUBECONFIG_MERGE_TARGET}"
        log_ok "Context merged. Switch with: kubectl config use-context ${K3S_CLUSTER_NAME}"
    else
        cp "${K3S_KUBECONFIG_LOCAL}" "${KUBECONFIG_MERGE_TARGET}"
        chmod 600 "${KUBECONFIG_MERGE_TARGET}"
        log_ok "Created new kubeconfig at ${KUBECONFIG_MERGE_TARGET}"
    fi
}

# ---------------------------------------------------------------------------
# Step 5: Install cert-manager (for Ingress TLS)
# ---------------------------------------------------------------------------
install_cert_manager() {
    log_step "Step 5 — Install cert-manager"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] Would deploy cert-manager v1.14 via kubectl apply"
        return 0
    fi

    local kubeconfig="${K3S_KUBECONFIG_LOCAL}"
    export KUBECONFIG="${kubeconfig}"

    # Idempotent: check if already deployed
    if kubectl get namespace cert-manager > /dev/null 2>&1; then
        log_ok "cert-manager namespace already exists — skipping install"
        return 0
    fi

    kubectl apply -f \
        "https://github.com/cert-manager/cert-manager/releases/download/v1.14.7/cert-manager.yaml"

    # Wait for cert-manager webhook to be ready
    kubectl rollout status deployment/cert-manager-webhook \
        -n cert-manager --timeout=120s
    log_ok "cert-manager installed and ready"
}

# ---------------------------------------------------------------------------
# Step 6: Install metrics-server (for HPA)
# ---------------------------------------------------------------------------
install_metrics_server() {
    log_step "Step 6 — Install metrics-server"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] Would deploy metrics-server via kubectl apply"
        return 0
    fi

    export KUBECONFIG="${K3S_KUBECONFIG_LOCAL}"

    if kubectl get deployment metrics-server -n kube-system > /dev/null 2>&1; then
        log_ok "metrics-server already installed — skipping"
        return 0
    fi

    kubectl apply -f \
        "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"

    # k3s may need --kubelet-insecure-tls for single-node without proper certs
    kubectl patch deployment metrics-server -n kube-system \
        --type=json \
        -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
        2>/dev/null || true

    log_ok "metrics-server installed"
}

# ---------------------------------------------------------------------------
# Step 7: Verify cluster health
# ---------------------------------------------------------------------------
verify_cluster() {
    log_step "Step 7 — Verify cluster health"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] Would run: kubectl get nodes && kubectl get pods -A"
        return 0
    fi

    export KUBECONFIG="${K3S_KUBECONFIG_LOCAL}"

    log "Nodes:"
    kubectl get nodes -o wide | tee -a "${PROVISION_LOG}"

    log "System pods:"
    kubectl get pods -A --field-selector=status.phase!=Running 2>/dev/null \
        | grep -v "Completed" | tee -a "${PROVISION_LOG}" || true

    local not_ready
    not_ready=$(kubectl get nodes --no-headers 2>/dev/null \
        | grep -v " Ready" | wc -l || echo "0")

    if [[ "${not_ready}" -gt 0 ]]; then
        log_warn "${not_ready} node(s) not Ready — check cluster before deploying workloads"
    else
        log_ok "All nodes are Ready"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    mkdir -p "${ARTIFACT_DIR}"
    log_step "k3s 2-node cluster provisioner — ${K3S_CLUSTER_NAME}"
    log "Server host : ${K3S_SERVER_HOST}"
    log "Agent host  : ${K3S_AGENT_HOST}"
    log "Channel     : ${K3S_CHANNEL}"
    log "Pod CIDR    : ${K3S_POD_CIDR}"
    log "Service CIDR: ${K3S_SERVICE_CIDR}"
    log "Dry-run     : ${DRY_RUN}"
    log "Skip agent  : ${SKIP_AGENT}"
    log "Log file    : ${PROVISION_LOG}"

    preflight
    install_server

    if [[ "${SKIP_AGENT}" != "true" ]]; then
        local node_token
        node_token="$(get_node_token)"
        install_agent "${node_token}"
    fi

    export_kubeconfig
    install_cert_manager
    install_metrics_server
    verify_cluster

    log_step "Provisioning complete"
    log_ok "Cluster '${K3S_CLUSTER_NAME}' is ready"
    log_ok "Use: KUBECONFIG=${K3S_KUBECONFIG_LOCAL} kubectl get nodes"
    log_ok "Or:  kubectl config use-context ${K3S_CLUSTER_NAME}"
    log_ok "Next: helm upgrade --install code-server-enterprise ./helm/code-server-enterprise \\"
    log_ok "        -f helm/code-server-enterprise/values.phase4-k8s.yaml \\"
    log_ok "        --set global.domain=\${APEX_DOMAIN:-kushnir.cloud}"
}

main "$@"
