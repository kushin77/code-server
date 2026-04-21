# @file        apps/presence-sidecar/src/index.ts
# @module      collaboration/presence-sidecar
# @description Real-time team presence tracking WebSocket service

import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { createClient, MatrixClient } from 'matrix-js-sdk';
import Redis from 'ioredis';
import express from 'express';
import promClient from 'prom-client';

// Configuration
const PORT = parseInt(process.env.PORT || '8089');
const MATRIX_HOMESERVER_URL = process.env.MATRIX_HOMESERVER_URL || 'https://matrix.kushnir.cloud';
const MATRIX_ACCESS_TOKEN = process.env.MATRIX_BOT_ACCESS_TOKEN || '';
const MATRIX_PRESENCE_ROOM_ID = process.env.MATRIX_PRESENCE_ROOM_ID || '';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const AWAY_TIMEOUT_MS = parseInt(process.env.PRESENCE_AWAY_TIMEOUT_MS || '300000'); // 5 min
const OFFLINE_TIMEOUT_MS = parseInt(process.env.PRESENCE_OFFLINE_TIMEOUT_MS || '900000'); // 15 min

// Metrics
const presenceUpdatesTotal = new promClient.Counter({
  name: 'presence_updates_total',
  help: 'Total number of presence updates processed',
  labelNames: ['status']
});

const connectedClientsGauge = new promClient.Gauge({
  name: 'connected_clients_total',
  help: 'Number of connected WebSocket clients'
});

const websocketLatencyHistogram = new promClient.Histogram({
  name: 'websocket_broadcast_latency_ms',
  help: 'Broadcast latency in milliseconds',
  buckets: [10, 50, 100, 250, 500, 1000]
});

// Data Models
interface PresenceUpdate {
  type: 'presence_update';
  userId: string;
  displayName: string;
  status: 'online' | 'away' | 'dnd' | 'offline';
  workspace?: string;
  file?: string;
  line?: number;
  character?: number;
  timestamp: number;
}

interface WorkspacePresenceState {
  users: {
    [userId: string]: {
      displayName: string;
      status: string;
      workspace?: string;
      file?: string;
      line?: number;
      lastSeen: number;
    };
  };
}

interface ClientSession {
  userId: string;
  ws: WebSocket;
  lastActivity: number;
  inactivityTimer?: NodeJS.Timeout;
}

// Initialize services
const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });
const matrixClient: MatrixClient = createClient({
  baseUrl: MATRIX_HOMESERVER_URL,
  accessToken: MATRIX_ACCESS_TOKEN,
  userId: `@presence-bot:${MATRIX_HOMESERVER_URL.replace(/https?:\/\//, '')}`
});

// Redis clients for pub/sub (for scaled deployments)
const redisPub = new Redis(REDIS_URL);
const redisSub = new Redis(REDIS_URL);

// In-memory state
const presenceState = new Map<string, PresenceUpdate>();
const clientSessions = new Map<string, ClientSession>();

// Extract user from WebSocket authentication
function extractUserFromToken(req: any): string {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.replace(/^Bearer /, '');
  
  // Validate token (simplified - in production use matrix SDK token validation)
  if (!token || token.length < 20) {
    throw new Error('Invalid authorization token');
  }
  
  return token; // Should be @username:homeserver from Matrix
}

// Set user away after inactivity
function scheduleAwayTimeout(userId: string, session: ClientSession) {
  if (session.inactivityTimer) {
    clearTimeout(session.inactivityTimer);
  }
  
  session.inactivityTimer = setTimeout(() => {
    const update: PresenceUpdate = {
      type: 'presence_update',
      userId,
      displayName: presenceState.get(userId)?.displayName || userId,
      status: 'away',
      timestamp: Date.now()
    };
    
    handlePresenceUpdate(update);
  }, AWAY_TIMEOUT_MS);
}

// Broadcast to all connected clients
function broadcast(message: any) {
  const startTime = Date.now();
  const payload = JSON.stringify(message);
  let successCount = 0;
  
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
      successCount++;
    }
  });
  
  const latency = Date.now() - startTime;
  websocketLatencyHistogram.observe(latency);
  
  console.log(`Broadcasted to ${successCount} clients (${latency}ms)`);
}

// Publish to Redis for scaled deployment
function publishToRedis(message: any) {
  redisPub.publish('presence:updates', JSON.stringify(message));
}

// Handle presence update
async function handlePresenceUpdate(update: PresenceUpdate) {
  presenceUpdatesTotal.labels(update.status).inc();
  
  presenceState.set(update.userId, update);
  
  // Broadcast to all connected clients (local and remote via Redis)
  broadcast(update);
  publishToRedis(update);
  
  // Persist to Matrix room state
  try {
    const stateEvent = {
      users: Object.fromEntries(presenceState)
    };
    
    await matrixClient.sendStateEvent(
      MATRIX_PRESENCE_ROOM_ID,
      'm.room.presence.workspace',
      stateEvent,
      '' // State key
    );
    
    console.log(`Persisted presence state for ${update.userId}`);
  } catch (error) {
    console.error(`Failed to persist presence to Matrix: ${error}`);
  }
}

// Set user offline
function setUserOffline(userId: string) {
  const session = clientSessions.get(userId);
  
  if (session?.inactivityTimer) {
    clearTimeout(session.inactivityTimer);
  }
  
  clientSessions.delete(userId);
  
  const update: PresenceUpdate = {
    type: 'presence_update',
    userId,
    displayName: presenceState.get(userId)?.displayName || userId,
    status: 'offline',
    timestamp: Date.now()
  };
  
  handlePresenceUpdate(update);
}

// WebSocket connection handler
wss.on('connection', (ws, req) => {
  let userId: string;
  
  try {
    userId = extractUserFromToken(req);
    console.log(`User ${userId} connected`);
  } catch (error) {
    console.error(`Connection rejected: ${error}`);
    ws.close(4001, 'Unauthorized');
    return;
  }
  
  // Register session
  const session: ClientSession = {
    userId,
    ws,
    lastActivity: Date.now()
  };
  clientSessions.set(userId, session);
  connectedClientsGauge.set(clientSessions.size);
  
  // Send initial state
  ws.send(JSON.stringify({
    type: 'initial_state',
    users: Array.from(presenceState.values())
  }));
  
  // Message handler
  ws.on('message', (data) => {
    try {
      const update = JSON.parse(data.toString()) as PresenceUpdate;
      update.userId = userId;
      update.timestamp = Date.now();
      
      // Update session activity
      session.lastActivity = Date.now();
      scheduleAwayTimeout(userId, session);
      
      handlePresenceUpdate(update);
    } catch (error) {
      console.error(`Invalid message from ${userId}: ${error}`);
      ws.send(JSON.stringify({ type: 'error', message: 'Invalid format' }));
    }
  });
  
  ws.on('error', (error) => {
    console.error(`WebSocket error for ${userId}: ${error}`);
  });
  
  ws.on('close', () => {
    console.log(`User ${userId} disconnected`);
    
    // Schedule offline after OFFLINE_TIMEOUT_MS
    const offlineTimer = setTimeout(() => {
      setUserOffline(userId);
    }, OFFLINE_TIMEOUT_MS);
    
    // Allow reconnect within timeout
    setTimeout(() => clearTimeout(offlineTimer), OFFLINE_TIMEOUT_MS);
  });
  
  // Schedule away timeout
  scheduleAwayTimeout(userId, session);
});

// Redis pub/sub for scaled deployment
redisSub.on('message', (channel, message) => {
  if (channel === 'presence:updates') {
    const update = JSON.parse(message) as PresenceUpdate;
    presenceState.set(update.userId, update);
    
    // Broadcast to local clients (excluding originator)
    const payload = JSON.stringify(update);
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(payload);
      }
    });
  }
});

redisSub.subscribe('presence:updates');

// Express health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    uptime: process.uptime(),
    connectedClients: clientSessions.size,
    presenceUpdates: presenceState.size
  });
});

// Prometheus metrics endpoint
app.get('/metrics', (req, res) => {
  res.set('Content-Type', promClient.register.contentType);
  res.end(promClient.register.metrics());
});

// REST fallback endpoint
app.get('/api/presence', (req, res) => {
  const users = Array.from(presenceState.values());
  res.json({
    type: 'presence_state',
    timestamp: Date.now(),
    users,
    count: users.length
  });
});

// Start server
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Presence Sidecar listening on port ${PORT}`);
  console.log(`WebSocket: ws://localhost:${PORT}`);
  console.log(`Health: http://localhost:${PORT}/health`);
  console.log(`Metrics: http://localhost:${PORT}/metrics`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Shutting down gracefully...');
  
  // Close all WebSocket connections
  wss.clients.forEach((client) => {
    client.close(1000, 'Server shutdown');
  });
  
  // Close server
  server.close();
  
  // Close Redis connections
  await redisPub.quit();
  await redisSub.quit();
  
  process.exit(0);
});
