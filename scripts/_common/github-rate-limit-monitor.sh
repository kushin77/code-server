#!/usr/bin/env bash
# @file        scripts/_common/github-rate-limit-monitor.sh
# @module      github/rate-limit-monitor
# @description GitHub API rate limit tracking, alerting, and dashboarding
#
# Provides:
# - Continuous rate limit monitoring
# - Alert thresholds (critical at <100, warning at <500)
# - Prometheus metrics export
# - Grafana dashboard integration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly RATE_LIMIT_CRITICAL=100
readonly RATE_LIMIT_WARNING=500
readonly RATE_LIMIT_CHECK_INTERVAL=300  # seconds (5 minutes)

# Prometheus metrics file
readonly METRICS_FILE="${METRICS_FILE:-/tmp/github_rate_limit_metrics.prom}"

# ============================================================================
# Rate Limit Metrics
# ============================================================================

#
# Record rate limit metrics in Prometheus format
#
github_record_metrics() {
  local token="$1"
  local rate_limit_status
  
  rate_limit_status=$(github_get_rate_limit_status "$token")
  
  local limit remaining reset
  limit=$(echo "$rate_limit_status" | jq -r '.limit')
  remaining=$(echo "$rate_limit_status" | jq -r '.remaining')
  reset=$(echo "$rate_limit_status" | jq -r '.reset')
  
  # Write Prometheus metrics
  cat > "$METRICS_FILE" <<EOF
# HELP github_rate_limit_remaining GitHub API remaining requests
# TYPE github_rate_limit_remaining gauge
github_rate_limit_remaining $remaining

# HELP github_rate_limit_limit GitHub API total request limit
# TYPE github_rate_limit_limit gauge
github_rate_limit_limit $limit

# HELP github_rate_limit_reset GitHub API reset time (Unix timestamp)
# TYPE github_rate_limit_reset gauge
github_rate_limit_reset $reset

# HELP github_rate_limit_exhaustion_percent GitHub API exhaustion percentage
# TYPE github_rate_limit_exhaustion_percent gauge
github_rate_limit_exhaustion_percent $(( 100 * (limit - remaining) / limit ))
EOF

  log_info "✓ Metrics recorded: $remaining/$limit remaining (resets at $(date -d @$reset))"
}

#
# Check rate limit and generate alerts
#
github_rate_limit_alert() {
  local token="$1"
  local rate_limit_status
  
  rate_limit_status=$(github_get_rate_limit_status "$token")
  
  local remaining reset
  remaining=$(echo "$rate_limit_status" | jq -r '.remaining')
  reset=$(echo "$rate_limit_status" | jq -r '.reset')
  
  if (( remaining < RATE_LIMIT_CRITICAL )); then
    log_fatal "🚨 CRITICAL: GitHub rate limit critical ($remaining/$RATE_LIMIT_CRITICAL remaining). Resets at $(date -d @$reset)"
    return 1
  elif (( remaining < RATE_LIMIT_WARNING )); then
    log_warn "⚠️ WARNING: GitHub rate limit approaching ($remaining/$RATE_LIMIT_WARNING remaining). Resets at $(date -d @$reset)"
  else
    log_info "✓ GitHub rate limit healthy: $remaining requests remaining"
  fi
  
  return 0
}

# ============================================================================
# Continuous Monitoring (Background Service)
# ============================================================================

#
# Start rate limit monitor as background daemon
#
github_monitor_start() {
  local token
  token=$(github_get_token)
  
  log_info "Starting GitHub rate limit monitor (check every ${RATE_LIMIT_CHECK_INTERVAL}s)..."
  
  while true; do
    github_record_metrics "$token"
    github_rate_limit_alert "$token" || true
    sleep "$RATE_LIMIT_CHECK_INTERVAL"
  done
}

#
# Monitor in foreground (for CI/scripts)
#
github_monitor_once() {
  local token
  token=$(github_get_token)
  
  github_record_metrics "$token"
  github_rate_limit_alert "$token"
}

# ============================================================================
# Exports
# ============================================================================

export -f github_record_metrics
export -f github_rate_limit_alert
export -f github_monitor_start
export -f github_monitor_once

# ============================================================================
# Main Entry Point
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-once}" in
    daemon)
      github_monitor_start
      ;;
    once|*)
      github_monitor_once
      ;;
  esac
fi
