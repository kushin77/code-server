# Matrix Governance & Admin Module

Provides comprehensive governance, administration, and compliance tooling for Matrix collaboration platform, including:

- **Admin Bot**: Automates space/room creation from templates
- **Space Templates**: Pre-configured team, project, and announcements spaces
- **Retention Policies**: Automatic message/media purging based on room type
- **Audit Logging**: Immutable audit trail of Matrix events
- **Moderation Tools**: Content filtering, rate limiting, user management

## Features

### 1. Admin Bot

The Matrix admin bot provides automated administration of spaces and rooms:

**Commands:**
- `!admin create-team <name>` - Create new team space from template
- `!admin create-project <name>` - Create new project space
- `!admin archive <room_id>` - Archive a room  
- `!admin retention <room_id> <days>` - Set retention policy
- `!admin list-templates` - List available templates
- `!admin members <room_id>` - List room members

**Features:**
- Auto-join org-wide announcement space
- SCIM integration for team mapping
- Bulk user provisioning
- Permission level enforcement

### 2. Space Templates

Three default templates provided:

| Template | Type | Visibility | Retention | Use Case |
|----------|------|------------|-----------|----------|
| `team-default` | Private | Invite-only | 90 days | Team collaboration |
| `project-default` | Semi-public | Knock-to-join | 30 days | Temporary projects |
| `public-announcements` | Public | Public | 365 days | Org announcements |

**Template Parameters:**
- Display name
- Avatar & topic
- Power levels (who can modify settings)
- Join rules (public/knock/private)
- Retention policy
- Auto-join configuration

### 3. Retention Policies

Automatic message cleanup based on room type:

```yaml
allowed_policies:
  - max_lifetime: 7d    # Ephemeral channels
  - max_lifetime: 30d   # Short-term projects
  - max_lifetime: 90d   # Default teams
  - max_lifetime: 365d  # Long-term archives
  - max_lifetime: 730d  # Compliance-required
```

**Purge Job:**
- Runs daily at 3 AM UTC
- Purges up to 100 rooms per run
- Respects per-room retention overrides
- Preserves audit logs

### 4. Audit Logging

Immutable append-only audit trail for compliance:

**Logged Events:**
- Room creation/deletion
- Member joins/leaves
- Message deletion/redaction
- Power level changes
- Room topic/avatar changes
- History visibility changes
- Moderation actions

**Storage:** PostgreSQL `audit` schema
**Retention:** Configurable (default 90 days)

### 5. Moderation

Optional moderation tooling for large organizations:

**Content Filtering:**
- Configurable regex patterns
- Actions: warn, redact, or ban
- Bypass list for trusted users

**Rate Limiting:**
- Messages-per-minute threshold
- Actions: warn, mute, or kick
- Per-user tracking

**Spam Detection:**
- Detects duplicate messages
- Identifies flooding patterns
- Auto-mutes repeat offenders

## Configuration

### Required Variables

```hcl
admin_bot_token         = "syt_admin_..."  # From GSM
admin_user_id          = "@admin:matrix.example.com"
homeserver_url         = "http://synapse:8008"
docker_network_id      = "net-app"  # Shared network
postgresql_database    = "matrix"
audit_database_url     = "postgres://user:pass@localhost/matrix"
```

### Optional Variables

```hcl
enable_admin_bot           = true
enable_retention_policies  = true
enable_space_templates     = true
enable_audit_logging       = true
enable_moderation          = false  # Optional

retention_default_max_lifetime = "90d"
audit_retention_days          = 90
rate_limit_messages_per_minute = 60
content_filtering_enabled      = false
```

## Usage

### Integrate with main Matrix module:

```hcl
module "matrix_governance" {
  source = "./modules/matrix-collab/modules/governance"

  enable_admin_bot        = true
  admin_bot_token        = data.aws_secretsmanager_secret_version.admin_token.secret_string
  admin_user_id          = "@admin:${var.matrix_domain}"
  homeserver_url         = "http://synapse:8008"
  docker_network_id      = docker_network.app_network.id
  audit_database_url     = var.postgresql_url
  
  retention_enabled               = true
  retention_default_max_lifetime  = "90d"
  space_template_team_retention   = 90
  space_template_project_retention = 30
}
```

### Admin Bot Deployment

The admin bot runs as a Docker container with:

- Health check: `/health` endpoint (port 3001)
- Restart: Unless stopped
- Network: Shared with Synapse
- Environment: Injected from module variables

### Synapse Configuration

Retention policies are configured in Synapse's `homeserver.yaml`:

```yaml
retention:
  enabled: true
  default_policy:
    max_lifetime: 90d
    min_lifetime: 1d
  allowed_policies:
    - max_lifetime: 7d
    - max_lifetime: 30d
    - max_lifetime: 90d
    - max_lifetime: 365d
    - max_lifetime: 730d
  purge_jobs:
    - interval: 1d
      max_rooms_per_run: 100
```

### Audit Logging Schema

PostgreSQL schema for audit events:

```sql
CREATE TABLE audit.events (
  id BIGSERIAL PRIMARY KEY,
  timestamp TIMESTAMP DEFAULT NOW(),
  event_type VARCHAR(255) NOT NULL,
  sender VARCHAR(255) NOT NULL,
  room_id VARCHAR(255),
  content_hash VARCHAR(64),  -- SHA256 of content
  action VARCHAR(50),
  metadata JSONB
);

CREATE INDEX idx_audit_timestamp ON audit.events(timestamp DESC);
CREATE INDEX idx_audit_room ON audit.events(room_id);
CREATE INDEX idx_audit_sender ON audit.events(sender);
```

## Integration with #1001 Synapse Homeserver

This module depends on:
- Synapse homeserver running and accessible
- PostgreSQL database for audit logging
- Admin bot service account credentials in GSM

## Integration with #1009 SSO/SCIM

When SCIM is configured:
- User team is determined from SCIM attributes
- Auto-join team spaces on first login
- Admin bot provisions team spaces from SCIM groups

## Outputs

```hcl
admin_bot_id              = "container_xyz..."
admin_bot_status          = "running"
audit_schema_name         = "audit"
space_templates_config    = "/etc/matrix/space-templates.yaml"
moderation_config_path    = "/etc/matrix/moderation.yaml"
retention_purge_container = "container_abc..."
```

## Definition of Done for Issue #1012

- [x] Space/room templates defined and documented
- [x] Admin bot deployment configuration (Docker/Terraform)
- [x] Retention policies configurable per room type
- [x] Retention purge job running daily
- [x] Audit logging PostgreSQL schema
- [x] Terraform module with all features
- [x] Configuration documentation
- [ ] Admin bot source code (TypeScript implementation)
- [ ] Unit tests for admin bot
- [ ] Integration tests with live Synapse
- [ ] Admin documentation and runbooks
- [ ] E2E tests for space templates and retention

## Next Steps

1. Implement admin bot TypeScript source code (`apps/matrix-admin-bot/`)
2. Add unit tests for admin bot command handlers
3. Create admin documentation and runbooks
4. Deploy to staging and validate with live Synapse
5. Implement moderation tooling (content filters, rate limiting)
6. Add E2E tests for template creation and retention

## Related Issues

- #1001 Matrix Homeserver Architecture (dependency)
- #1009 Google OIDC SSO Integration (optional, for SCIM)
- #1000 EPIC: Matrix-Based Real-Time Collaboration
