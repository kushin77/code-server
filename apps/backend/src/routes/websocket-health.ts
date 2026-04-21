/**
 * WebSocket health monitoring API routes
 */

import { Router, Request, Response } from 'express';
import { getWebSocketHealthService } from '../services/websocket-health';

const router = Router();
const healthService = getWebSocketHealthService();

/**
 * POST /websocket/register
 * Register a new WebSocket connection for monitoring
 */
router.post('/websocket/register', (req: Request, res: Response) => {
  try {
    const { connectionId, sessionId, userId } = req.body;

    if (!connectionId || !sessionId || !userId) {
      return res.status(400).json({
        error: 'Missing required fields: connectionId, sessionId, userId',
      });
    }

    const metrics = healthService.registerConnection(
      connectionId,
      sessionId,
      userId
    );

    res.status(201).json({
      success: true,
      metrics,
    });
  } catch (error) {
    console.error('Error registering connection:', error);
    res.status(500).json({ error: 'Failed to register connection' });
  }
});

/**
 * POST /websocket/health-check
 * Record a latency measurement (ping/pong response)
 */
router.post('/websocket/health-check', (req: Request, res: Response) => {
  try {
    const { connectionId, latencyMs } = req.body;

    if (!connectionId || latencyMs === undefined) {
      return res.status(400).json({
        error: 'Missing required fields: connectionId, latencyMs',
      });
    }

    healthService.recordHealthCheck(connectionId, latencyMs);
    const health = healthService.getConnectionHealth(connectionId);

    res.json({
      success: true,
      health,
    });
  } catch (error) {
    console.error('Error recording health check:', error);
    res.status(500).json({ error: 'Failed to record health check' });
  }
});

/**
 * POST /websocket/message-delivery
 * Record a successfully delivered message
 */
router.post('/websocket/message-delivery', (req: Request, res: Response) => {
  try {
    const { connectionId } = req.body;

    if (!connectionId) {
      return res.status(400).json({
        error: 'Missing required field: connectionId',
      });
    }

    healthService.recordMessageDelivery(connectionId);

    res.json({ success: true });
  } catch (error) {
    console.error('Error recording message delivery:', error);
    res.status(500).json({ error: 'Failed to record message delivery' });
  }
});

/**
 * POST /websocket/message-loss
 * Record message loss (unacknowledged messages)
 */
router.post('/websocket/message-loss', (req: Request, res: Response) => {
  try {
    const { connectionId, count = 1 } = req.body;

    if (!connectionId) {
      return res.status(400).json({
        error: 'Missing required field: connectionId',
      });
    }

    healthService.recordMessageLoss(connectionId, count);
    const health = healthService.getConnectionHealth(connectionId);

    res.json({
      success: true,
      health,
    });
  } catch (error) {
    console.error('Error recording message loss:', error);
    res.status(500).json({ error: 'Failed to record message loss' });
  }
});

/**
 * POST /websocket/reconnect
 * Record a reconnection attempt
 */
router.post('/websocket/reconnect', (req: Request, res: Response) => {
  try {
    const { connectionId, success = true } = req.body;

    if (!connectionId) {
      return res.status(400).json({
        error: 'Missing required field: connectionId',
      });
    }

    if (success) {
      healthService.recordReconnectionSuccess(connectionId);
    } else {
      healthService.recordReconnectionFailure(connectionId);
    }

    const health = healthService.getConnectionHealth(connectionId);

    res.json({
      success: true,
      health,
    });
  } catch (error) {
    console.error('Error recording reconnection:', error);
    res.status(500).json({ error: 'Failed to record reconnection' });
  }
});

/**
 * POST /websocket/close
 * Mark a connection as closed
 */
router.post('/websocket/close', (req: Request, res: Response) => {
  try {
    const { connectionId, error } = req.body;

    if (!connectionId) {
      return res.status(400).json({
        error: 'Missing required field: connectionId',
      });
    }

    healthService.closeConnection(connectionId, error);

    res.json({ success: true });
  } catch (error) {
    console.error('Error closing connection:', error);
    res.status(500).json({ error: 'Failed to close connection' });
  }
});

/**
 * GET /websocket/health/:connectionId
 * Get health status for a specific connection
 */
router.get(
  '/websocket/health/:connectionId',
  (req: Request, res: Response) => {
    try {
      const { connectionId } = req.params;
      const health = healthService.getConnectionHealth(connectionId);

      if (!health) {
        return res.status(404).json({ error: 'Connection not found' });
      }

      res.json(health);
    } catch (error) {
      console.error('Error getting connection health:', error);
      res.status(500).json({ error: 'Failed to get connection health' });
    }
  }
);

/**
 * GET /websocket/metrics
 * Get aggregated metrics across all connections
 */
router.get('/websocket/metrics', (req: Request, res: Response) => {
  try {
    const metrics = healthService.getAggregatedMetrics();
    res.json(metrics);
  } catch (error) {
    console.error('Error getting aggregated metrics:', error);
    res.status(500).json({ error: 'Failed to get aggregated metrics' });
  }
});

/**
 * GET /websocket/connections
 * Get all active connections
 */
router.get('/websocket/connections', (req: Request, res: Response) => {
  try {
    const connections = healthService.getActiveConnections();
    res.json({
      total: connections.length,
      connections,
    });
  } catch (error) {
    console.error('Error getting active connections:', error);
    res.status(500).json({ error: 'Failed to get active connections' });
  }
});

/**
 * GET /websocket/session/:sessionId
 * Get health stats for a specific session
 */
router.get('/websocket/session/:sessionId', (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const stats = healthService.getSessionHealth(sessionId);

    if (!stats) {
      return res.status(404).json({ error: 'Session not found' });
    }

    res.json(stats);
  } catch (error) {
    console.error('Error getting session health:', error);
    res.status(500).json({ error: 'Failed to get session health' });
  }
});

/**
 * GET /websocket/events
 * Get recent WebSocket health events
 */
router.get('/websocket/events', (req: Request, res: Response) => {
  try {
    const limit = parseInt(req.query.limit as string, 10) || 100;
    const events = healthService.getRecentEvents(Math.min(limit, 1000));

    res.json({
      total: events.length,
      events,
    });
  } catch (error) {
    console.error('Error getting events:', error);
    res.status(500).json({ error: 'Failed to get events' });
  }
});

/**
 * GET /websocket/prometheus
 * Get Prometheus-format metrics for Grafana
 */
router.get('/websocket/prometheus', (req: Request, res: Response) => {
  try {
    const metrics = healthService.getPrometheusMetrics();
    res.set('Content-Type', 'text/plain; charset=utf-8');
    res.send(metrics);
  } catch (error) {
    console.error('Error exporting Prometheus metrics:', error);
    res.status(500).json({ error: 'Failed to export metrics' });
  }
});

/**
 * GET /websocket/health
 * Overall health check endpoint
 */
router.get('/websocket/health', (req: Request, res: Response) => {
  try {
    const metrics = healthService.getAggregatedMetrics();

    const status = {
      status:
        metrics.criticalIssueCount === 0 ? 'healthy' : 'degraded',
      timestamp: metrics.timestamp,
      metrics: {
        activeConnections: metrics.activeConnections,
        healthyConnections: metrics.healthyConnections,
        healthyPercent: metrics.healthyPercent.toFixed(2),
        avgLatencyMs: metrics.avgLatencyMs.toFixed(2),
        avgDeliverySuccessRate:
          metrics.avgDeliverySuccessRate.toFixed(2),
        criticalIssues: metrics.criticalIssueCount,
        warnings: metrics.warningIssueCount,
      },
    };

    const statusCode =
      metrics.criticalIssueCount === 0 ? 200 : 503;
    res.status(statusCode).json(status);
  } catch (error) {
    console.error('Error checking health:', error);
    res.status(500).json({ error: 'Failed to check health' });
  }
});

export default router;
