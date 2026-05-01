FROM python:3.11-slim@sha256:ff71127c215572121f1991bacf17f39ec5fcfd2de1f1c01a595835495bb9adfc

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY apps/edge-agent/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY apps/edge-agent/models.py ./models/
COPY scripts/edge-agent/register-edge-agent.sh ./scripts/
COPY scripts/edge-agent/monitor-edge-agent-health.sh ./scripts/

# Make scripts executable
RUN chmod +x ./scripts/*.sh

# Non-root user
RUN useradd -u 1007 -m -s /sbin/nologin edge-agent \
    && chown -R edge-agent:edge-agent /app

# Create logging directory
RUN mkdir -p /var/log/edge-agent && chown edge-agent:edge-agent /var/log/edge-agent

USER edge-agent

# Expose port for health checks
EXPOSE 8081

# Health check - verify heartbeat process
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8081/health || exit 1

# Default command - start registration and heartbeat daemon
ENV EDGE_AGENT_ID=edge-agent-1
ENV CONTROL_PLANE=http://control-plane:8080
ENV EDGE_LOCATION=us-west
ENV EDGE_CAPACITY=8
ENV HEARTBEAT_INTERVAL=30
ENV HEARTBEAT_TIMEOUT=60
ENV LOG_LEVEL=INFO

# Run registration script which starts heartbeat daemon
CMD ["bash", "./scripts/register-edge-agent.sh"]
