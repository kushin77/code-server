#!/usr/bin/env node
/**
 * @file        scripts/clustering/websocket-gateway-cluster-api.js
 * @module      clustering/websocket-gateway
 * @description REST API for WebSocket gateway cluster management
 */

const express = require('express');
const WebSocketGatewayClusterService = require('./websocket-gateway-cluster-service');

const app = express();
const PORT = process.env.PORT || 9106;

// Initialize service
const clusterService = new WebSocketGatewayClusterService({
    clusterId: process.env.WS_CLUSTER_ID || 'ws-cluster-main',
    nodeCount: parseInt(process.env.WS_NODE_COUNT || '3'),
});

// Event listeners
clusterService.on('cluster-initialized', (context) => {
    console.log(`[WebSocket Cluster] Initialized: ${context.nodeCount} nodes`);
});

clusterService.on('connection-routed', (context) => {
    console.log(`[WebSocket Cluster] Routed ${context.connectionId} to ${context.nodeId}`);
});

clusterService.on('health-check-recorded', (context) => {
    console.log(`[WebSocket Cluster] Health: ${context.nodeId} - ${context.status} (${context.latencyMs}ms)`);
});

clusterService.on('connection-disconnected', (context) => {
    console.log(`[WebSocket Cluster] Disconnected ${context.connectionId} (${context.durationMs}ms)`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'websocket-gateway-cluster' });
});

// Route connection (idempotent)
app.post('/connections', (req, res) => {
    try {
        const connectionToken = req.headers['x-connection-token'] || 
            `conn-${req.body.connectionId}-${Date.now()}`;
        
        const route = clusterService.routeConnectionToNode(req.body, connectionToken);
        
        res.status(201).json({
            status: 'routed',
            connectionId: route.connectionId,
            nodeId: route.nodeId,
            gateway: route.gateway,
            channel: route.channel,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get route
app.get('/connections/:connectionId', (req, res) => {
    try {
        const route = clusterService.getRoute(req.params.connectionId);
        
        if (!route) {
            return res.status(404).json({ error: 'Route not found' });
        }
        
        res.json({
            connectionId: route.connectionId,
            nodeId: route.nodeId,
            gateway: route.gateway,
            userId: route.userId,
            status: route.status,
            durationMs: route.status === 'disconnected' ? route.durationMs : undefined,
            routedAt: route.routedAt,
            version: route.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query routes
app.get('/connections', (req, res) => {
    try {
        const filters = {
            nodeId: req.query.nodeId,
            status: req.query.status,
            userId: req.query.userId,
            workspaceId: req.query.workspaceId,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const routes = clusterService.queryRoutes(filters);
        
        res.json({
            total: routes.length,
            filters,
            routes: routes.map(r => ({
                connectionId: r.connectionId,
                nodeId: r.nodeId,
                status: r.status,
                userId: r.userId,
                routedAt: r.routedAt,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Disconnect connection
app.post('/connections/:connectionId/disconnect', (req, res) => {
    try {
        clusterService.disconnectConnection(req.params.connectionId);
        
        const route = clusterService.getRoute(req.params.connectionId);
        
        res.json({
            status: 'disconnected',
            connectionId: req.params.connectionId,
            durationMs: route.durationMs,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get node
app.get('/nodes/:nodeId', (req, res) => {
    try {
        const node = clusterService.getNode(req.params.nodeId);
        
        if (!node) {
            return res.status(404).json({ error: 'Node not found' });
        }
        
        res.json({
            nodeId: node.nodeId,
            host: node.host,
            port: node.port,
            status: node.status,
            currentConnections: node.currentConnections,
            maxConnections: node.maxConnections,
            utilizationPercent: (node.currentConnections / node.maxConnections * 100).toFixed(2),
            version: node.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get all nodes
app.get('/nodes', (req, res) => {
    try {
        const nodes = Array.from(clusterService.nodes.values());
        
        res.json({
            clusterId: clusterService.clusterId,
            nodeCount: nodes.length,
            nodes: nodes.map(n => ({
                nodeId: n.nodeId,
                status: n.status,
                currentConnections: n.currentConnections,
                maxConnections: n.maxConnections,
                utilizationPercent: (n.currentConnections / n.maxConnections * 100).toFixed(2),
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record health check
app.post('/nodes/:nodeId/health', (req, res) => {
    try {
        clusterService.recordHealthCheck(req.params.nodeId, req.body);
        
        const node = clusterService.getNode(req.params.nodeId);
        
        res.json({
            status: 'recorded',
            nodeId: req.params.nodeId,
            nodeStatus: node.status,
            version: node.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get cluster statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = clusterService.getClusterStatistics();
        
        res.json({
            clusterId: stats.clusterId,
            nodeCount: stats.nodeCount,
            totalConnections: stats.totalConnections,
            disconnectedConnections: stats.disconnectedConnections,
            nodeStatuses: stats.nodeStatuses,
            capacity: stats.nodeCapacity,
            avgConnectionDurationMs: stats.avgConnectionDuration,
            totalMessageRate: stats.totalMessageRate,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[WebSocket Gateway Cluster API] Listening on port ${PORT}`);
    console.log(`[WebSocket Gateway Cluster API] POST /connections - Route connection (idempotent)`);
    console.log(`[WebSocket Gateway Cluster API] GET /connections/:id - Get route`);
    console.log(`[WebSocket Gateway Cluster API] GET /connections - Query routes`);
    console.log(`[WebSocket Gateway Cluster API] POST /connections/:id/disconnect - Disconnect`);
    console.log(`[WebSocket Gateway Cluster API] GET /nodes/:id - Get node`);
    console.log(`[WebSocket Gateway Cluster API] GET /nodes - Get all nodes`);
    console.log(`[WebSocket Gateway Cluster API] POST /nodes/:id/health - Record health`);
    console.log(`[WebSocket Gateway Cluster API] GET /statistics - Get statistics`);
});
