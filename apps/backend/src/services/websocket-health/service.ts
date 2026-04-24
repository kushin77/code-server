/**
 * WebSocket health monitoring service.
 * Provides public API for WebSocket health tracking and monitoring.
 */

import { WebSocketHealthEngine, DEFAULT_HEALTH_CONFIG } from './engine';
import {
  WebSocketConnectionMetrics,
  WebSocketHealthStatus,
  WebSocketHealthConfig,
  ConnectionEvent,
  AggregatedHealthMetrics,
  PerSessionHealthStats,
} from './types';

type HealthEventCallback = (
  status: WebSocketHealthStatus,
  event: 'healthy' | 'degraded' | 'critical'
) => void;

export class WebSocketHealthService {
  private static instance: WebSocketHealthService;
  private engine: WebSocketHealthEngine;
  private healthEventCallbacks: HealthEventCallback[] = [];

  private constructor(config: Partial<WebSocketHealthConfig> = {}) {
    this.engine = new WebSocketHealthEngine(config);
  }

  /**
   * Get or create singleton instance
   */
  static getInstance(
    config: Partial<WebSocketHealthConfig> = {}
  ): WebSocketHealthService {
    if (!WebSocketHealthService.instance) {
      WebSocketHealthService.instance = new WebSocketHealthService(config);
    }
    return WebSocketHealthService.instance;
  }

  /**
   * Register a new WebSocket connection
   */
  registerConnection(
    connectionId: string,
    sessionId: string,
    userId: string
  ): WebSocketConnectionMetrics {
    return this.engine.registerConnection(connectionId, sessionId, userId);
  }

  /**
   * Record a health check measurement (ping/pong latency)
   */
  recordHealthCheck(connectionId: string, latencyMs: number): void {
    const measurement = this.engine.recordLatency(connectionId, latencyMs);

    // Check if health status changed
    const health = this.engine.getConnectionHealth(connectionId);
    if (health) {
      this.emitHealthEvent(health);
    }
  }

  /**
   * Record that a message was successfully delivered
   */
  recordMessageDelivery(connectionId: string): void {
    this.engine.recordMessageReceived(connectionId);
  }

  /**
   * Record message loss (unacknowledged messages)
   */
  recordMessageLoss(connectionId: string, count?: number): void {
    this.engine.recordMessageLoss(connectionId, count);
    const health = this.engine.getConnectionHealth(connectionId);
    if (health) {
      this.emitHealthEvent(health);
    }
  }

  /**
   * Record a reconnection attempt
   */
  recordReconnection(connectionId: string): void {
    this.engine.updateConnectionState(connectionId, 'reconnecting');
  }

  /**
   * Record reconnection failure
   */
  recordReconnectionFailure(connectionId: string): void {
    this.engine.recordReconnectionFailure(connectionId);
    const health = this.engine.getConnectionHealth(connectionId);
    if (health?.isCritical) {
      this.emitHealthEvent(health);
    }
  }

  /**
   * Mark connection as successfully reconnected
   */
  recordReconnectionSuccess(connectionId: string): void {
    this.engine.updateConnectionState(connectionId, 'connected');
  }

  /**
   * Mark connection as disconnected
   */
  closeConnection(connectionId: string, error?: string): void {
    this.engine.closeConnection(connectionId, error);
  }

  /**
   * Get health status for a connection
   */
  getConnectionHealth(connectionId: string): WebSocketHealthStatus | null {
    return this.engine.getConnectionHealth(connectionId);
  }

  /**
   * Get all active connections
   */
  getActiveConnections(): WebSocketConnectionMetrics[] {
    return this.engine.getAllConnections();
  }

  /**
   * Get aggregated metrics across all connections
   */
  getAggregatedMetrics(): AggregatedHealthMetrics {
    return this.engine.getAggregatedMetrics();
  }

  /**
   * Get health stats for a specific session
   */
  getSessionHealth(sessionId: string): PerSessionHealthStats | null {
    return this.engine.getSessionHealth(sessionId);
  }

  /**
   * Get recent events for streaming/logging
   */
  getRecentEvents(limit?: number): ConnectionEvent[] {
    return this.engine.getRecentEvents(limit);
  }

  /**
   * Get Prometheus metrics format
   */
  getPrometheusMetrics(): string {
    const metrics: string[] = [];
    const agg = this.engine.getAggregatedMetrics();
    const connections = this.engine.getAllConnections();

    // Counters
    metrics.push(`# HELP websocket_connections_active Active WebSocket connections`);
    metrics.push(`# TYPE websocket_connections_active gauge`);
    metrics.push(`websocket_connections_active ${agg.activeConnections}`);

    metrics.push(`# HELP websocket_connections_healthy Healthy WebSocket connections`);
    metrics.push(`# TYPE websocket_connections_healthy gauge`);
    metrics.push(`websocket_connections_healthy ${agg.healthyConnections}`);

    // Latency metrics
    metrics.push(`# HELP websocket_latency_ms Average WebSocket latency`);
    metrics.push(`# TYPE websocket_latency_ms gauge`);
    metrics.push(`websocket_latency_ms{quantile="avg"} ${agg.avgLatencyMs}`);
    metrics.push(`websocket_latency_ms{quantile="p95"} ${agg.p95LatencyMs}`);

    // Delivery metrics
    metrics.push(`# HELP websocket_delivery_rate Message delivery success rate`);
    metrics.push(`# TYPE websocket_delivery_rate gauge`);
    metrics.push(`websocket_delivery_rate ${agg.avgDeliverySuccessRate}`);

    // Uptime metrics
    metrics.push(`# HELP websocket_uptime_percent Connection uptime percentage`);
    metrics.push(`# TYPE websocket_uptime_percent gauge`);
    metrics.push(`websocket_uptime_percent ${agg.avgUptimePercent}`);

    // Reconnection attempts
    metrics.push(`# HELP websocket_reconnections_total Total reconnection attempts`);
    metrics.push(`# TYPE websocket_reconnections_total counter`);
    metrics.push(`websocket_reconnections_total ${agg.totalReconnectionAttempts}`);

    // Health issues
    metrics.push(`# HELP websocket_health_issues Health issues detected`);
    metrics.push(`# TYPE websocket_health_issues gauge`);
    metrics.push(
      `websocket_health_issues{severity="critical"} ${agg.criticalIssueCount}`
    );
    metrics.push(
      `websocket_health_issues{severity="warning"} ${agg.warningIssueCount}`
    );

    // Per-connection health scores
    metrics.push(`# HELP websocket_connection_health_score Connection health score (0-100)`);
    metrics.push(`# TYPE websocket_connection_health_score gauge`);
    connections.forEach((conn) => {
      metrics.push(
        `websocket_connection_health_score{connection_id="${conn.connectionId}",session_id="${conn.sessionId}",user_id="${conn.userId}"} ${conn.healthScore}`
      );
    });

    return metrics.join('\n') + '\n';
  }

  /**
   * Register callback for health events
   */
  onHealthEvent(callback: HealthEventCallback): void {
    this.healthEventCallbacks.push(callback);
  }

  /**
   * Remove health event callback
   */
  offHealthEvent(callback: HealthEventCallback): void {
    this.healthEventCallbacks = this.healthEventCallbacks.filter(
      (cb) => cb !== callback
    );
  }

  /**
   * Reset service (for testing)
   */
  reset(): void {
    this.engine.reset();
  }

  /**
   * Destroy service
   */
  destroy(): void {
    this.engine.destroy();
    this.healthEventCallbacks = [];
    WebSocketHealthService.instance = undefined as any;
  }

  private emitHealthEvent(status: WebSocketHealthStatus): void {
    let eventType: 'healthy' | 'degraded' | 'critical' = 'healthy';

    if (status.isCritical) {
      eventType = 'critical';
    } else if (
      status.connection.healthScore < 85 ||
      status.issues.length > 0
    ) {
      eventType = 'degraded';
    }

    this.healthEventCallbacks.forEach((callback) => {
      try {
        callback(status, eventType);
      } catch (error) {
        console.error('Error in health event callback:', error);
      }
    });
  }
}

/**
 * Get or create WebSocket health service singleton
 */
export function getWebSocketHealthService(
  config: Partial<WebSocketHealthConfig> = {}
): WebSocketHealthService {
  return WebSocketHealthService.getInstance(config);
}
