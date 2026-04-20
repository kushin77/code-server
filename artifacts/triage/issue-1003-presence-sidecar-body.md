## P1: Deploy Real-Time Presence Sidecar Service

### Summary

Deploy a lightweight Node.js service that tracks user presence (online/away/offline, current file, line number) and broadcasts updates to all connected code-server instances via WebSocket.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Presence Sidecar Service                     │
│                    (Node.js + Matrix SDK)                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   WebSocket Server                       │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │   │
│  │  │ Connection  │  │ Presence    │  │ Broadcast       │  │   │
│  │  │ Manager     │  │ Aggregator  │  │ Engine          │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │               Matrix State Event Sync                     │ │
│  │  Persists presence to Matrix room state for durability    │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
        │                      │                      │
        ▼                      ▼                      ▼
┌─────────────┐        ┌─────────────┐        ┌─────────────┐
│ code-server │        │ code-server │        │ code-server │
│ Instance 1  │        │ Instance 2  │        │ Instance N  │
└─────────────┘        └─────────────┘        └─────────────┘
```

### Data Model

```typescript
// Presence state event schema
interface PresenceUpdate {
  type: 'presence_update';
  userId: string;
  displayName: string;
  status: 'online' | 'away' | 'dnd' | 'offline';
  workspace: string;        // Workspace ID or name
  file?: string;            // Current file path (relative)
  line?: number;            // Current cursor line
  timestamp: number;        // Unix timestamp
}

// Room state event (Matrix m.room.presence.workspace)
interface WorkspacePresenceState {
  users: {
    [userId: string]: {
      displayName: string;
      status: string;
      workspace: string;
      file?: string;
      line?: number;
      lastSeen: number;
    };
  };
}
```

### Service Implementation

```typescript
// apps/presence-sidecar/src/index.ts

import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { createClient, MatrixClient } from 'matrix-js-sdk';

const wss = new WebSocketServer({ server: createServer() });
const presenceState = new Map<string, PresenceUpdate>();

// Broadcast to all connected clients
function broadcast(message: PresenceUpdate) {
  const payload = JSON.stringify(message);
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
    }
  });
}

wss.on('connection', (ws, req) => {
  const userId = extractUserFromToken(req);
  
  ws.on('message', (data) => {
    const update = JSON.parse(data.toString()) as PresenceUpdate;
    update.userId = userId;
    update.timestamp = Date.now();
    
    presenceState.set(userId, update);
    broadcast(update);
    syncToMatrix(update); // Persist to Matrix room state
  });

  ws.on('close', () => {
    setUserOffline(userId);
  });

  // Send current state on connect
  ws.send(JSON.stringify({
    type: 'initial_state',
    users: Array.from(presenceState.values())
  }));
});
```

### Docker Configuration

```yaml
# docker-compose.yml addition

presence-sidecar:
  build:
    context: ./apps/presence-sidecar
    dockerfile: Dockerfile
  container_name: presence-sidecar
  restart: unless-stopped
  environment:
    MATRIX_HOMESERVER_URL: ${MATRIX_HOMESERVER_URL}
    MATRIX_ACCESS_TOKEN: ${MATRIX_BOT_ACCESS_TOKEN}
    MATRIX_PRESENCE_ROOM_ID: ${MATRIX_PRESENCE_ROOM_ID}
    PORT: 8089
    LOG_LEVEL: info
  ports:
    - "8089:8089"
  networks:
    - net-app
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8089/health"]
    interval: 30s
    timeout: 10s
    retries: 3
  depends_on:
    - redis
```

### Scaling Strategy

| Scale | Architecture |
|-------|--------------|
| **Small (1-10 users)** | Single instance, in-memory state |
| **Medium (10-100 users)** | Single instance, Redis-backed state |
| **Large (100+ users)** | Multiple instances behind LB, Redis pub/sub |

```typescript
// For scaled deployment, use Redis pub/sub
import Redis from 'ioredis';

const pub = new Redis(process.env.REDIS_URL);
const sub = new Redis(process.env.REDIS_URL);

sub.subscribe('presence:updates');
sub.on('message', (channel, message) => {
  broadcast(JSON.parse(message));
});

function publishPresence(update: PresenceUpdate) {
  pub.publish('presence:updates', JSON.stringify(update));
}
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check for K8s probes |
| `/metrics` | GET | Prometheus metrics export |
| `/api/presence` | GET | Current presence state (REST fallback) |
| `ws://` | WebSocket | Real-time presence connection |

### Acceptance Criteria

- [ ] Service deploys in docker-compose
- [ ] WebSocket connections established from code-server extension
- [ ] Presence updates broadcast <500ms
- [ ] State persisted to Matrix room (survives restart)
- [ ] Auto-away after 5 min inactivity
- [ ] Auto-offline after 15 min disconnect
- [ ] Health endpoint for container orchestration
- [ ] Prometheus metrics exported
- [ ] Scales horizontally with Redis pub/sub
- [ ] Unit tests + integration tests

### Environment Variables

```bash
# .env additions
MATRIX_HOMESERVER_URL=https://matrix.kushnir.cloud
MATRIX_BOT_ACCESS_TOKEN=<bot-access-token>
MATRIX_PRESENCE_ROOM_ID=!roomid:matrix.kushnir.cloud
PRESENCE_SIDECAR_PORT=8089
PRESENCE_AWAY_TIMEOUT_MS=300000    # 5 min
PRESENCE_OFFLINE_TIMEOUT_MS=900000 # 15 min
```

### Dependencies

- Requires: #1001 (Matrix architecture - need homeserver URL)
- Requires: #957 (Redis HA - for scaled pub/sub)
- Blocks: #1002 (Team Hub extension - needs presence backend)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
