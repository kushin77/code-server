#!/bin/bash
###############################################################################
# @file scripts/_common/batch-template-docker-compose.sh
# @module infrastructure
# @description Batch replace hardcoded ports in docker-compose.yml with variables
# @governance GOV-002: No hardcoded values in configuration files
# @usage bash scripts/_common/batch-template-docker-compose.sh [--dry-run]
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRY_RUN="${1:-false}"

# Color output
log_info() { echo "ℹ $*"; }
log_success() { echo "✓ $*"; }
log_warn() { echo "⚠ $*"; }

echo "$(log_success "=== Docker Compose Port Templating ===" )"
echo ""

# Port mapping replacements (PORT:PORT → ${PORT_VAR}:${PORT_VAR})
declare -a REPLACEMENTS=(
  "4180:4180|oauth2-proxy|OAUTH2_PROXY_PORT"
  "9090:9090|prometheus|PROMETHEUS_PORT"
  "3100:3100|loki|LOKI_PORT"
  "6333:6333|qdrant|QDRANT_PORT"
  "8001:8001|reputation|REPUTATION_PORT"
  "8040:8040|multimodal-ai|MULTIMODAL_AI_PORT"
  "8020:8020|agent-runtime|AGENT_RUNTIME_PORT"
  "8050:8050|control-plane|CONTROL_PLANE_PORT"
  "8010:8010|paperclip|PAPERCLIP_PORT"
  "8080:8080|scheduler|SCHEDULER_PORT"
  "18181:8181|opa|OPA_PORT"
)

# Health check URL replacements (localhost:PORT → service:${PORT_VAR})
declare -a HEALTH_CHECKS=(
  "localhost:3000|grafana|GRAFANA_PORT"
  "localhost:8001|reputation|REPUTATION_PORT"
  "localhost:8040|multimodal-ai|MULTIMODAL_AI_PORT"
  "localhost:8020|agent-runtime|AGENT_RUNTIME_PORT"
  "localhost:8010|paperclip|PAPERCLIP_PORT"
  "localhost:8080|scheduler|SCHEDULER_PORT"
  "qdrant:6333|qdrant|QDRANT_PORT"
  "alertmanager:9093|alertmanager|ALERTMANAGER_PORT"
)

FILE="${REPO_ROOT}/docker-compose.yml"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
    echo ""
fi

echo "Port mapping replacements:"
for mapping in "${REPLACEMENTS[@]}"; do
    IFS="|" read -r OLD_PORT SERVICE VAR_NAME <<< "$mapping"
    OLD_PATTERN="\"${OLD_PORT}\""
    NEW_PATTERN="\"\${${VAR_NAME}}:\${${VAR_NAME}}\""
    
    if grep -q "$OLD_PATTERN" "$FILE" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "Would replace: $OLD_PATTERN → $NEW_PATTERN (service: $SERVICE)"
        else
            sed -i "s|\"${OLD_PORT}\"|\"${${VAR_NAME}}:${${VAR_NAME}}\"|g" "$FILE"
            log_success "Replaced: $OLD_PATTERN → \$${VAR_NAME}:${$VAR_NAME} ($SERVICE)"
        fi
    fi
done

echo ""
echo "Health check URL replacements:"
for check in "${HEALTH_CHECKS[@]}"; do
    IFS="|" read -r OLD_URL SERVICE VAR_NAME <<< "$check"
    # This is more complex - would need sed with backreferences
    if grep -q "$OLD_URL" "$FILE" 2>/dev/null; then
        log_warn "Found health check URL: $OLD_URL - manual replacement needed"
    fi
done

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "To apply changes, run without --dry-run:"
    log_info "bash scripts/_common/batch-template-docker-compose.sh"
else
    log_success "Docker compose file updated"
fi
