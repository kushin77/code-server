## P1: Configure Slack Bidirectional Bridge

### Summary

Deploy and configure the Slack-Matrix bridge (mautrix-slack or matrix-appservice-slack) for bidirectional message sync between Matrix rooms and Slack channels.

### Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                    Slack Workspace                            │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ #engineering-team                                        │ │
│  │ • Messages, threads, reactions, files                    │ │
│  │ • @mentions, emoji reactions                             │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                               ↕ Real-time sync
┌───────────────────────────────────────────────────────────────┐
│                    Slack-Matrix Bridge                        │
│  (mautrix-slack or matrix-appservice-slack)                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Double-puppeting (messages appear as original user)   │ │
│  │ • Thread mapping (Slack threads ↔ Matrix threads)       │ │
│  │ • Reaction sync (emoji reactions both ways)             │ │
│  │ • File upload relay (with compliance scanning)          │ │
│  │ • @mention translation (@user in Slack ↔ @mxid)         │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                               ↕ Matrix protocol
┌───────────────────────────────────────────────────────────────┐
│                    Matrix Homeserver                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ #engineering-team:matrix.kushnir.cloud                   │ │
│  │ • E2EE optional (bridge requires decryption)             │ │
│  │ • Full message history preserved                         │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

### Bridge Options

| Bridge | Pros | Cons | Recommendation |
|--------|------|------|----------------|
| **mautrix-slack** | Active development, puppeting, threads | Complex setup | ✅ Recommended |
| **matrix-appservice-slack** | Simple, official | Less features | For basic needs |
| **SyncRivo** (SaaS) | Zero ops, managed | Cost, less control | For rapid PoC |

### Configuration

```yaml
# config/slack-bridge/config.yaml (mautrix-slack)

homeserver:
  address: https://matrix.kushnir.cloud
  domain: matrix.kushnir.cloud

appservice:
  address: http://slack-bridge:29328
  hostname: 0.0.0.0
  port: 29328
  database: postgres://slack_bridge:password@postgres:5432/slack_bridge

bridge:
  username_template: "slack_{{.}}"
  displayname_template: "{{.RealName}} (Slack)"
  
  # Double puppeting: messages appear from actual user
  double_puppet_server_map:
    matrix.kushnir.cloud: https://matrix.kushnir.cloud
  
  # Channel mapping
  channel_mapping:
    slack_channel_id: "!matrixroomid:matrix.kushnir.cloud"
  
  # Relay mode for non-puppeted users
  relay:
    enabled: true
    message_formats:
      m.text: "{{ .Sender.Displayname }}: {{ .Message }}"

slack:
  # OAuth app credentials (from Slack App)
  client_id: ${SLACK_CLIENT_ID}
  client_secret: ${SLACK_CLIENT_SECRET}
  
  # Workspace configuration
  team_id: ${SLACK_TEAM_ID}
  bot_token: ${SLACK_BOT_TOKEN}
  user_token: ${SLACK_USER_TOKEN}
```

### Docker Configuration

```yaml
# docker-compose.yml addition

slack-bridge:
  image: dock.mau.dev/mautrix/slack:latest
  container_name: slack-bridge
  restart: unless-stopped
  volumes:
    - ./config/slack-bridge:/data
  environment:
    - MAUTRIX_DIRECT_STARTUP=true
  networks:
    - net-app
  depends_on:
    - postgres
    - synapse
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:29328/_matrix/mau/live"]
    interval: 30s
    timeout: 10s
    retries: 3
```

### Slack App Setup

1. **Create Slack App** at api.slack.com/apps
2. **OAuth Scopes** (Bot Token):
   - `channels:history`, `channels:read`, `channels:join`
   - `chat:write`, `chat:write.customize`
   - `users:read`, `users.profile:read`
   - `reactions:read`, `reactions:write`
   - `files:read`, `files:write`
3. **OAuth Scopes** (User Token for puppeting):
   - Same as above, plus `team:read`
4. **Event Subscriptions**:
   - URL: `https://matrix.kushnir.cloud/_matrix/appservice/slack/events`
   - Events: `message.channels`, `reaction_added`, `reaction_removed`, `file_shared`

### Terraform Configuration

```hcl
# terraform/modules/slack-bridge/main.tf

resource "kubernetes_secret" "slack_bridge_credentials" {
  metadata {
    name      = "slack-bridge-credentials"
    namespace = var.namespace
  }

  data = {
    SLACK_CLIENT_ID     = var.slack_client_id
    SLACK_CLIENT_SECRET = var.slack_client_secret
    SLACK_BOT_TOKEN     = var.slack_bot_token
    SLACK_TEAM_ID       = var.slack_team_id
  }
}

resource "kubernetes_deployment" "slack_bridge" {
  # ... deployment spec
}
```

### Acceptance Criteria

- [ ] mautrix-slack deployed and registered with Matrix homeserver
- [ ] Slack OAuth app created with required scopes
- [ ] At least one channel bridged (test channel)
- [ ] Messages flow Slack → Matrix in real-time
- [ ] Messages flow Matrix → Slack in real-time
- [ ] @mentions translated correctly
- [ ] Emoji reactions synced
- [ ] Threads supported
- [ ] Files uploaded relay with compliance scanning
- [ ] Double-puppeting enabled (messages show original sender)
- [ ] Terraform module for reproducible deployment
- [ ] Monitoring: bridge health in Prometheus

### Environment Variables

```bash
# .env additions for Slack bridge
SLACK_CLIENT_ID=<slack-app-client-id>
SLACK_CLIENT_SECRET=<slack-app-client-secret>
SLACK_BOT_TOKEN=xoxb-<bot-token>
SLACK_USER_TOKEN=xoxp-<user-token>
SLACK_TEAM_ID=T<team-id>
```

### Dependencies

- Requires: #1001 (Matrix homeserver deployed)
- Blocks: #1002 (Team Hub extension needs bridge for @mention)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
