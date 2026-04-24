/**
 * WebSocket connection health monitoring engine.
 * Tracks real-time connection state, latency, and reliability.
 */
export const DEFAULT_HEALTH_CONFIG = {
    enabled: true,
    healthCheckIntervalMs: 10 * 1000, // 10 seconds
    latencyCheckIntervalMs: 5 * 1000, // 5 seconds
    aggregationWindowMs: 60 * 1000, // 1 minute
    retentionMs: 24 * 60 * 60 * 1000, // 24 hours
    latencyWarningMs: 150,
    latencyCriticalMs: 500,
    staleConnectionThresholdMs: 30 * 1000, // 30 seconds no messages
    messageLossThresholdPercent: 5, // 5% loss is critical
    maxReconnectionAttempts: 5,
    targetDeliverySuccessRate: 99.5,
};
export class WebSocketHealthEngine {
    constructor(config = {}) {
        this.connections = new Map();
        this.latencyMeasurements = new Map();
        this.connectionEvents = [];
        this.healthIssues = new Map();
        this.cleanupInterval = null;
        this.healthCheckInterval = null;
        this.config = { ...DEFAULT_HEALTH_CONFIG, ...config };
        this.startCleanupInterval();
        this.startHealthCheckInterval();
    }
    /**
     * Register a new WebSocket connection
     */
    registerConnection(connectionId, sessionId, userId) {
        const now = Date.now();
        const metrics = {
            connectionId,
            sessionId,
            userId,
            state: 'connecting',
            connectedAt: now,
            lastHeartbeatAt: now,
            latencyMs: 0,
            averageLatencyMs: 0,
            p95LatencyMs: 0,
            maxLatencyMs: 0,
            minLatencyMs: Infinity,
            messagesSent: 0,
            messagesReceived: 0,
            messagesLost: 0,
            deliverySuccessRate: 100,
            reconnectionAttempts: 0,
            reconnectionFailures: 0,
            uptimePercent: 100,
            isHealthy: true,
            healthScore: 100,
        };
        this.connections.set(connectionId, metrics);
        this.latencyMeasurements.set(connectionId, []);
        this.healthIssues.set(connectionId, []);
        this.recordEvent({
            type: 'connected',
            connectionId,
            sessionId,
            userId,
            timestamp: now,
        });
        return metrics;
    }
    /**
     * Update connection state
     */
    updateConnectionState(connectionId, state) {
        const conn = this.connections.get(connectionId);
        if (!conn)
            return;
        const oldState = conn.state;
        conn.state = state;
        if (state === 'reconnecting') {
            conn.reconnectionAttempts++;
        }
        this.calculateHealthScore(conn);
        this.recordEvent({
            type: state === 'connected'
                ? 'connected'
                : state === 'disconnected'
                    ? 'disconnected'
                    : 'reconnecting',
            connectionId,
            sessionId: conn.sessionId,
            userId: conn.userId,
            timestamp: Date.now(),
        });
    }
    /**
     * Record a latency measurement
     */
    recordLatency(connectionId, latencyMs) {
        const conn = this.connections.get(connectionId);
        if (!conn) {
            throw new Error(`Connection ${connectionId} not found`);
        }
        const now = Date.now();
        const measurement = {
            id: `latency-${connectionId}-${now}`,
            connectionId,
            startTime: now - latencyMs,
            endTime: now,
            latencyMs,
            sequenceNumber: conn.messagesSent + conn.messagesReceived,
            successful: true,
        };
        // Update connection metrics
        conn.latencyMs = latencyMs;
        conn.lastHeartbeatAt = now;
        conn.messagesSent++;
        // Track latency history
        const measurements = this.latencyMeasurements.get(connectionId) || [];
        measurements.push(measurement);
        this.latencyMeasurements.set(connectionId, measurements);
        // Update percentiles
        this.updateLatencyStats(conn, measurements);
        // Check for latency spikes
        this.checkLatencyHealth(conn);
        this.calculateHealthScore(conn);
        return measurement;
    }
    /**
     * Record a message reception
     */
    recordMessageReceived(connectionId) {
        const conn = this.connections.get(connectionId);
        if (!conn)
            return;
        conn.messagesReceived++;
        conn.lastHeartbeatAt = Date.now();
        this.updateDeliveryRate(conn);
        this.calculateHealthScore(conn);
    }
    /**
     * Record a message loss
     */
    recordMessageLoss(connectionId, count = 1) {
        const conn = this.connections.get(connectionId);
        if (!conn)
            return;
        conn.messagesLost += count;
        this.updateDeliveryRate(conn);
        this.checkMessageLossHealth(conn);
        this.calculateHealthScore(conn);
    }
    /**
     * Record a reconnection failure
     */
    recordReconnectionFailure(connectionId) {
        const conn = this.connections.get(connectionId);
        if (!conn)
            return;
        conn.reconnectionAttempts++;
        conn.reconnectionFailures++;
        conn.state = 'disconnected';
        if (conn.reconnectionAttempts >= this.config.maxReconnectionAttempts) {
            this.addHealthIssue(connectionId, {
                type: 'frequent_reconnects',
                severity: 'critical',
                message: `Connection exceeded max reconnection attempts (${conn.reconnectionAttempts})`,
                detectedAt: Date.now(),
            });
            conn.isHealthy = false;
        }
        this.calculateHealthScore(conn);
    }
    /**
     * Close a connection
     */
    closeConnection(connectionId, error) {
        const conn = this.connections.get(connectionId);
        if (!conn)
            return;
        conn.state = 'disconnected';
        conn.error = error;
        this.calculateHealthScore(conn);
        this.recordEvent({
            type: 'disconnected',
            connectionId,
            sessionId: conn.sessionId,
            userId: conn.userId,
            timestamp: Date.now(),
            data: { error },
        });
    }
    /**
     * Get connection health status
     */
    getConnectionHealth(connectionId) {
        const conn = this.connections.get(connectionId);
        if (!conn)
            return null;
        const issues = this.healthIssues.get(connectionId) || [];
        const isCritical = issues.some((i) => i.severity === 'critical');
        return {
            connection: conn,
            timestamp: Date.now(),
            isCritical,
            issues,
        };
    }
    /**
     * Get aggregated metrics for all connections
     */
    getAggregatedMetrics() {
        const conns = Array.from(this.connections.values());
        const now = Date.now();
        if (conns.length === 0) {
            return {
                timestamp: now,
                activeConnections: 0,
                healthyConnections: 0,
                healthyPercent: 100,
                avgLatencyMs: 0,
                p95LatencyMs: 0,
                avgDeliverySuccessRate: 100,
                totalReconnectionAttempts: 0,
                avgUptimePercent: 100,
                criticalIssueCount: 0,
                warningIssueCount: 0,
            };
        }
        const activeConns = conns.filter((c) => c.state === 'connected' || c.state === 'connecting').length;
        const healthyConns = conns.filter((c) => c.isHealthy).length;
        let totalLatency = 0;
        let latencies = [];
        let totalDelivery = 0;
        let totalReconnects = 0;
        let totalUptime = 0;
        let criticalCount = 0;
        let warningCount = 0;
        conns.forEach((conn) => {
            totalLatency += conn.averageLatencyMs;
            if (conn.latencyMs > 0)
                latencies.push(conn.latencyMs);
            totalDelivery += conn.deliverySuccessRate;
            totalReconnects += conn.reconnectionAttempts;
            totalUptime += conn.uptimePercent;
            const issues = this.healthIssues.get(conn.connectionId) || [];
            issues.forEach((i) => {
                if (i.severity === 'critical')
                    criticalCount++;
                else
                    warningCount++;
            });
        });
        latencies = latencies.sort((a, b) => a - b);
        const p95Index = Math.floor((95 / 100) * latencies.length);
        return {
            timestamp: now,
            activeConnections: activeConns,
            healthyConnections: healthyConns,
            healthyPercent: (healthyConns / conns.length) * 100,
            avgLatencyMs: totalLatency / conns.length,
            p95LatencyMs: latencies.length > 0 ? latencies[p95Index] : 0,
            avgDeliverySuccessRate: totalDelivery / conns.length,
            totalReconnectionAttempts: totalReconnects,
            avgUptimePercent: totalUptime / conns.length,
            criticalIssueCount: criticalCount,
            warningIssueCount: warningCount,
        };
    }
    /**
     * Get per-session health stats
     */
    getSessionHealth(sessionId) {
        const sessionConns = Array.from(this.connections.values()).filter((c) => c.sessionId === sessionId);
        if (sessionConns.length === 0)
            return null;
        const healthy = sessionConns.filter((c) => c.isHealthy).length;
        const totalLatency = sessionConns.reduce((sum, c) => sum + c.averageLatencyMs, 0);
        const totalDelivery = sessionConns.reduce((sum, c) => sum + c.deliverySuccessRate, 0);
        const totalUptime = sessionConns.reduce((sum, c) => sum + c.uptimePercent, 0);
        return {
            sessionId,
            totalConnections: sessionConns.length,
            healthyConnections: healthy,
            healthPercent: (healthy / sessionConns.length) * 100,
            avgLatencyMs: totalLatency / sessionConns.length,
            deliverySuccessRate: totalDelivery / sessionConns.length,
            uptimePercent: totalUptime / sessionConns.length,
        };
    }
    /**
     * Get all active connections
     */
    getAllConnections() {
        return Array.from(this.connections.values()).filter((c) => c.state === 'connected' || c.state === 'connecting');
    }
    /**
     * Get recent events (for streaming to Prometheus/Grafana)
     */
    getRecentEvents(limit = 100) {
        return this.connectionEvents.slice(-limit);
    }
    /**
     * Reset monitoring (for testing)
     */
    reset() {
        this.connections.clear();
        this.latencyMeasurements.clear();
        this.connectionEvents = [];
        this.healthIssues.clear();
    }
    /**
     * Destroy the engine and cleanup resources
     */
    destroy() {
        if (this.cleanupInterval)
            clearInterval(this.cleanupInterval);
        if (this.healthCheckInterval)
            clearInterval(this.healthCheckInterval);
    }
    // Private methods
    updateLatencyStats(conn, measurements) {
        if (measurements.length === 0)
            return;
        const latencies = measurements.map((m) => m.latencyMs).sort((a, b) => a - b);
        conn.averageLatencyMs =
            latencies.reduce((a, b) => a + b, 0) / latencies.length;
        conn.minLatencyMs = Math.min(conn.minLatencyMs, latencies[0]);
        conn.maxLatencyMs = latencies[latencies.length - 1];
        const p95Index = Math.ceil((95 / 100) * latencies.length) - 1;
        conn.p95LatencyMs = latencies[Math.max(0, p95Index)];
    }
    checkLatencyHealth(conn) {
        const issues = this.healthIssues.get(conn.connectionId) || [];
        const hasLatencyIssue = issues.some((i) => i.type === 'high_latency');
        if (conn.latencyMs > this.config.latencyCriticalMs &&
            !hasLatencyIssue) {
            this.addHealthIssue(conn.connectionId, {
                type: 'high_latency',
                severity: 'critical',
                message: `Latency ${conn.latencyMs}ms exceeds critical threshold ${this.config.latencyCriticalMs}ms`,
                detectedAt: Date.now(),
            });
            conn.isHealthy = false;
        }
        else if (conn.latencyMs > this.config.latencyWarningMs &&
            !hasLatencyIssue) {
            this.addHealthIssue(conn.connectionId, {
                type: 'high_latency',
                severity: 'warning',
                message: `Latency ${conn.latencyMs}ms exceeds warning threshold ${this.config.latencyWarningMs}ms`,
                detectedAt: Date.now(),
            });
        }
    }
    updateDeliveryRate(conn) {
        const total = conn.messagesSent + conn.messagesLost;
        if (total === 0) {
            conn.deliverySuccessRate = 100;
            return;
        }
        conn.deliverySuccessRate = (conn.messagesSent / total) * 100;
    }
    checkMessageLossHealth(conn) {
        if (conn.deliverySuccessRate <
            100 - this.config.messageLossThresholdPercent) {
            this.addHealthIssue(conn.connectionId, {
                type: 'message_loss',
                severity: 'critical',
                message: `Message loss rate ${100 - conn.deliverySuccessRate}% exceeds threshold`,
                detectedAt: Date.now(),
            });
            conn.isHealthy = false;
        }
    }
    addHealthIssue(connectionId, issue) {
        const issues = this.healthIssues.get(connectionId) || [];
        const existing = issues.find((i) => i.type === issue.type);
        if (!existing) {
            issues.push(issue);
            this.healthIssues.set(connectionId, issues);
        }
    }
    recordEvent(event) {
        this.connectionEvents.push(event);
        if (this.connectionEvents.length > 10000) {
            this.connectionEvents = this.connectionEvents.slice(-5000);
        }
    }
    startCleanupInterval() {
        this.cleanupInterval = setInterval(() => {
            const cutoffTime = Date.now() - this.config.retentionMs;
            // Clean up old latency measurements
            this.latencyMeasurements.forEach((measurements, connectionId) => {
                const filtered = measurements.filter((m) => m.endTime >= cutoffTime);
                if (filtered.length === 0) {
                    this.latencyMeasurements.delete(connectionId);
                }
                else {
                    this.latencyMeasurements.set(connectionId, filtered);
                }
            });
            // Remove dead connections
            const now = Date.now();
            const connectionsToDelete = [];
            this.connections.forEach((conn, id) => {
                if (conn.state === 'disconnected' &&
                    now - conn.connectedAt > this.config.retentionMs) {
                    connectionsToDelete.push(id);
                }
            });
            connectionsToDelete.forEach((id) => this.connections.delete(id));
        }, 60 * 60 * 1000); // Run every hour
    }
    startHealthCheckInterval() {
        if (!this.config.enabled)
            return;
        this.healthCheckInterval = setInterval(() => {
            const now = Date.now();
            this.connections.forEach((conn) => {
                // Check for stale connections
                if (now - conn.lastHeartbeatAt >
                    this.config.staleConnectionThresholdMs) {
                    if (conn.state === 'connected' ||
                        conn.state === 'connecting') {
                        conn.state = 'stale';
                        this.addHealthIssue(conn.connectionId, {
                            type: 'stale_connection',
                            severity: 'warning',
                            message: `No messages for ${(now - conn.lastHeartbeatAt) / 1000}s`,
                            detectedAt: now,
                        });
                    }
                }
                // Update uptime
                const uptime = now - conn.connectedAt;
                const downtime = (conn.connectedAt - conn.lastHeartbeatAt) / uptime;
                conn.uptimePercent = Math.max(0, 100 * (1 - downtime));
                // Recalculate health score
                this.calculateHealthScore(conn);
            });
        }, this.config.healthCheckIntervalMs);
    }
    calculateHealthScore(conn) {
        let score = 100;
        // Latency impact
        if (conn.latencyMs > this.config.latencyCriticalMs)
            score -= 30;
        else if (conn.latencyMs > this.config.latencyWarningMs)
            score -= 15;
        // Delivery impact
        score -= 100 - conn.deliverySuccessRate;
        // Stability impact
        if (conn.reconnectionAttempts > 3)
            score -= 20;
        // Connection state impact
        if (conn.state !== 'connected')
            score -= 25;
        conn.healthScore = Math.max(0, score);
        conn.isHealthy = conn.healthScore >= 70;
    }
}
//# sourceMappingURL=engine.js.map