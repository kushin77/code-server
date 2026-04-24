#!/usr/bin/env node
/**
 * @file        scripts/integrations/redis-cluster-immutable-service.js
 * @module      integrations/redis
 * @description Redis cluster management with immutable configs and idempotent joins
 *
 * IaC Principles:
 * - Immutable: Cluster topology frozen once created
 * - Immutable: Node configurations frozen
 * - Idempotent: Same joinToken = same node joins cluster
 * - Versioned: Cluster versions for rollback
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class RedisClusterService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.baseUrl = options.baseUrl || process.env.REDIS_CLUSTER_URL || 'redis://localhost:6379';
        
        // Immutable cluster config (frozen)
        this.clusters = new Map(); // clusterId → frozen cluster
        
        // Immutable nodes (frozen)
        this.nodes = new Map(); // nodeId → frozen node
        
        // Token to nodeId mapping (idempotency)
        this.joinTokens = new Map(); // token → nodeId
        
        // Immutable slots mapping (frozen)
        this.slotMappings = new Map(); // clusterId → frozen slots array
        
        // Immutable replication config (frozen)
        this.replicationConfigs = new Map(); // nodeId → frozen config
        
        // Join history
        this.joinHistory = [];
    }
    
    /**
     * Create cluster (immutable)
     */
    createCluster(clusterData) {
        const clusterId = `cluster-${crypto.randomBytes(8).toString('hex')}`;
        
        const cluster = {
            // Identifiers (immutable)
            clusterId,
            name: clusterData.name,
            
            // Topology (immutable)
            nodeCount: clusterData.nodeCount || 3,
            replicationFactor: clusterData.replicationFactor || 1,
            
            // Configuration (immutable)
            timeout: clusterData.timeout || '5000',
            replConf: Object.freeze(clusterData.replConf || {}),
            
            // Slot distribution (immutable)
            totalSlots: 16384,
            slotsPerNode: 16384 / (clusterData.nodeCount || 3),
            
            // Settings (immutable)
            requirePass: clusterData.requirePass || null,
            masterAuth: clusterData.masterAuth || null,
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            // Status (mutable)
            enabled: true,
            initialized: false,
            memberCount: 0,
            
            version: 1,
        };
        
        Object.freeze(cluster);
        this.clusters.set(clusterId, cluster);
        
        this.emit('cluster-created', {
            clusterId,
            name: cluster.name,
            nodeCount: cluster.nodeCount,
        });
        
        return clusterId;
    }
    
    /**
     * Join node to cluster (idempotent)
     */
    joinCluster(clusterId, nodeData, joinToken) {
        // Idempotency check
        if (joinToken && this.joinTokens.has(joinToken)) {
            return this.joinTokens.get(joinToken);
        }
        
        const cluster = this.clusters.get(clusterId);
        if (!cluster) throw new Error(`Cluster ${clusterId} not found`);
        
        const nodeId = `node-${crypto.randomBytes(8).toString('hex')}`;
        
        const node = {
            // Identifiers (immutable)
            nodeId,
            clusterId,
            role: nodeData.role || 'replica',  // master, replica
            
            // Network (immutable)
            host: nodeData.host,
            port: nodeData.port,
            clusterPort: nodeData.clusterPort || (nodeData.port + 10000),
            
            // Identity (immutable)
            nodeName: nodeData.nodeName || `${nodeData.host}:${nodeData.port}`,
            
            // Configuration (immutable)
            slaveof: nodeData.slaveof || null,  // master node ID
            replicationOffset: 0,
            
            // Health (immutable config)
            heartbeatInterval: nodeData.heartbeatInterval || '1000',
            failoverTimeout: nodeData.failoverTimeout || '15000',
            
            // Timing (immutable)
            joinedAt: new Date().toISOString(),
            joinedAtMs: Date.now(),
            lastHeartbeat: new Date().toISOString(),
            
            // Status (mutable)
            status: 'handshaking',  // handshaking, connected, disconnected
            connected: false,
            lastError: null,
            
            version: 1,
        };
        
        Object.freeze(node);
        this.nodes.set(nodeId, node);
        
        if (joinToken) {
            this.joinTokens.set(joinToken, nodeId);
        }
        
        this.recordJoinHistory(nodeId, 'joined');
        
        this.emit('node-joined', {
            nodeId,
            clusterId,
            role: node.role,
            address: `${node.host}:${node.port}`,
        });
        
        return nodeId;
    }
    
    /**
     * Record node handshake (creates new version)
     */
    recordHandshake(nodeId, handshakeData) {
        const node = this.nodes.get(nodeId);
        if (!node) throw new Error(`Node ${nodeId} not found`);
        
        const updated = {
            ...node,
            status: 'connected',
            connected: true,
            lastHeartbeat: new Date().toISOString(),
            replicationOffset: handshakeData.replicationOffset || 0,
            version: node.version + 1,
        };
        
        Object.freeze(updated);
        this.nodes.set(nodeId, updated);
        
        this.emit('handshake-complete', {
            nodeId,
            clusterId: node.clusterId,
            status: updated.status,
        });
    }
    
    /**
     * Assign slot range to node (immutable)
     */
    assignSlotRange(clusterId, nodeId, startSlot, endSlot) {
        const cluster = this.clusters.get(clusterId);
        if (!cluster) throw new Error(`Cluster ${clusterId} not found`);
        
        const node = this.nodes.get(nodeId);
        if (!node) throw new Error(`Node ${nodeId} not found`);
        
        // Get or create slot mapping
        let mapping = this.slotMappings.get(clusterId);
        if (!mapping) {
            mapping = [];
        }
        
        // Create new immutable slot assignment
        const slotAssignment = Object.freeze({
            nodeId,
            startSlot,
            endSlot,
            slotCount: (endSlot - startSlot) + 1,
            assignedAt: new Date().toISOString(),
            assignedAtMs: Date.now(),
        });
        
        // Create new immutable array with assignment
        const updatedMapping = [...mapping, slotAssignment];
        Object.freeze(updatedMapping);
        
        this.slotMappings.set(clusterId, updatedMapping);
        
        this.emit('slots-assigned', {
            nodeId,
            clusterId,
            startSlot,
            endSlot,
            slotCount: slotAssignment.slotCount,
        });
    }
    
    /**
     * Create replication config (immutable)
     */
    createReplicationConfig(nodeId, configData) {
        const node = this.nodes.get(nodeId);
        if (!node) throw new Error(`Node ${nodeId} not found`);
        
        const config = {
            // Identifiers (immutable)
            nodeId,
            
            // Replication (immutable)
            replicaof: configData.replicaof || null,  // master address
            replicaPriority: configData.replicaPriority || 100,
            
            // Sync settings (immutable)
            replDisklessSyncDelay: configData.replDisklessSyncDelay || 5,
            replTimeout: configData.replTimeout || 60,
            
            // Backlog (immutable)
            replBacklogSize: configData.replBacklogSize || '67108864',  // 64MB
            replBacklogTtl: configData.replBacklogTtl || '3600',  // 1 hour
            
            // Behavior (immutable)
            minReplicasToWrite: configData.minReplicasToWrite || 0,
            minReplicasMaxLag: configData.minReplicasMaxLag || 10,
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            version: 1,
        };
        
        Object.freeze(config);
        this.replicationConfigs.set(nodeId, config);
        
        this.emit('replication-configured', {
            nodeId,
            replicaof: config.replicaof,
            priority: config.replicaPriority,
        });
        
        return config;
    }
    
    /**
     * Get cluster topology (immutable snapshot)
     */
    getClusterTopology(clusterId) {
        const cluster = this.clusters.get(clusterId);
        if (!cluster) return null;
        
        const clusterNodes = Array.from(this.nodes.values()).filter(n => n.clusterId === clusterId);
        
        const topology = {
            cluster: Object.freeze({ ...cluster }),
            nodes: Object.freeze(
                clusterNodes.map(n => Object.freeze(n))
            ),
            slotMapping: this.slotMappings.get(clusterId) || [],
        };
        
        return Object.freeze(topology);
    }
    
    /**
     * Get node (immutable snapshot)
     */
    getNode(nodeId) {
        const node = this.nodes.get(nodeId);
        return node ? Object.freeze({ ...node }) : null;
    }
    
    /**
     * Query nodes by cluster (immutable array)
     */
    queryNodesByCluster(clusterId, filters = {}) {
        let nodes = Array.from(this.nodes.values())
            .filter(n => n.clusterId === clusterId);
        
        if (filters.role) {
            nodes = nodes.filter(n => n.role === filters.role);
        }
        
        if (filters.status) {
            nodes = nodes.filter(n => n.status === filters.status);
        }
        
        nodes.sort((a, b) => b.joinedAtMs - a.joinedAtMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            nodes.slice(0, limit).map(n => Object.freeze(n))
        );
    }
    
    /**
     * Get cluster statistics (immutable)
     */
    getClusterStats(clusterId) {
        const cluster = this.clusters.get(clusterId);
        if (!cluster) return null;
        
        const clusterNodes = Array.from(this.nodes.values())
            .filter(n => n.clusterId === clusterId);
        
        const stats = {
            clusterId,
            clusterName: cluster.name,
            version: cluster.version,
            
            totalNodes: clusterNodes.length,
            masterNodes: clusterNodes.filter(n => n.role === 'master').length,
            replicaNodes: clusterNodes.filter(n => n.role === 'replica').length,
            
            connectedNodes: clusterNodes.filter(n => n.connected).length,
            disconnectedNodes: clusterNodes.filter(n => !n.connected).length,
            
            totalSlots: cluster.totalSlots,
            assignedSlots: this.slotMappings.get(clusterId)
                ? this.slotMappings.get(clusterId).reduce((sum, s) => sum + s.slotCount, 0)
                : 0,
            
            avgReplicationOffset: clusterNodes.length > 0
                ? (clusterNodes.reduce((sum, n) => sum + (n.replicationOffset || 0), 0) / clusterNodes.length).toFixed(0)
                : 0,
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Record join history
     */
    recordJoinHistory(nodeId, action) {
        const node = this.nodes.get(nodeId);
        
        const record = Object.freeze({
            timestamp: new Date().toISOString(),
            timestampMs: Date.now(),
            action,
            nodeId,
            clusterId: node.clusterId,
            role: node.role,
            status: node.status,
        });
        
        this.joinHistory.push(record);
    }
}

module.exports = RedisClusterService;
