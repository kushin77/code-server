## P2: Admin & Governance Tooling (Space Templates, Moderation, Retention)

### Summary

Implement administrative tooling for Matrix collaboration infrastructure including space/room templates, moderation controls, data retention policies, and governance automation.

### Governance Requirements

| Requirement | Implementation |
|-------------|----------------|
| **Room Templates** | Pre-configured rooms for teams, projects, incidents |
| **Auto-Join** | New users auto-joined to org-wide spaces |
| **Moderation** | Content filtering, user restrictions, audit logging |
| **Retention** | Configurable message retention per room/space |
| **Compliance** | Export, legal hold, audit trail |

### Space/Room Templates

```yaml
# config/matrix-templates/spaces.yaml

templates:
  - name: "team-default"
    display_name: "Team: {team_name}"
    type: "space"
    power_levels:
      users_default: 0
      events_default: 50
      state_default: 50
    auto_join_rooms:
      - "#general:matrix.kushnir.cloud"
      - "#announcements:matrix.kushnir.cloud"
    children:
      - name: "general"
        topic: "General discussion for {team_name}"
      - name: "random"
        topic: "Off-topic chat"
      - name: "standup"
        topic: "Daily standup notes"
        
  - name: "project"
    display_name: "Project: {project_name}"
    type: "space"
    retention_days: 365
    children:
      - name: "design"
      - name: "dev"
      - name: "qa"
      - name: "releases"
      
  - name: "incident"
    display_name: "🚨 Incident: {incident_id}"
    type: "room"
    retention_days: 730  # 2 years for compliance
    invite_only: true
    audit_logging: true
```

### Auto-Join Configuration

```yaml
# homeserver.yaml additions

auto_join_rooms:
  - "#welcome:matrix.kushnir.cloud"
  - "#announcements:matrix.kushnir.cloud"
  
auto_join_rooms_for_guests: false
```

### Admin Bot Implementation

```typescript
// apps/matrix-admin-bot/src/index.ts

import { MatrixClient, AutojoinRoomsMixin } from 'matrix-bot-sdk';

class AdminBot {
  private client: MatrixClient;
  
  async onNewUser(userId: string): Promise<void> {
    // Determine user's team from SCIM/IdP attributes
    const team = await this.getUserTeam(userId);
    
    // Create or join team space
    const spaceId = await this.getOrCreateTeamSpace(team);
    await this.inviteToSpace(userId, spaceId);
    
    // Send welcome message
    await this.sendWelcomeMessage(userId);
  }
  
  async createFromTemplate(
    templateName: string,
    variables: Record<string, string>
  ): Promise<string> {
    const template = await this.loadTemplate(templateName);
    const roomId = await this.client.createRoom({
      name: this.interpolate(template.display_name, variables),
      topic: template.topic,
      preset: template.invite_only ? 'private_chat' : 'public_chat',
      power_level_content_override: template.power_levels,
      initial_state: [
        // Retention policy
        {
          type: 'm.room.retention',
          state_key: '',
          content: { max_lifetime: template.retention_days * 86400000 }
        }
      ]
    });
    
    return roomId;
  }
  
  // Admin commands: !admin create-team <name>, !admin archive <room>, etc.
  async handleCommand(roomId: string, sender: string, command: string): Promise<void> {
    if (!await this.isAdmin(sender)) {
      return this.reply(roomId, "You don't have admin permissions.");
    }
    
    const [cmd, ...args] = command.split(' ');
    switch (cmd) {
      case 'create-team':
        await this.createFromTemplate('team-default', { team_name: args[0] });
        break;
      case 'archive':
        await this.archiveRoom(args[0]);
        break;
      case 'retention':
        await this.setRetention(args[0], parseInt(args[1]));
        break;
    }
  }
}
```

### Retention Policy Management

```yaml
# Element Server Suite Pro retention configuration

retention:
  enabled: true
  default_policy:
    max_lifetime: 90d
    min_lifetime: 1d
  
  allowed_policies:
    - max_lifetime: 7d    # Ephemeral rooms
    - max_lifetime: 30d   # Short-term projects
    - max_lifetime: 90d   # Default
    - max_lifetime: 365d  # Long-term projects
    - max_lifetime: 730d  # Compliance (2 years)
    
  purge_jobs:
    - interval: 1d
      max_rooms_per_run: 100
```

### Moderation Tools

```typescript
// apps/matrix-admin-bot/src/moderation.ts

interface ModerationConfig {
  // Content filters
  content_filters: {
    enabled: boolean;
    patterns: RegExp[];
    action: 'warn' | 'redact' | 'ban';
  };
  
  // Rate limiting
  rate_limits: {
    messages_per_minute: number;
    action: 'warn' | 'mute' | 'kick';
  };
  
  // Audit logging
  audit_logging: {
    enabled: boolean;
    events: string[];  // m.room.message, m.room.member, etc.
    retention_days: number;
  };
}

class Moderator {
  async filterContent(event: MatrixEvent): Promise<boolean> {
    for (const pattern of this.config.content_filters.patterns) {
      if (pattern.test(event.content.body)) {
        await this.takeAction(event, this.config.content_filters.action);
        return false;
      }
    }
    return true;
  }
  
  async logAuditEvent(event: MatrixEvent): Promise<void> {
    await this.auditStore.insert({
      timestamp: Date.now(),
      event_type: event.type,
      sender: event.sender,
      room_id: event.room_id,
      content_hash: hash(event.content),  // Don't store actual content
      action: 'logged'
    });
  }
}
```

### Terraform Resources

```hcl
# terraform/modules/matrix-governance/main.tf

# Admin bot deployment
resource "docker_container" "matrix_admin_bot" {
  name  = "matrix-admin-bot"
  image = "kushin77/matrix-admin-bot:latest"
  
  env = [
    "MATRIX_HOMESERVER_URL=${var.homeserver_url}",
    "MATRIX_ACCESS_TOKEN=${var.admin_bot_token}",
    "AUDIT_DATABASE_URL=${var.audit_database_url}"
  ]
}

# Retention purge job (cron)
resource "kubernetes_cron_job" "retention_purge" {
  metadata {
    name = "matrix-retention-purge"
  }
  
  spec {
    schedule = "0 3 * * *"  # Daily at 3 AM
    job_template {
      spec {
        template {
          spec {
            containers {
              name  = "purge"
              image = "matrixdotorg/synapse-admin:latest"
              args  = ["purge-history", "--before", "90d"]
            }
          }
        }
      }
    }
  }
}
```

### Acceptance Criteria

- [ ] Space/room templates defined and documented
- [ ] Admin bot deployed and operational
- [ ] Auto-join configured for org-wide spaces
- [ ] Template creation via admin commands
- [ ] Retention policies configurable per room
- [ ] Retention purge job running daily
- [ ] Audit logging enabled for key events
- [ ] Content moderation filters (optional)
- [ ] Rate limiting configured
- [ ] Admin documentation complete

### Dependencies

- Requires: #1001 (Matrix homeserver)
- Requires: #1009 (SSO/SCIM for user team mapping)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
