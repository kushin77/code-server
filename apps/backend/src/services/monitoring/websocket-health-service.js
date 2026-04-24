#!/usr/bin/env node
// @file        apps/backend/src/services/monitoring/websocket-health-service.ts
// @module      services/monitoring
// @description Service for monitoring WebSocket connection health with quality scoring
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
const logger = getLogger('WebSocketHealthService');
/**
 * WebSocket Health Service
 * Monitors connection health with quality scoring and automatic reconnection
 */
class WebSocketHealthService extends EventEmitter {
    constructor() {
        super();
        this.connections = new Map();
        this.metricsHistory = new Map();
        this.connectionsByUser = new Map();
        this.MAX_METRICS_HISTORY = 100;
        this.QUALITY_THRESHOLD_GOOD = 75;
        this.QUALITY_THRESHOLD_DEGRADED = 50;
    }
    static getInstance() {
        if (!WebSocketHealthService.instance) {
            WebSocketHealthService.instance = new WebSocketHealthService();
        }
        return WebSocketHealthService.instance;
    }
    /**
     * Reset all state (for testing)
     */
    reset() {
        this.connections.clear();
        this.metricsHistory.clear();
        this.connectionsByUser.clear();
    }
    /**
     * Register a new WebSocket connection
     */
    registerConnection(connectionId, type, userId, workspaceId) {
        const health = {
            connectionId,
            type,
            userId,
            workspaceId,
            connected: true,
            qualityScore: 100,
            latency: 0,
            jitter: 0,
            packetLoss: 0,
            lastPingTime: Date.now(),
            lastPongTime: Date.now(),
            lastQualityUpdate: Date.now(),
            reconnectAttempts: 0,
            createdAt: Date.now(),
            metrics: [],
        };
        this.connections.set(connectionId, health);
        // Track connections per user
        if (!this.connectionsByUser.has(userId)) {
            this.connectionsByUser.set(userId, []);
        }
        this.connectionsByUser.get(userId).push(connectionId);
        this.emit('connectionRegistered', health);
        logger.info(`WebSocket connection registered: ${connectionId} (${type}) for user ${userId}`);
        return health;
    }
    /**
     * Record ping sent
     */
    recordPingSent(connectionId) {
        const health = this.connections.get(connectionId);
        if (!health)
            return undefined;
        health.lastPingTime = Date.now();
        return health;
    }
    /**
     * Record pong received and update latency
     */
    recordPongReceived(connectionId) {
        const health = this.connections.get(connectionId);
        if (!health)
            return undefined;
        const latency = Date.now() - health.lastPingTime;
        health.lastPongTime = Date.now();
        health.latency = latency;
        // Calculate jitter (simplified: deviation from previous latency)
        if (health.metrics.length > 0) {
            const previousLatency = health.metrics[health.metrics.length - 1].latency;
            health.jitter = Math.abs(latency - previousLatency);
        }
        this.updateQualityScore(connectionId);
        return health;
    }
    /**
     * Record packet loss
     */
    recordPacketLoss(connectionId, lossPercentage) {
        const health = this.connections.get(connectionId);
        if (!health)
            return undefined;
        health.packetLoss = Math.max(0, Math.min(100, lossPercentage));
        this.updateQualityScore(connectionId);
        return health;
    }
    /**
     * Update quality score based on latency, jitter, and packet loss
     */
    updateQualityScore(connectionId) {
        const health = this.connections.get(connectionId);
        if (!health)
            return;
        // Quality score calculation:
        // Base 100 - deductions for latency, jitter, packet loss
        let score = 100;
        // Latency: < 50 ms = 100, linear degradation to 0 at 500 ms
        if (health.latency > 50) {
            const latencyPenalty = ((health.latency - 50) / 450) * 50; // Max 50 point penalty
            score -= Math.min(50, latencyPenalty);
        }
        // Jitter: < 10 ms = 0 penalty, max 20 point penalty at 100 ms jitter
        if (health.jitter > 10) {
            const jitterPenalty = ((health.jitter - 10) / 90) * 20; // Max 20 point penalty
            score -= Math.min(20, jitterPenalty);
        }
        // Packet loss: 1% = -10 points, 10% = -50+ points
        if (health.packetLoss > 0) {
            const lossPercentage = health.packetLoss;
            const lossPenalty = lossPercentage * 0.65; // Max ~65 point penalty at 100% loss
            score -= Math.min(65, lossPenalty);
        }
        health.qualityScore = Math.max(0, Math.min(100, score));
        health.lastQualityUpdate = Date.now();
        // Record metric
        const metric = {
            latency: health.latency,
            jitter: health.jitter,
            packetLoss: health.packetLoss,
            timestamp: Date.now(),
        };
        health.metrics.push(metric);
        if (health.metrics.length > this.MAX_METRICS_HISTORY) {
            health.metrics.shift();
        }
        // Emit events based on quality thresholds
        if (health.qualityScore < this.QUALITY_THRESHOLD_DEGRADED) {
            this.emit('connectionDegraded', health);
        }
        else if (health.qualityScore >= this.QUALITY_THRESHOLD_GOOD) {
            this.emit('connectionHealthy', health);
        }
    }
    /**
     * Mark connection as disconnected
     */
    markDisconnected(connectionId) {
        const health = this.connections.get(connectionId);
        if (!health)
            return undefined;
        health.connected = false;
        this.emit('connectionDisconnected', health);
        logger.info(`WebSocket connection disconnected: ${connectionId}`);
        return health;
    }
    /**
     * Attempt reconnection
     */
    attemptReconnection(connectionId) {
        const health = this.connections.get(connectionId);
        if (!health)
            return undefined;
        health.reconnectAttempts++;
        health.lastReconnectTime = Date.now();
        // Exponential backoff: 2^n seconds, max 30 seconds
        const backoffSeconds = Math.min(30, Math.pow(2, Math.max(0, health.reconnectAttempts - 1)));
        this.emit('reconnectionAttempted', {
            connection: health,
            backoffSeconds,
            attemptNumber: health.reconnectAttempts,
        });
        logger.info(`Reconnection attempt ${health.reconnectAttempts} for ${connectionId}, backoff: ${backoffSeconds}s`);
        return health;
    }
    /**
     * Reconnection successful
     */
    reconnectionSuccessful(connectionId) {
        const health = this.connections.get(connectionId);
        if (!health)
            return undefined;
        health.connected = true;
        health.reconnectAttempts = 0;
        health.qualityScore = 100;
        this.emit('reconnectionSuccessful', health);
        logger.info(`WebSocket connection reconnected successfully: ${connectionId}`);
        return health;
    }
    /**
     * Get connection health
     */
    getConnection(connectionId) {
        return this.connections.get(connectionId);
    }
    /**
     * Get all connections for a user
     */
    getConnectionsForUser(userId) {
        const connectionIds = this.connectionsByUser.get(userId) || [];
        return connectionIds
            .map((id) => this.connections.get(id))
            .filter((conn) => conn);
    }
    /**
     * Get connections by type
     */
    getConnectionsByType(type) {
        return Array.from(this.connections.values()).filter((c) => c.type === type);
    }
    /**
     * Get degraded connections (quality < threshold)
     */
    getDegradedConnections(workspaceId) {
        return Array.from(this.connections.values()).filter((c) => {
            const qualityMatch = c.qualityScore < this.QUALITY_THRESHOLD_DEGRADED;
            const workspaceMatch = !workspaceId || c.workspaceId === workspaceId;
            return qualityMatch && workspaceMatch && c.connected;
        });
    }
    /**
     * Get average quality score for workspace
     */
    getAverageQuality(workspaceId) {
        const connections = workspaceId
            ? Array.from(this.connections.values()).filter((c) => c.workspaceId === workspaceId && c.connected)
            : Array.from(this.connections.values()).filter((c) => c.connected);
        if (connections.length === 0)
            return 100;
        const totalScore = connections.reduce((sum, c) => sum + c.qualityScore, 0);
        return totalScore / connections.length;
    }
    /**
     * Get workspace health statistics
     */
    getWorkspaceStats(workspaceId) {
        const connections = Array.from(this.connections.values()).filter((c) => c.workspaceId === workspaceId);
        const connected = connections.filter((c) => c.connected);
        const degraded = connections.filter((c) => c.qualityScore < this.QUALITY_THRESHOLD_DEGRADED && c.connected);
        const byType = {
            collaboration: 0,
            presence: 0,
            'voice-signaling': 0,
            'session-broker': 0,
        };
        connections.forEach((c) => {
            byType[c.type]++;
        });
        return {
            totalConnections: connections.length,
            connectedCount: connected.length,
            disconnectedCount: connections.length - connected.length,
            averageQuality: this.getAverageQuality(workspaceId),
            degradedCount: degraded.length,
            connectionsByType: byType,
        };
    }
    /**
     * Unregister connection (cleanup)
     */
    unregisterConnection(connectionId) {
        const health = this.connections.get(connectionId);
        if (!health)
            return;
        // Remove from user's connections
        const userConnections = this.connectionsByUser.get(health.userId);
        if (userConnections) {
            const index = userConnections.indexOf(connectionId);
            if (index > -1) {
                userConnections.splice(index, 1);
            }
        }
        this.connections.delete(connectionId);
        this.metricsHistory.delete(connectionId);
        this.emit('connectionUnregistered', health);
        logger.info(`WebSocket connection unregistered: ${connectionId}`);
    }
    /**
     * Get system-wide health summary
     */
    getSystemHealth() {
        const connections = Array.from(this.connections.values());
        const active = connections.filter((c) => c.connected);
        const degraded = connections.filter((c) => c.qualityScore < this.QUALITY_THRESHOLD_DEGRADED && c.connected);
        const reconnecting = connections.filter((c) => c.reconnectAttempts > 0);
        const totalScore = active.length > 0 ? active.reduce((sum, c) => sum + c.qualityScore, 0) / active.length : 100;
        return {
            totalConnections: connections.length,
            activeConnections: active.length,
            systemQuality: totalScore,
            degradedConnections: degraded.length,
            reconnectingConnections: reconnecting.length,
        };
    }
}
const instance = new WebSocketHealthService();
export default instance;
export { WebSocketHealthService };
//# sourceMappingURL=websocket-health-service.js.map