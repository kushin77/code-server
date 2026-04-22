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
