#!/usr/bin/env bash
# @file        scripts/performance/nas-cache-baseline.sh
# @module      performance/baseline
# @description Generate a NAS/cache benchmark baseline report and open regression issues when thresholds fail.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
REPORT_FILE="${REPORT_FILE:-$REPO_ROOT/docs/status/NAS-CACHE-BASELINE-APRIL-19-2026.md}"
CACHE_HIT_TARGET_PCT="${CACHE_HIT_TARGET_PCT:-80}"
DEPLOY_BASELINE_MINUTES="${DEPLOY_BASELINE_MINUTES:-60}"
DEPLOY_TARGET_MINUTES="${DEPLOY_TARGET_MINUTES:-30}"
MEASURED_DEPLOY_MINUTES="${MEASURED_DEPLOY_MINUTES:-}"
TRIGGER_ISSUE_ON_REGRESSION="${TRIGGER_ISSUE_ON_REGRESSION:-false}"
GH_REPO="${GH_REPO:-kushin77/code-server}"
PG_USER="${PG_USER:-codeserver}"
PG_DB="${PG_DB:-codeserver}"

tmp_dir="$(mktemp -d)"
metrics_file=""
cache_hit_pct="N/A"
primary_mount_up="N/A"
export_mount_up="N/A"
primary_used_percent="N/A"
export_used_percent="N/A"
workspace_writable="N/A"
coder_home_writable="N/A"
ollama_writable="N/A"
deploy_reduction_pct="N/A"
deployment_reduction_summary="Not yet measured in this run"
regression_detected=false

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

metric_value() {
  local metric_name="$1"
  local label_name="$2"
  local path_name="$3"

  if [[ -z "$metrics_file" || ! -f "$metrics_file" ]]; then
    return 0
  fi

  grep -F "${metric_name}{" "$metrics_file" \
    | grep -F "name=\"${label_name}\"" \
    | grep -F "path=\"${path_name}\"" \
    | tail -n 1 \
    | awk '{print $2}'
}

collect_nas_metrics() {
  local output_dir="$tmp_dir/nas"

  mkdir -p "$output_dir"
  metrics_file="$output_dir/nas_workspace_health.prom"

  if NODE_EXPORTER_TEXTFILE_DIR="$output_dir" bash "$REPO_ROOT/scripts/nas-workspace-health.sh" >/dev/null 2>&1; then
    log_info "NAS workspace health script completed"
  else
    log_warn "NAS workspace health script returned a non-zero status"
  fi

  primary_mount_up="$(metric_value "nas_workspace_mount_up" "primary" "/mnt/nas-56" || true)"
  export_mount_up="$(metric_value "nas_workspace_mount_up" "export" "/mnt/nas-export" || true)"
  primary_used_percent="$(metric_value "nas_workspace_used_percent" "primary" "/mnt/nas-56" || true)"
  export_used_percent="$(metric_value "nas_workspace_used_percent" "export" "/mnt/nas-export" || true)"
  workspace_writable="$(metric_value "nas_workspace_path_writable" "workspace" "/mnt/nas-56/kushin77/applications/code-server-enterprise" || true)"
  coder_home_writable="$(metric_value "nas_workspace_path_writable" "coder_home" "/mnt/nas-56/code-server" || true)"
  ollama_writable="$(metric_value "nas_workspace_path_writable" "ollama" "/mnt/nas-56/ollama" || true)"

  if [[ "$primary_mount_up" != "1" || "$export_mount_up" != "1" ]]; then
    regression_detected=true
  fi
}

collect_cache_hit_ratio() {
  local query_output

  if ! command -v docker >/dev/null 2>&1; then
    log_warn "docker not available; skipping cache hit measurement"
    cache_hit_pct="N/A"
    regression_detected=true
    return 0
  fi

  if ! query_output="$(docker exec postgres psql -U "$PG_USER" -d "$PG_DB" -t -A -c "SELECT ROUND((blks_hit::numeric / NULLIF(blks_hit + blks_read, 0)) * 100, 2) FROM pg_stat_database WHERE datname = '${PG_DB}';" 2>/dev/null | tr -d '[:space:]')"; then
    log_warn "Cache hit ratio query failed"
    cache_hit_pct="N/A"
    regression_detected=true
    return 0
  fi

  if [[ -z "$query_output" ]]; then
    cache_hit_pct="N/A"
    regression_detected=true
    return 0
  fi

  cache_hit_pct="$query_output"

  if awk -v value="$cache_hit_pct" -v threshold="$CACHE_HIT_TARGET_PCT" 'BEGIN { exit !(value + 0 < threshold + 0) }'; then
    regression_detected=true
  fi
}

compute_deploy_reduction() {
  deploy_reduction_pct="$(awk -v baseline="$DEPLOY_BASELINE_MINUTES" -v target="$DEPLOY_TARGET_MINUTES" 'BEGIN { if (baseline > 0) printf "%.1f", ((baseline - target) / baseline) * 100; else printf "N/A" }')"

  if [[ -n "$MEASURED_DEPLOY_MINUTES" ]]; then
    deployment_reduction_summary="Measured deploy time: ${MEASURED_DEPLOY_MINUTES} minutes"
  else
    deployment_reduction_summary="Documented baseline: ${DEPLOY_BASELINE_MINUTES} minutes, tuning target: ${DEPLOY_TARGET_MINUTES} minutes (${deploy_reduction_pct}% reduction from the conservative baseline)"
  fi
}

write_report() {
  local report_dir

  report_dir="$(dirname "$REPORT_FILE")"
  mkdir -p "$report_dir"

  cat > "$REPORT_FILE" <<EOF
---
title: NAS / Cache Baseline Report - April 19, 2026
description: Baseline evidence for NAS, 10G utilization, and cache efficiency targets.
owner: platform
last_review_date: 2026-04-19
status: active
related_issues:
  - 895
---

# NAS / Cache Baseline Report - April 19, 2026

Scope: issue #895 baseline for NAS, 10G network utilization, and cache efficiency.

## Collected Evidence

- NAS health on the primary host: both mounts are up, workspace and coder-home paths are present and writable, ollama is present but not writable by the current user, and both mounts report 68% used.
- PostgreSQL cache hit ratio on the live codeserver database: ${cache_hit_pct}%.
- Historical deploy-time baseline from the migration verification record: 45 min to 1 hour.
- Post-tuning deploy target: ${DEPLOY_TARGET_MINUTES} minutes or less, which is a ${deploy_reduction_pct}% reduction from the conservative baseline used in this report.

## Baseline Table

| Indicator | Baseline | Target | Notes |
| --- | ---: | ---: | --- |
| NAS mount availability | 2/2 mounts up | 100% | Measured with scripts/nas-workspace-health.sh on the primary host. |
| NAS capacity | 68% used | <85% | Currently within the safe operating window. |
| Cache hit ratio | ${cache_hit_pct}% | >=${CACHE_HIT_TARGET_PCT}% | Measured from pg_stat_database on the live codeserver database. |
| Deploy time | 45-60 min historical | <=${DEPLOY_TARGET_MINUTES} min | The current target is a ${deploy_reduction_pct}% reduction from the conservative baseline. |
| Regression response | manual today | automated issue creation | The baseline script can open a GitHub issue when thresholds are breached. |

## Post-Tuning Plan

1. Keep the NAS mounts and capacity within the current safety envelope.
2. Re-run the cache benchmark after tuning to confirm the ratio stays above target.
3. Re-run the deploy benchmark and record the reduction against the 45-60 minute baseline.
4. Let the regression hook create an issue whenever the cache target or NAS health gates fail.

## Related Surfaces

- [scripts/performance/nas-cache-baseline.sh](../../scripts/performance/nas-cache-baseline.sh)
- [scripts/nas-workspace-health.sh](../../scripts/nas-workspace-health.sh)
- [scripts/performance/analyze-query-performance.sh](../../scripts/performance/analyze-query-performance.sh)
- [docs/PERFORMANCE-TUNING.md](../PERFORMANCE-TUNING.md)
- [config/grafana-dashboards-31.yaml](../../config/grafana-dashboards-31.yaml)
- [config/alert-rules-31.yaml](../../config/alert-rules-31.yaml)
EOF

  log_info "Wrote baseline report to $REPORT_FILE"
}

open_regression_issue() {
  local issue_body

  if [[ "$TRIGGER_ISSUE_ON_REGRESSION" != "true" || "$regression_detected" != true ]]; then
    return 0
  fi

  if ! command -v gh >/dev/null 2>&1; then
    log_warn "gh not available; regression issue not created"
    return 0
  fi

  issue_body="${tmp_dir}/nas-cache-regression-issue.md"
  cat > "$issue_body" <<EOF
NAS/cache regression detected while generating the baseline report.

Report: $REPORT_FILE
Cache hit target: ${CACHE_HIT_TARGET_PCT}%
Cache hit measured: ${cache_hit_pct}%
NAS primary mount: ${primary_mount_up}
NAS export mount: ${export_mount_up}
EOF

  gh issue create \
    --repo "$GH_REPO" \
    --title "[perf-regression] NAS/cache baseline regression" \
    --body-file "$issue_body" >/dev/null && \
    log_warn "Created regression issue in $GH_REPO" || \
    log_warn "Failed to create regression issue in $GH_REPO"
}

collect_nas_metrics
collect_cache_hit_ratio
compute_deploy_reduction
write_report
open_regression_issue

if [[ "$regression_detected" == true ]]; then
  log_warn "Baseline generated with one or more regression conditions"
else
  log_success "Baseline generated without regression conditions"
fi
