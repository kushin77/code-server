# Docker Compose service template
# Render this file with envsubst or the repository's templating pipeline.
# All values are intentionally parameterized for immutable deployments.

services:
  ${service_name}:
    image: ${image_name}:${image_tag}
    container_name: ${container_name}
    restart: unless-stopped
    networks:
      - ${network_name}
    user: "${user_uid}:${user_gid}"
    environment:
      - SERVICE_NAME=${service_name}
      - SERVICE_DOMAIN=${service_domain}
    expose:
      - "${service_port}"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:${health_port}${health_path} || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    labels:
      - "com.kushnir.service=${service_name}"