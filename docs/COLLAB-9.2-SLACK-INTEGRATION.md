# Slack Slash Command Integration - Implementation Guide

## Overview

This document describes the implementation of the **Slack `/share-ide` slash command** (Collab-9.2), which enables users to launch temporary shared IDE sessions directly from Slack channels.

## Features

- ✅ **Slash Command**: `/share-ide [optional: repository path]`
- ✅ **Session Management**: Automatic TTL-based expiration (24 hours)
- ✅ **Real-time Sharing**: Instant shareable links with copy-to-clipboard
- ✅ **Rich Formatting**: Slack Block Kit with buttons and interactive elements
- ✅ **Admin Controls**: Revoke sessions via admin API
- ✅ **Multi-channel Support**: Track sessions per Slack channel
- ✅ **Fallback Handling**: Graceful degradation if API unavailable

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│                          Slack Workspace                         │
├─────────────────────────────────────────────────────────────────┤
│  User types: /share-ide /src/components                          │
│  ↓                                                               │
│  Slack processes command request                                 │
│  ↓                                                               │
└─────────────────────────────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────────────────────────────┐
│                       code-server Backend                        │
├─────────────────────────────────────────────────────────────────┤
│  POST /api/slack/commands/share-ide                             │
│  ↓                                                               │
│  verifySlackRequest() [HMAC signature check]                    │
│  ↓                                                               │
│  createSharedSession() [Generate session + store in Redis]      │
│  ↓                                                               │
│  Format response with Slack Block Kit                           │
│  ↓                                                               │
│  Return 200 with formatted message                              │
└─────────────────────────────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Redis (Session Store)                         │
├─────────────────────────────────────────────────────────────────┤
│  Key: slack:session:{sessionId}                                 │
│  Value: { sessionId, createdBy, expiresAt, shareUrl, ... }     │
│  TTL: 86400 seconds (24 hours)                                  │
│                                                                 │
│  Key: slack:channel:{channelId}:sessions                        │
│  Value: [sessionId1, sessionId2, ...]                           │
└─────────────────────────────────────────────────────────────────┘
```

### Request/Response Flow

**Request**:
```bash
POST https://api.kushnir.cloud/api/slack/commands/share-ide
Content-Type: application/x-www-form-urlencoded
X-Slack-Signature: v0=<signature>
X-Slack-Request-Timestamp: <timestamp>

command=/share-ide&
user_id=U12345678&
user_name=alice&
team_id=T12345678&
channel_id=C12345678&
text=/src/components&
response_url=https://hooks.slack.com/commands/...&
trigger_id=...
```

**Response** (Block Kit):
```json
{
  "response_type": "in_channel",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "🚀 <@U12345678> launched a shared IDE session!"
      }
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Session ID:*\n`abc123xyz`"
        },
        {
          "type": "mrkdwn",
          "text": "*Expires:*\n<!date^1713574800^{date_long_pretty} at {time}|...>"
        }
      ]
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": { "type": "plain_text", "text": "Join Session", "emoji": true },
          "url": "https://ide.kushnir.cloud/share/abc123xyz",
          "style": "primary"
        }
      ]
    }
  ]
}
```

## Setup Instructions

### Step 1: Create Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **"Create New App"** → **"From scratch"**
3. **App name**: `IDE Session Launcher`
4. **Workspace**: Select your Slack workspace
5. Click **"Create App"**

### Step 2: Configure Slash Command

1. Go to **"Slash Commands"** in the sidebar
2. Click **"Create New Command"**
3. Fill in:
   - **Command**: `/share-ide`
   - **Request URL**: `https://api.kushnir.cloud/api/slack/commands/share-ide`
   - **Short Description**: `Launch a temporary shared IDE session`
   - **Usage hint**: `[optional: repository path]`
   - **Escape channels, users, and teams in command text**: OFF
4. Click **"Save"**

### Step 3: Configure OAuth

1. Go to **"OAuth & Permissions"** in the sidebar
2. Under **"Scopes"** → **"Bot Token Scopes"**, add:
   - `commands`
   - `chat:write`
   - `users:read`
   - `team:read`
   - `app_mentions:read`
   - `reactions:read`
3. Under **"Redirect URLs"**, add:
   - `https://api.kushnir.cloud/api/slack/oauth/callback`
4. Scroll to top and click **"Install to Workspace"**
5. Copy the **Bot User OAuth Token** (starts with `xoxb-`)

### Step 4: Configure Environment Variables

Add to `.env` or your deployment configuration:

```bash
# Slack Bot Configuration
SLACK_BOT_TOKEN=xoxb-your-token-here
SLACK_SIGNING_SECRET=your-signing-secret-here
SLACK_ADMIN_SECRET=your-admin-secret-here  # For admin APIs

# Session Configuration
SLACK_SESSION_TTL_SECONDS=86400  # 24 hours
IDE_BASE_URL=https://ide.kushnir.cloud

# Redis Configuration
REDIS_URL=redis://localhost:6379
```

**Finding Signing Secret**:
1. In your Slack app settings, go to **"Basic Information"**
2. Scroll to **"App Credentials"**
3. Copy the **Signing Secret**

### Step 5: Mount Routes in Backend

In `apps/backend/src/index.ts`:

```typescript
import slackRouter from './routes/slack.js';

// Mount Slack integration routes
app.use('/api/slack', slackRouter);
```

### Step 6: Deploy

```bash
# Build backend
npm run build

# Deploy to production
docker compose up -d

# Verify health
curl https://api.kushnir.cloud/api/slack/health
```

## API Endpoints

### Create Shared Session (Slack Command)

```
POST /api/slack/commands/share-ide
Content-Type: application/x-www-form-urlencoded
X-Slack-Signature: v0=<signature>
X-Slack-Request-Timestamp: <timestamp>
```

**Response**: Slack Block Kit message (in_channel)

**Errors**:
- `401`: Invalid Slack signature
- `400`: Invalid command format
- `500`: Server error

---

### Get Session Info

```
GET /api/slack/sessions/:sessionId
```

**Response**:
```json
{
  "sessionId": "uuid",
  "createdBy": {
    "userId": "U12345678",
    "userName": "alice",
    "teamId": "T12345678"
  },
  "createdAt": 1713488400000,
  "expiresAt": 1713574800000,
  "shareUrl": "https://ide.kushnir.cloud/share/uuid",
  "channelId": "C12345678",
  "repositoryPath": "/src/components"
}
```

---

### List Channel Sessions

```
GET /api/slack/channels/:channelId/sessions
```

**Response**:
```json
{
  "channelId": "C12345678",
  "sessions": [ /* array of session objects */ ],
  "count": 2
}
```

---

### Revoke Session (Admin)

```
DELETE /api/slack/sessions/:sessionId
X-Admin-Secret: <admin-secret>
```

**Response**:
```json
{
  "success": true,
  "message": "Session revoked"
}
```

**Errors**:
- `401`: Invalid admin secret
- `404`: Session not found
- `500`: Server error

---

### Health Check

```
GET /api/slack/health
```

**Response**:
```json
{
  "status": "ok",
  "service": "slack-integration",
  "timestamp": "2024-04-20T10:30:45.123Z"
}
```

## Frontend Integration

### Displaying Sessions

Use the `SharedSessionModal` component:

```typescript
import { SharedSessionModal } from '@/components/shared-session-modal';

function App() {
  const [session, setSession] = useState<SharedSession | null>(null);

  return (
    <SharedSessionModal
      open={!!session}
      session={session}
      onClose={() => setSession(null)}
      onRevoke={async (sessionId) => {
        await fetch(`/api/slack/sessions/${sessionId}`, {
          method: 'DELETE',
          headers: { 'X-Admin-Secret': adminSecret },
        });
      }}
    />
  );
}
```

### Features

- Copy session URL to clipboard
- Display expiration countdown
- Show created-by information
- Join button (opens shared session)
- Admin revoke button
- Auto-hide copy confirmation

## Security Considerations

### Request Verification

All Slack requests are verified using HMAC-SHA256:

```typescript
const baseString = `v0:${timestamp}:${body}`;
const hash = createHmac('sha256', signingSecret)
  .update(baseString)
  .digest('hex');
```

### Timestamp Validation

Requests older than 5 minutes are rejected to prevent replay attacks.

### Session Isolation

- Sessions are per-channel
- Session IDs are UUIDs (cryptographically random)
- Session data includes initiator info (audit trail)

### Admin APIs

Admin endpoints require `X-Admin-Secret` header for sensitive operations (revoke).

## Session Lifecycle

### Creation
```
User types: /share-ide /src/components
↓
Slack sends request to webhook
↓
Backend generates UUID + stores in Redis (24-hour TTL)
↓
Returns formatted message to channel
```

### Active
```
Users click "Join Session" or open share URL
↓
Frontend launches IDE with shared session context
↓
Session remains active until:
  - Last user disconnects, OR
  - 24-hour TTL expires
```

### Termination
```
Admin clicks "Revoke" in modal, OR
Session expires naturally, OR
Manual DELETE /api/slack/sessions/{id}
↓
Session removed from Redis
↓
New access attempts fail with 404
```

## Testing

### Manual Testing

```bash
# 1. Create session via Slack command
# (Type /share-ide in Slack channel)

# 2. Get session info
curl https://api.kushnir.cloud/api/slack/sessions/uuid

# 3. List channel sessions
curl https://api.kushnir.cloud/api/slack/channels/C12345678/sessions

# 4. Revoke session (admin)
curl -X DELETE https://api.kushnir.cloud/api/slack/sessions/uuid \
  -H "X-Admin-Secret: your-secret"
```

### Unit Tests

```bash
npm run test -- apps/backend/src/integrations/slack/__tests__/handler.test.ts
```

Coverage:
- ✅ Request signature verification
- ✅ Session creation and storage
- ✅ Session retrieval
- ✅ Channel session listing
- ✅ Session revocation
- ✅ Complete lifecycle scenarios
- ✅ Concurrent session handling

## Troubleshooting

### Issue: Slack reports "Slash command returned invalid request"

**Solution**: Verify the request URL is correct and backend is reachable:
```bash
curl -X POST https://api.kushnir.cloud/api/slack/health
```

### Issue: "Invalid request URL"

**Solution**: The URL must be HTTPS. Update in Slack app settings:
```
Request URL: https://api.kushnir.cloud/api/slack/commands/share-ide
```

### Issue: Sessions expire too quickly

**Solution**: Check `SLACK_SESSION_TTL_SECONDS` environment variable:
```bash
# Should be at least 86400 (24 hours)
echo $SLACK_SESSION_TTL_SECONDS
```

### Issue: "Unauthorized" when revoking sessions

**Solution**: Verify admin secret header:
```bash
curl -X DELETE https://api.kushnir.cloud/api/slack/sessions/uuid \
  -H "X-Admin-Secret: $SLACK_ADMIN_SECRET"
```

## Monitoring

### Metrics to Track

- **Session Creation Rate**: `slack:session:created:counter`
- **Active Sessions**: `slack:active:sessions:gauge`
- **Session Duration**: `slack:session:duration:histogram`
- **API Latency**: `slack:api:latency:histogram`
- **Error Rate**: `slack:errors:counter`

### Logging

All operations are logged:
```
[Slack] Shared session created: abc123xyz
  initiator: alice
  channel: #product
  repository: /src/components
  expiresAt: 2024-04-20T10:30:45Z
```

## Rollout Plan

### Phase 1: Internal Testing (Week 1)
- Deploy to staging
- Test with internal team
- Verify Slack app configuration
- Validate session lifecycle

### Phase 2: Limited Rollout (Week 2)
- Enable for select teams
- Monitor error rates
- Gather feedback

### Phase 3: General Availability (Week 3)
- Enable for all workspaces
- Announce in #product
- Provide user documentation

## Related Issues

- **#1164**: EPIC [Collab-9] GitHub Integration Hub
- **#1165**: [Collab-9.1] Ticket Linking (COMPLETED)
- **#1167**: [Collab-9.3] CI/CD Status Notifications
- **1168**: [Collab-9.4] Figma Design Integration
- **#1169**: [Collab-9.5] Sentry Error Notifications

## Future Enhancements

- [ ] Support for ephemeral messages (private responses)
- [ ] Session notifications (user joined/left)
- [ ] Recording and playback
- [ ] Session templates and presets
- [ ] Slack workflow integration
- [ ] Analytics dashboard

---

**Implementation Status**: ✅ COMPLETE  
**Last Updated**: 2026-04-20  
**Owner**: Engineering Team
