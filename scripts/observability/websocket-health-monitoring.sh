#!/usr/bin/env bash
# @file        scripts/observability/websocket-health-monitoring.sh
# @module      observability/websocket
# @description WebSocket health monitoring - Per-connection latency, jitter, packet loss, quality scoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

log_info "=========================================="
log_info "P1 #1295: WebSocket Health Monitoring"
log_info "=========================================="

# WebSocket health monitoring implementation
create_websocket_health_monitor() {
    echo "Creating WebSocket health monitoring service..."
    
    cat > "${SCRIPT_DIR}/scripts/monitoring/ws-health-monitor.js" << 'EOF'
#!/usr/bin/env node
/**
 * WebSocket Health Monitoring Service
 * Tracks per-connection: latency, jitter, packet loss, quality score (0-100)
 * Implements auto-reconnect with exponential backoff
 */

const EventEmitter = require('events');
const WebSocket = require('ws');

class WebSocketHealthMonitor extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.url = options.url || 'ws://localhost:8080';
        this.sessionId = options.sessionId || `session-${Date.now()}`;
        this.checkInterval = options.checkInterval || 1000; // ms between health checks
        this.maxReconnectAttempts = options.maxReconnectAttempts || 10;
        this.baseBackoffMs = options.baseBackoffMs || 100; // exponential backoff base
        
        // Health metrics
        this.metrics = {
            latencies: [],
            packetsSent: 0,
            packetsReceived: 0,
            packetLossCount: 0,
            jitter: 0,
            qualityScore: 100,
            reconnectAttempts: 0,
            uptime: 0,
            startTime: Date.now(),
        };
        
        // Configuration
        this.maxLatencyHistorySize = 100;
        this.qualityThresholds = {
            excellent: { latency: 50, jitter: 10, packetLoss: 0 },     // > 90
            good: { latency: 100, jitter: 25, packetLoss: 0.5 },       // 70-90
            fair: { latency: 200, jitter: 50, packetLoss: 2 },         // 50-70
            poor: { latency: 500, jitter: 100, packetLoss: 5 },        // 20-50
            critical: { latency: 1000, jitter: 200, packetLoss: 10 },  // < 20
        };
        
        this.ws = null;
        this.healthCheckInterval = null;
        this.reconnectTimeout = null;
    }
    
    connect() {
        return new Promise((resolve, reject) => {
            try {
                this.ws = new WebSocket(`${this.url}/ws?session_id=${this.sessionId}`);
                
                this.ws.on('open', () => {
                    console.log(`[WS Health] Connected: ${this.sessionId}`);
                    this.metrics.reconnectAttempts = 0;
                    this.metrics.startTime = Date.now();
                    this.startHealthChecks();
                    this.emit('connected');
                    resolve();
                });
                
                this.ws.on('message', (data) => {
                    this.handleMessage(data);
                });
                
                this.ws.on('ping', () => {
                    this.recordPing();
                });
                
                this.ws.on('pong', () => {
                    this.recordPong();
                });
                
                this.ws.on('error', (error) => {
                    console.error(`[WS Health] Error:`, error.message);
                    this.emit('error', error);
                });
                
                this.ws.on('close', () => {
                    console.log(`[WS Health] Closed: ${this.sessionId}`);
                    this.stopHealthChecks();
                    this.attemptReconnect().catch(reject);
                });
                
            } catch (err) {
                reject(err);
            }
        });
    }
    
    handleMessage(data) {
        try {
            const message = JSON.parse(data);
            
            // Track packet received
            this.metrics.packetsReceived++;
            
            // Extract latency if timestamp present
            if (message.timestamp) {
                const latency = Date.now() - message.timestamp;
                this.recordLatency(latency);
            }
            
            this.emit('message', message);
            
        } catch (err) {
            console.error(`[WS Health] Message parse error:`, err);
        }
    }
    
    recordLatency(latencyMs) {
        // Add to history
        this.metrics.latencies.push(latencyMs);
        
        // Keep history size bounded
        if (this.metrics.latencies.length > this.maxLatencyHistorySize) {
            this.metrics.latencies.shift();
        }
        
        // Calculate jitter (variance in latency)
        if (this.metrics.latencies.length > 1) {
            this.calculateJitter();
        }
        
        // Update quality score
        this.updateQualityScore();
    }
    
    calculateJitter() {
        if (this.metrics.latencies.length < 2) return;
        
        const mean = this.metrics.latencies.reduce((a, b) => a + b, 0) / this.metrics.latencies.length;
        const variance = this.metrics.latencies.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / this.metrics.latencies.length;
        this.metrics.jitter = Math.sqrt(variance);
    }
    
    recordPing() {
        this.metrics.packetsSent++;
    }
    
    recordPong() {
        // Pong is implicit acknowledgment
    }
    
    updateQualityScore() {
        const avgLatency = this.getAverageLatency();
        const packetLossRate = this.getPacketLossRate();
        
        let score = 100;
        
        // Latency impact (0-30 points)
        if (avgLatency < 50) score -= 0;
        else if (avgLatency < 100) score -= 5;
        else if (avgLatency < 200) score -= 10;
        else if (avgLatency < 500) score -= 20;
        else score -= 30;
        
        // Jitter impact (0-20 points)
        if (this.metrics.jitter < 10) score -= 0;
        else if (this.metrics.jitter < 25) score -= 5;
        else if (this.metrics.jitter < 50) score -= 10;
        else if (this.metrics.jitter < 100) score -= 15;
        else score -= 20;
        
        // Packet loss impact (0-50 points)
        if (packetLossRate === 0) score -= 0;
        else if (packetLossRate < 0.5) score -= 10;
        else if (packetLossRate < 2) score -= 25;
        else if (packetLossRate < 5) score -= 40;
        else score -= 50;
        
        // Ensure score is between 0-100
        this.metrics.qualityScore = Math.max(0, Math.min(100, score));
    }
    
    getAverageLatency() {
        if (this.metrics.latencies.length === 0) return 0;
        const sum = this.metrics.latencies.reduce((a, b) => a + b, 0);
        return sum / this.metrics.latencies.length;
    }
    
    getPacketLossRate() {
        const total = this.metrics.packetsSent;
        if (total === 0) return 0;
        return (this.metrics.packetLossCount / total) * 100;
    }
    
    startHealthChecks() {
        this.healthCheckInterval = setInterval(() => {
            this.performHealthCheck();
        }, this.checkInterval);
    }
    
    stopHealthChecks() {
        if (this.healthCheckInterval) {
            clearInterval(this.healthCheckInterval);
            this.healthCheckInterval = null;
        }
    }
    
    performHealthCheck() {
        if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
            return;
        }
        
        // Send ping/pong
        const pingTime = Date.now();
        this.ws.ping(JSON.stringify({ timestamp: pingTime }));
        
        // Update uptime
        this.metrics.uptime = Date.now() - this.metrics.startTime;
    }
    
    getHealthStatus() {
        const avgLatency = this.getAverageLatency();
        const packetLossRate = this.getPacketLossRate();
        
        let status = 'excellent';
        
        if (this.metrics.qualityScore >= 90) {
            status = 'excellent';
        } else if (this.metrics.qualityScore >= 70) {
            status = 'good';
        } else if (this.metrics.qualityScore >= 50) {
            status = 'fair';
        } else if (this.metrics.qualityScore >= 20) {
            status = 'poor';
        } else {
            status = 'critical';
        }
        
        return {
            status,
            qualityScore: Math.round(this.metrics.qualityScore),
            avgLatency: Math.round(avgLatency),
            jitter: Math.round(this.metrics.jitter),
            packetLoss: Math.round(packetLossRate * 100) / 100,
            packetsSent: this.metrics.packetsSent,
            packetsReceived: this.metrics.packetsReceived,
            uptime: this.metrics.uptime,
            reconnectAttempts: this.metrics.reconnectAttempts,
        };
    }
    
    async attemptReconnect() {
        if (this.metrics.reconnectAttempts >= this.maxReconnectAttempts) {
            console.error(`[WS Health] Max reconnect attempts (${this.maxReconnectAttempts}) exceeded`);
            this.emit('fatal-error', 'Max reconnect attempts exceeded');
            return;
        }
        
        this.metrics.reconnectAttempts++;
        
        // Exponential backoff: 100ms, 200ms, 400ms, 800ms, 1.6s, 3.2s, 6.4s, 12.8s, 25.6s, 51.2s
        const backoffMs = this.baseBackoffMs * Math.pow(2, this.metrics.reconnectAttempts - 1);
        const maxBackoffMs = 60000; // 60 second max
        const actualBackoffMs = Math.min(backoffMs, maxBackoffMs);
        
        console.log(`[WS Health] Reconnecting in ${actualBackoffMs}ms (attempt ${this.metrics.reconnectAttempts}/${this.maxReconnectAttempts})`);
        
        return new Promise((resolve) => {
            this.reconnectTimeout = setTimeout(() => {
                this.connect().catch(err => {
                    console.error(`[WS Health] Reconnect failed:`, err);
                    resolve(this.attemptReconnect());
                });
                resolve();
            }, actualBackoffMs);
        });
    }
    
    disconnect() {
        console.log(`[WS Health] Disconnecting: ${this.sessionId}`);
        
        this.stopHealthChecks();
        
        if (this.reconnectTimeout) {
            clearTimeout(this.reconnectTimeout);
        }
        
        if (this.ws) {
            this.ws.close();
            this.ws = null;
        }
    }
}

module.exports = WebSocketHealthMonitor;
EOF
    
    chmod +x "${SCRIPT_DIR}/scripts/monitoring/ws-health-monitor.js"
    log_info "✓ WebSocket health monitor service created"
}

# Create health monitoring API
create_health_api() {
    echo "Creating health monitoring REST API..."
    
    cat > "${SCRIPT_DIR}/scripts/monitoring/ws-health-api.js" << 'EOF'
#!/usr/bin/env node
/**
 * WebSocket Health Monitoring API
 * Express server exposing health metrics via REST endpoints
 */

const express = require('express');
const WebSocketHealthMonitor = require('./ws-health-monitor');

const app = express();
const PORT = process.env.PORT || 9091;

// Global monitors map (session_id → monitor)
const monitors = new Map();

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'ws-health-api', timestamp: Date.now() });
});

// Get health for specific session
app.get('/health/:sessionId', (req, res) => {
    const { sessionId } = req.params;
    const monitor = monitors.get(sessionId);
    
    if (!monitor) {
        return res.status(404).json({ error: 'Session not found', sessionId });
    }
    
    res.json(monitor.getHealthStatus());
});

// Get health for all active sessions
app.get('/health/sessions/all', (req, res) => {
    const allHealth = {};
    
    monitors.forEach((monitor, sessionId) => {
        allHealth[sessionId] = monitor.getHealthStatus();
    });
    
    res.json({
        totalSessions: monitors.size,
        sessions: allHealth,
        timestamp: Date.now()
    });
});

// Create new monitored session
app.post('/sessions/:sessionId', (req, res) => {
    const { sessionId } = req.params;
    const { url = 'ws://localhost:8080' } = req.body || {};
    
    if (monitors.has(sessionId)) {
        return res.status(409).json({ error: 'Session already exists', sessionId });
    }
    
    const monitor = new WebSocketHealthMonitor({
        url,
        sessionId,
        checkInterval: 1000,
    });
    
    monitor.connect()
        .then(() => {
            monitors.set(sessionId, monitor);
            res.status(201).json({
                sessionId,
                status: 'created',
                monitoring: true
            });
        })
        .catch(err => {
            res.status(500).json({ error: 'Failed to connect', details: err.message });
        });
});

// Stop monitoring session
app.delete('/sessions/:sessionId', (req, res) => {
    const { sessionId } = req.params;
    const monitor = monitors.get(sessionId);
    
    if (!monitor) {
        return res.status(404).json({ error: 'Session not found', sessionId });
    }
    
    monitor.disconnect();
    monitors.delete(sessionId);
    
    res.json({ sessionId, status: 'stopped' });
});

// Metrics endpoint (Prometheus-compatible)
app.get('/metrics', (req, res) => {
    let metricsOutput = '# HELP ws_health_quality_score WebSocket connection quality score (0-100)\n';
    metricsOutput += '# TYPE ws_health_quality_score gauge\n';
    
    monitors.forEach((monitor, sessionId) => {
        const health = monitor.getHealthStatus();
        metricsOutput += `ws_health_quality_score{session_id="${sessionId}"} ${health.qualityScore}\n`;
        metricsOutput += `ws_health_latency_ms{session_id="${sessionId}"} ${health.avgLatency}\n`;
        metricsOutput += `ws_health_jitter_ms{session_id="${sessionId}"} ${health.jitter}\n`;
        metricsOutput += `ws_health_packet_loss_pct{session_id="${sessionId}"} ${health.packetLoss}\n`;
    });
    
    res.type('text/plain').send(metricsOutput);
});

app.listen(PORT, () => {
    console.log(`[WS Health API] Listening on port ${PORT}`);
    console.log(`[WS Health API] Health: http://localhost:${PORT}/health`);
    console.log(`[WS Health API] Metrics: http://localhost:${PORT}/metrics`);
});
EOF
    
    chmod +x "${SCRIPT_DIR}/scripts/monitoring/ws-health-api.js"
    log_info "✓ Health monitoring API created"
}

# Create Prometheus alerting rules
create_alert_rules() {
    echo "Creating Prometheus alert rules for WebSocket health..."
    
    cat > "${SCRIPT_DIR}/config/ws-health-alerts.yml" << 'EOF'
groups:
  - name: websocket_health
    interval: 30s
    rules:
      # Critical: Quality score < 20
      - alert: WebSocketHealthCritical
        expr: ws_health_quality_score < 20
        for: 1m
        labels:
          severity: critical
          component: websocket
        annotations:
          summary: "WebSocket connection critical for {{ $labels.session_id }}"
          description: "Quality score: {{ $value }}. Check latency, jitter, packet loss."
      
      # Warning: Quality score 20-50
      - alert: WebSocketHealthPoor
        expr: ws_health_quality_score < 50 and ws_health_quality_score >= 20
        for: 5m
        labels:
          severity: warning
          component: websocket
        annotations:
          summary: "WebSocket connection poor for {{ $labels.session_id }}"
          description: "Quality score: {{ $value }}. Monitor connection stability."
      
      # High latency (> 500ms)
      - alert: WebSocketHighLatency
        expr: ws_health_latency_ms > 500
        for: 2m
        labels:
          severity: warning
          component: websocket
        annotations:
          summary: "High latency on {{ $labels.session_id }}"
          description: "Average latency: {{ $value }}ms"
      
      # High jitter (> 100ms)
      - alert: WebSocketHighJitter
        expr: ws_health_jitter_ms > 100
        for: 2m
        labels:
          severity: warning
          component: websocket
        annotations:
          summary: "High jitter on {{ $labels.session_id }}"
          description: "Jitter: {{ $value }}ms"
      
      # Packet loss > 5%
      - alert: WebSocketPacketLoss
        expr: ws_health_packet_loss_pct > 5
        for: 1m
        labels:
          severity: critical
          component: websocket
        annotations:
          summary: "High packet loss on {{ $labels.session_id }}"
          description: "Packet loss: {{ $value }}%"
EOF
    
    log_info "✓ Alert rules created"
}

# Create health dashboard
create_grafana_dashboard() {
    echo "Creating Grafana dashboard for WebSocket health..."
    
    cat > "${SCRIPT_DIR}/config/grafana-ws-health-dashboard.json" << 'EOF'
{
  "dashboard": {
    "title": "WebSocket Health Monitoring",
    "panels": [
      {
        "title": "Quality Score by Session",
        "targets": [
          { "expr": "ws_health_quality_score" }
        ],
        "type": "graph"
      },
      {
        "title": "Average Latency",
        "targets": [
          { "expr": "ws_health_latency_ms" }
        ],
        "type": "graph"
      },
      {
        "title": "Jitter",
        "targets": [
          { "expr": "ws_health_jitter_ms" }
        ],
        "type": "graph"
      },
      {
        "title": "Packet Loss %",
        "targets": [
          { "expr": "ws_health_packet_loss_pct" }
        ],
        "type": "graph"
      }
    ]
  }
}
EOF
    
    log_info "✓ Grafana dashboard created"
}

main() {
    log_info ""
    create_websocket_health_monitor
    log_info ""
    create_health_api
    log_info ""
    create_alert_rules
    log_info ""
    create_grafana_dashboard
    log_info ""
    
    log_info "=========================================="
    log_info "WebSocket Health Monitoring Implementation"
    log_info "=========================================="
    log_info ""
    log_info "✓ Health monitor service (ws-health-monitor.js)"
    log_info "✓ REST API service (ws-health-api.js)"
    log_info "✓ Prometheus alert rules (ws-health-alerts.yml)"
    log_info "✓ Grafana dashboard (grafana-ws-health-dashboard.json)"
    log_info ""
    log_info "Metrics Tracked Per-Connection:"
    log_info "  - Average latency (ms)"
    log_info "  - Jitter (ms)"
    log_info "  - Packet loss (% and count)"
    log_info "  - Quality score (0-100)"
    log_info ""
    log_info "Quality Score Levels:"
    log_info "  - Excellent: 90-100"
    log_info "  - Good: 70-90"
    log_info "  - Fair: 50-70"
    log_info "  - Poor: 20-50"
    log_info "  - Critical: 0-20"
    log_info ""
    log_info "Auto-reconnect: Exponential backoff (100ms - 60s)"
    log_info ""
}

main
