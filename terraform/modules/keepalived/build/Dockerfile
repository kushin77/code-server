# Dockerfile for Keepalived — VRRP failover
# Env-var driven: config written at runtime by entrypoint.sh
# Required env vars: KEEPALIVED_CONF, VRRP_VIP
# Optional bind mounts for custom scripts (mounted at /usr/local/bin/)

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    keepalived \
    iputils-ping \
    curl \
    bash \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /etc/keepalived /var/log/keepalived && \
    chmod 755 /etc/keepalived /var/log/keepalived

# Copy default health monitor and notify scripts into image
COPY vrrp-health-monitor.sh /usr/local/bin/vrrp-health-monitor.sh
COPY keepalived-notify.sh   /usr/local/bin/keepalived-notify.sh
RUN chmod 755 /usr/local/bin/vrrp-health-monitor.sh \
              /usr/local/bin/keepalived-notify.sh

# Entrypoint: writes config from KEEPALIVED_CONF env var, then exec keepalived
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

HEALTHCHECK --interval=10s --timeout=3s --retries=2 \
    CMD ping -c 1 127.0.0.1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
