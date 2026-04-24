#!/usr/bin/env node
/**
 * @file        scripts/observability/websocket-health-service.js
 * @module      observability/websocket
 * @description WebSocket connection health monitoring with immutable connection states
 *
 * IaC Principles:
 * - Immutable: Connection snapshots frozen once recorded
 * - Immutable: Health checks frozen once completed
 * - Idempotent: Same connection window = same health score
 * - Versioned: Connection state versions for auditing
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class WebSocketHealthService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.serviceName = options.serviceName || 'code-server';
        this.healthCheckIntervalMs = options.healthCheckIntervalMs || 30000; // 30s
        
        // Immutable connection states (frozen)
        this.connections = new Map(); // connectionId → frozen connection
        
        // Health checks (frozen)
        this.healthChecks = new Map(); // healthCheckId → frozen check
        
        // Connection metrics (rolling window)
        this.metrics = new Map(); // connectionId → metrics history
        
        // Token-based idempotency
        this.checkTokens = new Map(); // token → healthCheckId
    }
    
    /**
     * Register WebSocket connection (immutable)
     */
    registerConnection(connectionData) {
        const connectionId = `ws-${crypto.randomBytes(8).toString('hex')}`;
        
        const connection = {
            // Identifiers (immutable)
            connectionId,
            clientId: connectionData.clientId,
            userId: connectionData.userId,
            workspaceId: connectionData.workspaceId,
            
            // Connection info (immutable)
            remoteAddress: connectionData.remoteAddress,
            userAgent: connectionData.userAgent,
            
            // Timing (immutable)
            connectedAt: Date.now(),
            connectedAtIso: new Date().toISOString(),
            lastHeartbeat: Date.now(),
            
            // Status (mutable during connection, frozen after close)
            status: 'connected',  // connected, degraded, disconnected
            
            // Health (immutable snapshots)
            health: {
                latency: 0,
                jitter: 0,
                packetLoss: 0,
                score: 100,
            },
            
            // Metrics (immutable array)
            metricsHistory: [],
            
            // Message counts (immutable)
            messageCounts: Object.freeze({
                sent: 0,
                received: 0,
                errors: 0,
            }),
            
            // Reconnect info (immutable)
            reconnectCount: 0,
            lastReconnect: null,
            
            version: 1,
        };
        
        // Initialize metrics history
        this.metrics.set(connectionId, []);
        
        // Freeze connection
        Object.freeze(connection);
        this.connections.set(connectionId, connection);
        
        this.emit('connection-registered', {
            connectionId,
            userId: connection.userId,
            workspaceId: connection.workspaceId,
        });
        
        return connectionId;
    }
    
    /**
     * Record heartbeat (updates connection version)
     */
    recordHeartbeat(connectionId, latency) {
        const connection = this.connections.get(connectionId);
        if (!connection) throw new Error(`Connection ${connectionId} not found`);
        
        const now = Date.now();
        
        // Record metric
        const metricsHistory = this.metrics.get(connectionId) || [];
        metricsHistory.push({ latency, timestamp: now });
        // Keep rolling window (last 1000 heartbeats)
        this.metrics.set(connectionId, metricsHistory.slice(-1000));
        
        // Update connection (new version)
        const updatedConnection = {
            ...connection,
            lastHeartbeat: now,
            health: Object.freeze({
                latency,
                jitter: this.calculateJitter(metricsHistory),
                packetLoss: 0,
                score: this.calculateHealthScore(latency, metricsHistory),
            }),
            version: connection.version + 1,
        };
        
        Object.freeze(updatedConnection);
        this.connections.set(connectionId, updatedConnection);
        
        return updatedConnection;
    }
    
    /**
     * Calculate jitter (standard deviation of latencies)
     */
    calculateJitter(history) {
        if (history.length < 2) return 0;
        
        const latencies = history.slice(-100).map(m => m.latency);
        const mean = latencies.reduce((a, b) => a + b, 0) / latencies.length;
        const variance = latencies.reduce((sum, lat) => sum + Math.pow(lat - mean, 2), 0) / latencies.length;
        
        return Math.sqrt(variance);
    }
    
    /**
     * Calculate health score
     */
    calculateHealthScore(currentLatency, history) {
        // Score based on latency percentile
        if (history.length === 0) return 100;
        
        const latencies = history.slice(-100).map(m => m.latency).sort((a, b) => a - b);
        const p99 = latencies[Math.floor(latencies.length * 0.99)];
        
        // Scoring: 100 at 0ms, 90 at 100ms, 50 at 500ms, 0 at 1000ms+
        let score = 100;
        if (currentLatency > 1000) {
            score = 0;
        } else if (currentLatency > 500) {
            score = 50 - ((currentLatency - 500) / 500) * 50;
        } else if (currentLatency > 100) {
            score = 90 - ((currentLatency - 100) / 400) * 40;
        } else if (currentLatency > 0) {
            score = 100 - (currentLatency / 100) * 10;
        }
        
        return Math.max(0, Math.min(100, score));
    }
    
    /**
     * Perform health check (idempotent)
     */
    performHealthCheck(connectionId, checkToken) {
        // Check idempotency
        if (this.checkTokens.has(checkToken)) {
            return this.checkTokens.get(checkToken);
        }
        
        const connection = this.connections.get(connectionId);
        if (!connection) throw new Error(`Connection ${connectionId} not found`);
        
        const now = Date.now();
        const timeSinceHeartbeat = now - connection.lastHeartbeat;
        
        // Determine status
        let status = 'connected';
        if (timeSinceHeartbeat > 60000) {  // 60s
            status = 'disconnected';
        } else if (timeSinceHeartbeat > 30000) {  // 30s
            status = 'degraded';
        }
        
        const healthCheckId = `health-${crypto.randomBytes(8).toString('hex')}`;
        
        // Create immutable health check
        const healthCheck = {
            // Identifiers (immutable)
            healthCheckId,
            connectionId,
            userId: connection.userId,
            workspaceId: connection.workspaceId,
            
            // Check time (immutable)
            checkedAt: new Date().toISOString(),
            timestamp: now,
            
            // Connection health (immutable)
            connectionStatus: status,
            latency: connection.health.latency,
            jitter: connection.health.jitter,
            healthScore: connection.health.score,
            
            // Metrics (immutable)
            timeSinceHeartbeat: timeSinceHeartbeat,
            connectionDuration: now - connection.connectedAt,
            
            // Assessment (immutable)
            healthy: connection.health.score >= 70,
            recommendation: this.generateRecommendation(status, connection.health.score),
            
            version: 1,
        };
        
        // Freeze health check
        Object.freeze(healthCheck);
        this.healthChecks.set(healthCheckId, healthCheck);
        
        // Store token
        this.checkTokens.set(checkToken, healthCheckId);
        
        this.emit('health-check-completed', {
            healthCheckId,
            connectionId,
            status,
            score: connection.health.score,
        });
        
        return healthCheckId;
    }
    
    /**
     * Generate recommendation
     */
    generateRecommendation(status, score) {
        if (status === 'disconnected') {
            return 'Connection lost. Immediate reconnection required.';
        } else if (status === 'degraded') {
            return 'Connection degraded. Monitor and consider graceful reconnection.';
        } else if (score < 70) {
            return 'Health score below threshold. Investigate latency or packet loss.';
        } else if (score < 85) {
            return 'Connection health acceptable but not optimal. Monitor.';
        }
        return 'Connection health is good.';
    }
    
    /**
     * Get connection state (immutable snapshot)
     */
    getConnectionState(connectionId) {
        const connection = this.connections.get(connectionId);
        return connection ? Object.freeze({ ...connection }) : null;
    }
    
    /**
     * Get health check (immutable snapshot)
     */
    getHealthCheck(healthCheckId) {
        const check = this.healthChecks.get(healthCheckId);
        return check ? Object.freeze({ ...check }) : null;
    }
    
    /**
     * Query connections (immutable array)
     */
    queryConnections(filters = {}) {
        const connections = Array.from(this.connections.values());
        
        let filtered = connections;
        
        // Filter by status
        if (filters.status) {
            filtered = filtered.filter(c => c.status === filters.status);
        }
        
        // Filter by health threshold
        if (filters.minHealthScore) {
            filtered = filtered.filter(c => c.health.score >= filters.minHealthScore);
        }
        
        // Filter by user
        if (filters.userId) {
            filtered = filtered.filter(c => c.userId === filters.userId);
        }
        
        // Filter by workspace
        if (filters.workspaceId) {
            filtered = filtered.filter(c => c.workspaceId === filters.workspaceId);
        }
        
        // Sort by health score (descending)
        filtered.sort((a, b) => b.health.score - a.health.score);
        
        // Limit results
        const limit = filters.limit || 100;
        return Object.freeze(
            filtered.slice(0, limit).map(c => Object.freeze(c))
        );
    }
    
    /**
     * Get health statistics (immutable snapshot)
     */
    getHealthStatistics() {
        const allConnections = Array.from(this.connections.values());
        
        const stats = {
            totalConnections: allConnections.length,
            byStatus: {
                connected: allConnections.filter(c => c.status === 'connected').length,
                degraded: allConnections.filter(c => c.status === 'degraded').length,
                disconnected: allConnections.filter(c => c.status === 'disconnected').length,
            },
            averageHealthScore: allConnections.length > 0
                ? (allConnections.reduce((sum, c) => sum + c.health.score, 0) / allConnections.length)
                : 0,
            healthyConnections: allConnections.filter(c => c.health.score >= 70).length,
            medianLatency: this.calculateMedianLatency(allConnections),
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Calculate median latency
     */
    calculateMedianLatency(connections) {
        const latencies = connections.map(c => c.health.latency).sort((a, b) => a - b);
        if (latencies.length === 0) return 0;
        return latencies[Math.floor(latencies.length / 2)];
    }
    
    /**
     * Close connection (creates new version)
     */
    closeConnection(connectionId) {
        const connection = this.connections.get(connectionId);
        if (!connection) throw new Error(`Connection ${connectionId} not found`);
        
        const closedConnection = {
            ...connection,
            status: 'disconnected',
            disconnectedAt: Date.now(),
            disconnectedAtIso: new Date().toISOString(),
            version: connection.version + 1,
        };
        
        Object.freeze(closedConnection);
        this.connections.set(connectionId, closedConnection);
        
        this.emit('connection-closed', {
            connectionId,
            duration: closedConnection.disconnectedAt - connection.connectedAt,
        });
        
        return closedConnection;
    }
}

module.exports = WebSocketHealthService;
