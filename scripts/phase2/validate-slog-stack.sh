#!/usr/bin/env bash
# @file scripts/phase2/validate-slog-stack.sh
# @description Phase 2 - Validate SLOG observability stack components are deployable.
# Referenced by GitHub issue #2398 (Post-Deployment Validation) and EPIC-2 (#2370).

set -euo pipefail

# Required error handling traps (pre-commit policy)
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../_common/init.sh"

ARTIFACT="${REPO_ROOT}/artifacts/phase2-slog-stack-$(date -u +%Y%m%dT%H%M%SZ).md"

components=(
    "OpenSearch:scripts/phase2/deploy-opensearch-cluster.sh"
    "Fluentd:scripts/phase2/deploy-fluentd-aggregator.sh"
    "Prometheus:scripts/phase2/deploy-prometheus-metrics.sh"
    "Grafana:scripts/phase2/deploy-grafana-dashboards.sh"
)

log_info "=== Phase 2 SLOG Stack Validation ==="

results=()
ok=0
miss=0
for entry in "${components[@]}"; do
    name="${entry%%:*}"
    path="${entry##*:}"
    if [ -f "${REPO_ROOT}/${path}" ]; then
        results+=("PRESENT | ${name} | ${path}")
        ok=$((ok + 1))
        log_success "  ${name}: ${path}"
    else
        results+=("MISSING | ${name} | ${path}")
        miss=$((miss + 1))
        log_warning "  ${name}: missing ${path}"
    fi
done

# Compose manifest sanity check
compose_present="MISSING"
if [ -f "${REPO_ROOT}/docker-compose.observability.yml" ]; then
    compose_present="PRESENT"
fi
log_info "  docker-compose.observability.yml: ${compose_present}"

{
    printf '# Phase 2 SLOG Stack Validation\n\n'
    printf 'Generated: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '## Deployment Scripts\n\n'
    printf '| Status | Component | Path |\n|---|---|---|\n'
    for r in "${results[@]}"; do
        printf '| %s |\n' "${r}"
    done
    printf '\n## Compose Manifest\n\n- docker-compose.observability.yml: %s\n\n' "${compose_present}"
    printf '## Summary\n\n- Present: %d/%d\n- Missing: %d\n' \
        "${ok}" "${#components[@]}" "${miss}"
} > "${ARTIFACT}"

log_success "Report: ${ARTIFACT}"
exit 0
