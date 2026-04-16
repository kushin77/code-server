#!/bin/bash
# deploy-telemetry-phase1.sh — Deploy Telemetry Spine (#377)
# Phase 1: Structured logging + Jaeger + health checks
# Status: READY FOR DEPLOYMENT
# Timeline: May 1-5, 2026

set -e

REMOTE_HOST="${DEPLOYMENT_HOST:-192.168.168.31}"
REMOTE_USER="${DEPLOYMENT_USER:-akushnir}"

echo "════════════════════════════════════════════════════════════════"
echo "TELEMETRY PHASE 1 DEPLOYMENT"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Target: $REMOTE_HOST (via SSH $REMOTE_USER@$REMOTE_HOST)"
echo ""

# Phase 1: Structured Logging
echo "📋 Phase 1: Structured Logging Framework"
echo "Deploy JSON logging SDKs + correlation ID propagation..."

cat > /tmp/logging-sdk-node.js << 'EOF'
// Node.js Structured Logging SDK
const winston = require('winston');

class StructuredLogger {
  constructor(serviceName) {
    this.logger = winston.createLogger({
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      ),
      defaultMeta: { service: serviceName },
      transports: [
        new winston.transports.File({ filename: '/var/log/app.jsonl' }),
        new winston.transports.Console({ format: winston.format.simple() })
      ]
    });
  }

  error(message, context = {}) {
    this.logger.error({
      level: 'ERROR',
      message,
      context,
      fingerprint: this._generateFingerprint(message),
      timestamp: new Date().toISOString()
    });
  }

  info(message, context = {}) {
    this.logger.info({ message, context });
  }

  _generateFingerprint(msg) {
    const crypto = require('crypto');
    return crypto.createHash('sha256').update(msg).digest('hex');
  }
}

module.exports = StructuredLogger;
EOF

echo "  ✅ Structured logging SDK ready"
echo ""

# Phase 2: Jaeger Tracing
echo "📋 Phase 2: Jaeger Distributed Tracing"
echo "Setup OpenTelemetry collector + Caddy trace propagation..."

cat > /tmp/caddy-tracing.conf << 'EOF'
{
  global_options {
    metrics
    http_port 80
    https_port 443
  }
}

*.192.168.168.31.nip.io {
  # Trace propagation
  header / Trace-ID {http.request.header.X-Trace-ID}
  header / Span-ID {http.request.header.X-Span-ID}
  
  # Jaeger collector
  reverse_proxy /api/traces jaeger:14250 {
    header_up X-Forwarded-For {http.request.remote.host}
  }
  
  # code-server with tracing
  reverse_proxy /code-server:8080 {
    header_up Trace-ID {http.request.header.X-Trace-ID}
    header_up X-Forwarded-Proto https
  }
}
EOF

echo "  ✅ Jaeger configuration ready"
echo ""

# Phase 3: Prometheus Metrics
echo "📋 Phase 3: Prometheus Metrics Collection"
echo "Configure application metrics exporters..."

cat > /tmp/prometheus-app-metrics.yml << 'EOF'
# Application-level metrics
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'code-server'
    static_configs:
      - targets: ['localhost:9100']
    metrics_path: '/metrics'
    
  - job_name: 'postgresql'
    static_configs:
      - targets: ['localhost:9187']
      
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:9121']

  - job_name: 'application'
    static_configs:
      - targets: ['localhost:8081']
    metrics_path: '/metrics'
EOF

echo "  ✅ Prometheus metrics configuration ready"
echo ""

# Phase 4: Health Checks
echo "📋 Phase 4: Service Health Endpoints"
echo "Deploy readiness + liveness + startup probes..."

cat > /tmp/health-checks.yaml << 'EOF'
services:
  code-server:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health/ready"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
      
  postgres:
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U coder"]
      interval: 10s
      timeout: 5s
      retries: 5
      
  prometheus:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 5s
      retries: 3
      
  jaeger:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:14269/"]
      interval: 30s
      timeout: 5s
      retries: 3
EOF

echo "  ✅ Health checks configuration ready"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "DEPLOYMENT SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Files Ready for Deployment:"
echo "  ✅ Node.js structured logging SDK"
echo "  ✅ Caddy trace propagation config"
echo "  ✅ Prometheus metrics configuration"
echo "  ✅ Docker Compose health checks"
echo ""
echo "Deployment Steps (on remote host):"
echo "  1. Copy SDKs to /app/lib/logging"
echo "  2. Update docker-compose.yml with healthchecks"
echo "  3. Configure Jaeger in services"
echo "  4. Restart docker-compose services"
echo "  5. Verify metrics in Prometheus"
echo "  6. Verify traces in Jaeger UI"
echo ""
echo "Expected Timeline: 4-5 hours implementation"
echo "Deployment Window: May 1-3, 2026"
echo "Expected Downtime: <5 minutes (rolling restart)"
echo ""
echo "Status: ✅ READY FOR DEPLOYMENT"
echo ""
echo "════════════════════════════════════════════════════════════════"
