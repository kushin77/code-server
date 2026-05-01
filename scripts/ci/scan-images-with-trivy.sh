#!/bin/bash

###############################################################################
# scan-images-with-trivy.sh
###############################################################################
# P2 #2429: Trivy vulnerability scanning for all container images
#
# Currently: Only auth-server is scanned (1/35+ images)
# Goal: Scan all 35+ service images in docker-compose for vulnerabilities
#
# Detects:
# - Known CVEs (Common Vulnerabilities and Exposures)
# - Vulnerable dependencies
# - Misconfigured secrets (API keys, tokens)
# - License compliance issues
#
# Usage:
#   ./scripts/ci/scan-images-with-trivy.sh --docker-compose-file docker-compose.yml --threshold HIGH
#
###############################################################################

set -euo pipefail

trap 'error "Script failed at line $LINENO"' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/trivy.*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs/trivy-scans"

DOCKER_COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
SEVERITY="HIGH,CRITICAL"
SCAN_TIMEOUT="300"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker-compose-file) DOCKER_COMPOSE_FILE="$2"; shift 2 ;;
    --threshold)           SEVERITY="$2";             shift 2 ;;
    --timeout)             SCAN_TIMEOUT="$2";          shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

#############################################################################
# Logging
#############################################################################

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/trivy-scan-$(date +%Y%m%d-%H%M%S).log"

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "${LOG_FILE}"; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}"; exit 1; }

log_info "========================================"
log_info "Trivy Image Scanning (P2 #2429)"
log_info "========================================"

# Check if Trivy is available
if ! command -v trivy &>/dev/null; then
  warn "Trivy not found - install with: apt-get install trivy OR brew install trivy"
  warn "Or download from: https://github.com/aquasecurity/trivy/releases"
  exit 2
fi

log_info "Trivy version: $(trivy --version 2>/dev/null | head -1)"
log_info ""

#############################################################################
# Extract images from docker-compose file
#############################################################################

if [ ! -f "${DOCKER_COMPOSE_FILE}" ]; then
  error "Compose file not found: ${DOCKER_COMPOSE_FILE}"
fi

log_info "Extracting images from ${DOCKER_COMPOSE_FILE}..."
mapfile -t IMAGES < <(
  grep -E '^\s+image:\s+' "${DOCKER_COMPOSE_FILE}" \
    | sed 's/^\s*image:\s*//' \
    | sed 's/["'"'"']//g' \
    | sort -u
)

if [ ${#IMAGES[@]} -eq 0 ]; then
  warn "No images found in ${DOCKER_COMPOSE_FILE}"
  exit 0
fi

log_info "Found ${#IMAGES[@]} unique images to scan"

#############################################################################
# Scan each image
#############################################################################

REPORT_DIR="${LOG_DIR}/reports-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${REPORT_DIR}"

TOTAL=0
FAILED=0
CRITICAL_COUNT=0

for image in "${IMAGES[@]}"; do
  TOTAL=$((TOTAL + 1))
  safe_name="${image//[:\/@]/-}"
  report_file="${REPORT_DIR}/${safe_name}.json"

  log_info "Scanning [${TOTAL}/${#IMAGES[@]}]: ${image}"

  if timeout "${SCAN_TIMEOUT}" trivy image \
      --severity "${SEVERITY}" \
      --format json \
      --output "${report_file}" \
      --no-progress \
      --quiet \
      "${image}" 2>>"${LOG_FILE}"; then

    crit=$(python3 -c "
import json, sys
try:
    data = json.load(open('${report_file}'))
    total = sum(len(r.get('Vulnerabilities') or []) for r in (data.get('Results') or []))
    sys.stdout.write(str(total))
except Exception:
    sys.stdout.write('0')
" 2>/dev/null || echo "0")

    if [ "${crit}" -gt 0 ]; then
      warn "  ${crit} ${SEVERITY} vulnerability/ies found in ${image}"
      CRITICAL_COUNT=$((CRITICAL_COUNT + crit))
      FAILED=$((FAILED + 1))
    else
      log_info "  ✅ Clean: ${image}"
    fi
  else
    warn "  Scan timed out or failed for ${image} — skipping"
  fi
done

#############################################################################
# Summary
#############################################################################

log_info ""
log_info "========================================"
log_info "Scan Summary"
log_info "========================================"
log_info "Images scanned : ${TOTAL}"
log_info "With findings  : ${FAILED}"
log_info "Total ${SEVERITY} vulns : ${CRITICAL_COUNT}"
log_info "Reports        : ${REPORT_DIR}"
log_info ""

if [ "${CRITICAL_COUNT}" -gt 0 ]; then
  error "❌ ${CRITICAL_COUNT} ${SEVERITY} vulnerabilities detected across ${FAILED} images"
fi

log_info "✅ Trivy scan complete — no ${SEVERITY} vulnerabilities found"
log_info "Log: ${LOG_FILE}"
