#!/bin/bash
# @file implement-network-policies.sh
# @module security
# @description Implement network security policies and service isolation
# @governance GOV-002 - P1 Priority 4: Network segmentation and access control
# @idempotent YES

set -euo pipefail

# Source canonical bootstrap (provides log_info, log_error, and shared configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Load service names (init.sh exports REPO_ROOT)
source "${REPO_ROOT}/scripts/_common/service-names.env"
CONFIG_DIR="${REPO_DIR}/config"
LOG_FILE="${REPO_DIR}/logs/network-policies.log"

mkdir -p "${CONFIG_DIR}/network-policies" "${REPO_DIR}/logs"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# ============================================================================
# NETWORK ARCHITECTURE DOCUMENTATION
# ============================================================================

create_network_architecture() {
  log "Creating network architecture documentation..."
  
  cat > "${CONFIG_DIR}/NETWORK-ARCHITECTURE.md" <<'EOF'
# Network Security Architecture - P1 Priority 4

## Network Segments

### 1. Public Network (ingress-net)
- **Purpose:** External traffic entry point
- **Services:** Caddy (reverse proxy), oauth2-proxy
- **Exposed Ports:** 80 (HTTP), 443 (HTTPS), 4180 (oauth2)
- **Access:** Internet (0.0.0.0/0)

### 2. Application Network (services-net)
- **Purpose:** Internal service-to-service communication
- **Services:** OPA, Prometheus, Grafana, Loki, Qdrant, Ollama, RedPanda
- **Access:** Only services within network
- **Ports:** Internal only, no external exposure

### 3. Database Network (database-net)
- **Purpose:** Isolated database tier
- **Services:** PostgreSQL, Redis
- **Access:** Only application services
- **Credentials:** Require authentication (passwords)

### 4. Management Network (admin-net)
- **Purpose:** Isolated admin/monitoring access
- **Services:** Monitoring agents, log collectors
- **Access:** Restricted to admin IPs
- **Ports:** 9090 (Prometheus internal), 5432 (db replication)

## Traffic Flow

### Allowed Connections

```
Internet → Caddy (443/TCP)
         → oauth2-proxy (4180/TCP)
           ↓
       API Backend (internal)
           ↓
       OPA Policy Engine (8181/TCP)
       PostgreSQL (5432/TCP, SSL required)
       Redis (6379/TCP, auth required)

Prometheus (9090) ← scrape targets
       ↓
Prometheus ← Grafana (internal)
       ↓
Loki ← Promtail (log shipper)
```

### Denied Connections

- ❌ External → PostgreSQL (direct access blocked)
- ❌ External → Redis (direct access blocked)
- ❌ Application → Unregistered services
- ❌ Database → External networks

## Service Isolation Matrix

| From | To | Port | Protocol | Status |
|------|----|----|----------|--------|
| caddy | api-backend | 3100 | TCP | ✅ ALLOW |
| caddy | oauth2-proxy | 4180 | TCP | ✅ ALLOW |
| api-backend | postgres | 5432 | TCP | ✅ ALLOW (SSL) |
| api-backend | redis | 6379 | TCP | ✅ ALLOW (AUTH) |
| api-backend | opa | 8181 | TCP | ✅ ALLOW |
| prometheus | services | 9090 | TCP | ✅ ALLOW (metrics) |
| external | postgres | 5432 | TCP | ❌ DENY |
| external | redis | 6379 | TCP | ❌ DENY |
| external | opa | 8181 | TCP | ❌ DENY |

## Docker Network Configuration

### Public Network
```yaml
networks:
  ingress-net:
    driver: bridge
    driver_opts:
      com.docker.network.driver.mtu: 1500
      com.docker.network.bridge.name: br-public
    ipam:
      config:
        - subnet: 10.0.1.0/24
```

### Internal Services Network
```yaml
networks:
  services-net:
    driver: bridge
    internal: false  # Allow external if needed
    driver_opts:
      com.docker.network.driver.mtu: 1500
      com.docker.network.bridge.name: br-services
    ipam:
      config:
        - subnet: 10.0.2.0/24
```

### Database Network
```yaml
networks:
  database-net:
    driver: bridge
    internal: true   # No external access
    driver_opts:
      com.docker.network.driver.mtu: 1500
      com.docker.network.bridge.name: br-database
    ipam:
      config:
        - subnet: 10.0.3.0/24
```

## Firewall Rules (iptables/UFW)

### Host-level rules

```bash
# Allow external traffic to Caddy only
ufw allow 80/tcp
ufw allow 443/tcp

# Block direct access to database ports
ufw deny 5432/tcp
ufw deny 6379/tcp

# Block direct access to internal services
ufw deny 8181/tcp  # OPA
ufw deny 8080/tcp  # App
ufw deny 9090/tcp  # Prometheus (external)
```

## Monitoring Network Traffic

### View Docker network connections
```bash
docker network ls
docker network inspect services-net
```

### Monitor container traffic
```bash
docker stats --no-stream
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

### Verify network policies
```bash
# Test connectivity
docker exec "${POSTGRES_CONTAINER_NAME}" ping "${REDIS_CONTAINER_NAME}"
docker exec api-backend curl -f http://opa:8181/health
```

## Security Benefits

1. **Isolation:** Database tier isolated from direct internet access
2. **Least Privilege:** Services only connect to required dependencies
3. **Monitoring:** All connections can be logged and monitored
4. **Compliance:** Meets SOC 2, PCI-DSS network segmentation requirements
5. **Incident Response:** Compromised service can't access entire network

EOF
  
  log "✓ Created network architecture documentation"
}

# ============================================================================
# NETWORK POLICIES CONFIGURATION
# ============================================================================

create_network_policies_config() {
  log "Creating network policies configuration..."
  
  cat > "${CONFIG_DIR}/network-policies/base-network-policies.yaml" <<'EOF'
# =============================================================================
# Network Security Policies - Base Configuration
# =============================================================================
# These policies define allowed inter-service communication
# Apply via: docker network create or Kubernetes NetworkPolicy

version: '3.9'

networks:
  # Public/Ingress network - only Caddy and oauth2-proxy exposed
  ingress-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.1.0/24
          gateway: 10.0.1.1

  # Internal services network - backend, OPA, monitoring
  services-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.2.0/24
          gateway: 10.0.2.1

  # Database network - isolated, internal only
  database-net:
    driver: bridge
    internal: true  # No external routing
    ipam:
      config:
        - subnet: 10.0.3.0/24
          gateway: 10.0.3.1

# =============================================================================
# Service Network Assignments (reference for docker-compose.yml)
# =============================================================================

services:
  # Public services - exposed to internet
  caddy:
    networks:
      ingress-net:
        ipv4_address: 10.0.1.10
      services-net:
        ipv4_address: 10.0.2.10

  oauth2-proxy:
    networks:
      ingress-net:
        ipv4_address: 10.0.1.11

  # Application tier - internal services
  api-backend:
    networks:
      services-net:
        ipv4_address: 10.0.2.20
      database-net:
        ipv4_address: 10.0.3.20

  opa:
    networks:
      services-net:
        ipv4_address: 10.0.2.30

  prometheus:
    networks:
      services-net:
        ipv4_address: 10.0.2.40

  grafana:
    networks:
      services-net:
        ipv4_address: 10.0.2.41

  loki:
    networks:
      services-net:
        ipv4_address: 10.0.2.42

  redpanda:
    networks:
      services-net:
        ipv4_address: 10.0.2.50

  # Database tier - isolated
  postgres:
    networks:
      database-net:
        ipv4_address: 10.0.3.100

  redis:
    networks:
      database-net:
        ipv4_address: 10.0.3.101

  qdrant:
    networks:
      services-net:
        ipv4_address: 10.0.2.60
EOF
  
  log "✓ Created base network policies configuration"
}

# ============================================================================
# NETWORK POLICIES RULES
# ============================================================================

create_network_rules() {
  log "Creating network policies rules..."
  
  cat > "${CONFIG_DIR}/network-policies/traffic-rules.md" <<'EOF'
# Network Traffic Rules - P1 Priority 4

## Ingress Rules (Inbound)

### Public Services (Allowed from Internet)
- **80/tcp**: HTTP → Caddy (redirect to HTTPS)
- **443/tcp**: HTTPS → Caddy (TLS gateway)
- **4180/tcp**: OAuth2-Proxy → oauth2-proxy (auth flows)

### Blocked from Internet
- **5432/tcp**: PostgreSQL (no direct internet access)
- **6379/tcp**: Redis (no direct internet access)
- **8181/tcp**: OPA (policy engine internal only)
- **8080/tcp**: Application API (internal only)
- **9090/tcp**: Prometheus (internal monitoring only)

## Egress Rules (Outbound)

### Internal Service Communication (Allowed)
- **caddy** → **api-backend** (10.0.2.20:3100)
- **caddy** → **oauth2-proxy** (10.0.1.11:4180)
- **api-backend** → **postgres** (10.0.3.100:5432, SSL required)
- **api-backend** → **redis** (10.0.3.101:6379, AUTH required)
- **api-backend** → **opa** (10.0.2.30:8181)
- **prometheus** → **all-services** (metrics scraping)
- **loki** → **all-services** (log collection)

### Internet Egress (Allowed for updates)
- **80/tcp**: HTTP (package updates, external APIs)
- **443/tcp**: HTTPS (external APIs, downloads)
- **DNS**: 53/udp (DNS resolution)

## Kubernetes NetworkPolicy Examples

```yaml
---
# Deny all ingress by default (default-deny)
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress

---
# Allow Caddy ingress from internet
kind: NetworkPolicy
metadata:
  name: allow-caddy-public
spec:
  podSelector:
    matchLabels:
      app: caddy
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443

---
# Allow api-backend to database tier
kind: NetworkPolicy
metadata:
  name: allow-api-to-database
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: application
    ports:
    - protocol: TCP
      port: 5432

---
# Allow Prometheus metrics scraping
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
spec:
  podSelector:
    matchLabels:
      metrics: enabled
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 9090
```

EOF
  
  log "✓ Created network traffic rules"
}

# ============================================================================
# VERIFICATION SCRIPT
# ============================================================================

create_verification_script() {
  log "Creating network policy verification script..."
  
  cat > "${CONFIG_DIR}/network-policies/verify-network-policies.sh" <<'EOF'
#!/bin/bash
# Verify network policies are correctly configured

echo "Network Policy Verification - P1 Priority 4"
echo "==========================================="
echo ""

# Check Docker networks exist
echo "1. Checking Docker networks..."
docker network ls | grep -E "ingress-net|services-net|database-net" || echo "❌ Networks not found"

# Verify public services are exposed
echo ""
echo "2. Verifying public service exposure..."
docker port caddy 443/tcp || echo "❌ Caddy not exposed"
docker port oauth2-proxy 4180/tcp || echo "❌ oauth2-proxy not exposed"

# Test internal connectivity
echo ""
echo "3. Testing internal connectivity..."
docker exec api-backend curl -s http://opa:8181/health >/dev/null && echo "✓ API → OPA" || echo "❌ API → OPA"
docker exec api-backend psql -h postgres -U postgres -d postgres -c "SELECT 1" >/dev/null 2>&1 && echo "✓ API → PostgreSQL" || echo "❌ API → PostgreSQL"

# Check blocked connections
echo ""
echo "4. Verifying blocked connections..."
timeout 2 bash -c "echo | nc -w1 postgres 5432" >/dev/null 2>&1 && echo "❌ PostgreSQL exposed (should be blocked)" || echo "✓ PostgreSQL blocked"
timeout 2 bash -c "echo | nc -w1 redis 6379" >/dev/null 2>&1 && echo "❌ Redis exposed (should be blocked)" || echo "✓ Redis blocked"

# Display network configuration
echo ""
echo "5. Current network configuration..."
docker inspect $(docker ps -q -f "label=com.docker.compose.service=caddy") --format='Network: {{range .NetworkSettings.Networks}}{{.NetworkID}} {{end}}'

echo ""
echo "==========================================="
EOF
  
  chmod +x "${CONFIG_DIR}/network-policies/verify-network-policies.sh"
  log "✓ Created verification script"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  log "==========================================="
  log "Network Security Policies - P1 Priority 4"
  log "==========================================="
  log ""
  
  create_network_architecture
  create_network_policies_config
  create_network_rules
  create_verification_script
  
  log ""
  log "✓ Network Security Policies Created"
  log "==========================================="
  log "Configuration Files:"
  log "  Architecture: ${CONFIG_DIR}/NETWORK-ARCHITECTURE.md"
  log "  Policies: ${CONFIG_DIR}/network-policies/base-network-policies.yaml"
  log "  Rules: ${CONFIG_DIR}/network-policies/traffic-rules.md"
  log ""
  log "Next Steps:"
  log "1. Update docker-compose.yml with network assignments"
  log "2. Verify networks created correctly"
  log "3. Test inter-service connectivity"
  log "4. Monitor network policies in production"
  log "==========================================="
}

main "$@"
