#!/usr/bin/env bash
# @file        scripts/ops/staging-validation.sh
# @module      ops/staging
# @description Generate a staging validation dry-run report from the current readiness evidence.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$REPO_ROOT/scripts/_common/init.sh"

TARGET_HOST="${TARGET_HOST:-192.168.168.42}"
OUTPUT_MD="${OUTPUT_MD:-artifacts/staging/staging-validation-dry-run.md}"
RUNBOOK_FILE="${RUNBOOK_FILE:-docs/PRODUCTION-DEPLOYMENT-RUNBOOK.md}"
PERF_GUIDE_FILE="${PERF_GUIDE_FILE:-docs/PERFORMANCE-LOAD-TESTING-GUIDE.md}"
PERF_REPORT_FILE="${PERF_REPORT_FILE:-artifacts/performance-tests/PERFORMANCE-TEST-ANALYSIS-APR22-2026.md}"
STAGING_REPORT_FILE="${STAGING_REPORT_FILE:-artifacts/staging/staging-deployment-report.md}"
# Find latest readiness report if not explicitly set, convert to relative path
if [[ -z "${READINESS_REPORT_FILE:-}" ]]; then
  latest_readiness="$(ls -t "$REPO_ROOT/artifacts/triage/deployment-readiness-report"*.md 2>/dev/null | head -1)"
  if [[ -n "$latest_readiness" ]]; then
    READINESS_REPORT_FILE="${latest_readiness#$REPO_ROOT/}"
  else
    READINESS_REPORT_FILE="artifacts/triage/deployment-readiness-report-20260423.md"
  fi
fi

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ops/staging-validation.sh [--output-md <file>] [--target-host <host>]

Options:
  --output-md       Markdown report to generate. Defaults to artifacts/staging/staging-validation-dry-run.md.
  --target-host     Staging host to reference in the report. Defaults to 192.168.168.42.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-md)
      OUTPUT_MD="${2:-}"
      shift 2
      ;;
    --target-host)
      TARGET_HOST="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_fatal "Unknown argument: $1"
      ;;
  esac
done

required_files=(
  "$RUNBOOK_FILE"
  "$PERF_GUIDE_FILE"
  "$PERF_REPORT_FILE"
  "$STAGING_REPORT_FILE"
  "$READINESS_REPORT_FILE"
)

missing_files=()
for file_path in "${required_files[@]}"; do
  if [[ ! -f "$REPO_ROOT/$file_path" ]]; then
    missing_files+=("$file_path")
  fi
done

if (( ${#missing_files[@]} > 0 )); then
  log_fatal "Missing required staging evidence files: ${missing_files[*]}"
fi

mkdir -p "$(dirname "$REPO_ROOT/$OUTPUT_MD")"

GENERATED_AT="$(date -u -Iseconds)"
BRANCH_NAME="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo main)"
GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"

cat > "$REPO_ROOT/$OUTPUT_MD" <<EOF
# Staging Validation Dry Run

**Generated**: ${GENERATED_AT}
**Target Host**: ${TARGET_HOST}
**Status**: READY TO EXECUTE

## Evidence Anchors

- Runbook: ${RUNBOOK_FILE}
- Performance guide: ${PERF_GUIDE_FILE}
- Performance evidence: ${PERF_REPORT_FILE}
- Staging report: ${STAGING_REPORT_FILE}
- Readiness report: ${READINESS_REPORT_FILE}

## Validation Focus

This dry run confirms that the staging validation inputs exist and are aligned for the Apr 27-29 execution window.

### Ready Checks

- [x] Production deployment runbook available
- [x] Performance testing guide available
- [x] Performance evidence available
- [x] Staging evidence available
- [x] Readiness evidence available

## Execution Notes

The actual staging run should verify the following against the target host:

- SSH access to ${TARGET_HOST}
- Docker services up and healthy
- Database connectivity
- Redis connectivity
- Monitoring dashboards active
- Backup and restore flow usable
- Failover and replication checks passing

## Recommendation

Proceed with the Apr 27-29 staging validation window using the current evidence set.

## Repository State

- Branch: ${BRANCH_NAME}
- Commit: ${GIT_COMMIT}

EOF

log_info "Staging validation dry run generated: ${OUTPUT_MD}"