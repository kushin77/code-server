## P2: Configure Google Chat Bidirectional Bridge

### Summary

Deploy and configure a Google Chat-Matrix bridge for bidirectional message sync. Note: Google Chat has limited API support compared to Slack/Teams.

### Challenges

| Challenge | Impact | Mitigation |
|-----------|--------|------------|
| No public presence API | Can't sync "typing" or online status | Accept limitation |
| Limited bot capabilities | Bots can only respond, not proactively message | Use webhook + bot hybrid |
| Workspace admin approval | Requires org-level app approval | Plan for admin coordination |

### Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                    Google Workspace                           │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Google Chat Space: Engineering                          │ │
│  │ • Messages, threads, reactions                          │ │
│  │ • Limited: No public presence API                       │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                               ↕ Google Chat API
┌───────────────────────────────────────────────────────────────┐
│                Google Chat-Matrix Bridge                      │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Message relay (bot + webhook hybrid)                  │ │
│  │ • @mention translation                                   │ │
│  │ • Thread ID mapping                                      │ │
│  │ • Reaction sync (limited)                                │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                               ↕ Matrix protocol
┌───────────────────────────────────────────────────────────────┐
│                    Matrix Homeserver                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ #engineering-chat:matrix.kushnir.cloud                   │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

### Bridge Options

| Option | Description | Recommendation |
|--------|-------------|----------------|
| **matrix-googlechat** | Community bridge | Limited maintenance |
| **Custom via Chat API** | Build webhook + bot | Most control |
| **SyncRivo** (SaaS) | Managed bridge | Easiest path |

### Google Cloud Setup

1. **Enable Chat API** in Google Cloud Console
2. **Create Chat App**:
   - Interactive app (receives events)
   - Add to target Google Chat space
3. **Service Account**:
   - Domain-wide delegation for sending as users
4. **Webhook** (incoming):
   - For Matrix → Google Chat messages

### Custom Bridge Implementation

```typescript
// apps/google-chat-bridge/src/index.ts

import { chat_v1, auth } from '@googleapis/chat';

const chatClient = new chat_v1.Chat({
  auth: new auth.GoogleAuth({
    keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    scopes: ['https://www.googleapis.com/auth/chat.bot']
  })
});

// Matrix → Google Chat
async function relayToGoogleChat(matrixMessage: MatrixMessage) {
  await chatClient.spaces.messages.create({
    parent: `spaces/${GOOGLE_CHAT_SPACE_ID}`,
    requestBody: {
      text: `${matrixMessage.sender}: ${matrixMessage.content}`
    }
  });
}

// Google Chat → Matrix (webhook handler)
app.post('/chat/events', async (req, res) => {
  const event = req.body;
  if (event.type === 'MESSAGE') {
    await matrixClient.sendMessage(MATRIX_ROOM_ID, {
      msgtype: 'm.text',
      body: event.message.text,
      formatted_body: formatGoogleChatMessage(event.message)
    });
  }
  res.json({ ok: true });
});
```

### Acceptance Criteria

- [ ] Google Chat API enabled in GCP
- [ ] Chat app created and added to workspace
- [ ] Service account configured with domain-wide delegation
- [ ] At least one space bridged
- [ ] Messages flow Google Chat → Matrix
- [ ] Messages flow Matrix → Google Chat
- [ ] @mentions work both directions
- [ ] Thread support (where possible)
- [ ] Admin approval obtained for workspace

### Environment Variables

```bash
# .env additions for Google Chat bridge
GOOGLE_CHAT_SPACE_ID=spaces/XXXXXX
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

### Limitations Documented

- No real-time presence (typing indicators, online status)
- Bot must be explicitly added to spaces
- Some message formatting may be lossy
- Workspace admin approval required

### Dependencies

- Requires: #1001 (Matrix homeserver deployed)
- Requires: Google Workspace admin access
- Lower priority than Slack (#1004)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
