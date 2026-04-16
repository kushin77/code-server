# Keepalived Service Configuration for docker-compose
# P2 #365: VRRP High Availability Failover
# 
# Add this service to docker-compose.yml for automatic failover between primary/replica
# Usage: docker-compose up -d keepalived
# 
# Architecture:
#   - Runs with host network (required for VRRP protocol)
#   - Primary: MASTER role, priority 100
#   - Replica: BACKUP role, priority 50
#   - Virtual IP: ${VIRTUAL_IP} (e.g., 192.168.168.30)
#   - Failover time: < 3 seconds
#   - Health checks: Docker daemon, code-server, PostgreSQL, HTTP endpoint

# Add to docker-compose.yml services section:

  keepalived:
    image: osixia/keepalived:2.0.25-amd64
    container_name: keepalived
    hostname: keepalived
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    volumes:
      - ./config/keepalived/keepalived.conf:/container/service/keepalived/assets/keepalived.conf:ro
      - ./scripts/keepalived/:/usr/local/bin/:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - KEEPALIVED_CONF=/container/service/keepalived/assets/keepalived.conf
      - KEEPALIVED_SCRIPT_DIR=/usr/local/bin
      - LOG_LEVEL=${CADDY_LOG_LEVEL:-info}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "5"
        labels: "service=keepalived,env=production"
    labels:
      - "service=keepalived"
      - "env=production"
      - "component=networking"
      - "tier=infrastructure"
    healthcheck:
      test: ["CMD", "ip", "addr", "show", "eth0:vip"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      - code-server
      - postgres
      - prometheus
    # No exposed ports - uses host network for VRRP
    # Traffic flow: Client -> ${VIRTUAL_IP} -> Keepalived -> Active Master

# NOTE: VRRP requires Linux kernel support (not available in Docker Desktop on Mac/Windows)
# For development on Windows/Mac, either:
#   1. Use manual failover (no automatic detection)
#   2. Deploy to Linux VM/cloud provider
#   3. Skip keepalived in dev, enable only in production on 192.168.168.31
