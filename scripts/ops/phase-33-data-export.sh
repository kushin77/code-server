#!/usr/bin/env bash
################################################################################
# @file scripts/ops/phase-33-data-export.sh
# @description Phase 33 — Observability Data Export Pipeline orchestrator
#
# Modes:
#   --mode full          Export all sources to file sink
#   --mode incremental   Export only records since --since <ISO8601>
#   --mode source        Export single source (--source <name>)
#   --mode status        Print export summary from last manifest
#   --mode schedule      Run full export + rotate old exports (>7 days)
#
# Usage:
#   bash scripts/ops/phase-33-data-export.sh --mode full
#   bash scripts/ops/phase-33-data-export.sh --mode incremental --since 2026-05-01T00:00:00Z
#   bash scripts/ops/phase-33-data-export.sh --mode source --source phase32
#   bash scripts/ops/phase-33-data-export.sh --mode schedule --dry-run
#
# @governance GOV-003 (data retention, export encryption)
# @since 2026-05-01
################################################################################

set -euo pipefail
trap 'log_error "Phase 33 failed at line $LINENO"; exit 1' ERR
trap 'log_info "Phase 33 cleanup..."; rm -f /tmp/phase33*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

################################################################################
# Defaults
################################################################################

MODE="${MODE:-full}"
DRY_RUN="${DRY_RUN:-false}"
SINCE=""
SOURCE_NAME=""
EXPORT_DIR="${REPO_ROOT}/artifacts/exports"
RETENTION_DAYS=7

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)        MODE="$2";        shift 2 ;;
    --since)       SINCE="$2";       shift 2 ;;
    --source)      SOURCE_NAME="$2"; shift 2 ;;
    --export-dir)  EXPORT_DIR="$2";  shift 2 ;;
    --retention)   RETENTION_DAYS="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true;     shift ;;
    --help|-h)
      echo "Usage: $0 --mode {full|incremental|source|status|schedule} [options]"
      echo ""
      echo "Options:"
      echo "  --mode MODE         Export mode (full|incremental|source|status|schedule)"
      echo "  --since ISO8601     Incremental cutoff timestamp"
      echo "  --source NAME       Source name for --mode source"
      echo "  --export-dir DIR    Output directory (default: artifacts/exports)"
      echo "  --retention DAYS    Rotate exports older than N days (default: 7)"
      echo "  --dry-run           Simulate without writing"
      exit 0
      ;;
    *) shift ;;
  esac
done

mkdir -p "${EXPORT_DIR}"
STATE_FILE="${EXPORT_DIR}/.last-export-state.json"
LOG_FILE="${EXPORT_DIR}/export.log"

# ---------------------------------------------------------------------------
# Helper: Run Python exporter
# ---------------------------------------------------------------------------
_run_exporter() {
  local extra_args=("$@")
  local dry_flag=""
  [[ "${DRY_RUN}" == "true" ]] && dry_flag="--dry-run"

  python3 -m apps.observability.data_exporter \
    --output-dir "${EXPORT_DIR}" \
    ${dry_flag} \
    "${extra_args[@]}" \
    2>&1 | tee -a "${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# Helper: Save state after successful export
# ---------------------------------------------------------------------------
_save_state() {
  local ts="$1"
  local records="$2"
  cat > "${STATE_FILE}" <<JSEOF
{
  "last_export_ts": "${ts}",
  "last_records": ${records},
  "exported_by": "phase-33-data-export.sh"
}
JSEOF
}

# ---------------------------------------------------------------------------
# Mode: full
# ---------------------------------------------------------------------------
run_full() {
  log_info "=== Phase 33 FULL Export ==="
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local output
  output="$(_run_exporter --mode full --json)" || true
  local records; records="$(echo "${output}" | python3 -c "
import json,sys
try:
    d = json.loads(''.join(line for line in sys.stdin if line.strip().startswith('{') or line.strip().startswith('}')))
    print(d.get('record_count', 0))
except:
    print(0)
" 2>/dev/null || echo 0)"
  _save_state "${ts}" "${records}"
  log_info "=== FULL EXPORT COMPLETE: ${records} records ==="
}

# ---------------------------------------------------------------------------
# Mode: incremental
# ---------------------------------------------------------------------------
run_incremental() {
  log_info "=== Phase 33 INCREMENTAL Export (since=${SINCE:-last}) ==="

  # Default to last successful export timestamp
  if [[ -z "${SINCE}" && -f "${STATE_FILE}" ]]; then
    SINCE="$(python3 -c "import json; print(json.load(open('${STATE_FILE}'))['last_export_ts'])" 2>/dev/null || echo "")"
  fi

  if [[ -z "${SINCE}" ]]; then
    log_warn "No --since provided and no prior state found; falling back to full export"
    run_full
    return
  fi

  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  _run_exporter --mode incremental --since "${SINCE}" || true
  _save_state "${ts}" "incremental"
  log_info "=== INCREMENTAL EXPORT COMPLETE (since ${SINCE}) ==="
}

# ---------------------------------------------------------------------------
# Mode: source
# ---------------------------------------------------------------------------
run_source() {
  if [[ -z "${SOURCE_NAME}" ]]; then
    log_error "--source required for --mode source"
    exit 1
  fi
  log_info "=== Phase 33 SOURCE Export (${SOURCE_NAME}) ==="
  _run_exporter --mode source --source "${SOURCE_NAME}" || true
  log_info "=== SOURCE EXPORT COMPLETE ==="
}

# ---------------------------------------------------------------------------
# Mode: status
# ---------------------------------------------------------------------------
run_status() {
  log_info "=== Phase 33 Export Status ==="

  if [[ -f "${STATE_FILE}" ]]; then
    python3 - <<PYEOF
import json
with open('${STATE_FILE}') as f:
    s = json.load(f)
print(f"  Last Export:    {s.get('last_export_ts', 'never')}")
print(f"  Records:        {s.get('last_records', 0)}")
PYEOF
  else
    log_warn "No export state found. Run: bash $0 --mode full"
  fi

  # Count export files
  local count; count="$(find "${EXPORT_DIR}" -name 'export-*.jsonl' -o -name 'export-*.jsonl.gz' 2>/dev/null | wc -l | tr -d ' ')"
  local manifests; manifests="$(find "${EXPORT_DIR}" -name 'manifest-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  log_info "  Export files:   ${count}"
  log_info "  Manifests:      ${manifests}"
  log_info "  Export dir:     ${EXPORT_DIR}"
}

# ---------------------------------------------------------------------------
# Mode: schedule (export + rotate old files)
# ---------------------------------------------------------------------------
run_schedule() {
  log_info "=== Phase 33 SCHEDULED Export + Rotation ==="
  run_full

  if [[ "${DRY_RUN}" != "true" ]]; then
    local rotated=0
    while IFS= read -r f; do
      log_info "Rotating old export: ${f}"
      rm -f "${f}"
      (( rotated++ )) || true
    done < <(find "${EXPORT_DIR}" \
      \( -name 'export-*.jsonl' -o -name 'manifest-*.json' -o -name 'export-*.jsonl.gz' \) \
      -mtime "+${RETENTION_DAYS}" 2>/dev/null || true)
    log_info "Rotated ${rotated} old export files (>${RETENTION_DAYS} days)"
  else
    local count; count="$(find "${EXPORT_DIR}" \
      \( -name 'export-*.jsonl' -o -name 'manifest-*.json' \) \
      -mtime "+${RETENTION_DAYS}" 2>/dev/null | wc -l | tr -d ' ')"
    log_info "[dry-run] Would rotate ${count} files older than ${RETENTION_DAYS} days"
  fi

  log_info "=== SCHEDULED EXPORT COMPLETE ==="
}

################################################################################
# Main dispatch
################################################################################

log_info "Starting Phase 33 data export (mode=${MODE}, dry_run=${DRY_RUN})"

cd "${REPO_ROOT}"

case "${MODE}" in
  full)        run_full        ;;
  incremental) run_incremental ;;
  source)      run_source      ;;
  status)      run_status      ;;
  schedule)    run_schedule    ;;
  *)
    log_error "Unknown mode: ${MODE}. Use: full|incremental|source|status|schedule"
    exit 1
    ;;
esac
