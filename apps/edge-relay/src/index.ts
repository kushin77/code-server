// @file        apps/edge-relay/src/index.ts
// @module      infrastructure/edge-relay
// @description Lightweight WebSocket proxy for geographic edge relay nodes

import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import express from 'express';
import promClient from 'prom-client';

// Configuration
const PORT = parseInt(process.env.PORT || '8090');
const PRIMARY_WS_URL = process.env.PRIMARY_WS_URL || 'ws://localhost:8089';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const REGION_ID = process.env.REGION_ID || 'unknown';
const RELAY_ID = process.env.RELAY_ID || `relay-${REGION_ID}-${Date.now()}`;

// Metrics
const connectionsTotal = new promClient.Counter({
  name: 'edge_relay_connections_total',
  help: 'Total number of WebSocket connections handled',
  labelNames: ['direction']
});

const activeConnectionsGauge = new promClient.Gauge({
  name: 'edge_relay_active_connections',
  help: 'Number of active WebSocket connections'
});

const connectionLatencyHistogram = new promClient.Histogram({
  name: 'edge_relay_connection_latency_ms',
  help: 'Connection establishment latency in milliseconds',
  buckets: [10, 25, 50, 100, 250, 500]
});

const messageRelayCounter = new promClient.Counter({
  name: 'edge_relay_messages_relayed_total',
  help: 'Total number of messages relayed',
  labelNames: ['direction']
});

// Express app for health checks and metrics
const app = express();

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    region: REGION_ID,
    relayId: RELAY_ID,
    timestamp: new Date().toISOString()
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  try {
    const metrics = await promClient.register.metrics();
    res.set('Content-Type', promClient.register.contentType);
    res.end(metrics);
  } catch (error) {
    res.status(500).end(error);
  }
});

// WebSocket proxy server
const server = createServer(app);
const wss = new WebSocketServer({ server });

// Connection tracking
const activeConnections = new Map<string, {
  client: WebSocket;
  upstream: WebSocket;
  startTime: number;
}>();

function generateConnectionId(): string {
  return `conn_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

wss.on('connection', (clientWs: WebSocket, req) => {
  const connectionId = generateConnectionId();
  const startTime = Date.now();

  connectionsTotal.inc({ direction: 'inbound' });
  activeConnectionsGauge.inc();

  console.log(`[${connectionId}] New client connection from ${req.socket.remoteAddress}`);

  // Connect to upstream server
  const upstreamWs = new WebSocket(PRIMARY_WS_URL);

  upstreamWs.on('open', () => {
    const latency = Date.now() - startTime;
    connectionLatencyHistogram.observe(latency);
    console.log(`[${connectionId}] Upstream connection established in ${latency}ms`);

    // Store connection info
    activeConnections.set(connectionId, {
      client: clientWs,
      upstream: upstreamWs,
      startTime
    });

    // Relay messages from client to upstream
    clientWs.on('message', (data) => {
      if (upstreamWs.readyState === WebSocket.OPEN) {
        upstreamWs.send(data);
        messageRelayCounter.inc({ direction: 'client_to_upstream' });
      }
    });

    // Relay messages from upstream to client
    upstreamWs.on('message', (data) => {
      if (clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(data);
        messageRelayCounter.inc({ direction: 'upstream_to_client' });
      }
    });
  });

  upstreamWs.on('error', (error) => {
    console.error(`[${connectionId}] Upstream connection error:`, error.message);
    if (clientWs.readyState === WebSocket.OPEN) {
      clientWs.close(1011, 'Upstream connection failed');
    }
  });

  upstreamWs.on('close', (code, reason) => {
    console.log(`[${connectionId}] Upstream connection closed: ${code} ${reason}`);
    if (clientWs.readyState === WebSocket.OPEN) {
      clientWs.close(code, reason);
    }
  });

  clientWs.on('close', (code, reason) => {
    console.log(`[${connectionId}] Client connection closed: ${code} ${reason}`);
    if (upstreamWs.readyState === WebSocket.OPEN) {
      upstreamWs.close(code, reason);
    }
    activeConnections.delete(connectionId);
    activeConnectionsGauge.dec();
  });

  clientWs.on('error', (error) => {
    console.error(`[${connectionId}] Client connection error:`, error.message);
    if (upstreamWs.readyState === WebSocket.OPEN) {
      upstreamWs.close(1002, 'Client error');
    }
    activeConnections.delete(connectionId);
    activeConnectionsGauge.dec();
  });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Received SIGTERM, shutting down gracefully...');

  // Close all active connections
  for (const [connectionId, connection] of activeConnections) {
    connection.client.close(1001, 'Server shutdown');
    connection.upstream.close(1001, 'Server shutdown');
  }

  server.close(() => {
    console.log('Server shut down');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('Received SIGINT, shutting down gracefully...');
  process.exit(0);
});

// Start server
server.listen(PORT, () => {
  console.log(`Edge relay ${RELAY_ID} listening on port ${PORT}`);
  console.log(`Region: ${REGION_ID}`);
  console.log(`Primary WS URL: ${PRIMARY_WS_URL}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log(`Metrics: http://localhost:${PORT}/metrics`);
});