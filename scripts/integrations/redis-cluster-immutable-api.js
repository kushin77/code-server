#!/usr/bin/env node
/**
 * @file        scripts/integrations/redis-cluster-immutable-api.js
 * @module      integrations/redis
 * @description REST API for Redis cluster management
 */

const express = require('express');
const RedisClusterService = require('./redis-cluster-immutable-service');

const app = express();
const PORT = process.env.PORT || 9113;

// Initialize service
const redisService = new RedisClusterService({
    baseUrl: process.env.REDIS_CLUSTER_URL,
});

// Event listeners
redisService.on('cluster-created', (context) => {
    console.log(`[Redis Cluster] Created: ${context.name} (${context.nodeCount} nodes)`);
});

redisService.on('node-joined', (context) => {
    console.log(`[Redis Cluster] Node: ${context.nodeId} (${context.role}) → ${context.address}`);
});

redisService.on('handshake-complete', (context) => {
    console.log(`[Redis Cluster] Handshake: ${context.nodeId} - ${context.status}`);
});

redisService.on('slots-assigned', (context) => {
    console.log(`[Redis Cluster] Slots: ${context.nodeId} - [${context.startSlot}..${context.endSlot}] (${context.slotCount} slots)`);
});

redisService.on('replication-configured', (context) => {
    console.log(`[Redis Cluster] Replication: ${context.nodeId} - priority ${context.priority}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'redis-cluster-integration' });
});

// Create cluster
app.post('/clusters', (req, res) => {
    try {
        const clusterId = redisService.createCluster(req.body);
        
        const cluster = redisService.clusters.get(clusterId);
        
        res.status(201).json({
            status: 'created',
            clusterId,
            name: cluster.name,
            nodeCount: cluster.nodeCount,
            replicationFactor: cluster.replicationFactor,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Join node to cluster (idempotent)
app.post('/clusters/:clusterId/join', (req, res) => {
    try {
        const joinToken = req.headers['x-join-token'] || 
            `join-${req.body.nodeName}-${Date.now()}`;
        
        const nodeId = redisService.joinCluster(req.params.clusterId, req.body, joinToken);
        
        const node = redisService.getNode(nodeId);
        
        res.status(201).json({
            status: 'joined',
            nodeId,
            clusterId: req.params.clusterId,
            role: node.role,
            address: `${node.host}:${node.port}`,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record node handshake
app.post('/nodes/:nodeId/handshake', (req, res) => {
    try {
        redisService.recordHandshake(req.params.nodeId, req.body);
        
        const node = redisService.getNode(req.params.nodeId);
        
        res.json({
            status: 'handshake-recorded',
            nodeId: req.params.nodeId,
            nodeStatus: node.status,
            connected: node.connected,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get node
app.get('/nodes/:nodeId', (req, res) => {
    try {
        const node = redisService.getNode(req.params.nodeId);
        
        if (!node) {
            return res.status(404).json({ error: 'Node not found' });
        }
        
        res.json({
            nodeId: node.nodeId,
            clusterId: node.clusterId,
            role: node.role,
            host: node.host,
            port: node.port,
            status: node.status,
            connected: node.connected,
            joinedAt: node.joinedAt,
            lastHeartbeat: node.lastHeartbeat,
            replicationOffset: node.replicationOffset,
            version: node.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query nodes by cluster
app.get('/clusters/:clusterId/nodes', (req, res) => {
    try {
        const filters = {
            role: req.query.role,
            status: req.query.status,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const nodes = redisService.queryNodesByCluster(req.params.clusterId, filters);
        
        res.json({
            total: nodes.length,
            clusterId: req.params.clusterId,
            nodes: nodes.map(n => ({
                nodeId: n.nodeId,
                role: n.role,
                address: `${n.host}:${n.port}`,
                status: n.status,
                connected: n.connected,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Assign slots to node
app.post('/nodes/:nodeId/slots', (req, res) => {
    try {
        const node = redisService.getNode(req.params.nodeId);
        
        redisService.assignSlotRange(
            node.clusterId,
            req.params.nodeId,
            req.body.startSlot,
            req.body.endSlot
        );
        
        res.json({
            status: 'slots-assigned',
            nodeId: req.params.nodeId,
            startSlot: req.body.startSlot,
            endSlot: req.body.endSlot,
            slotCount: (req.body.endSlot - req.body.startSlot) + 1,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create replication config
app.post('/nodes/:nodeId/replication', (req, res) => {
    try {
        const config = redisService.createReplicationConfig(req.params.nodeId, req.body);
        
        res.status(201).json({
            status: 'configured',
            nodeId: req.params.nodeId,
            replicaof: config.replicaof,
            replicaPriority: config.replicaPriority,
            replBacklogSize: config.replBacklogSize,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get cluster topology
app.get('/clusters/:clusterId/topology', (req, res) => {
    try {
        const topology = redisService.getClusterTopology(req.params.clusterId);
        
        if (!topology) {
            return res.status(404).json({ error: 'Cluster not found' });
        }
        
        res.json({
            clusterId: req.params.clusterId,
            clusterName: topology.cluster.name,
            nodeCount: topology.nodes.length,
            version: topology.cluster.version,
            nodes: topology.nodes.map(n => ({
                nodeId: n.nodeId,
                role: n.role,
                address: `${n.host}:${n.port}`,
                status: n.status,
                connected: n.connected,
            })),
            slotMapping: topology.slotMapping.map(s => ({
                nodeId: s.nodeId,
                slotRange: `[${s.startSlot}..${s.endSlot}]`,
                slotCount: s.slotCount,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get cluster statistics
app.get('/clusters/:clusterId/stats', (req, res) => {
    try {
        const stats = redisService.getClusterStats(req.params.clusterId);
        
        if (!stats) {
            return res.status(404).json({ error: 'Cluster not found' });
        }
        
        res.json({
            clusterId: stats.clusterId,
            clusterName: stats.clusterName,
            version: stats.version,
            totalNodes: stats.totalNodes,
            masterNodes: stats.masterNodes,
            replicaNodes: stats.replicaNodes,
            connectedNodes: stats.connectedNodes,
            disconnectedNodes: stats.disconnectedNodes,
            totalSlots: stats.totalSlots,
            assignedSlots: stats.assignedSlots,
            slotsRemaining: stats.totalSlots - stats.assignedSlots,
            avgReplicationOffset: stats.avgReplicationOffset,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Redis Cluster Integration API] Listening on port ${PORT}`);
    console.log(`[Redis Cluster Integration API] POST /clusters - Create cluster`);
    console.log(`[Redis Cluster Integration API] POST /clusters/:id/join - Join node (idempotent)`);
    console.log(`[Redis Cluster Integration API] POST /nodes/:id/handshake - Record handshake`);
    console.log(`[Redis Cluster Integration API] GET /nodes/:id - Get node`);
    console.log(`[Redis Cluster Integration API] GET /clusters/:id/nodes - Query cluster nodes`);
    console.log(`[Redis Cluster Integration API] POST /nodes/:id/slots - Assign slot range`);
    console.log(`[Redis Cluster Integration API] POST /nodes/:id/replication - Configure replication`);
    console.log(`[Redis Cluster Integration API] GET /clusters/:id/topology - Get cluster topology`);
    console.log(`[Redis Cluster Integration API] GET /clusters/:id/stats - Get cluster statistics`);
});
