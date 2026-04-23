#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/monitoring.ts
// @module      github-task-sync/monitoring
// @description Monitoring and observability for webhook pipeline
// @owner       collab-9
// @status      active

import { EventEmitter } from 'events';
import { getLogger } from '../../utils/logging';

const logger = getLogger('webhook-monitoring');

export interface MetricsSnapshot {
  timestamp: number;
  webhooks: {
    received: number;
    processed: number;
    failed: number;
    deduplicated: number;
    avgLatencyMs: number;
    p99LatencyMs: number;
  };
  websocket: {
    connectedClients: number;
    broadcastCount: number;
    failedBroadcasts: number;
    avgBroadcastLatencyMs: number;
  };
  database: {
    writes: number;
    errors: number;
    avgLatencyMs: number;
  };
  errors: {
    signatureErrors: number;
    processingErrors: number;
    broadcastErrors: number;
    databaseErrors: number;
  };
  health: {
    status: 'healthy' | 'degraded' | 'unhealthy';
    uptime: number;
    lastCheck: number;
  };
}

/**
 * WebSocket Pipeline Monitoring
 * Tracks performance metrics, errors, and health status
 */
export class PipelineMonitor extends EventEmitter {
  private metrics = {
    webhooks: {
      received: 0,
      processed: 0,
      failed: 0,
      deduplicated: 0,
      latencies: [] as number[],
    },
    websocket: {
      connectedClients: 0,
      broadcastCount: 0,
      failedBroadcasts: 0,
      broadcastLatencies: [] as number[],
    },
    database: {
      writes: 0,
      errors: 0,
      latencies: [] as number[],
    },
    errors: {
      signatureErrors: 0,
      processingErrors: 0,
      broadcastErrors: 0,
      databaseErrors: 0,
    },
  };

  private startTime = Date.now();
  private lastHealthCheck = Date.now();
  private maxLatencyBufferSize = 1000;

  constructor(private serviceName: string = 'webhook-pipeline') {
    super();
    logger.info(`Monitoring initialized for ${serviceName}`);
  }

  /**
   * Record webhook received event
   */
  recordWebhookReceived(deliveryId: string): void {
    this.metrics.webhooks.received++;
    logger.debug(`Webhook received: ${deliveryId}`);
  }

  /**
   * Record webhook processing with latency
   */
  recordWebhookProcessed(deliveryId: string, latencyMs: number, deduplicated: boolean = false): void {
    this.metrics.webhooks.processed++;
    if (deduplicated) {
      this.metrics.webhooks.deduplicated++;
    } else {
      this.metrics.webhooks.latencies.push(latencyMs);
      this.maintainBufferSize();
    }

    if (latencyMs > 100) {
      logger.warn(`Slow webhook processing: ${deliveryId} (${latencyMs}ms)`);
    }

    this.emit('webhook-processed', { deliveryId, latencyMs, deduplicated });
  }

  /**
   * Record webhook processing failure
   */
  recordWebhookError(deliveryId: string, error: string, errorType: 'signature' | 'processing' | 'database'): void {
    this.metrics.webhooks.failed++;

    switch (errorType) {
      case 'signature':
        this.metrics.errors.signatureErrors++;
        break;
      case 'processing':
        this.metrics.errors.processingErrors++;
        break;
      case 'database':
        this.metrics.errors.databaseErrors++;
        break;
    }

    logger.error(`Webhook error: ${deliveryId} (${errorType}): ${error}`);
    this.emit('webhook-error', { deliveryId, error, errorType });
  }

  /**
   * Record WebSocket broadcast with latency
   */
  recordBroadcast(messageId: string, clientCount: number, latencyMs: number): void {
    this.metrics.websocket.broadcastCount++;
    this.metrics.websocket.broadcastLatencies.push(latencyMs);
    this.maintainBufferSize();

    if (latencyMs > 50) {
      logger.warn(`Slow broadcast: ${messageId} to ${clientCount} clients (${latencyMs}ms)`);
    }

    this.emit('broadcast-sent', { messageId, clientCount, latencyMs });
  }

  /**
   * Record broadcast failure
   */
  recordBroadcastError(messageId: string, clientId: string, error: string): void {
    this.metrics.websocket.failedBroadcasts++;
    this.metrics.errors.broadcastErrors++;

    logger.error(`Broadcast error: ${messageId} to ${clientId}: ${error}`);
    this.emit('broadcast-error', { messageId, clientId, error });
  }

  /**
   * Record database write with latency
   */
  recordDatabaseWrite(queryId: string, latencyMs: number): void {
    this.metrics.database.writes++;
    this.metrics.database.latencies.push(latencyMs);
    this.maintainBufferSize();

    if (latencyMs > 100) {
      logger.warn(`Slow database write: ${queryId} (${latencyMs}ms)`);
    }
  }

  /**
   * Record database error
   */
  recordDatabaseError(queryId: string, error: string): void {
    this.metrics.database.errors++;
    this.metrics.errors.databaseErrors++;

    logger.error(`Database error: ${queryId}: ${error}`);
    this.emit('database-error', { queryId, error });
  }

  /**
   * Update connected WebSocket client count
   */
  setConnectedClients(count: number): void {
    this.metrics.websocket.connectedClients = count;
  }

  /**
   * Get current metrics snapshot
   */
  getMetrics(): MetricsSnapshot {
    const webhookLatencies = this.metrics.webhooks.latencies;
    const broadcastLatencies = this.metrics.websocket.broadcastLatencies;
    const dbLatencies = this.metrics.database.latencies;

    return {
      timestamp: Date.now(),
      webhooks: {
        received: this.metrics.webhooks.received,
        processed: this.metrics.webhooks.processed,
        failed: this.metrics.webhooks.failed,
        deduplicated: this.metrics.webhooks.deduplicated,
        avgLatencyMs: this.calculateAvg(webhookLatencies),
        p99LatencyMs: this.calculatePercentile(webhookLatencies, 99),
      },
      websocket: {
        connectedClients: this.metrics.websocket.connectedClients,
        broadcastCount: this.metrics.websocket.broadcastCount,
        failedBroadcasts: this.metrics.websocket.failedBroadcasts,
        avgBroadcastLatencyMs: this.calculateAvg(broadcastLatencies),
      },
      database: {
        writes: this.metrics.database.writes,
        errors: this.metrics.database.errors,
        avgLatencyMs: this.calculateAvg(dbLatencies),
      },
      errors: this.metrics.errors,
      health: this.getHealthStatus(),
    };
  }

  /**
   * Get health status
   */
  private getHealthStatus(): { status: 'healthy' | 'degraded' | 'unhealthy'; uptime: number; lastCheck: number } {
    const now = Date.now();
    const uptime = now - this.startTime;

    // Calculate error rate
    const totalEvents = this.metrics.webhooks.received;
    const failureRate = totalEvents > 0 ? (this.metrics.webhooks.failed / totalEvents) * 100 : 0;

    // Check latency
    const avgLatency = this.calculateAvg(this.metrics.webhooks.latencies);
    const p99Latency = this.calculatePercentile(this.metrics.webhooks.latencies, 99);

    let status: 'healthy' | 'degraded' | 'unhealthy' = 'healthy';

    if (failureRate > 10 || p99Latency > 200) {
      status = 'unhealthy';
    } else if (failureRate > 5 || p99Latency > 150) {
      status = 'degraded';
    }

    if (status !== 'healthy') {
      logger.warn(`Service health: ${status} (failure rate: ${failureRate.toFixed(2)}%, P99: ${p99Latency}ms)`);
    }

    this.lastHealthCheck = now;
    return { status, uptime, lastCheck: this.lastHealthCheck };
  }

  /**
   * Helper: Calculate average
   */
  private calculateAvg(values: number[]): number {
    if (values.length === 0) return 0;
    const sum = values.reduce((a, b) => a + b, 0);
    return Math.round(sum / values.length);
  }

  /**
   * Helper: Calculate percentile
   */
  private calculatePercentile(values: number[], percentile: number): number {
    if (values.length === 0) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const index = Math.ceil((percentile / 100) * sorted.length) - 1;
    return sorted[Math.max(0, index)];
  }

  /**
   * Helper: Maintain latency buffer size
   */
  private maintainBufferSize(): void {
    const latencies = [
      ...this.metrics.webhooks.latencies,
      ...this.metrics.websocket.broadcastLatencies,
      ...this.metrics.database.latencies,
    ];

    if (latencies.length > this.maxLatencyBufferSize) {
      const trimSize = Math.floor(this.maxLatencyBufferSize * 0.8);
      this.metrics.webhooks.latencies = this.metrics.webhooks.latencies.slice(-trimSize);
      this.metrics.websocket.broadcastLatencies = this.metrics.websocket.broadcastLatencies.slice(-trimSize);
      this.metrics.database.latencies = this.metrics.database.latencies.slice(-trimSize);
    }
  }

  /**
   * Reset metrics (for testing)
   */
  reset(): void {
    this.metrics = {
      webhooks: { received: 0, processed: 0, failed: 0, deduplicated: 0, latencies: [] },
      websocket: { connectedClients: 0, broadcastCount: 0, failedBroadcasts: 0, broadcastLatencies: [] },
      database: { writes: 0, errors: 0, latencies: [] },
      errors: {
        signatureErrors: 0,
        processingErrors: 0,
        broadcastErrors: 0,
        databaseErrors: 0,
      },
    };
    this.startTime = Date.now();
  }
}

export default PipelineMonitor;