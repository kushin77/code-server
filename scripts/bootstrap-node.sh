#!/bin/bash
# scripts/bootstrap-node.sh
# ==========================
# Provision any bare-metal Ubuntu host to a production role in <15 minutes.
# Implements the 10-step bootstrap design from issue #367.
#
# Usage:
#   sudo ./scripts/bootstrap-node.sh --role <role> [--env production] [--dry-run] [--no-dns]
#
# Options:
#   --role      Node role from environments/<env>/hosts.yml (required)
#   --env       Target environment (default: production)
#   --dry-run   Print all steps without executing (safe to audit)
#   --no-dns    Skip DNS registration (CoreDNS already running)
#   --help      Show this help
#
# Examples:
#   sudo ./scripts/bootstrap-node.sh --role primary
#   sudo ./scripts/bootstrap-node.sh --role gpu-worker --env production
#   sudo ./scripts/bootstrap-node.sh --role replica --dry-run
#
# Prerequisites:
#   - Ubuntu 22.04 or 24.04
#   - Repo already cloned on target node
#   - SSH key-based access to primary.prod.internal
#   - Run as non-root user via sudo (not as root directly)

set -euo pipefail

# ─── Constants ────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
LOG_FILE="/var/log/bootstrap-node.log"
MIN_UBUNTU_VERSION="22"
DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_APT_REPO="https://download.docker.com/linux/ubuntu"

# ─── Defaults ─────────────────────────────────────────────────────────────────

ROLE=""
ENV_NAME="production"
DRY_RUN=false
SKIP_DNS=false

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Logging ──────────────────────────────────────────────────────────────────

log()     { echo -e "${BOLD}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "${LOG_FILE}"; }
log_ok()  { echo -e "${GREEN}  ✓${RESET} $*" | tee -a "${LOG_FILE}"; }
log_warn(){ echo -e "${YELLOW}  ⚠${RESET} $*" | tee -a "${LOG_FILE}"; }
log_err() { echo -e "${RED}  ✗${RESET} $*" | tee -a "${LOG_FILE}" >&2; }
log_step(){ echo -e "\n${BLUE}${BOLD}━━ Step $1: $2 ━━${RESET}" | tee -a "${LOG_FILE}"; }
dry()     {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}  [DRY-RUN]${RESET} $*" | tee -a "${LOG_FILE}"
        return 0
    fi
    "$@"
}

# ─── Help ─────────────────────────────────────────────────────────────────────

usage() {
    sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# ─── Argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --role)       ROLE="$2"; shift 2 ;;
        --env)        ENV_NAME="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --no-dns)     SKIP_DNS=true; shift ;;
        --help|-h)    usage ;;
        *) log_err "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "${ROLE}" ]]; then
    log_err "--role is required"
    usage
fi

# ─── Step 1: Preflight checks ─────────────────────────────────────────────────

log_step "1" "Preflight checks"

# Must be run with sudo (not as root directly, to preserve $SUDO_USER)
if [[ "${EUID}" -ne 0 ]]; then
    log_err "This script must be run with sudo: sudo $0 $*"
    exit 1
fi

if [[ -z "${SUDO_USER:-}" ]]; then
    log_err "Run with 'sudo' as a non-root user, not as root directly"
    exit 1
fi

# OS check
OS_VERSION=""
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    OS_VERSION="${VERSION_ID:-0}"
fi
MAJOR_VERSION="${OS_VERSION%%.*}"
if [[ "${ID:-}" != "ubuntu" ]] || [[ "${MAJOR_VERSION}" -lt "${MIN_UBUNTU_VERSION}" ]]; then
    log_err "Requires Ubuntu ${MIN_UBUNTU_VERSION}.04+, detected: ${ID:-unknown} ${OS_VERSION}"
    exit 1
fi
log_ok "OS: Ubuntu ${OS_VERSION}"

# Repo root must contain expected files
if [[ ! -f "${REPO_ROOT}/environments/${ENV_NAME}/hosts.yml" ]]; then
    log_err "Inventory not found: ${REPO_ROOT}/environments/${ENV_NAME}/hosts.yml"
    log_err "Clone the repo first: git clone <repo> && cd code-server-enterprise"
    exit 1
fi
log_ok "Repo root: ${REPO_ROOT}"
log_ok "Inventory: environments/${ENV_NAME}/hosts.yml"

# Network reachability to primary
INVENTORY_FILE="${REPO_ROOT}/environments/${ENV_NAME}/hosts.yml"
PRIMARY_IP=""
if command -v yq &>/dev/null && [[ -f "${INVENTORY_FILE}" ]]; then
    # Use canonical inventory (env.sh) when available
    # shellcheck source=scripts/lib/env.sh
    source "${REPO_ROOT}/scripts/lib/env.sh" 2>/dev/null || true
    PRIMARY_IP="${PRIMARY_HOST:-}"
fi
if [[ -z "${PRIMARY_IP}" ]]; then
    log_warn "yq or inventory not available — reading primary IP from inventory fallback"
    PRIMARY_IP="$(grep -A2 'role: primary' "${INVENTORY_FILE}" 2>/dev/null | grep 'ip:' | awk '{print $2}' || echo "")"
fi

if ! ping -c 2 -W 3 "${PRIMARY_IP}" &>/dev/null 2>&1; then
    log_warn "Cannot ping primary (${PRIMARY_IP}) — continuing (may be bootstrapping primary itself)"
else
    log_ok "Network: primary ${PRIMARY_IP} reachable"
fi

log_ok "Preflight checks passed"

# ─── Step 2: System dependencies ──────────────────────────────────────────────

log_step "2" "System dependencies"

PACKAGES_NEEDED=(git curl jq keepalived age sops)

# Add Docker only if not already installed
if ! command -v docker &>/dev/null; then
    log "Installing Docker CE..."
    dry apt-get update -qq
    dry apt-get install -y -qq ca-certificates gnupg lsb-release

    # Docker GPG key
    dry install -m 0755 -d /etc/apt/keyrings
    if [[ "${DRY_RUN}" == "false" ]]; then
        curl -fsSL "${DOCKER_GPG_URL}" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_APT_REPO} $(lsb_release -cs) stable" \
            > /etc/apt/sources.list.d/docker.list
    else
        echo -e "${YELLOW}  [DRY-RUN]${RESET} Would add Docker apt repo and GPG key" | tee -a "${LOG_FILE}"
    fi
    dry apt-get update -qq
    dry apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    dry systemctl enable --now docker
    dry usermod -aG docker "${SUDO_USER}"
    log_ok "Docker CE installed"
else
    log_ok "Docker CE already installed: $(docker --version 2>/dev/null || true)"
fi

# Install yq if missing
if ! command -v yq &>/dev/null; then
    log "Installing yq..."
    if [[ "${DRY_RUN}" == "false" ]]; then
        YQ_VERSION="$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest | grep tag_name | cut -d '"' -f 4)"
        YQ_VERSION="${YQ_VERSION:-v4.40.5}"
        curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
            -o /usr/local/bin/yq
        chmod +x /usr/local/bin/yq
    else
        echo -e "${YELLOW}  [DRY-RUN]${RESET} Would install yq from GitHub releases" | tee -a "${LOG_FILE}"
    fi
    log_ok "yq installed"
else
    log_ok "yq already installed: $(yq --version 2>/dev/null || true)"
fi

# Install remaining packages
INSTALL_LIST=()
for pkg in "${PACKAGES_NEEDED[@]}"; do
    if ! command -v "${pkg}" &>/dev/null && ! dpkg -l "${pkg}" &>/dev/null 2>&1; then
        INSTALL_LIST+=("${pkg}")
    fi
done

if [[ ${#INSTALL_LIST[@]} -gt 0 ]]; then
    log "Installing: ${INSTALL_LIST[*]}"
    dry apt-get update -qq
    dry apt-get install -y -qq "${INSTALL_LIST[@]}"
    log_ok "Installed: ${INSTALL_LIST[*]}"
else
    log_ok "All base packages already installed"
fi

# ─── Step 3: Read inventory ────────────────────────────────────────────────────

log_step "3" "Read inventory for role '${ROLE}'"

INVENTORY_FILE="${REPO_ROOT}/environments/${ENV_NAME}/hosts.yml"

# Verify role exists in inventory
ROLE_COUNT=0
if command -v yq &>/dev/null && [[ "${DRY_RUN}" == "false" ]]; then
    ROLE_COUNT="$(yq '[.hosts[] | select(.roles[] == "'"${ROLE}"'")] | length' "${INVENTORY_FILE}" 2>/dev/null || echo 0)"
fi

if [[ "${DRY_RUN}" == "false" ]] && [[ "${ROLE_COUNT}" -eq 0 ]]; then
    log_err "Role '${ROLE}' not found in ${INVENTORY_FILE}"
    log_err "Available roles: $(yq '.hosts[].roles[]' "${INVENTORY_FILE}" 2>/dev/null | sort -u | tr '\n' ', ' || true)"
    exit 1
fi

# Export topology variables from inventory
if command -v yq &>/dev/null && [[ "${DRY_RUN}" == "false" ]]; then
    export PRIMARY_HOST
    export REPLICA_HOST
    export VIP_IP
    export THIS_HOST_IP
    export THIS_FQDN
    PRIMARY_HOST="$(yq '.hosts[] | select(.roles[] == "primary") | .ip' "${INVENTORY_FILE}" | head -1)"
    REPLICA_HOST="$(yq '.hosts[] | select(.roles[] == "replica") | .ip' "${INVENTORY_FILE}" | head -1 || echo "")"
    VIP_IP="$(yq '.vip.ip // "192.168.168.30"' "${INVENTORY_FILE}" || echo "192.168.168.30")"
    THIS_HOST_IP="$(yq '.hosts[] | select(.roles[] == "'"${ROLE}"'") | .ip' "${INVENTORY_FILE}" | head -1)"
    THIS_FQDN="$(yq '.hosts[] | select(.roles[] == "'"${ROLE}"'") | .fqdn' "${INVENTORY_FILE}" | head -1 || echo "${ROLE}.prod.internal")"
else
    # Dry-run defaults
    PRIMARY_HOST="${PRIMARY_IP}"
    REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
    VIP_IP="192.168.168.30"
    THIS_HOST_IP="${PRIMARY_IP}"
    THIS_FQDN="${ROLE}.prod.internal"
fi

log_ok "PRIMARY_HOST=${PRIMARY_HOST}"
log_ok "VIP_IP=${VIP_IP}"
log_ok "THIS_FQDN=${THIS_FQDN}"

# ─── Step 4: DNS registration ──────────────────────────────────────────────────

log_step "4" "DNS registration"

if [[ "${SKIP_DNS}" == "true" ]]; then
    log_ok "Skipping DNS registration (--no-dns)"
else
    ZONE_FILE="${REPO_ROOT}/config/coredns/zones/prod.internal.zone"

    # Add A-record if not already present
    A_RECORD="${ROLE}    IN A    ${THIS_HOST_IP}"
    if [[ -f "${ZONE_FILE}" ]] && grep -q "^${ROLE}" "${ZONE_FILE}" 2>/dev/null; then
        log_ok "DNS A-record for ${ROLE} already exists in zone file"
    else
        log "Adding DNS A-record: ${A_RECORD}"
        if [[ "${DRY_RUN}" == "false" ]]; then
            echo "${A_RECORD}" >> "${ZONE_FILE}"
            # Increment SOA serial (YYYYMMDDNN format)
            TODAY="$(date +%Y%m%d)"
            CURRENT_SERIAL="$(grep -oP 'SOA.*\K[0-9]{10}' "${ZONE_FILE}" | head -1 || echo "${TODAY}01")"
            if [[ "${CURRENT_SERIAL}" == "${TODAY}"* ]]; then
                NN=$(( 10#${CURRENT_SERIAL: -2} + 1 ))
                NEW_SERIAL="${TODAY}$(printf '%02d' "${NN}")"
            else
                NEW_SERIAL="${TODAY}01"
            fi
            sed -i "s/${CURRENT_SERIAL}/${NEW_SERIAL}/" "${ZONE_FILE}"
        else
            echo -e "${YELLOW}  [DRY-RUN]${RESET} Would add: ${A_RECORD} to ${ZONE_FILE}" | tee -a "${LOG_FILE}"
        fi
        log_ok "Zone file updated (serial bumped)"
    fi

    # Reload CoreDNS on primary
    log "Reloading CoreDNS on primary (${PRIMARY_HOST})..."
    if [[ "${DRY_RUN}" == "false" ]]; then
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            "${SUDO_USER}@${PRIMARY_HOST}" \
            "docker exec coredns kill -SIGUSR1 1 2>/dev/null || docker restart coredns" 2>/dev/null || \
            log_warn "Could not reload CoreDNS — reload manually: docker exec coredns kill -SIGUSR1 1"
    else
        echo -e "${YELLOW}  [DRY-RUN]${RESET} Would reload CoreDNS on ${PRIMARY_HOST}" | tee -a "${LOG_FILE}"
    fi

    # Configure systemd-resolved for *.prod.internal
    RESOLVED_DROP_IN="/etc/systemd/resolved.conf.d/prod-internal.conf"
    if [[ ! -f "${RESOLVED_DROP_IN}" ]]; then
        log "Configuring systemd-resolved for *.prod.internal → ${PRIMARY_HOST}..."
        dry mkdir -p /etc/systemd/resolved.conf.d
        if [[ "${DRY_RUN}" == "false" ]]; then
            cat > "${RESOLVED_DROP_IN}" <<EOF
# Bootstrap: forward .prod.internal queries to CoreDNS on primary
[Resolve]
DNS=${PRIMARY_HOST}
Domains=prod.internal
EOF
            systemctl restart systemd-resolved
        else
            echo -e "${YELLOW}  [DRY-RUN]${RESET} Would create ${RESOLVED_DROP_IN}" | tee -a "${LOG_FILE}"
        fi
        log_ok "systemd-resolved configured for prod.internal"
    else
        log_ok "systemd-resolved drop-in already present"
    fi
fi

# ─── Step 5: TLS certificates ──────────────────────────────────────────────────

log_step "5" "TLS certificates"

TLS_DIR="/etc/ssl/prod-internal"
CERT_FILE="${TLS_DIR}/host.crt"
KEY_FILE="${TLS_DIR}/host.key"

if [[ -f "${CERT_FILE}" ]] && [[ -f "${KEY_FILE}" ]]; then
    CERT_EXPIRY="$(openssl x509 -enddate -noout -in "${CERT_FILE}" 2>/dev/null | cut -d= -f2 || echo "unknown")"
    log_ok "TLS cert already present (expires: ${CERT_EXPIRY})"
else
    log "Generating self-signed TLS certificate for ${THIS_FQDN}..."
    if [[ "${DRY_RUN}" == "false" ]]; then
        mkdir -p "${TLS_DIR}"
        chmod 750 "${TLS_DIR}"
        openssl req -x509 -nodes -newkey rsa:4096 \
            -keyout "${KEY_FILE}" \
            -out "${CERT_FILE}" \
            -days 3650 \
            -subj "/CN=${THIS_FQDN}/O=prod.internal/C=US" \
            -addext "subjectAltName=DNS:${THIS_FQDN},DNS:${ROLE}.prod.internal,IP:${THIS_HOST_IP}" \
            2>/dev/null
        chmod 640 "${KEY_FILE}"
        chmod 644 "${CERT_FILE}"
    else
        echo -e "${YELLOW}  [DRY-RUN]${RESET} Would generate RSA-4096 cert for ${THIS_FQDN}" | tee -a "${LOG_FILE}"
    fi
    log_ok "TLS certificate created: ${CERT_FILE}"
fi

# ─── Step 6: SOPS/age key setup ────────────────────────────────────────────────

log_step "6" "SOPS/age key setup"

AGE_KEY_DIR="/home/${SUDO_USER}/.config/sops/age"
AGE_KEY_FILE="${AGE_KEY_DIR}/keys.txt"

if [[ -f "${AGE_KEY_FILE}" ]]; then
    log_ok "age key already present for ${SUDO_USER}"
else
    log "Generating age key for ${SUDO_USER}..."
    if [[ "${DRY_RUN}" == "false" ]]; then
        sudo -u "${SUDO_USER}" mkdir -p "${AGE_KEY_DIR}"
        chmod 700 "${AGE_KEY_DIR}"
        sudo -u "${SUDO_USER}" age-keygen -o "${AGE_KEY_FILE}" 2>/dev/null
        chmod 600 "${AGE_KEY_FILE}"
        AGE_PUBKEY="$(sudo -u "${SUDO_USER}" age-keygen -y "${AGE_KEY_FILE}" 2>/dev/null || grep '^# public key' "${AGE_KEY_FILE}" | awk '{print $NF}')"
        log_warn "New age public key: ${AGE_PUBKEY}"
        log_warn "Add to .sops.yaml recipients and re-encrypt secrets before using SOPS"
    else
        echo -e "${YELLOW}  [DRY-RUN]${RESET} Would generate age key for ${SUDO_USER}" | tee -a "${LOG_FILE}"
    fi
    log_ok "age key generated: ${AGE_KEY_FILE}"
fi

# Set SOPS_AGE_KEY_FILE for downstream commands
export SOPS_AGE_KEY_FILE="${AGE_KEY_FILE}"

# ─── Step 7: Deploy role services ─────────────────────────────────────────────

log_step "7" "Deploy role services (profile: ${ROLE})"

COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log_err "docker-compose.yml not found at ${REPO_ROOT}"
    exit 1
fi

# Check if services already running for this profile
RUNNING_COUNT=0
if command -v docker &>/dev/null && [[ "${DRY_RUN}" == "false" ]]; then
    RUNNING_COUNT="$(cd "${REPO_ROOT}" && docker compose ps --status running --format json 2>/dev/null | wc -l || echo 0)"
fi

if [[ "${RUNNING_COUNT}" -gt 0 ]]; then
    log_ok "Docker Compose services already running (${RUNNING_COUNT} containers) — skipping up"
else
    log "Starting services for role '${ROLE}'..."
    if [[ "${DRY_RUN}" == "false" ]]; then
        cd "${REPO_ROOT}"
        # Pull latest images before starting
        docker compose pull --quiet 2>/dev/null || log_warn "Could not pull latest images — using cached"
        docker compose --profile "${ROLE}" up -d --remove-orphans
        # Wait for health checks (max 3 minutes)
        log "Waiting for services to become healthy (timeout: 3m)..."
        TIMEOUT=180
        START_TIME="$(date +%s)"
        while true; do
            UNHEALTHY="$(docker compose ps --format json 2>/dev/null | \
                python3 -c "import sys,json; [print(c['Name']) for c in json.load(sys.stdin) if c.get('Health','') not in ('healthy','')]" 2>/dev/null || true)"
            if [[ -z "${UNHEALTHY}" ]]; then
                break
            fi
            ELAPSED=$(( $(date +%s) - START_TIME ))
            if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
                log_warn "Timeout waiting for healthy: ${UNHEALTHY}"
                break
            fi
            sleep 5
        done
    else
        echo -e "${YELLOW}  [DRY-RUN]${RESET} Would run: docker compose --profile ${ROLE} up -d" | tee -a "${LOG_FILE}"
    fi
    log_ok "Services started for role '${ROLE}'"
fi

# ─── Step 8: Keepalived (primary/replica roles only) ───────────────────────────

log_step "8" "Keepalived VRRP"

KEEPALIVED_ROLES=("primary" "replica")
NEEDS_KEEPALIVED=false
for r in "${KEEPALIVED_ROLES[@]}"; do
    if [[ "${ROLE}" == "${r}" ]]; then
        NEEDS_KEEPALIVED=true
        break
    fi
done

if [[ "${NEEDS_KEEPALIVED}" == "false" ]]; then
    log_ok "Keepalived not required for role '${ROLE}' — skipping"
else
    KEEPALIVED_SRC="${REPO_ROOT}/config/keepalived/keepalived-${ROLE}.conf"

    if [[ ! -f "${KEEPALIVED_SRC}" ]]; then
        log_warn "Keepalived template not found: ${KEEPALIVED_SRC} — run scripts/deploy-keepalived.sh"
    else
        KEEPALIVED_DEST="/etc/keepalived/keepalived.conf"
        VRRP_AUTH_PASS="${VRRP_AUTH_PASS:-}"

        if [[ -z "${VRRP_AUTH_PASS}" ]]; then
            log_warn "VRRP_AUTH_PASS not set — using placeholder 'CHANGEME' (update before production use)"
            VRRP_AUTH_PASS="CHANGEME"
        fi

        log "Deploying Keepalived config for role '${ROLE}'..."
        if [[ "${DRY_RUN}" == "false" ]]; then
            mkdir -p /etc/keepalived
            sed "s/\$VRRP_AUTH_PASS/${VRRP_AUTH_PASS}/g" "${KEEPALIVED_SRC}" > "${KEEPALIVED_DEST}"
            # Validate config
            keepalived --config-test --config-file "${KEEPALIVED_DEST}" 2>/dev/null || \
                log_warn "keepalived --config-test failed — review ${KEEPALIVED_DEST}"
            systemctl enable --now keepalived
            # Verify VIP (only on primary)
            if [[ "${ROLE}" == "primary" ]]; then
                sleep 3
                if ip addr show | grep -q "${VIP_IP}"; then
                    log_ok "VIP ${VIP_IP} assigned to this host"
                else
                    log_warn "VIP ${VIP_IP} not yet visible — may take a few seconds after peer sync"
                fi
            fi
        else
            echo -e "${YELLOW}  [DRY-RUN]${RESET} Would deploy ${KEEPALIVED_SRC} → ${KEEPALIVED_DEST}" | tee -a "${LOG_FILE}"
        fi
        log_ok "Keepalived configured for role '${ROLE}'"
    fi
fi

# ─── Step 9: Register with Prometheus ──────────────────────────────────────────

log_step "9" "Prometheus scrape target registration"

TARGETS_DIR="${REPO_ROOT}/config/prometheus/targets"
TARGET_FILE="${TARGETS_DIR}/${ROLE}.yml"

if [[ -f "${TARGET_FILE}" ]] && grep -q "${THIS_HOST_IP}" "${TARGET_FILE}" 2>/dev/null; then
    log_ok "Prometheus scrape target already registered: ${TARGET_FILE}"
else
    log "Registering Prometheus scrape target for ${THIS_FQDN}..."
    if [[ "${DRY_RUN}" == "false" ]]; then
        mkdir -p "${TARGETS_DIR}"
        cat > "${TARGET_FILE}" <<EOF
# Auto-generated by bootstrap-node.sh for role: ${ROLE}
# Host: ${THIS_FQDN} (${THIS_HOST_IP})
- targets:
    - "${THIS_FQDN}:9100"   # node_exporter
    - "${THIS_FQDN}:9323"   # docker metrics
  labels:
    role: "${ROLE}"
    env: "${ENV_NAME}"
    host: "${THIS_FQDN}"
EOF
        log_ok "Prometheus target file created: ${TARGET_FILE}"

        # Reload Prometheus on primary if reachable
        if ping -c 1 -W 2 "${PRIMARY_HOST}" &>/dev/null 2>&1; then
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                "${SUDO_USER}@${PRIMARY_HOST}" \
                "docker exec prometheus kill -SIGHUP 1 2>/dev/null || true" 2>/dev/null && \
                log_ok "Prometheus reloaded on primary" || \
                log_warn "Could not reload Prometheus — reload manually"
        fi
    else
        echo -e "${YELLOW}  [DRY-RUN]${RESET} Would create ${TARGET_FILE} with scrape targets for ${THIS_FQDN}" | tee -a "${LOG_FILE}"
    fi
fi

# ─── Step 10: Validation ───────────────────────────────────────────────────────

log_step "10" "Validation"

PASS=0; FAIL=0

check() {
    local desc="$1"
    local cmd="$2"
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}  [DRY-RUN]${RESET} Would check: ${desc}" | tee -a "${LOG_FILE}"
        return 0
    fi
    if eval "${cmd}" &>/dev/null 2>&1; then
        log_ok "${desc}"
        (( PASS++ )) || true
    else
        log_warn "FAIL: ${desc}"
        (( FAIL++ )) || true
    fi
}

check "Docker daemon running"                "systemctl is-active docker"
check "Docker Compose up (containers exist)" "docker compose -f '${COMPOSE_FILE}' ps --status running 2>/dev/null | grep -q Up"
check "systemd-resolved running"             "systemctl is-active systemd-resolved"
check "DNS resolves primary.prod.internal"   "getent hosts primary.prod.internal"
check "DNS resolves ${THIS_FQDN}"            "getent hosts '${THIS_FQDN}'"
check "TLS cert file exists"                 "test -f '${CERT_FILE}'"
check "age key file exists"                  "test -f '${AGE_KEY_FILE}'"

if [[ "${NEEDS_KEEPALIVED}" == "true" ]]; then
    check "keepalived service running" "systemctl is-active keepalived"
    if [[ "${ROLE}" == "primary" ]]; then
        check "VIP ${VIP_IP} assigned" "ip addr | grep -q '${VIP_IP}'"
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Bootstrap complete — role: ${ROLE} | env: ${ENV_NAME}${RESET}"
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}Dry-run complete — no changes were made${RESET}"
else
    echo -e "${GREEN}Validation: ${PASS} passed${RESET}"
    if [[ "${FAIL}" -gt 0 ]]; then
        echo -e "${YELLOW}            ${FAIL} warnings (see above)${RESET}"
    fi
    echo ""
    echo "Post-bootstrap checklist:"
    echo "  docker compose ps                     # Verify all containers healthy"
    echo "  getent hosts ${THIS_FQDN}             # Verify DNS"
    echo "  curl -sf http://${THIS_FQDN}/healthz  # Verify HTTP health"
    if [[ "${NEEDS_KEEPALIVED}" == "true" ]]; then
        echo "  ip addr | grep ${VIP_IP}              # Verify VIP assignment"
    fi
fi
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo "Full log: ${LOG_FILE}"
