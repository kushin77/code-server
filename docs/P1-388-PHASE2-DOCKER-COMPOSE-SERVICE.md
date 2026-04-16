# Docker Compose addition for P1 #388 Phase 2: Token Microservice
# Add this section to docker-compose.tpl under the services: block

# TOKEN MICROSERVICE (Service-to-Service JWT Authentication)
# Port: 8888 (internal), not exposed publicly
# Purpose: Issue and validate JWT tokens for inter-service authentication
# Security: No secrets in plaintext, all via environment variables from .env
token-microservice:
  build:
    context: .
    dockerfile: Dockerfile.token-microservice
  image: ${REGISTRY}/token-microservice:${TOKEN_MICROSERVICE_VERSION:-latest}
  container_name: token-microservice
  restart: unless-stopped
  networks:
    - kushnir-net
  environment:
    # Flask configuration
    FLASK_ENV: production
    FLASK_DEBUG: "false"
    
    # OIDC configuration
    OIDC_ISSUER: https://oidc.kushnir.cloud
    OIDC_PROVIDER_URL: https://keycloak.kushnir.cloud
    PLATFORM_NAME: kushnir-platform
    
    # Token configuration
    TOKEN_TTL_MINUTES: 15
    REFRESH_WINDOW_MINUTES: 5
    
    # Service account secrets (loaded from .env via env_file)
    CODE_SERVER_SECRET: ${CODE_SERVER_CLIENT_SECRET}
    POSTGRESQL_SECRET: ${POSTGRESQL_CLIENT_SECRET}
    REDIS_SECRET: ${REDIS_CLIENT_SECRET}
    GRAFANA_SECRET: ${GRAFANA_CLIENT_SECRET}
    PROMETHEUS_SECRET: ${PROMETHEUS_CLIENT_SECRET}
    ALERTMANAGER_SECRET: ${ALERTMANAGER_CLIENT_SECRET}
    OLLAMA_SECRET: ${OLLAMA_CLIENT_SECRET}
    LOKI_SECRET: ${LOKI_CLIENT_SECRET}
    JAEGER_SECRET: ${JAEGER_CLIENT_SECRET}
    OAUTH2_PROXY_SECRET: ${OAUTH2_PROXY_CLIENT_SECRET}
    
    # Logging
    LOG_LEVEL: INFO
    
  env_file:
    - .env
  
  ports:
    # Internal only - NOT exposed to host/internet
    - "127.0.0.1:8888:8888"
  
  volumes:
    # Mount for RSA private key (created once, persisted)
    - token-microservice-keys:/etc/token-microservice:ro
    # Mount for temporary files
    - /tmp
  
  # Health check
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8888/health"]
    interval: 30s
    timeout: 5s
    retries: 3
    start_period: 10s
  
  # Security options
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  cap_add:
    - NET_BIND_SERVICE
  
  # Resource limits
  mem_limit: 256m
  memswap_limit: 256m
  cpus: "0.5"
  
  # Logging
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"
  
  # Dependencies
  depends_on:
    # Wait for core services to be healthy
    - postgresql
    - redis
  
  # Restart policy
  restart: unless-stopped

---
# Update docker-compose volumes section:
volumes:
  token-microservice-keys:
    driver: local
    driver_opts:
      type: tmpfs
      device: tmpfs

---
# Update docker-compose networks section:
# Ensure kushnir-net bridge allows service discovery
networks:
  kushnir-net:
    driver: bridge
    driver_opts:
      com.docker.network.driver.mtu: 9000
    ipam:
      config:
        - subnet: 10.0.0.0/24
