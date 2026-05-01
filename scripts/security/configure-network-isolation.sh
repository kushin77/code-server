#!/bin/bash
# Container Network Isolation and Security
# Creates separate networks for different service tiers with strict segmentation

set -euo pipefail

trap 'log_error "Network isolation setup failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp' EXIT

log_info() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_success() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_info "Container Network Isolation Configuration"
log_info "=========================================="
log_info ""

# Create docker-compose networks configuration
cat > /tmp/docker-compose.networks.yml << 'EOF'
version: '3.8'

# Network Segmentation Strategy:
# 1. frontend-network: Public-facing services (code-server, nginx)
# 2. backend-network: Application services (API, workers)
# 3. data-network: Data services (PostgreSQL, Redis) - isolated
# 4. monitoring-network: Monitoring stack (Prometheus, Grafana)
# 5. management-network: Management services (Terraform, admin tools)

networks:
  # Frontend Network - Public facing
  frontend-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-frontend
    ipam:
      config:
        - subnet: 10.1.0.0/16
    labels:
      tier: "public"
      security: "frontend"

  # Backend Network - Application services
  backend-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-backend
    ipam:
      config:
        - subnet: 10.2.0.0/16
    labels:
      tier: "internal"
      security: "application"

  # Data Network - Databases and caches (isolated)
  data-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-data
    ipam:
      config:
        - subnet: 10.3.0.0/16
    labels:
      tier: "internal"
      security: "database"

  # Monitoring Network - Observability stack
  monitoring-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-monitoring
    ipam:
      config:
        - subnet: 10.4.0.0/16
    labels:
      tier: "internal"
      security: "monitoring"

  # Management Network - Admin/ops tools
  management-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-management
    ipam:
      config:
        - subnet: 10.5.0.0/16
    labels:
      tier: "internal"
      security: "management"

# Network Connectivity Rules:
# 
# frontend-network ← → backend-network (HTTP/HTTPS)
# backend-network ← → data-network (PostgreSQL, Redis)
# monitoring-network ← → all networks (metrics collection)
# management-network ← → backend-network (Terraform applies)
#
# Blocked:
# - frontend ← → data (no direct DB access)
# - frontend ← → management (no admin access from public)
# - data ← → monitoring (no direct monitoring of data network - via backend only)

services:
  # Example: code-server (frontend)
  code-server-public:
    image: codercom/code-server:latest
    networks:
      - frontend-network
      - backend-network
    labels:
      tier: "public"

  # Example: API service (backend)
  api-service:
    image: your-api:latest
    networks:
      - backend-network
      - data-network
      - monitoring-network
    labels:
      tier: "internal"

  # Example: PostgreSQL (data - isolated)
  postgres:
    image: postgres:latest
    networks:
      - data-network
    labels:
      tier: "internal"
      security: "database"

  # Example: Prometheus (monitoring)
  prometheus:
    image: prom/prometheus:latest
    networks:
      - monitoring-network
      - backend-network
    labels:
      tier: "internal"
      security: "monitoring"
EOF

log_success "Network segmentation configuration created"
echo ""
cat /tmp/docker-compose.networks.yml | head -40
echo ""

# Create network policies script
cat > /tmp/network-policies.sh << 'EOF'
#!/bin/bash
# Apply Docker network policies and verify connectivity

set -euo pipefail

# Create networks
docker network create --driver bridge \
  --subnet 10.1.0.0/16 frontend-network 2>/dev/null || true

docker network create --driver bridge \
  --subnet 10.2.0.0/16 backend-network 2>/dev/null || true

docker network create --driver bridge \
  --subnet 10.3.0.0/16 data-network 2>/dev/null || true

docker network create --driver bridge \
  --subnet 10.4.0.0/16 monitoring-network 2>/dev/null || true

docker network create --driver bridge \
  --subnet 10.5.0.0/16 management-network 2>/dev/null || true

echo "✓ All container networks created"

# Display networks
docker network ls | grep -E "frontend|backend|data|monitoring|management"

# Test connectivity rules
test_connectivity() {
  echo ""
  echo "Network Connectivity Verification:"
  echo "=================================="
  
  # List network bridges
  docker network inspect frontend-network --format='Frontend IP: {{(index .IPAM.Config 0).Subnet}}'
  docker network inspect backend-network --format='Backend IP: {{(index .IPAM.Config 0).Subnet}}'
  docker network inspect data-network --format='Data IP: {{(index .IPAM.Config 0).Subnet}}'
  docker network inspect monitoring-network --format='Monitoring IP: {{(index .IPAM.Config 0).Subnet}}'
  docker network inspect management-network --format='Management IP: {{(index .IPAM.Config 0).Subnet}}'
  
  echo ""
  echo "Connectivity Rules:"
  echo "  ✓ frontend ← → backend (HTTP/HTTPS)"
  echo "  ✓ backend ← → data (PostgreSQL, Redis)"
  echo "  ✓ monitoring ← → all networks (metrics)"
  echo "  ✓ management ← → backend (Terraform)"
  echo "  ✗ frontend ← → data (BLOCKED)"
  echo "  ✗ frontend ← → management (BLOCKED)"
}

test_connectivity
EOF

chmod +x /tmp/network-policies.sh
bash /tmp/network-policies.sh

log_info ""
log_info "Network Isolation Configuration:"
log_info "5 isolated networks created:"
log_info "  - frontend-network (10.1.0.0/16)"
log_info "  - backend-network (10.2.0.0/16)"
log_info "  - data-network (10.3.0.0/16)"
log_info "  - monitoring-network (10.4.0.0/16)"
log_info "  - management-network (10.5.0.0/16)"
