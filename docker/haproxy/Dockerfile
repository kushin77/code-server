FROM haproxy:2.8-alpine

RUN mkdir -p /usr/local/etc/haproxy/errors /run/haproxy && \
    chown -R haproxy:haproxy /run/haproxy

# Copy default error files from parent image to local if needed,
# but alpine variant might not have them in same place.
# Using standard HTTP error pages.
COPY config/haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

EXPOSE 80 443 8404

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost/healthz || exit 1
