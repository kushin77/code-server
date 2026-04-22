#!/usr/bin/env node
/**
 * @file        scripts/observability/websocket-health-api.js
 * @module      observability/websocket
 * @description REST API for WebSocket health monitoring with immutable connection snapshots
 *
 * IaC Principles:
 * - Immutable: Health snapshots frozen once computed
 * - Idempotent: Same connection ID always returns consistent health data
 * - Versioned: All health records timestamped for audit trail
 */

const express = require('express');
const WebSocketHealthService = require('./websocket-health-service');

const app = express();
const PORT = process.env.PORT || 9102;

// Initialize service
const healthService = new WebSocketHealthService({
    serviceName: process.env.SERVICE_NAME || 'code-server',
});

// Event listeners
healthService.on('connection-registered', (context) => {
    console.log(`[WebSocket Health] Connection registered: ${context.connectionId} - User ${context.userId}`);
});

healthService.on('health-check-completed', (context) => {
    console.log(`[WebSocket Health] Health check: ${context.connectionId} - Status: ${context.status}, Score: ${context.score.toFixed(1)}`);
});

healthService.on('connection-closed', (context) => {
    console.log(`[WebSocket Health] Connection closed: ${context.connectionId} - Duration: ${context.duration}ms`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'websocket-health' });
});

// Register connection
app.post('/connections', (req, res) => {
    try {
        const { clientId, userId, workspaceId, remoteAddress, userAgent } = req.body;
        
        if (!clientId || !userId) {
            return res.status(400).json({ error: 'clientId and userId are required' });
        }
        
        const connectionId = healthService.registerConnection({
            clientId,
            userId,
            workspaceId,
            remoteAddress,
            userAgent,
        });
        
        res.status(201).json({
            status: 'registered',
            connectionId,
            userId,
            workspaceId,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record heartbeat
app.post('/connections/:connectionId/heartbeat', (req, res) => {
    try {
        const { latency } = req.body;
        
        if (latency === undefined) {
            return res.status(400).json({ error: 'latency is required' });
        }
        
        const connection = healthService.recordHeartbeat(req.params.connectionId, latency);
        
        res.json({
            status: 'recorded',
            connectionId: req.params.connectionId,
            latency,
            healthScore: connection.health.score,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Perform health check (idempotent)
app.post('/connections/:connectionId/check', (req, res) => {
    try {
        const checkToken = req.headers['x-check-token'] || 
            `check-${req.params.connectionId}-${Date.now()}`;
        
        const healthCheckId = healthService.performHealthCheck(
            req.params.connectionId,
            checkToken
        );
        
        const healthCheck = healthService.getHealthCheck(healthCheckId);
        
        res.status(201).json({
            status: 'checked',
            healthCheckId,
            connectionStatus: healthCheck.connectionStatus,
            healthScore: healthCheck.healthScore.toFixed(1),
            healthy: healthCheck.healthy,
            recommendation: healthCheck.recommendation,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get connection state
app.get('/connections/:connectionId', (req, res) => {
    try {
        const connection = healthService.getConnectionState(req.params.connectionId);
        
        if (!connection) {
            return res.status(404).json({ error: 'Connection not found' });
        }
        
        res.json({
            connectionId: connection.connectionId,
            userId: connection.userId,
            workspaceId: connection.workspaceId,
            status: connection.status,
            connectedAt: connection.connectedAtIso,
            lastHeartbeat: new Date(connection.lastHeartbeat).toISOString(),
            latency: connection.health.latency,
            jitter: connection.health.jitter.toFixed(2),
            healthScore: connection.health.score.toFixed(1),
            version: connection.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query connections
app.get('/connections', (req, res) => {
    try {
        const filters = {
            status: req.query.status,
            minHealthScore: req.query.minHealthScore ? parseInt(req.query.minHealthScore) : undefined,
            userId: req.query.userId,
            workspaceId: req.query.workspaceId,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const connections = healthService.queryConnections(filters);
        
        res.json({
            total: connections.length,
            filters,
            connections: connections.map(c => ({
                connectionId: c.connectionId,
                userId: c.userId,
                workspaceId: c.workspaceId,
                status: c.status,
                healthScore: c.health.score.toFixed(1),
                latency: c.latency,
                connectedAt: c.connectedAtIso,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get health statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = healthService.getHealthStatistics();
        
        res.json({
            totalConnections: stats.totalConnections,
            byStatus: stats.byStatus,
            healthyConnections: stats.healthyConnections,
            averageHealthScore: stats.averageHealthScore.toFixed(1),
            medianLatency: stats.medianLatency,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get health check
app.get('/health-checks/:healthCheckId', (req, res) => {
    try {
        const check = healthService.getHealthCheck(req.params.healthCheckId);
        
        if (!check) {
            return res.status(404).json({ error: 'Health check not found' });
        }
        
        res.json({
            healthCheckId: check.healthCheckId,
            connectionId: check.connectionId,
            checkedAt: check.checkedAt,
            status: check.connectionStatus,
            healthScore: check.healthScore.toFixed(1),
            latency: check.latency,
            jitter: check.jitter.toFixed(2),
            healthy: check.healthy,
            recommendation: check.recommendation,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Close connection
app.post('/connections/:connectionId/close', (req, res) => {
    try {
        const connection = healthService.closeConnection(req.params.connectionId);
        
        res.json({
            status: 'closed',
            connectionId: req.params.connectionId,
            duration: connection.disconnectedAt - connection.connectedAt,
            closedAt: connection.disconnectedAtIso,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[WebSocket Health API] Listening on port ${PORT}`);
    console.log(`[WebSocket Health API] POST /connections - Register connection`);
    console.log(`[WebSocket Health API] POST /connections/:id/heartbeat - Record heartbeat`);
    console.log(`[WebSocket Health API] POST /connections/:id/check - Health check (idempotent)`);
    console.log(`[WebSocket Health API] GET /connections/:id - Get connection state`);
    console.log(`[WebSocket Health API] GET /connections - Query connections`);
    console.log(`[WebSocket Health API] GET /statistics - Get statistics`);
    console.log(`[WebSocket Health API] POST /connections/:id/close - Close connection`);
});
