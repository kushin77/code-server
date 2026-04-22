/**
 * WebSocket health monitoring test suite
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { WebSocketHealthEngine, DEFAULT_HEALTH_CONFIG } from '../engine';
import { getWebSocketHealthService, } from '../service';
describe('WebSocketHealthEngine', () => {
    let engine;
    beforeEach(() => {
        engine = new WebSocketHealthEngine(DEFAULT_HEALTH_CONFIG);
    });
    afterEach(() => {
        engine.destroy();
    });
    describe('Connection Registration', () => {
        it('should register a new connection', () => {
            const metrics = engine.registerConnection('conn1', 'sess1', 'user1');
            expect(metrics).toBeDefined();
            expect(metrics.connectionId).toBe('conn1');
            expect(metrics.sessionId).toBe('sess1');
            expect(metrics.userId).toBe('user1');
            expect(metrics.state).toBe('connecting');
            expect(metrics.isHealthy).toBe(true);
            expect(metrics.healthScore).toBe(100);
        });
        it('should track multiple connections', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.registerConnection('conn2', 'sess1', 'user2');
            engine.registerConnection('conn3', 'sess2', 'user3');
            const allConns = engine.getAllConnections();
            expect(allConns.length).toBe(3);
        });
    });
    describe('Latency Tracking', () => {
        it('should record latency measurements', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            const measurement = engine.recordLatency('conn1', 50);
            expect(measurement.latencyMs).toBe(50);
            expect(measurement.successful).toBe(true);
            const conn = engine.getConnectionHealth('conn1');
            expect(conn?.connection.latencyMs).toBe(50);
        });
        it('should update latency statistics', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.recordLatency('conn1', 40);
            engine.recordLatency('conn1', 60);
            engine.recordLatency('conn1', 50);
            const health = engine.getConnectionHealth('conn1');
            const conn = health?.connection;
            expect(conn?.averageLatencyMs).toBe(50);
            expect(conn?.minLatencyMs).toBe(40);
            expect(conn?.maxLatencyMs).toBe(60);
            expect(conn?.p95LatencyMs).toBeGreaterThanOrEqual(50);
        });
        it('should detect high latency issues', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            // Record latency exceeding critical threshold
            engine.recordLatency('conn1', DEFAULT_HEALTH_CONFIG.latencyCriticalMs + 100);
            const health = engine.getConnectionHealth('conn1');
            expect(health?.isCritical).toBe(true);
            expect(health?.issues.some((i) => i.type === 'high_latency')).toBe(true);
            expect(health?.connection.isHealthy).toBe(false);
        });
    });
    describe('Message Delivery Tracking', () => {
        it('should track message delivery', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.recordLatency('conn1', 50); // Sends message
            engine.recordMessageReceived('conn1'); // Receives response
            const health = engine.getConnectionHealth('conn1');
            expect(health?.connection.messagesSent).toBe(1);
            expect(health?.connection.messagesReceived).toBe(1);
            expect(health?.connection.deliverySuccessRate).toBe(100);
        });
        it('should calculate delivery success rate', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            // Send 10 messages
            for (let i = 0; i < 10; i++) {
                engine.recordLatency('conn1', 50);
            }
            // Only receive 9 (1 lost)
            for (let i = 0; i < 9; i++) {
                engine.recordMessageReceived('conn1');
            }
            engine.recordMessageLoss('conn1', 1);
            const health = engine.getConnectionHealth('conn1');
            expect(health?.connection.messagesLost).toBe(1);
            expect(health?.connection.deliverySuccessRate).toBeLessThan(100);
        });
        it('should detect excessive message loss', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            // Send 100 messages, lose 10 (10% loss)
            for (let i = 0; i < 100; i++) {
                engine.recordLatency('conn1', 50);
            }
            for (let i = 0; i < 90; i++) {
                engine.recordMessageReceived('conn1');
            }
            engine.recordMessageLoss('conn1', 10);
            const health = engine.getConnectionHealth('conn1');
            expect(health?.issues.some((i) => i.type === 'message_loss')).toBe(true);
            expect(health?.connection.isHealthy).toBe(false);
        });
    });
    describe('Connection State Management', () => {
        it('should update connection state', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.updateConnectionState('conn1', 'connected');
            let health = engine.getConnectionHealth('conn1');
            expect(health?.connection.state).toBe('connected');
            engine.updateConnectionState('conn1', 'disconnecting');
            health = engine.getConnectionHealth('conn1');
            expect(health?.connection.state).toBe('disconnecting');
        });
        it('should track reconnection attempts', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.updateConnectionState('conn1', 'reconnecting');
            engine.updateConnectionState('conn1', 'reconnecting');
            const health = engine.getConnectionHealth('conn1');
            expect(health?.connection.reconnectionAttempts).toBe(2);
        });
        it('should detect frequent reconnections as critical', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            // Exceed max reconnection attempts
            const maxAttempts = DEFAULT_HEALTH_CONFIG.maxReconnectionAttempts;
            for (let i = 0; i < maxAttempts + 1; i++) {
                engine.recordReconnectionFailure('conn1');
            }
            const health = engine.getConnectionHealth('conn1');
            expect(health?.isCritical).toBe(true);
            expect(health?.issues.some((i) => i.type === 'frequent_reconnects')).toBe(true);
        });
    });
    describe('Stale Connection Detection', () => {
        it('should detect stale connections', (done) => {
            const config = {
                ...DEFAULT_HEALTH_CONFIG,
                staleConnectionThresholdMs: 100,
                healthCheckIntervalMs: 50,
            };
            const testEngine = new WebSocketHealthEngine(config);
            testEngine.registerConnection('conn1', 'sess1', 'user1');
            testEngine.recordLatency('conn1', 50);
            // Wait for health check to detect staleness
            setTimeout(() => {
                const health = testEngine.getConnectionHealth('conn1');
                expect(health?.connection.state).toBe('stale');
                expect(health?.issues.some((i) => i.type === 'stale_connection')).toBe(true);
                testEngine.destroy();
                done();
            }, 200);
        });
    });
    describe('Aggregated Metrics', () => {
        it('should calculate aggregated metrics', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.registerConnection('conn2', 'sess1', 'user2');
            engine.recordLatency('conn1', 50);
            engine.recordLatency('conn2', 60);
            const agg = engine.getAggregatedMetrics();
            expect(agg.activeConnections).toBe(2);
            expect(agg.avgLatencyMs).toBeGreaterThan(0);
        });
        it('should calculate health percentage', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.registerConnection('conn2', 'sess1', 'user2');
            engine.recordLatency('conn1', DEFAULT_HEALTH_CONFIG.latencyCriticalMs + 100);
            const agg = engine.getAggregatedMetrics();
            expect(agg.healthyPercent).toBeLessThan(100);
            expect(agg.healthyConnections).toBe(1);
        });
        it('should track critical and warning issues', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.recordLatency('conn1', DEFAULT_HEALTH_CONFIG.latencyCriticalMs + 100);
            const agg = engine.getAggregatedMetrics();
            expect(agg.criticalIssueCount).toBeGreaterThan(0);
        });
    });
    describe('Session-Level Stats', () => {
        it('should calculate per-session health', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            engine.registerConnection('conn2', 'sess1', 'user2');
            engine.registerConnection('conn3', 'sess2', 'user3');
            engine.recordLatency('conn1', 50);
            engine.recordLatency('conn2', 60);
            const sessionHealth = engine.getSessionHealth('sess1');
            expect(sessionHealth?.sessionId).toBe('sess1');
            expect(sessionHealth?.totalConnections).toBe(2);
            expect(sessionHealth?.avgLatencyMs).toBeGreaterThan(0);
        });
        it('should return null for non-existent session', () => {
            const sessionHealth = engine.getSessionHealth('nonexistent');
            expect(sessionHealth).toBeNull();
        });
    });
    describe('Event Recording', () => {
        it('should record connection events', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            const events = engine.getRecentEvents(100);
            expect(events.length).toBeGreaterThan(0);
            expect(events[0].type).toBe('connected');
            expect(events[0].connectionId).toBe('conn1');
        });
    });
    describe('Health Score Calculation', () => {
        it('should calculate health score based on metrics', () => {
            engine.registerConnection('conn1', 'sess1', 'user1');
            let health = engine.getConnectionHealth('conn1');
            expect(health?.connection.healthScore).toBe(100);
            engine.recordLatency('conn1', 200); // Warning level
            health = engine.getConnectionHealth('conn1');
            expect(health?.connection.healthScore).toBeLessThan(100);
        });
    });
});
describe('WebSocketHealthService', () => {
    let service;
    beforeEach(() => {
        service = getWebSocketHealthService();
    });
    afterEach(() => {
        service.destroy();
    });
    it('should be a singleton', () => {
        const service2 = getWebSocketHealthService();
        expect(service).toBe(service2);
    });
    it('should register connections', () => {
        const metrics = service.registerConnection('conn1', 'sess1', 'user1');
        expect(metrics.connectionId).toBe('conn1');
    });
    it('should record health checks', () => {
        service.registerConnection('conn1', 'sess1', 'user1');
        service.recordHealthCheck('conn1', 50);
        const health = service.getConnectionHealth('conn1');
        expect(health?.connection.latencyMs).toBe(50);
    });
    it('should record message delivery', () => {
        service.registerConnection('conn1', 'sess1', 'user1');
        service.recordMessageDelivery('conn1');
        const health = service.getConnectionHealth('conn1');
        expect(health?.connection.messagesReceived).toBe(1);
    });
    it('should record message loss', () => {
        service.registerConnection('conn1', 'sess1', 'user1');
        service.recordMessageLoss('conn1', 5);
        const health = service.getConnectionHealth('conn1');
        expect(health?.connection.messagesLost).toBe(5);
    });
    it('should emit health events', () => {
        const callback = vi.fn();
        service.onHealthEvent(callback);
        service.registerConnection('conn1', 'sess1', 'user1');
        service.recordHealthCheck('conn1', DEFAULT_HEALTH_CONFIG.latencyCriticalMs + 100);
        expect(callback).toHaveBeenCalledWith(expect.any(Object), 'critical');
    });
    it('should export Prometheus metrics', () => {
        service.registerConnection('conn1', 'sess1', 'user1');
        service.recordHealthCheck('conn1', 50);
        const metrics = service.getPrometheusMetrics();
        expect(metrics).toContain('websocket_connections_active');
        expect(metrics).toContain('websocket_latency_ms');
        expect(metrics).toContain('websocket_delivery_rate');
    });
    it('should get session health', () => {
        service.registerConnection('conn1', 'sess1', 'user1');
        service.recordHealthCheck('conn1', 50);
        const sessionHealth = service.getSessionHealth('sess1');
        expect(sessionHealth?.sessionId).toBe('sess1');
    });
    it('should close connections', () => {
        service.registerConnection('conn1', 'sess1', 'user1');
        service.closeConnection('conn1', 'test error');
        const health = service.getConnectionHealth('conn1');
        expect(health?.connection.state).toBe('disconnected');
        expect(health?.connection.error).toBe('test error');
    });
});
//# sourceMappingURL=websocket-health.test.js.map