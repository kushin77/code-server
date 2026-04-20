# Matrix Admin Bot

TypeScript-based admin bot for Matrix collaboration platform governance.

## Features

- **Space/Room Templates**: Create pre-configured spaces from templates (team, project, announcements)
- **Admin Commands**: Manage spaces and policies via Matrix chat commands
- **Retention Policies**: Set and manage message retention for rooms
- **Audit Logging**: Immutable audit trail of administrative actions
- **Moderation**: Optional content filtering and rate limiting

## Development

### Setup

```bash
# Install dependencies
pnpm install

# Build TypeScript
pnpm build

# Run tests
pnpm test

# Watch mode
pnpm test:watch
```

### Local Development

```bash
# Start in development mode
pnpm dev

# Set environment variables
export MATRIX_HOMESERVER_URL=http://localhost:8008
export MATRIX_ACCESS_TOKEN=your_token_here
export MATRIX_ADMIN_USER=@admin:localhost
export AUDIT_DATABASE_URL=postgres://user:pass@localhost/matrix
```

## Architecture

```
apps/matrix-admin-bot/
├── src/
│   ├── index.ts                    # Main bot entry point
│   ├── commands/
│   │   └── handler.ts              # Command routing and handling
│   └── services/
│       ├── template-manager.ts     # Space/room template creation
│       ├── retention-manager.ts    # Retention policy management
│       ├── audit-logger.ts         # Immutable audit logging
│       └── moderation-manager.ts   # Content filtering, rate limiting
├── Dockerfile                      # Container build
├── package.json                    # Dependencies
└── tsconfig.json                   # TypeScript configuration
```

## Admin Commands

All commands start with `!admin`:

### Space Management

```
!admin create-team <name>      # Create new team space
!admin create-project <name>   # Create new project space
!admin archive <room_id>       # Archive a room
```

### Policies

```
!admin retention <room_id> <days>  # Set retention policy
```

### Information

```
!admin list-templates          # List available templates
!admin members <room_id>       # List room members
!admin help                    # Show command help
```

## Configuration

### Environment Variables

Required:
- `MATRIX_HOMESERVER_URL` - Synapse homeserver URL (default: http://localhost:8008)
- `MATRIX_ACCESS_TOKEN` - Bot's Matrix access token (from GSM or .env)
- `MATRIX_ADMIN_USER` - Bot's Matrix user ID (e.g., @admin:example.com)
- `AUDIT_DATABASE_URL` - PostgreSQL connection string

Optional:
- `LOG_LEVEL` - Logging level (default: info)
- `AUDIT_RETENTION_DAYS` - Days to keep audit logs (default: 90)

### Docker Environment

```dockerfile
ENV MATRIX_HOMESERVER_URL=http://synapse:8008
ENV MATRIX_ADMIN_USER=@admin:matrix.example.com
# Access token and database URL from secrets
```

## Testing

### Unit Tests

```bash
pnpm test
```

Tests cover:
- Template creation and interpolation
- Retention policy configuration
- Audit logging
- Command handling

### Integration Tests

```bash
# Requires live Synapse server and PostgreSQL
MATRIX_HOMESERVER_URL=http://synapse:8008 \
AUDIT_DATABASE_URL=postgres://... \
pnpm test:integration
```

## Deployment

### Docker Build

```bash
# From workspace root
docker build -f apps/matrix-admin-bot/Dockerfile -t matrix-admin-bot:latest .
```

### Docker Compose

```yaml
services:
  matrix-admin-bot:
    image: kushin77/matrix-admin-bot:latest
    container_name: matrix-admin-bot
    restart: unless-stopped
    networks:
      - net-app
    environment:
      MATRIX_HOMESERVER_URL: http://synapse:8008
      MATRIX_ADMIN_USER: "@admin:matrix.example.com"
      AUDIT_DATABASE_URL: postgres://matrix:password@postgres:5432/matrix
      LOG_LEVEL: info
    depends_on:
      - synapse
      - postgres
    healthcheck:
      test: ["CMD", "node", "-e", "process.exit(0)"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Terraform Deployment

See `terraform/modules/matrix-collab/modules/governance/` for full IaC configuration.

## Database Schema

The admin bot creates PostgreSQL tables for:

- `audit.events` - Immutable audit log of actions
- `audit.retention_policies` - Room retention policy configuration
- `audit.room_templates` - Tracking of rooms created from templates

## Integration with Matrix Homeserver

Requires:
- Synapse homeserver running and accessible
- Admin-level access token for the bot user
- PostgreSQL database for audit logging
- Network connectivity to homeserver API

## Next Steps

- [ ] Implement TypeScript build and compilation
- [ ] Add E2E tests with live Synapse instance
- [ ] Implement moderation tooling (content filters)
- [ ] Create admin dashboard (web UI)
- [ ] Add Kubernetes deployment manifests
- [ ] Implement event subscriptions for auto-cleanup

## Related Issues

- #1012: Admin & Governance Tooling (this implementation)
- #1001: Matrix Homeserver Architecture (dependency)
- #1009: SSO/SCIM Integration (optional, for group provisioning)
