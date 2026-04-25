#!/usr/bin/env bash
# @file        scripts/_common/hosts.sh
# @module      infrastructure/networking
# @description Centralized host resolution library — eliminates hardcoded IPs
# @governance  GOV-002: IaC, immutable, idempotent — all IPs via env vars only
# Issue #1536: Networking, DNS & Performance — Service Discovery, Eliminate Hardcoded IPs
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/_common/hosts.sh"
#   ssh "${PRIMARY_HOST}" "docker ps"
#   scp config.yml "${REPLICA_HOST}:/etc/app/"

set -euo pipefail

# ── Host Configuration (override via environment) ────────────────────────────

# Primary compute node (code-server, Ollama, main services)
: "${PRIMARY_HOST:=192.168.168.31}"

# Replica compute node (HA failover, monitoring)
: "${REPLICA_HOST:=192.168.168.42}"

# NAS node (persistent storage, backups)
: "${NAS_HOST:=192.168.168.56}"

# Domain root (for FQDN construction)
: "${DOMAIN:=kushnir.cloud}"

# SSH user (default: current user)
: "${SSH_USER:=${USER:-ops}}"

# SSH key path (default: ~/.ssh/id_ed25519)
: "${SSH_KEY:=${HOME}/.ssh/id_ed25519}"

# ── Derived FQDNs ─────────────────────────────────────────────────────────────

IDE_HOST="${IDE_HOST:-ide.${DOMAIN}}"
API_HOST="${API_HOST:-api.${DOMAIN}}"
GRAFANA_HOST="${GRAFANA_HOST:-grafana.${DOMAIN}}"

# ── SSH Helper Functions ──────────────────────────────────────────────────────

# Run a command on the primary host
ssh_primary() {
  local cmd="$1"
  ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
      "${SSH_USER}@${PRIMARY_HOST}" "${cmd}"
}

# Run a command on the replica host
ssh_replica() {
  local cmd="$1"
  ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
      "${SSH_USER}@${REPLICA_HOST}" "${cmd}"
}

# Run a command on both hosts
ssh_all_hosts() {
  local cmd="$1"
  echo "[hosts] Running on PRIMARY (${PRIMARY_HOST}): ${cmd}"
  ssh_primary "${cmd}"
  echo "[hosts] Running on REPLICA (${REPLICA_HOST}): ${cmd}"
  ssh_replica "${cmd}"
}

# SCP a file to the primary host
scp_to_primary() {
  local src="$1"
  local dst="$2"
  scp -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
      "${src}" "${SSH_USER}@${PRIMARY_HOST}:${dst}"
}

# SCP a file to the replica host
scp_to_replica() {
  local src="$1"
  local dst="$2"
  scp -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
      "${src}" "${SSH_USER}@${REPLICA_HOST}:${dst}"
}

# SCP a file to both hosts
scp_to_all_hosts() {
  local src="$1"
  local dst="$2"
  scp_to_primary "${src}" "${dst}"
  scp_to_replica "${src}" "${dst}"
}

# ── DNS / Connectivity Validation ────────────────────────────────────────────

# Verify all configured hosts are reachable
check_host_connectivity() {
  local all_ok=true
  local timeout_sec="${1:-3}"

  for host_var in PRIMARY_HOST REPLICA_HOST NAS_HOST; do
    local host="${!host_var}"
    if ping -c 1 -W "${timeout_sec}" "${host}" >/dev/null 2>&1; then
      echo "[hosts] ✓ ${host_var}=${host} reachable"
    else
      echo "[hosts] ✗ ${host_var}=${host} UNREACHABLE" >&2
      all_ok=false
    fi
  done

  if [ "${all_ok}" = "false" ]; then
    return 1
  fi
  return 0
}

# Verify Docker service discovery within a compose network
# Usage: check_docker_dns <container_name> <service_to_resolve>
check_docker_dns() {
  local container="${1}"
  local service="${2}"
  if docker exec "${container}" nslookup "${service}" >/dev/null 2>&1; then
    echo "[hosts] ✓ DNS ${service} resolves from ${container}"
  else
    echo "[hosts] ✗ DNS ${service} FAILS from ${container}" >&2
    return 1
  fi
}

# ── NAS Mount Helpers ─────────────────────────────────────────────────────────

NAS_PERSISTENT_PATH="${NAS_PERSISTENT_PATH:-/nas/persistent}"
NAS_HOT_PATH="${NAS_HOT_PATH:-/nas/hot}"
NAS_COLD_PATH="${NAS_COLD_PATH:-/nas/cold}"

# Check NAS mount health with latency threshold
check_nas_health() {
  local threshold_ms="${1:-100}"

  if ! mountpoint -q "${NAS_PERSISTENT_PATH}" 2>/dev/null; then
    echo "[hosts] ✗ NAS not mounted at ${NAS_PERSISTENT_PATH}" >&2
    return 1
  fi

  local start_ns
  start_ns=$(date +%s%N)
  ls "${NAS_PERSISTENT_PATH}" >/dev/null 2>&1
  local end_ns
  end_ns=$(date +%s%N)
  local latency_ms=$(( (end_ns - start_ns) / 1000000 ))

  if [ "${latency_ms}" -gt "${threshold_ms}" ]; then
    echo "[hosts] ⚠ NAS latency ${latency_ms}ms exceeds threshold ${threshold_ms}ms" >&2
    return 1
  fi

  echo "[hosts] ✓ NAS ${NAS_HOST} healthy (latency: ${latency_ms}ms)"
  return 0
}

# ── Export All Variables ──────────────────────────────────────────────────────

export PRIMARY_HOST REPLICA_HOST NAS_HOST DOMAIN SSH_USER SSH_KEY
export IDE_HOST API_HOST GRAFANA_HOST
export NAS_PERSISTENT_PATH NAS_HOT_PATH NAS_COLD_PATH
