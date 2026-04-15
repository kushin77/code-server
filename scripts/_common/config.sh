#!/usr/bin/env bash
################################################################################
# File:          scripts/_common/config.sh
# Owner:         Platform Engineering
# Purpose:       SINGLE SOURCE OF TRUTH for all environment constants.
#                Eliminates duplicate DEPLOY_HOST / DEPLOY_USER / DOMAIN
#                definitions scattered across 20+ scripts.
# Compatibility: bash 4.0+
# Dependencies:  None — must be sourceable standalone
# Source:        source "$(dirname "$0")/../_common/config.sh"
#                (or via _common/init.sh)
# Last Updated:  April 14, 2026
################################################################################
#
# OVERRIDE RULES
#   Every constant uses ${VAR:-default} syntax so environment variables set
#   before sourcing take precedence. CI overrides via env; local dev uses defaults.
#
# USAGE
#   Do NOT hardcode any of these values in any script. If you find a hardcoded
#   IP, hostname, user, or path — replace it with the constant defined here.
#
################################################################################

# Guard against double-sourcing
[[ -n "${_COMMON_CONFIG_LOADED:-}" ]] && return 0
readonly _COMMON_CONFIG_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# INFRASTRUCTURE
# ─────────────────────────────────────────────────────────────────────────────

# Primary production host
readonly DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
readonly DEPLOY_USER="${DEPLOY_USER:-akushnir}"
readonly DEPLOY_DIR="${DEPLOY_DIR:-/home/akushnir/code-server-enterprise}"

# Standby / replica host
readonly STANDBY_HOST="${STANDBY_HOST:-192.168.168.30}"
readonly STANDBY_USER="${STANDBY_USER:-akushnir}"

# Infrastructure services (NAS, backup destinations, observability)
readonly NAS_HOST="${NAS_HOST:-192.168.168.56}"
readonly NAS_EXPORT_PATH="${NAS_EXPORT_PATH:-/export}"
readonly NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas}"

readonly BACKUP_DEST_PRIMARY="${BACKUP_DEST_PRIMARY:-192.168.168.11:/export/backups/models}"
readonly BACKUP_DEST_SECONDARY="${BACKUP_DEST_SECONDARY:-192.168.168.12:/export/backups/models}"

readonly OBSERVABILITY_HOST="${OBSERVABILITY_HOST:-192.168.168.31}"

# SSH options (no interactive prompts in CI)
readonly SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10}"

# ─────────────────────────────────────────────────────────────────────────────
# DOMAIN & ACCESS
# ─────────────────────────────────────────────────────────────────────────────

readonly DOMAIN="${DOMAIN:-ide.kushnir.cloud}"
readonly REPO="${REPO:-kushin77/code-server}"
readonly REPO_URL="${REPO_URL:-https://github.com/kushin77/code-server}"

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER
# ─────────────────────────────────────────────────────────────────────────────

readonly ENTERPRISE_NETWORK="${ENTERPRISE_NETWORK:-code-server-enterprise_enterprise}"
readonly DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-$DEPLOY_DIR/docker-compose.yml}"
readonly COMPOSE_PROJECT="${COMPOSE_PROJECT:-code-server-enterprise}"

# Container names (used as identifiers across scripts)
readonly CONTAINER_CODE_SERVER="${CONTAINER_CODE_SERVER:-code-server}"
readonly CONTAINER_CADDY="${CONTAINER_CADDY:-caddy}"
readonly CONTAINER_OLLAMA="${CONTAINER_OLLAMA:-ollama}"
readonly CONTAINER_POSTGRES="${CONTAINER_POSTGRES:-postgres}"
readonly CONTAINER_REDIS="${CONTAINER_REDIS:-redis}"
readonly CONTAINER_PROMETHEUS="${CONTAINER_PROMETHEUS:-prometheus}"
readonly CONTAINER_GRAFANA="${CONTAINER_GRAFANA:-grafana}"
readonly CONTAINER_ALERTMANAGER="${CONTAINER_ALERTMANAGER:-alertmanager}"

# ─────────────────────────────────────────────────────────────────────────────
# PORTS
# ─────────────────────────────────────────────────────────────────────────────

readonly PORT_CODE_SERVER="${PORT_CODE_SERVER:-8080}"
readonly PORT_CADDY_HTTP="${PORT_CADDY_HTTP:-80}"
readonly PORT_CADDY_HTTPS="${PORT_CADDY_HTTPS:-443}"
readonly PORT_OLLAMA="${PORT_OLLAMA:-11434}"
readonly PORT_POSTGRES="${PORT_POSTGRES:-5432}"
readonly PORT_REDIS="${PORT_REDIS:-6379}"
readonly PORT_PROMETHEUS="${PORT_PROMETHEUS:-9090}"
readonly PORT_GRAFANA="${PORT_GRAFANA:-3000}"
readonly PORT_ALERTMANAGER="${PORT_ALERTMANAGER:-9093}"

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING & OBSERVABILITY
# ─────────────────────────────────────────────────────────────────────────────

# Log level: 0=debug 1=info 2=warn 3=error 4=fatal
LOG_LEVEL="${LOG_LEVEL:-1}"
# Output format: text (human) or json (Loki/Grafana ingestion)
LOG_FORMAT="${LOG_FORMAT:-text}"
# Log file path (empty = stdout only)
LOG_FILE="${LOG_FILE:-}"
LOG_NO_COLOR="${LOG_NO_COLOR:-0}"

# ─────────────────────────────────────────────────────────────────────────────
# TIMEOUTS & RETRIES
# ─────────────────────────────────────────────────────────────────────────────

readonly HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"  # seconds
readonly HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-5}"
readonly DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-300}"             # 5 minutes
readonly SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"

# ─────────────────────────────────────────────────────────────────────────────
# PATHS
# ─────────────────────────────────────────────────────────────────────────────

readonly BACKUP_DIR="${BACKUP_DIR:-/home/akushnir/.backups/code-server}"
readonly LOG_DIR="${LOG_DIR:-/home/akushnir/.logs/code-server}"
readonly CONFIG_DIR="${CONFIG_DIR:-/home/akushnir/.config/code-server}"
