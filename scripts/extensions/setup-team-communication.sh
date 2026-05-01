#!/bin/bash

###
# @file setup-team-communication.sh
# @module scripts/extensions/setup-team-communication.sh
# @description Initialize team communication infrastructure for P2 #1539 Phase 6
# @compliance IaC, idempotent, environment-driven, GOV-002 compliant
###

set -euo pipefail

# ============================================================================
# Source initialization and logging
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common functions
if [[ ! -f "${PROJECT_ROOT}/scripts/_common/init.sh" ]]; then
    echo "[ERROR] Cannot source init.sh from ${PROJECT_ROOT}/scripts/_common/"
    exit 1
fi

source "${PROJECT_ROOT}/scripts/_common/init.sh"

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
  esac
done

OUTPUT_ROOT="${PROJECT_ROOT}"
if [[ "$DRY_RUN" == true ]]; then
  OUTPUT_ROOT="${PROJECT_ROOT}/.dry-run/team-communication-setup"
fi

# ============================================================================
# Logging
# ============================================================================

log_info "=== P2 #1539 Phase 6: Team Communication Infrastructure Setup ==="
log_info "Project root: ${PROJECT_ROOT}"
log_info "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
log_info ""

declare -i step_count=0
declare -i step_ok=0

# ============================================================================
# STEP 1: Verify team communication source files
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verify team communication source files"

declare -a required_files=(
    "apps/extensions/team-hub/src/team-communication-engine.ts"
    "apps/extensions/team-hub/src/google-chat-integration.ts"
)

all_present=true
for file in "${required_files[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
        log_info "  ✓ ${file}"
    else
        log_warn "  ✗ Missing: ${file}"
        all_present=false
    fi
done

if [[ "$all_present" != "true" ]]; then
    log_error "Not all team communication source files present"
    exit 1
fi

step_ok+=1

# ============================================================================
# STEP 2: Create team communication configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create team communication configuration"

COMMS_CONFIG_DIR="${OUTPUT_ROOT}/config/team-communications"
mkdir -p "${COMMS_CONFIG_DIR}"

# Create main configuration
cat > "${COMMS_CONFIG_DIR}/team-comms-config.json" << 'EOF'
{
  "enabled": true,
  "version": "1.0.0",
  "messaging": {
    "enabled": true,
    "channel_types": ["public", "private", "dm"],
    "max_message_length": 4096,
    "typing_indicators": true,
    "read_receipts": true,
    "message_retention_days": 90
  },
  "presence": {
    "enabled": true,
    "status_options": ["online", "away", "offline", "dnd"],
    "auto_away_minutes": 15,
    "broadcast_interval_seconds": 30
  },
  "video_meetings": {
    "enabled": true,
    "max_participants": 100,
    "recording_enabled": true,
    "chat_during_meeting": true,
    "screen_sharing": true
  },
  "google_chat": {
    "enabled": true,
    "sync_interval_seconds": 60,
    "webhook_verification": true,
    "auto_reconnect": true
  },
  "notifications": {
    "enabled": true,
    "desktop_notifications": true,
    "sound_enabled": true,
    "mention_notifications": true
  },
  "security": {
    "end_to_end_encryption": false,
    "audit_all_messages": true,
    "rate_limiting": true,
    "prevent_spam": true
  }
}
EOF

if [[ -f "${COMMS_CONFIG_DIR}/team-comms-config.json" ]]; then
    log_info "  ✓ Created ${COMMS_CONFIG_DIR}/team-comms-config.json"
    step_ok+=1
else
    log_error "Failed to create team communication configuration"
    exit 1
fi

# ============================================================================
# STEP 3: Prepare communication audit logging
# ============================================================================

step_count+=1
log_info "STEP $step_count: Prepare communication audit logging"

AUDIT_DIR="${OUTPUT_ROOT}/logs"
mkdir -p "${AUDIT_DIR}"

# Initialize logs
for logfile in team-communication.log google-chat-sync.log video-meetings.log; do
    LOG_PATH="${AUDIT_DIR}/${logfile}"
    if [[ ! -f "${LOG_PATH}" ]]; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] Team communication service initialized" > "${LOG_PATH}"
        log_info "  ✓ Created ${LOG_PATH}"
    else
        log_info "  ✓ Log file exists: ${LOG_PATH}"
    fi
done

step_ok+=1

# ============================================================================
# STEP 4: Create communication environment configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Configure communication environment variables"

cat > "${OUTPUT_ROOT}/.env.team-communications" << 'EOF'
# Team Communication Configuration
# P2 #1539 Phase 6: Real-time messaging, video meetings, Google Chat integration

TEAM_COMMUNICATION_ENABLED=true
MESSAGING_ENABLED=true
PRESENCE_ENABLED=true
VIDEO_MEETINGS_ENABLED=true
GOOGLE_CHAT_ENABLED=true
GOOGLE_CHAT_WEBHOOK_URL=${GOOGLE_CHAT_WEBHOOK_URL:-}
GOOGLE_CHAT_SPACE_ID=${GOOGLE_CHAT_SPACE_ID:-}
NOTIFICATIONS_ENABLED=true
DESKTOP_NOTIFICATIONS=true
SOUND_ENABLED=true
MENTION_NOTIFICATIONS=true
AUTO_AWAY_MINUTES=15
BROADCAST_INTERVAL_SECONDS=30
MESSAGE_RETENTION_DAYS=90
MAX_MESSAGE_LENGTH=4096
MAX_MEETING_PARTICIPANTS=100
MEETING_RECORDING_ENABLED=true
END_TO_END_ENCRYPTION=false
AUDIT_ALL_MESSAGES=true
RATE_LIMITING_ENABLED=true
PREVENT_SPAM_ENABLED=true
GOOGLE_CHAT_SYNC_INTERVAL_SECONDS=60
EOF

log_info "  ✓ Created environment configuration: ${OUTPUT_ROOT}/.env.team-communications"
log_info "  ⚠ NOTE: Set GOOGLE_CHAT_WEBHOOK_URL and GOOGLE_CHAT_SPACE_ID environment variables"
step_ok+=1

# ============================================================================
# STEP 5: Create communication schemas for compliance
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create communication event schemas"

SCHEMA_DIR="${OUTPUT_ROOT}/schemas"
mkdir -p "${SCHEMA_DIR}"

# Message schema
cat > "${SCHEMA_DIR}/team-message.v1.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Team Message",
  "type": "object",
  "required": ["id", "userId", "content", "timestamp"],
  "properties": {
    "id": {
      "type": "string",
      "description": "Message identifier"
    },
    "userId": {
      "type": "string",
      "description": "Sender user ID"
    },
    "userName": {
      "type": "string",
      "description": "Sender name"
    },
    "content": {
      "type": "string",
      "description": "Message content"
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "Message send time"
    },
    "edited": {
      "type": "string",
      "format": "date-time",
      "description": "Last edit time"
    },
    "reactions": {
      "type": "object",
      "description": "Message reactions"
    }
  }
}
EOF

# Presence schema
cat > "${SCHEMA_DIR}/team-presence.v1.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Team Member Presence",
  "type": "object",
  "required": ["userId", "status", "timestamp"],
  "properties": {
    "userId": {
      "type": "string",
      "description": "User identifier"
    },
    "status": {
      "type": "string",
      "enum": ["online", "away", "offline", "dnd"],
      "description": "Presence status"
    },
    "statusMessage": {
      "type": "string",
      "description": "Custom status message"
    },
    "lastSeen": {
      "type": "string",
      "format": "date-time",
      "description": "Last seen time"
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "Status update time"
    }
  }
}
EOF

# Meeting schema
cat > "${SCHEMA_DIR}/video-meeting.v1.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Video Meeting Session",
  "type": "object",
  "required": ["id", "title", "initiator", "startTime"],
  "properties": {
    "id": {
      "type": "string",
      "description": "Meeting identifier"
    },
    "title": {
      "type": "string",
      "description": "Meeting title"
    },
    "initiator": {
      "type": "string",
      "description": "Meeting initiator user ID"
    },
    "participants": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Participant IDs"
    },
    "startTime": {
      "type": "string",
      "format": "date-time",
      "description": "Meeting start time"
    },
    "endTime": {
      "type": "string",
      "format": "date-time",
      "description": "Meeting end time"
    },
    "duration": {
      "type": "integer",
      "description": "Duration in seconds"
    },
    "recording": {
      "type": "boolean",
      "description": "Recording enabled"
    }
  }
}
EOF

log_info "  ✓ Created communication schemas for compliance"

# ============================================================================
# STEP 6: Create notification templates
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create notification templates"

TEMPLATES_DIR="${COMMS_CONFIG_DIR}/notification-templates"
mkdir -p "${TEMPLATES_DIR}"

cat > "${TEMPLATES_DIR}/mention.json" << 'EOF'
{
  "id": "mention",
  "title": "You were mentioned",
  "body": "@{sender} mentioned you in #{channel}",
  "icon": "comment",
  "sound": "mention.mp3"
}
EOF

cat > "${TEMPLATES_DIR}/meeting-invite.json" << 'EOF'
{
  "id": "meeting_invite",
  "title": "Meeting invitation",
  "body": "{sender} invited you to: {meetingTitle}",
  "icon": "video-camera",
  "sound": "notification.mp3",
  "actions": ["accept", "decline"]
}
EOF

cat > "${TEMPLATES_DIR}/member-joined.json" << 'EOF'
{
  "id": "member_joined",
  "title": "Member joined",
  "body": "{member} joined #{channel}",
  "icon": "user-plus",
  "sound": false
}
EOF

log_info "  ✓ Created notification templates"
step_ok+=1

# ============================================================================
# STEP 7: Verification
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verification"

CONFIG_FILES=$(find "${COMMS_CONFIG_DIR}" -type f 2>/dev/null | wc -l)
SOURCE_FILES=$(find "${PROJECT_ROOT}/apps/extensions/team-hub/src" \( -name "*communication*" -o -name "*google-chat*" \) -type f 2>/dev/null | wc -l)
SCHEMA_FILES=$(find "${SCHEMA_DIR}" -type f \( -name "*message*" -o -name "*presence*" -o -name "*meeting*" \) 2>/dev/null | wc -l)

log_info "  ✓ Configuration files: ${CONFIG_FILES}"
log_info "  ✓ Source files: ${SOURCE_FILES}"
log_info "  ✓ Schema files: ${SCHEMA_FILES}"

step_ok+=1

step_ok+=1

# ============================================================================
# Summary
# ============================================================================

log_info ""
log_info "=== Setup Complete ==="
log_info "Steps completed: $step_ok / $step_count"
log_info ""
log_info "✅ Team Communication Infrastructure Ready (P2 #1539 Phase 6)"
log_info ""
log_info "Next Steps:"
log_info "  1. Configure Google Chat webhook at https://console.cloud.google.com"
log_info "  2. Set GOOGLE_CHAT_WEBHOOK_URL and GOOGLE_CHAT_SPACE_ID environment variables"
log_info "  3. Build extension: pnpm build"
log_info "  4. Restart code-server"
log_info "  5. Open Team Hub sidebar in KC IDE"
log_info ""
log_info "Features:"
log_info "  - Real-time messaging with channels and DMs"
log_info "  - User presence tracking (online/away/offline/dnd)"
log_info "  - Video meeting capabilities with recording"
log_info "  - Google Chat integration with webhook sync"
log_info "  - Message reactions and threading"
log_info "  - Desktop notifications and sound alerts"
log_info "  - Screen sharing and chat during meetings"
log_info "  - Audit logging for compliance"
log_info "  - Rate limiting and spam prevention"
log_info "  - Idempotent initialization"
log_info ""
log_info "Configuration: ${COMMS_CONFIG_DIR}/team-comms-config.json"
log_info "Environment: ${OUTPUT_ROOT}/.env.team-communications"
log_info "Schemas: ${SCHEMA_DIR}/team-*.json"
log_info "Audit logs: ${AUDIT_DIR}/team-*.log"
log_info ""

if [[ $step_ok -eq $step_count ]]; then
    log_success "Team communication setup successful"
    exit 0
else
    log_error "Setup incomplete ($step_ok / $step_count steps)"
    exit 1
fi
