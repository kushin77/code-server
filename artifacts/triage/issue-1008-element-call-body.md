## P2: Element Call (MatrixRTC) Fallback Integration

### Summary

Integrate Element Call (MatrixRTC) as a zero-cost voice/video fallback when Google Meet is unavailable or when teams prefer a native Matrix-based solution.

### Why Element Call

| Benefit | Description |
|---------|-------------|
| **Native Matrix** | No external dependency, works with any Matrix client |
| **Zero Cost** | No per-user licensing (unlike Zoom/Teams) |
| **E2EE** | End-to-end encrypted voice/video |
| **Fallback** | Works even if Google/Slack/Teams is down |
| **Self-Hosted** | Full sovereignty over call data |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ code-server IDE - Team Hub Sidebar                              │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Quick Actions                                               │ │
│ │ [📞 Start Meet] [🎤 Voice Call] ← Element Call              │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Element Call (MatrixRTC)                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • WebRTC-based voice/video                              │   │
│  │ • SFU (Selective Forwarding Unit) for scaling           │   │
│  │ • E2EE using MLS (Messaging Layer Security)             │   │
│  │ • Integrated with Matrix room membership                │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LiveKit SFU                                  │
│  (Self-hosted or Element-managed)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • WebRTC media routing                                  │   │
│  │ • Scales to 100+ participants                           │   │
│  │ • Low latency voice/video                               │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Components

1. **Element Call Widget**: Embeddable WebRTC widget
2. **LiveKit SFU**: Media server for multi-party calls
3. **JWT Authentication**: For call room access control

### Docker Configuration

```yaml
# docker-compose.yml additions

livekit:
  image: livekit/livekit-server:latest
  container_name: livekit
  restart: unless-stopped
  ports:
    - "7880:7880"    # WebSocket
    - "7881:7881"    # HTTP API
    - "7882:7882/udp" # WebRTC UDP
  environment:
    LIVEKIT_KEYS: "devkey: ${LIVEKIT_SECRET}"
  networks:
    - net-app

element-call:
  image: vectorim/element-call:latest
  container_name: element-call
  restart: unless-stopped
  environment:
    LIVEKIT_URL: ws://livekit:7880
    MATRIX_HOMESERVER: https://matrix.kushnir.cloud
  ports:
    - "8585:80"
  networks:
    - net-app
  depends_on:
    - livekit
    - synapse
```

### Extension Integration

```typescript
// extensions/team-hub/src/elementCall.ts

interface CallOptions {
  roomId: string;
  displayName: string;
  audioOnly?: boolean;
}

export async function startElementCall(options: CallOptions): Promise<void> {
  const callWidget = document.createElement('iframe');
  callWidget.src = `${ELEMENT_CALL_URL}/room/${options.roomId}?displayName=${options.displayName}&audioOnly=${options.audioOnly}`;
  callWidget.style.cssText = 'position:fixed;top:0;right:0;width:400px;height:300px;z-index:9999;';
  
  document.body.appendChild(callWidget);
  
  // Notify Matrix room
  await matrixClient.sendMessage(options.roomId, {
    msgtype: 'm.text',
    body: `📞 ${options.displayName} started a voice call. Click to join: ${ELEMENT_CALL_URL}/room/${options.roomId}`
  });
}
```

### Caddyfile Configuration

```caddy
# Add Element Call routing

call.kushnir.cloud {
    reverse_proxy element-call:80
}

# LiveKit WebSocket
wss://livekit.kushnir.cloud {
    reverse_proxy livekit:7880
}
```

### Acceptance Criteria

- [ ] LiveKit SFU deployed
- [ ] Element Call widget accessible
- [ ] "Voice Call" button in Team Hub extension
- [ ] Click starts Element Call in overlay/popup
- [ ] Call link posted to Matrix room
- [ ] Works without Google/Slack/Teams access
- [ ] E2EE enabled for calls
- [ ] Audio-only mode available
- [ ] Scales to 10+ concurrent participants

### Terraform Configuration

```hcl
# terraform/modules/element-call/main.tf

resource "docker_container" "livekit" {
  name  = "livekit"
  image = "livekit/livekit-server:latest"
  # ... configuration
}

resource "docker_container" "element_call" {
  name  = "element-call"
  image = "vectorim/element-call:latest"
  # ... configuration
}
```

### Dependencies

- Requires: #1001 (Matrix homeserver)
- Requires: #1002 (Team Hub extension)
- Nice-to-have, not blocking Google Meet (#1007)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
