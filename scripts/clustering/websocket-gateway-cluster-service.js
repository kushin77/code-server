#!/usr/bin/env node
/**
 * @file        scripts/clustering/websocket-gateway-cluster-service.js
 * @module      clustering/websocket-gateway
 * @description 3-node WebSocket gateway cluster with immutable states and idempotent routing
 *
 * IaC Principles:
 * - Immutable: Node states frozen once registered
 * - Immutable: Routing tables frozen per version
 * - Idempotent: Same connection = same node assignment
 * - Versioned: Cluster state versions for audit trail
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class WebSocketGatewayClusterService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.clusterId = options.clusterId || 'ws-cluster-' + crypto.randomBytes(4).toString('hex');
        this.nodeCount = options.nodeCount || 3;
        
        // Immutable cluster nodes (frozen)
        this.nodes = new Map(); // nodeId → frozen node
        
        // Immutable routing table (frozen)
        this.routingTable = new Map(); // connectionId → frozen route
        
        // Connection token to route mapping (idempotency)
        this.connectionTokens = new Map(); // token → connectionId
        
        // Cluster state history (immutable versions)
        this.stateHistory = [];
        
        // Initialize cluster nodes
        this.initializeClusterNodes();
    }
    
    /**
     * Initialize cluster nodes (immutable)
     */
    initializeClusterNodes() {
        for (let i = 0; i < this.nodeCount; i++) {
            const nodeId = `ws-node-${i}`;
            const now = Date.now();
            
            const node = {
                // Identifiers (immutable)
                nodeId,
                clusterId: this.clusterId,
                nodeIndex: i,
                
                // Network info (immutable)
                host: process.env[`WS_NODE_${i}_HOST`] || `ws-node-${i}.cluster.local`,
                port: process.env[`WS_NODE_${i}_PORT`] || (9200 + i),
                protocol: 'ws',
                
                // Capacity (immutable)
                maxConnections: 10000,
                maxMessagesPerSecond: 50000,
                
                // Status (mutable)
                status: 'ready',
                currentConnections: 0,
                activeChannels: 0,
                
                // Metrics (immutable array)
                metrics: Object.freeze([]),
                
                // Timing (immutable)
                registeredAt: new Date().toISOString(),
                registeredAtMs: now,
                lastHealthCheckMs: now,
                
                // Version
                version: 1,
            };
            
            Object.freeze(node);
            this.nodes.set(nodeId, node);
        }
        
        this.recordClusterState('nodes_initialized');
        
        this.emit('cluster-initialized', {
            clusterId: this.clusterId,
            nodeCount: this.nodeCount,
            nodes: Array.from(this.nodes.keys()),
        });
    }

    /**
     * Resolve the routing key for a connection
     */
    getRoutingKey(connectionData, connectionToken) {
        return connectionData.sessionId || connectionToken || connectionData.connectionId;
    }

    /**
     * Select a node using consistent hashing
     */
    selectNodeByConsistentHash(availableNodes, routingKey) {
        const hashBuffer = crypto.createHash('sha256').update(String(routingKey || '')).digest();
        return availableNodes[hashBuffer.readUInt32BE(0) % availableNodes.length];
    }
    
    /**
     * Route connection to node (idempotent)
     */
    routeConnectionToNode(connectionData, connectionToken) {
        // Idempotency check
        if (connectionToken && this.connectionTokens.has(connectionToken)) {
            const connectionId = this.connectionTokens.get(connectionToken);
            const existingRoute = this.getRoute(connectionId);

            if (existingRoute && existingRoute.status === 'active') {
                return existingRoute;
            }

            this.connectionTokens.delete(connectionToken);
        }
        
        const connectionId = connectionData.connectionId || (
            connectionToken || connectionData.sessionId
                ? `conn-${String(connectionToken || connectionData.sessionId)}-${crypto.randomBytes(4).toString('hex')}`
                : null
        );
        if (!connectionId) {
            throw new Error('connectionId is required');
        }

        const routingKey = this.getRoutingKey(connectionData, connectionToken);

        // Find node using consistent hashing
        const availableNodes = Array.from(this.nodes.values())
            .filter(n => n.status === 'ready' && n.currentConnections < n.maxConnections)
            .sort((a, b) => a.nodeId.localeCompare(b.nodeId));
        
        if (availableNodes.length === 0) {
            throw new Error('No available WebSocket nodes');
        }
        
        const selectedNode = this.selectNodeByConsistentHash(availableNodes, routingKey);
        
        // Create immutable route
        const route = {
            // Identifiers (immutable)
            connectionId,
            nodeId: selectedNode.nodeId,
            
            // Connection details (immutable)
            userId: connectionData.userId,
            sessionId: connectionData.sessionId,
            workspaceId: connectionData.workspaceId,
            
            // Routing info (immutable)
            gateway: `${selectedNode.protocol}://${selectedNode.host}:${selectedNode.port}`,
            channel: connectionData.channel || 'default',
            
            // Timing (immutable)
            routedAt: new Date().toISOString(),
            routedAtMs: Date.now(),
            
            // Status (mutable)
            status: 'active',
            lastMessageAt: Date.now(),
            
            version: 1,
        };
        
        Object.freeze(route);
        this.routingTable.set(connectionId, route);
        
        if (connectionToken) {
            this.connectionTokens.set(connectionToken, connectionId);
        }
        
        // Update node (create new version)
        this.updateNodeConnections(selectedNode.nodeId, 1);
        
        this.recordClusterState('connection_routed');
        
        this.emit('connection-routed', {
            connectionId,
            nodeId: selectedNode.nodeId,
            gateway: route.gateway,
        });
        
        return route;
    }
    
    /**
     * Update node connections (creates new node version)
     */
    updateNodeConnections(nodeId, delta) {
        const currentNode = this.nodes.get(nodeId);
        if (!currentNode) throw new Error(`Node ${nodeId} not found`);
        
        const updated = {
            ...currentNode,
            currentConnections: Math.max(0, currentNode.currentConnections + delta),
            lastHealthCheckMs: Date.now(),
            version: currentNode.version + 1,
        };
        
        Object.freeze(updated);
        this.nodes.set(nodeId, updated);
    }
    
    /**
     * Record health check (creates new node version)
     */
    recordHealthCheck(nodeId, healthData) {
        const currentNode = this.nodes.get(nodeId);
        if (!currentNode) throw new Error(`Node ${nodeId} not found`);
        
        const now = Date.now();
        
        // Create immutable health metric
        const metric = Object.freeze({
            timestamp: now,
            latencyMs: healthData.latencyMs || 0,
            cpuPercent: healthData.cpuPercent || 0,
            memoryPercent: healthData.memoryPercent || 0,
            connectionCount: healthData.connectionCount || 0,
            messageRate: healthData.messageRate || 0,
        });
        
        const updated = {
            ...currentNode,
            status: healthData.healthy ? 'ready' : 'degraded',
            currentConnections: healthData.connectionCount || currentNode.currentConnections,
            metrics: Object.freeze([
                ...currentNode.metrics,
                metric,
            ].slice(-100)), // Keep last 100 metrics
            lastHealthCheckMs: now,
            version: currentNode.version + 1,
        };
        
        Object.freeze(updated);
        this.nodes.set(nodeId, updated);
        
        this.emit('health-check-recorded', {
            nodeId,
            status: updated.status,
            latencyMs: healthData.latencyMs,
            connectionCount: updated.currentConnections,
        });
    }
    
    /**
     * Disconnect connection (creates new route version)
     */
    disconnectConnection(connectionId) {
        const route = this.routingTable.get(connectionId);
        if (!route) throw new Error(`Route ${connectionId} not found`);
        
        // Update node
        this.updateNodeConnections(route.nodeId, -1);
        
        // Create new route version
        const updated = {
            ...route,
            status: 'disconnected',
            disconnectedAt: new Date().toISOString(),
            disconnectedAtMs: Date.now(),
            durationMs: Date.now() - route.routedAtMs,
            version: route.version + 1,
        };
        
        Object.freeze(updated);
        this.routingTable.set(connectionId, updated);

        for (const [token, mappedConnectionId] of this.connectionTokens.entries()) {
            if (mappedConnectionId === connectionId) {
                this.connectionTokens.delete(token);
            }
        }
        
        this.recordClusterState('connection_disconnected');
        
        this.emit('connection-disconnected', {
            connectionId,
            nodeId: route.nodeId,
            durationMs: updated.durationMs,
        });
    }
    
    /**
     * Get route (immutable snapshot)
     */
    getRoute(connectionId) {
        const route = this.routingTable.get(connectionId);
        return route ? Object.freeze({ ...route }) : null;
    }
    
    /**
     * Get node (immutable snapshot)
     */
    getNode(nodeId) {
        const node = this.nodes.get(nodeId);
        return node ? Object.freeze({ ...node }) : null;
    }
    
    /**
     * Query routes (immutable array)
     */
    queryRoutes(filters = {}) {
        let routes = Array.from(this.routingTable.values());
        
        if (filters.nodeId) {
            routes = routes.filter(r => r.nodeId === filters.nodeId);
        }
        
        if (filters.status) {
            routes = routes.filter(r => r.status === filters.status);
        }
        
        if (filters.userId) {
            routes = routes.filter(r => r.userId === filters.userId);
        }
        
        if (filters.workspaceId) {
            routes = routes.filter(r => r.workspaceId === filters.workspaceId);
        }
        
        routes.sort((a, b) => b.routedAtMs - a.routedAtMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            routes.slice(0, limit).map(r => Object.freeze(r))
        );
    }
    
    /**
     * Get cluster statistics (immutable)
     */
    getClusterStatistics() {
        const allNodes = Array.from(this.nodes.values());
        const allRoutes = Array.from(this.routingTable.values());
        
        const stats = {
            clusterId: this.clusterId,
            nodeCount: allNodes.length,
            totalConnections: allRoutes.filter(r => r.status === 'active').length,
            disconnectedConnections: allRoutes.filter(r => r.status === 'disconnected').length,
            totalRoutes: allRoutes.length,
            
            nodeStatuses: Object.freeze({
                ready: allNodes.filter(n => n.status === 'ready').length,
                degraded: allNodes.filter(n => n.status === 'degraded').length,
                offline: allNodes.filter(n => n.status === 'offline').length,
            }),
            
            nodeCapacity: Object.freeze({
                totalCapacity: allNodes.reduce((sum, n) => sum + n.maxConnections, 0),
                usedCapacity: allRoutes.filter(r => r.status === 'active').length,
                utilizationPercent: (
                    (allRoutes.filter(r => r.status === 'active').length /
                    allNodes.reduce((sum, n) => sum + n.maxConnections, 0)) * 100
                ).toFixed(2),
            }),
            
            avgConnectionDuration: this.calculateAvgConnectionDuration(allRoutes),
            totalMessageRate: allNodes.reduce((sum, n) => 
                sum + (n.metrics[n.metrics.length - 1]?.messageRate || 0), 0
            ),
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Calculate average connection duration
     */
    calculateAvgConnectionDuration(routes) {
        const disconnected = routes.filter(r => r.status === 'disconnected' && r.durationMs);
        if (disconnected.length === 0) return 0;
        
        const totalDuration = disconnected.reduce((sum, r) => sum + r.durationMs, 0);
        return Math.round(totalDuration / disconnected.length);
    }
    
    /**
     * Record cluster state (immutable)
     */
    recordClusterState(action) {
        const now = Date.now();
        const state = {
            timestamp: new Date().toISOString(),
            timestampMs: now,
            action,
            nodeStates: Object.freeze(
                Array.from(this.nodes.entries()).map(([id, node]) =>
                    Object.freeze({
                        nodeId: id,
                        status: node.status,
                        connections: node.currentConnections,
                        version: node.version,
                    })
                )
            ),
            routeCount: this.routingTable.size,
            version: this.stateHistory.length + 1,
        };
        
        Object.freeze(state);
        this.stateHistory.push(state);
    }
}

module.exports = WebSocketGatewayClusterService;
