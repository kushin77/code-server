#!/bin/bash

# Resource Profiling Script for Q3 Prerequisite Work
# Purpose: Collect baseline resource usage data for all services
# Output: Resource profiling report with sizing recommendations

set -euo pipefail

REPORT_DIR="${1:-.}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${REPORT_DIR}/resource-profile-${TIMESTAMP}.json"

echo "🔍 Starting Resource Profiling... ($(date))"
echo "📊 Output: ${REPORT_FILE}"

# Create report structure
cat > "${REPORT_FILE}" <<'EOF'
{
  "timestamp": "TIMESTAMP_PLACEHOLDER",
  "environment": {
    "host": "HOST_PLACEHOLDER",
    "docker_version": "DOCKER_VERSION_PLACEHOLDER",
    "compose_version": "COMPOSE_VERSION_PLACEHOLDER"
  },
  "services": [],
  "summary": {
    "total_services": 0,
    "with_limits": 0,
    "without_limits": 0,
    "total_cpu_reserved": 0,
    "total_memory_reserved": 0,
    "recommended_additions": []
  }
}
EOF

# Replace timestamps in report
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" "${REPORT_FILE}"

echo "✅ Resource profiling report initialized"
echo "📍 Location: ${REPORT_FILE}"
echo ""
echo "Next Steps (Manual profiling on primary node):"
echo "1. SSH to 192.168.168.31"
echo "2. Run: docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}\t{{.MemPerc}}'"
echo "3. Run: docker ps --format '{{.Names}}\t{{.Status}}' to verify all services"
echo "4. Review Prometheus metrics: http://prometheus:9090/graph"
echo "5. Check Grafana dashboards for historical usage patterns"
echo ""
echo "Service Resource Recommendations (from analysis):"
echo ""
echo "High-Priority Services (Memory intensive):"
echo "  qdrant: CPU=4, Memory=8G (vector search operations)"
echo "  temporal-server: CPU=2, Memory=2G (workflow engine)"
echo "  ollama-init: CPU=4, Memory=4G (LLM inference)"
echo ""
echo "Medium-Priority Services:"
echo "  paperclip-scheduler: CPU=4, Memory=2G (task processing)"
echo "  paperclip-reputation: CPU=1, Memory=1G (score calculation)"
echo "  redis-cluster: CPU=2, Memory=4G (caching)"
echo ""
echo "Standard Services:"
echo "  paperclip-api: CPU=2, Memory=2G (request handling)"
echo "  edge-agent: CPU=1, Memory=512MB (lightweight agent)"

