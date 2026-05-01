#!/bin/bash

###
# @file setup-collaboration-intelligence.sh
# @module scripts/extensions/setup-collaboration-intelligence.sh
# @description Initialize real-time collaboration intelligence for P2 #1539 Phase 3
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

# ============================================================================
# Logging
# ============================================================================

log_info "=== P2 #1539 Phase 3: Real-Time Collaboration Intelligence Setup ==="
log_info "Project root: ${PROJECT_ROOT}"
log_info "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
log_info ""

declare -i step_count=0
declare -i step_ok=0

# ============================================================================
# STEP 1: Verify collaboration source files
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verify collaboration intelligence source files"

declare -a required_files=(
    "apps/extensions/team-hub/src/collaboration-detector.ts"
    "apps/extensions/team-hub/src/conflict-resolver.ts"
)

all_present=true
for file in "${required_files[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
        log_info "  ✓ ${file}"
        step_ok+=1
    else
        log_warn "  ✗ Missing: ${file}"
        all_present=false
    fi
done

if [[ "$all_present" != "true" ]]; then
    log_error "Not all collaboration intelligence source files present"
    exit 1
fi

# ============================================================================
# STEP 2: Create collaboration configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create collaboration intelligence configuration"

COLLAB_CONFIG_DIR="${PROJECT_ROOT}/config/collaboration"
mkdir -p "${COLLAB_CONFIG_DIR}"

# Create collaboration config
cat > "${COLLAB_CONFIG_DIR}/intelligence-config.json" << 'EOF'
{
  "enabled": true,
  "version": "1.0.0",
  "real_time_detection": {
    "enabled": true,
    "track_file_edits": true,
    "track_user_presence": true,
    "conflict_detection_enabled": true
  },
  "conflict_resolution": {
    "enabled": true,
    "auto_suggest_merges": true,
    "require_approval_for_high_severity": true,
    "merge_confidence_threshold": 0.7
  },
  "audit_logging": {
    "enabled": true,
    "log_file": "logs/collaboration-intelligence.log",
    "log_level": "info"
  },
  "notifications": {
    "enabled": true,
    "notify_on_conflict": true,
    "notify_on_merge_suggestion": true
  }
}
EOF

if [[ -f "${COLLAB_CONFIG_DIR}/intelligence-config.json" ]]; then
    log_info "  ✓ Created ${COLLAB_CONFIG_DIR}/intelligence-config.json"
    step_ok+=1
else
    log_error "Failed to create collaboration configuration"
    exit 1
fi

# ============================================================================
# STEP 3: Create collaboration event logging
# ============================================================================

step_count+=1
log_info "STEP $step_count: Prepare collaboration event logging"

AUDIT_DIR="${PROJECT_ROOT}/logs"
mkdir -p "${AUDIT_DIR}"

# Initialize collaboration log
COLLAB_LOG="${AUDIT_DIR}/collaboration-intelligence.log"
if [[ ! -f "${COLLAB_LOG}" ]]; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] Collaboration intelligence service initialized" > "${COLLAB_LOG}"
    log_info "  ✓ Created ${COLLAB_LOG}"
else
    log_info "  ✓ Log file already exists: ${COLLAB_LOG}"
fi

step_ok+=1

# ============================================================================
# STEP 4: Create environment configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Configure environment variables"

cat > "${PROJECT_ROOT}/.env.collaboration-intelligence" << 'EOF'
# Collaboration Intelligence Configuration
# P2 #1539 Phase 3: Enable real-time collaboration detection and conflict prediction

COLLABORATION_ENABLED=true
COLLABORATION_DETECTION_ENABLED=true
CONFLICT_RESOLUTION_ENABLED=true
TRACK_FILE_EDITS=true
TRACK_USER_PRESENCE=true
AUTO_SUGGEST_MERGES=true
MERGE_CONFIDENCE_THRESHOLD=0.7
REQUIRE_APPROVAL_HIGH_SEVERITY=true
COLLABORATION_AUDIT_LOG=logs/collaboration-intelligence.log
EOF

log_info "  ✓ Created environment configuration: .env.collaboration-intelligence"
step_ok+=1

# ============================================================================
# STEP 5: Create event schema for compliance
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create event schema for compliance"

SCHEMA_DIR="${PROJECT_ROOT}/schemas"
mkdir -p "${SCHEMA_DIR}"

cat > "${SCHEMA_DIR}/collaboration-event.v1.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Collaboration Intelligence Event",
  "type": "object",
  "required": ["id", "type", "timestamp", "userId"],
  "properties": {
    "id": {
      "type": "string",
      "description": "Unique event identifier"
    },
    "type": {
      "type": "string",
      "enum": ["user_joined", "user_left", "file_edit_start", "file_edit_end", "conflict_detected", "conflict_resolved"],
      "description": "Event type"
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "When event occurred"
    },
    "userId": {
      "type": "string",
      "description": "User identifier"
    },
    "userName": {
      "type": "string",
      "description": "Human-readable username"
    },
    "filePath": {
      "type": "string",
      "description": "File being edited (if applicable)"
    },
    "severity": {
      "type": "string",
      "enum": ["info", "warning", "error"],
      "description": "Event severity"
    }
  }
}
EOF

if [[ -f "${SCHEMA_DIR}/collaboration-event.v1.json" ]]; then
    log_info "  ✓ Created event schema: ${SCHEMA_DIR}/collaboration-event.v1.json"
    step_ok+=1
else
    log_error "Failed to create event schema"
    exit 1
fi

# ============================================================================
# STEP 6: Verification
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verification"

CONFIG_FILES=$(find "${COLLAB_CONFIG_DIR}" -type f 2>/dev/null | wc -l)
SOURCE_FILES=$(find "${PROJECT_ROOT}/apps/extensions/team-hub/src" -name "*collaboration*" -o -name "*conflict*" 2>/dev/null | wc -l)

log_info "  ✓ Configuration files: ${CONFIG_FILES}"
log_info "  ✓ Source files: ${SOURCE_FILES}"
log_info "  ✓ Event logging: enabled"

step_ok+=1

# ============================================================================
# Summary
# ============================================================================

log_info ""
log_info "=== Setup Complete ==="
log_info "Steps completed: $step_ok / $step_count"
log_info ""
log_info "✅ Collaboration Intelligence Ready (P2 #1539 Phase 3)"
log_info ""
log_info "Next Steps:"
log_info "  1. TypeScript compilation: pnpm build"
log_info "  2. Extension activation: code-server restart"
log_info "  3. Verify logs: tail -f logs/collaboration-intelligence.log"
log_info ""
log_info "Features:"
log_info "  - Real-time user presence tracking"
log_info "  - File edit conflict detection"
log_info "  - AI-assisted merge suggestions (5 strategies per conflict)"
log_info "  - Conflict severity calculation"
log_info "  - Automatic audit logging for compliance"
log_info "  - User approval workflow for high-severity conflicts"
log_info ""
log_info "Configuration: ${COLLAB_CONFIG_DIR}/intelligence-config.json"
log_info "Event schema: ${SCHEMA_DIR}/collaboration-event.v1.json"
log_info "Audit log: ${COLLAB_LOG}"
log_info ""

if [[ $step_ok -eq $step_count ]]; then
    log_success "Collaboration intelligence setup successful"
    exit 0
else
    log_error "Setup incomplete ($step_ok / $step_count steps)"
    exit 1
fi
