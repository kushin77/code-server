#!/usr/bin/env bash
# @file        scripts/ci/check-code-smells.sh
# @module      ci/code-quality
# @description enforce code-smell guardrails for eslint warnings, suppression hygiene, and TODO tracking

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPORT_PATH="${REPORT_PATH:-artifacts/triage/code-smell-audit-report.md}"
STRICT_MODE="${STRICT_MODE:-1}"
RUN_ESLINT="${RUN_ESLINT:-1}"
RUN_UNUSED_EXPORT_CHECKS="${RUN_UNUSED_EXPORT_CHECKS:-1}"
RUN_COMPLEXITY_CHECKS="${RUN_COMPLEXITY_CHECKS:-1}"
FRONTEND_COMPLEXITY_MAX="${FRONTEND_COMPLEXITY_MAX:-40}"
AGENT_FARM_COMPLEXITY_MAX="${AGENT_FARM_COMPLEXITY_MAX:-10}"

PNPM_CMD=(pnpm)
if ! command -v pnpm >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    PNPM_CMD=(npm exec --yes pnpm@latest --)
    log_warn "pnpm not found on PATH; falling back to npm exec pnpm"
  else
    log_warn "pnpm is not installed and npm fallback is unavailable"
  fi
fi

mkdir -p "$(dirname "$REPORT_PATH")"

ALLOWLIST_DIR_REGEX='^(\.git|node_modules|artifacts|docs|deprecated|build|dist|coverage|scripts/_archive|k8s|kubernetes|terraform)($|/)'
TARGET_FILE_REGEX='\.(ts|tsx|js|jsx|py)$'

run_package_eslint() {
  local package_dir="$1"
  shift

  (
    cd "$package_dir"
    if [[ "${PNPM_CMD[0]}" == "pnpm" ]]; then
      pnpm exec eslint "$@"
    else
      npm exec --yes pnpm@latest -- exec eslint "$@"
    fi
  )
}

eslint_fail=0
suppress_fail=0
todo_fail=0
unused_export_fail=0
complexity_fail=0

print_report_header() {
  cat > "$REPORT_PATH" <<EOF
# Code Smell Audit Report

- Timestamp (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Strict mode: ${STRICT_MODE}
- Run ESLint checks: ${RUN_ESLINT}
- Run unused-export checks: ${RUN_UNUSED_EXPORT_CHECKS}
- Run complexity checks: ${RUN_COMPLEXITY_CHECKS}
- Frontend complexity max threshold: ${FRONTEND_COMPLEXITY_MAX}
- Agent farm complexity max threshold: ${AGENT_FARM_COMPLEXITY_MAX}

## ESLint Strict Mode
EOF
}

run_unused_export_checks() {
  echo "" >> "$REPORT_PATH"
  echo "## Unused Export Checks" >> "$REPORT_PATH"

  if [[ "$RUN_UNUSED_EXPORT_CHECKS" != "1" ]]; then
    echo "- Skipped (RUN_UNUSED_EXPORT_CHECKS=${RUN_UNUSED_EXPORT_CHECKS})" >> "$REPORT_PATH"
    return
  fi

  if [[ "${PNPM_CMD[0]}" != "pnpm" && "${PNPM_CMD[0]}" != "npm" ]]; then
    echo "- FAILED: pnpm is not installed" >> "$REPORT_PATH"
    unused_export_fail=1
    return
  fi

  local findings=0
  local frontend_report=""
  local ext_report=""
  frontend_report="$(${PNPM_CMD[@]} dlx ts-prune@0.10.3 -p apps/frontend/tsconfig.json 2>/dev/null \
    | grep -Ev \
      -e '\\apps\\frontend\\src\\App\.tsx' \
      -e '\\apps\\frontend\\src\\hooks\\index\.ts' \
      -e '\\apps\\frontend\\src\\store\\index\.ts' \
      -e '\\apps\\frontend\\src\\types\\index\.ts' \
      -e '\\apps\\frontend\\src\\types\\repo-card\.ts' \
      -e '\\apps\\frontend\\src\\utils\\auth-sw-register\.ts' \
      -e '\\apps\\frontend\\src\\utils\\multiRepoPolicy\.ts' \
      -e '\\apps\\frontend\\src\\utils\\repoHomeData\.ts' \
      -e '\\apps\\frontend\\src\\utils\\session-keepalive\.ts' \
      -e '\\apps\\frontend\\src\\utils\\session-sync\.ts' \
      -e '\\apps\\frontend\\src\\utils\\workspaceSessionPersistence\.ts' \
      -e '\\apps\\frontend\\src\\utils\\ws-session-handoff\.ts' \
    | sed '/^$/d' || true)"
  ext_report="$(${PNPM_CMD[@]} dlx ts-prune@0.10.3 -p apps/extensions/agent-farm/tsconfig.json 2>/dev/null \
    | grep -Ev \
      -e '\\apps\\extensions\\agent-farm\\src\\extension\.ts' \
      -e '\\apps\\extensions\\agent-farm\\src\\types\.ts' \
      -e '\\apps\\extensions\\agent-farm\\src\\agents\\' \
      -e '\\apps\\extensions\\agent-farm\\src\\deployment\\GitOpsOrchestrator\.ts' \
      -e '\\apps\\extensions\\agent-farm\\src\\ml\\' \
      -e '\\apps\\extensions\\agent-farm\\src\\phases\\phase[0-9]+\\index\.ts' \
      -e '\\apps\\extensions\\agent-farm\\src\\phases\\phase7\\Phase7ObservabilityAgent\.ts' \
    | sed '/^$/d' || true)"

  if [[ -n "$frontend_report" ]]; then
    findings=$((findings + 1))
    echo "- FAIL: apps/frontend has unused exports" >> "$REPORT_PATH"
    echo "" >> "$REPORT_PATH"
    echo "### apps/frontend ts-prune findings" >> "$REPORT_PATH"
    echo '```' >> "$REPORT_PATH"
    printf '%s\n' "$frontend_report" >> "$REPORT_PATH"
    echo '```' >> "$REPORT_PATH"
  else
    echo "- PASS: apps/frontend has zero ts-prune findings" >> "$REPORT_PATH"
  fi

  if [[ -n "$ext_report" ]]; then
    findings=$((findings + 1))
    echo "- FAIL: apps/extensions/agent-farm has unused exports" >> "$REPORT_PATH"
    echo "" >> "$REPORT_PATH"
    echo "### apps/extensions/agent-farm ts-prune findings" >> "$REPORT_PATH"
    echo '```' >> "$REPORT_PATH"
    printf '%s\n' "$ext_report" >> "$REPORT_PATH"
    echo '```' >> "$REPORT_PATH"
  else
    echo "- PASS: apps/extensions/agent-farm has zero ts-prune findings" >> "$REPORT_PATH"
  fi

  if [[ $findings -gt 0 ]]; then
    unused_export_fail=1
  fi
}

run_complexity_checks() {
  echo "" >> "$REPORT_PATH"
  echo "## Complexity Checks" >> "$REPORT_PATH"

  if [[ "$RUN_COMPLEXITY_CHECKS" != "1" ]]; then
    echo "- Skipped (RUN_COMPLEXITY_CHECKS=${RUN_COMPLEXITY_CHECKS})" >> "$REPORT_PATH"
    return
  fi

  if [[ "${PNPM_CMD[0]}" != "pnpm" && "${PNPM_CMD[0]}" != "npm" ]]; then
    echo "- FAILED: pnpm is not installed" >> "$REPORT_PATH"
    complexity_fail=1
    return
  fi

  local frontend_ok=1
  local ext_ok=1

  if run_package_eslint "apps/frontend" . --ext ts,tsx --max-warnings 0 --rule "complexity: [\"error\", ${FRONTEND_COMPLEXITY_MAX}]"; then
    echo "- PASS: apps/frontend complexity <= ${FRONTEND_COMPLEXITY_MAX}" >> "$REPORT_PATH"
  else
    frontend_ok=0
    echo "- FAIL: apps/frontend has complexity violations > ${FRONTEND_COMPLEXITY_MAX}" >> "$REPORT_PATH"
  fi

  if run_package_eslint "apps/extensions/agent-farm" src --ext ts --max-warnings 0 --rule "complexity: [\"error\", ${AGENT_FARM_COMPLEXITY_MAX}]"; then
    echo "- PASS: apps/extensions/agent-farm complexity <= ${AGENT_FARM_COMPLEXITY_MAX}" >> "$REPORT_PATH"
  else
    ext_ok=0
    echo "- FAIL: apps/extensions/agent-farm has complexity violations > ${AGENT_FARM_COMPLEXITY_MAX}" >> "$REPORT_PATH"
  fi

  if [[ $frontend_ok -eq 0 || $ext_ok -eq 0 ]]; then
    complexity_fail=1
  fi
}

run_eslint_checks() {
  if [[ "$RUN_ESLINT" != "1" ]]; then
    echo "- Skipped (RUN_ESLINT=${RUN_ESLINT})" >> "$REPORT_PATH"
    return
  fi

  if [[ "${PNPM_CMD[0]}" != "pnpm" && "${PNPM_CMD[0]}" != "npm" ]]; then
    log_warn "pnpm is required for ESLint checks" || true
    echo "- FAILED: pnpm is not installed" >> "$REPORT_PATH"
    eslint_fail=1
    return
  fi

  local frontend_ok=1
  local ext_ok=1

  if run_package_eslint "apps/frontend" . --ext ts,tsx --max-warnings 0 --report-unused-disable-directives; then
    echo "- PASS: apps/frontend eslint strict check" >> "$REPORT_PATH"
  else
    frontend_ok=0
    echo "- FAIL: apps/frontend eslint strict check" >> "$REPORT_PATH"
  fi

  if run_package_eslint "apps/extensions/agent-farm" src --ext ts --max-warnings 0 --report-unused-disable-directives; then
    echo "- PASS: apps/extensions/agent-farm eslint strict check" >> "$REPORT_PATH"
  else
    ext_ok=0
    echo "- FAIL: apps/extensions/agent-farm eslint strict check" >> "$REPORT_PATH"
  fi

  if [[ $frontend_ok -eq 0 || $ext_ok -eq 0 ]]; then
    eslint_fail=1
  fi
}

scan_unexplained_suppressions() {
  local findings=0
  echo "" >> "$REPORT_PATH"
  echo "## Suppression Hygiene" >> "$REPORT_PATH"

  while IFS= read -r file; do
    while IFS= read -r hit; do
      local line_no
      local line
      line_no="${hit%%:*}"
      line="${hit#*:}"

      if grep -Eq 'eslint-disable' <<< "$line"; then
        if ! grep -Eqi '#[0-9]+|because|reason|--' <<< "$line"; then
          findings=$((findings + 1))
          echo "- FAIL: ${file}:${line_no} has unexplained eslint-disable" >> "$REPORT_PATH"
        fi
      fi

      if grep -Eq 'noqa' <<< "$line"; then
        if ! grep -Eqi 'noqa:[[:space:]]*[A-Z0-9,]+|#[0-9]+|because|reason|--' <<< "$line"; then
          findings=$((findings + 1))
          echo "- FAIL: ${file}:${line_no} has unexplained noqa" >> "$REPORT_PATH"
        fi
      fi
    done < <(grep -nE 'eslint-disable|noqa' "$file" || true)
  done < <(git ls-files | grep -Ev "$ALLOWLIST_DIR_REGEX" | grep -E "$TARGET_FILE_REGEX" || true)

  if [[ $findings -eq 0 ]]; then
    echo "- PASS: no unexplained eslint-disable/noqa markers" >> "$REPORT_PATH"
  else
    suppress_fail=1
  fi
}

scan_todo_hygiene() {
  local findings=0
  echo "" >> "$REPORT_PATH"
  echo "## TODO Hygiene" >> "$REPORT_PATH"

  while IFS= read -r file; do
    while IFS= read -r hit; do
      local line_no
      local line
      line_no="${hit%%:*}"
      line="${hit#*:}"

      if ! grep -Eq '#[0-9]+' <<< "$line"; then
        findings=$((findings + 1))
        echo "- FAIL: ${file}:${line_no} has TODO/FIXME/HACK without issue reference" >> "$REPORT_PATH"
      fi
    done < <(grep -nE '^[[:space:]]*(//|#|/\*|\*)[[:space:]]*(TODO|FIXME|HACK)\b|//[[:space:]]*(TODO|FIXME|HACK)\b' "$file" || true)
  done < <(git ls-files | grep -Ev "$ALLOWLIST_DIR_REGEX" | grep -E "$TARGET_FILE_REGEX" || true)

  if [[ $findings -eq 0 ]]; then
    echo "- PASS: TODO/FIXME/HACK markers are issue-linked or absent" >> "$REPORT_PATH"
  else
    todo_fail=1
  fi
}

main() {
  print_report_header
  run_eslint_checks
  run_unused_export_checks
  run_complexity_checks
  scan_unexplained_suppressions
  scan_todo_hygiene

  local failures=$((eslint_fail + unused_export_fail + complexity_fail + suppress_fail + todo_fail))
  echo "" >> "$REPORT_PATH"
  echo "## Summary" >> "$REPORT_PATH"
  echo "- eslint_fail: ${eslint_fail}" >> "$REPORT_PATH"
  echo "- unused_export_fail: ${unused_export_fail}" >> "$REPORT_PATH"
  echo "- complexity_fail: ${complexity_fail}" >> "$REPORT_PATH"
  echo "- suppress_fail: ${suppress_fail}" >> "$REPORT_PATH"
  echo "- todo_fail: ${todo_fail}" >> "$REPORT_PATH"
  echo "- total_failure_flags: ${failures}" >> "$REPORT_PATH"

  if [[ $failures -gt 0 && "$STRICT_MODE" == "1" ]]; then
    log_fatal "Code smell audit failed. See ${REPORT_PATH}"
  fi

  if [[ $failures -gt 0 ]]; then
    log_warn "Code smell audit found issues. See ${REPORT_PATH}" || true
    return 1
  fi

  log_info "Code smell audit passed. Report: ${REPORT_PATH}"
}

main "$@"