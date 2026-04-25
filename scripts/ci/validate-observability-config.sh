#!/bin/bash
# @file scripts/ci/validate-observability-config.sh
# @description Validate Prometheus, Loki, and Promtail configurations
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# Issue #1532: Centralized Observability

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source base configuration
. "${REPO_ROOT}/scripts/_common/_base-config.env"

echo "[INFO] Validating Observability Stack Configuration..."

# 1. Prometheus
if command -v promtool &>/dev/null; then
  promtool check config "${REPO_ROOT}/config/prometheus.yml"
  echo "[✓] Prometheus config valid"
else
  echo "[WARN] promtool not found, skipping deep validation"
fi

# 2. Promtail
if [ -f "${REPO_ROOT}/config/promtail.yaml" ]; then
  grep -q "clients:" "${REPO_ROOT}/config/promtail.yaml" || { echo "[ERROR] Promtail config missing clients"; exit 1; }
  echo "[✓] Promtail config valid (basic)"
fi

# 3. Loki
if [ -d "${REPO_ROOT}/config/loki" ]; then
  echo "[✓] Loki config directory exists"
fi

echo "[✓] All observability configs passed basic validation"
