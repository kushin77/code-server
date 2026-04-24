// @file        apps/presence-sidecar/src/index.ts
// @module      collaboration/presence-sidecar
// @description Real-time team presence tracking WebSocket service
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { createClient } from 'matrix-js-sdk';
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
// Initialize services
const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });
const matrixClient = createClient({
    baseUrl: MATRIX_HOMESERVER_URL,
    accessToken: MATRIX_ACCESS_TOKEN,
    userId: `@presence-bot:${MATRIX_HOMESERVER_URL.replace(/https?:\/\//, '')}`
});
// Redis clients for pub/sub (for scaled deployments)
const redisPub = new Redis(REDIS_URL);
const redisSub = new Redis(REDIS_URL);
const PRESENCE_SNAPSHOT_KEY = 'presence:snapshot';
const PRESENCE_SNAPSHOT_TTL_SECONDS = 4 * 60 * 60;
// In-memory state
const presenceState = new Map();
const clientSessions = new Map();
// Extract user from WebSocket authentication
function extractUserFromToken(req) {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace(/^Bearer /, '');
    // Validate token (simplified - in production use matrix SDK token validation)
    if (!token || token.length < 20) {
        throw new Error('Invalid authorization token');
    }
    return token; // Should be @username:homeserver from Matrix
}
// Set user away after inactivity
function scheduleAwayTimeout(userId, session) {
    if (session.inactivityTimer) {
        clearTimeout(session.inactivityTimer);
    }
    session.inactivityTimer = setTimeout(() => {
        const previous = presenceState.get(userId);
        const update = {
            ...previous,
            type: 'presence_update',
            userId,
            displayName: previous?.displayName || userId,
            status: 'away',
            timestamp: Date.now()
        };
        handlePresenceUpdate(update);
    }, AWAY_TIMEOUT_MS);
}
// Broadcast to all connected clients
function broadcast(message) {
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
async function persistPresenceSnapshot() {
    const snapshot = {
        users: Array.from(presenceState.values()),
        updatedAt: Date.now()
    };
    await redisPub.set(PRESENCE_SNAPSHOT_KEY, JSON.stringify(snapshot), 'EX', PRESENCE_SNAPSHOT_TTL_SECONDS);
}
async function restorePresenceSnapshot() {
    try {
        const rawSnapshot = await redisPub.get(PRESENCE_SNAPSHOT_KEY);
        if (!rawSnapshot) {
            return;
        }
        const parsed = JSON.parse(rawSnapshot);
        const users = Array.isArray(parsed) ? parsed : parsed.users;
        if (!Array.isArray(users)) {
            return;
        }
        presenceState.clear();
        users.forEach((user) => {
            presenceState.set(user.userId, user);
        });
        console.log(`Restored ${presenceState.size} presence records from Redis`);
    }
    catch (error) {
        console.error(`Failed to restore presence snapshot from Redis: ${error}`);
    }
}
// Publish to Redis for scaled deployment
function publishToRedis(message) {
    redisPub.publish('presence:updates', JSON.stringify(message));
}
// Handle presence update
async function handlePresenceUpdate(update) {
    presenceUpdatesTotal.labels(update.status).inc();
    const mergedUpdate = {
        ...presenceState.get(update.userId),
        ...update
    };
    presenceState.set(update.userId, mergedUpdate);
    // Broadcast to all connected clients (local and remote via Redis)
    broadcast(mergedUpdate);
    publishToRedis(mergedUpdate);
    await persistPresenceSnapshot();
    // Persist to Matrix room state
    try {
        const stateEvent = {
            users: Object.fromEntries(presenceState)
        };
        await matrixClient.sendStateEvent(MATRIX_PRESENCE_ROOM_ID, 'm.room.presence.workspace', stateEvent, '' // State key
        );
        console.log(`Persisted presence state for ${update.userId}`);
    }
    catch (error) {
        console.error(`Failed to persist presence to Matrix: ${error}`);
    }
}
// Set user offline
function setUserOffline(userId) {
    const session = clientSessions.get(userId);
    if (session?.inactivityTimer) {
        clearTimeout(session.inactivityTimer);
    }
    clientSessions.delete(userId);
    const update = {
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
    let userId;
    try {
        userId = extractUserFromToken(req);
        console.log(`User ${userId} connected`);
    }
    catch (error) {
        console.error(`Connection rejected: ${error}`);
        ws.close(4001, 'Unauthorized');
        return;
    }
    // Register session
    const session = {
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
            const update = JSON.parse(data.toString());
            update.userId = userId;
            update.timestamp = Date.now();
            // Update session activity
            session.lastActivity = Date.now();
            scheduleAwayTimeout(userId, session);
            handlePresenceUpdate(update);
        }
        catch (error) {
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
        const update = JSON.parse(message);
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
app.get('/snapshot', (req, res) => {
    const users = Array.from(presenceState.values());
    res.json({
        type: 'presence_state',
        timestamp: Date.now(),
        users,
        count: users.length
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
async function startServer() {
    await restorePresenceSnapshot();
    server.listen(PORT, '0.0.0.0', () => {
        console.log(`Presence Sidecar listening on port ${PORT}`);
        console.log(`WebSocket: ws://localhost:${PORT}`);
        console.log(`Health: http://localhost:${PORT}/health`);
        console.log(`Metrics: http://localhost:${PORT}/metrics`);
    });
}
void startServer().catch((error) => {
    console.error(`Failed to start presence sidecar: ${error}`);
    process.exit(1);
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
//# sourceMappingURL=index.js.map