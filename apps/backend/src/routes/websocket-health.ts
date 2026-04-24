#!/usr/bin/env node
// @file        apps/backend/src/routes/websocket-health.ts
// @module      routes
// @description REST API routes for WebSocket health monitoring

import { Router, Request, Response } from 'express';
import service, { ConnectionHealth, ConnectionType } from '../services/monitoring/websocket-health-service';
import { getLogger } from '../lib/logger';

const logger = getLogger('WebSocketHealthRoutes');
const router = Router();

/**
 * Serialize connection for JSON response
 */
function serializeConnection(connection: ConnectionHealth): any {
  return {
    connectionId: connection.connectionId,
    type: connection.type,
    userId: connection.userId,
    workspaceId: connection.workspaceId,
    connected: connection.connected,
    qualityScore: connection.qualityScore,
    latency: connection.latency,
    jitter: connection.jitter,
    packetLoss: connection.packetLoss,
    lastPingTime: connection.lastPingTime,
    lastPongTime: connection.lastPongTime,
    lastQualityUpdate: connection.lastQualityUpdate,
    reconnectAttempts: connection.reconnectAttempts,
    lastReconnectTime: connection.lastReconnectTime,
    createdAt: connection.createdAt,
    metrics: connection.metrics,
  };
}

/**
 * POST /api/websocket-health/register
 * Register a new WebSocket connection
 */
router.post('/register', (req: Request, res: Response) => {
  try {
    const { connectionId, type, userId, workspaceId } = req.body;

    if (!connectionId || !type || !userId || !workspaceId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: connectionId, type, userId, workspaceId',
      });
    }

    const validTypes: ConnectionType[] = ['collaboration', 'presence', 'voice-signaling', 'session-broker'];
    if (!validTypes.includes(type)) {
      return res.status(400).json({
        success: false,
        error: `Invalid connection type. Must be one of: ${validTypes.join(', ')}`,
      });
    }

    const health = service.registerConnection(connectionId, type, userId, workspaceId);

    return res.status(201).json({
      success: true,
      data: serializeConnection(health),
    });
  } catch (error) {
    logger.error('Error registering connection', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to register connection',
    });
  }
});

/**
 * GET /api/websocket-health/connections/:id
 * Get connection health by ID
 */
router.get('/connections/:id', (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const health = service.getConnection(id);

    if (!health) {
      return res.status(404).json({
        success: false,
        error: 'Connection not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: serializeConnection(health),
    });
  } catch (error) {
    logger.error('Error retrieving connection', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to retrieve connection',
    });
  }
});

/**
 * GET /api/websocket-health/user/:userId/connections
 * Get all connections for a user
 */
router.get('/user/:userId/connections', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const connections = service.getConnectionsForUser(userId);

    return res.status(200).json({
      success: true,
      data: connections.map(serializeConnection),
    });
  } catch (error) {
    logger.error('Error retrieving user connections', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to retrieve user connections',
    });
  }
});

/**
 * GET /api/websocket-health/type/:type
 * Get all connections by type
 */
router.get('/type/:type', (req: Request, res: Response) => {
  try {
    const { type } = req.params;

    const validTypes: ConnectionType[] = ['collaboration', 'presence', 'voice-signaling', 'session-broker'];
    if (!validTypes.includes(type as ConnectionType)) {
      return res.status(400).json({
        success: false,
        error: `Invalid connection type. Must be one of: ${validTypes.join(', ')}`,
      });
    }

    const connections = service.getConnectionsByType(type as ConnectionType);

    return res.status(200).json({
      success: true,
      data: connections.map(serializeConnection),
    });
  } catch (error) {
    logger.error('Error retrieving connections by type', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to retrieve connections',
    });
  }
});

/**
 * GET /api/websocket-health/degraded
 * Get degraded connections
 */
router.get('/degraded', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.query;

    const degraded = service.getDegradedConnections(workspaceId as string | undefined);

    return res.status(200).json({
      success: true,
      data: degraded.map(serializeConnection),
    });
  } catch (error) {
    logger.error('Error retrieving degraded connections', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to retrieve degraded connections',
    });
  }
});

/**
 * GET /api/websocket-health/workspace/:workspaceId/stats
 * Get workspace health statistics
 */
router.get('/workspace/:workspaceId/stats', (req: Request, res: Response) => {
  try {
    const { workspaceId } = req.params;
    const stats = service.getWorkspaceStats(workspaceId);

    return res.status(200).json({
      success: true,
      data: stats,
    });
  } catch (error) {
    logger.error('Error retrieving workspace stats', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to retrieve workspace stats',
    });
  }
});

/**
 * GET /api/websocket-health/system/health
 * Get system-wide health summary
 */
router.get('/system/health', (req: Request, res: Response) => {
  try {
    const health = service.getSystemHealth();

    return res.status(200).json({
      success: true,
      data: health,
    });
  } catch (error) {
    logger.error('Error retrieving system health', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to retrieve system health',
    });
  }
});

/**
 * PATCH /api/websocket-health/connections/:id/ping
 * Record ping sent
 */
router.patch('/connections/:id/ping', (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const health = service.recordPingSent(id);

    if (!health) {
      return res.status(404).json({
        success: false,
        error: 'Connection not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: serializeConnection(health),
    });
  } catch (error) {
    logger.error('Error recording ping', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to record ping',
    });
  }
});

/**
 * PATCH /api/websocket-health/connections/:id/pong
 * Record pong received and update latency
 */
router.patch('/connections/:id/pong', (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const health = service.recordPongReceived(id);

    if (!health) {
      return res.status(404).json({
        success: false,
        error: 'Connection not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: serializeConnection(health),
    });
  } catch (error) {
    logger.error('Error recording pong', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to record pong',
    });
  }
});

/**
 * PATCH /api/websocket-health/connections/:id/packet-loss
 * Record packet loss percentage
 */
router.patch('/connections/:id/packet-loss', (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { lossPercentage } = req.body;

    if (typeof lossPercentage !== 'number') {
      return res.status(400).json({
        success: false,
        error: 'lossPercentage must be a number',
      });
    }

    const health = service.recordPacketLoss(id, lossPercentage);

    if (!health) {
      return res.status(404).json({
        success: false,
        error: 'Connection not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: serializeConnection(health),
    });
  } catch (error) {
    logger.error('Error recording packet loss', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to record packet loss',
    });
  }
});

/**
 * POST /api/websocket-health/connections/:id/disconnect
 * Mark connection as disconnected
 */
router.post('/connections/:id/disconnect', (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const health = service.markDisconnected(id);

    if (!health) {
      return res.status(404).json({
        success: false,
        error: 'Connection not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: serializeConnection(health),
    });
  } catch (error) {
    logger.error('Error marking connection as disconnected', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to disconnect',
    });
  }
});

/**
 * POST /api/websocket-health/connections/:id/reconnect
 * Attempt reconnection
 */
router.post('/connections/:id/reconnect', (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const health = service.attemptReconnection(id);

    if (!health) {
      return res.status(404).json({
        success: false,
        error: 'Connection not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: serializeConnection(health),
    });
  } catch (error) {
    logger.error('Error attempting reconnection', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to attempt reconnection',
    });
  }
});

/**
 * POST /api/websocket-health/connections/:id/reconnect-success
 * Mark reconnection as successful
 */
router.post('/connections/:id/reconnect-success', (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const health = service.reconnectionSuccessful(id);

    if (!health) {
      return res.status(404).json({
        success: false,
        error: 'Connection not found',
      });
    }

    return res.status(200).json({
      success: true,
      data: serializeConnection(health),
    });
  } catch (error) {
    logger.error('Error marking reconnection successful', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to mark reconnection successful',
    });
  }
});

/**
 * DELETE /api/websocket-health/connections/:id
 * Unregister and cleanup connection
 */
router.delete('/connections/:id', (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const health = service.getConnection(id);

    if (!health) {
      return res.status(404).json({
        success: false,
        error: 'Connection not found',
      });
    }

    service.unregisterConnection(id);

    return res.status(200).json({
      success: true,
      data: { connectionId: id },
    });
  } catch (error) {
    logger.error('Error unregistering connection', { error });
    return res.status(500).json({
      success: false,
      error: 'Failed to unregister connection',
    });
  }
});

export default router;
