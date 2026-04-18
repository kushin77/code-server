# Dockerfile for Keepalived — VRRP failover
# Based on Debian stable with minimal dependencies

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    keepalived \
        iputils-ping \
        curl \
        bash \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create keepalived config directory
RUN mkdir -p /etc/keepalived /var/log/keepalived && \
    chmod 755 /etc/keepalived /var/log/keepalived

# Health check
HEALTHCHECK --interval=10s --timeout=3s --retries=2 \
    CMD ping -c 1 127.0.0.1 || exit 1

# Entrypoint: Run Keepalived in foreground
ENTRYPOINT ["/usr/sbin/keepalived", "-f", "/etc/keepalived/keepalived.conf", "-D", "-l"]
CMD []
