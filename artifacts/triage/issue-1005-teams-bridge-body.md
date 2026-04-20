## P2: Configure Microsoft Teams Bidirectional Bridge

### Summary

Deploy and configure the Microsoft Teams-Matrix bridge for bidirectional message sync between Matrix rooms and Teams channels.

### Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                    Microsoft Teams                            │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Team: Engineering / Channel: General                    │ │
│  │ • Messages, threads, reactions, files                    │ │
│  │ • @mentions, GIF/sticker support                         │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                               ↕ Microsoft Graph API
┌───────────────────────────────────────────────────────────────┐
│                    Teams-Matrix Bridge                        │
│  (mautrix-teams or custom Graph API integration)             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Message relay (both directions)                        │ │
│  │ • @mention translation                                   │ │
│  │ • Adaptive card rendering (Teams → Matrix)               │ │
│  │ • File attachment relay                                  │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                               ↕ Matrix protocol
┌───────────────────────────────────────────────────────────────┐
│                    Matrix Homeserver                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ #engineering-general:matrix.kushnir.cloud                │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

### Bridge Options

| Bridge | Status | Notes |
|--------|--------|-------|
| **mautrix-teams** | In development | Best future option |
| **Custom Graph API** | Build custom | Full control, more work |
| **SyncRivo** (SaaS) | Available | Managed, paid |

### Azure AD App Registration

1. **Register App** in Azure Portal → App Registrations
2. **API Permissions** (Application):
   - `ChannelMessage.Read.All` - Read channel messages
   - `ChannelMessage.Send` - Send channel messages
   - `Team.ReadBasic.All` - Read team info
   - `User.Read.All` - Read user profiles
   - `Chat.ReadWrite.All` - For DMs (optional)
3. **Authentication**:
   - Add redirect URI for OAuth flow
   - Generate client secret

### Configuration

```yaml
# config/teams-bridge/config.yaml

homeserver:
  address: https://matrix.kushnir.cloud
  domain: matrix.kushnir.cloud

appservice:
  address: http://teams-bridge:29329
  port: 29329
  database: postgres://teams_bridge:password@postgres:5432/teams_bridge

bridge:
  username_template: "teams_{{.}}"
  displayname_template: "{{.DisplayName}} (Teams)"

azure:
  tenant_id: ${AZURE_TENANT_ID}
  client_id: ${AZURE_CLIENT_ID}
  client_secret: ${AZURE_CLIENT_SECRET}

channel_mapping:
  # Teams Team/Channel ID → Matrix Room ID
  "team-id/channel-id": "!matrixroomid:matrix.kushnir.cloud"
```

### Docker Configuration

```yaml
# docker-compose.yml addition

teams-bridge:
  image: mautrix/teams:latest  # or custom build
  container_name: teams-bridge
  restart: unless-stopped
  volumes:
    - ./config/teams-bridge:/data
  environment:
    AZURE_TENANT_ID: ${AZURE_TENANT_ID}
    AZURE_CLIENT_ID: ${AZURE_CLIENT_ID}
    AZURE_CLIENT_SECRET: ${AZURE_CLIENT_SECRET}
  networks:
    - net-app
  depends_on:
    - postgres
    - synapse
```

### Acceptance Criteria

- [ ] Azure AD app registered with required permissions
- [ ] Teams bridge deployed and registered with Matrix homeserver
- [ ] At least one channel bridged (test channel)
- [ ] Messages flow Teams → Matrix
- [ ] Messages flow Matrix → Teams
- [ ] @mentions work both directions
- [ ] Adaptive cards rendered as formatted text in Matrix
- [ ] File attachments relayed
- [ ] Terraform module created

### Environment Variables

```bash
# .env additions for Teams bridge
AZURE_TENANT_ID=<tenant-id>
AZURE_CLIENT_ID=<client-id>
AZURE_CLIENT_SECRET=<client-secret>
```

### Dependencies

- Requires: #1001 (Matrix homeserver deployed)
- Requires: Azure AD admin access

### Parent

EPIC #TBD (Matrix Collaboration Hub)
