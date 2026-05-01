#!/bin/bash

###
# @file setup-advanced-team-coordination.sh
# @module scripts/extensions/setup-advanced-team-coordination.sh
# @description Initialize advanced team coordination infrastructure for P2 #1539 Phase 7
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
  OUTPUT_ROOT="${PROJECT_ROOT}/.dry-run/team-coordination-setup"
fi

# ============================================================================
# Logging
# ============================================================================

log_info "=== P2 #1539 Phase 7: Advanced Team Coordination Setup ==="
log_info "Project root: ${PROJECT_ROOT}"
log_info "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
log_info ""

declare -i step_count=0
declare -i step_ok=0

# ============================================================================
# STEP 1: Verify advanced team coordination source files
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verify advanced team coordination source files"

declare -a required_files=(
    "apps/extensions/team-hub/src/team-orchestrator-engine.ts"
    "apps/extensions/team-hub/src/team-coordination-handler.ts"
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
    log_error "Not all team coordination source files present"
    exit 1
fi

step_ok+=1

# ============================================================================
# STEP 2: Create team coordination configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create team coordination configuration"

COORDINATION_CONFIG_DIR="${OUTPUT_ROOT}/config/team-coordination"
mkdir -p "${COORDINATION_CONFIG_DIR}"

# Create main configuration
cat > "${COORDINATION_CONFIG_DIR}/coordination-config.json" << 'EOF'
{
  "enabled": true,
  "version": "1.0.0",
  "orchestration": {
    "enabled": true,
    "auto_assignment": true,
    "auto_assignment_strategy": "load_balancing",
    "skill_matching": true,
    "timezone_aware": true,
    "work_hours_respected": true,
    "availability_threshold_percent": 10
  },
  "workflows": {
    "enabled": true,
    "automation_enabled": true,
    "max_workflows": 50,
    "task_dependency_tracking": true,
    "critical_task_escalation": true
  },
  "reporting": {
    "enabled": true,
    "real_time_capacity_monitoring": true,
    "workload_alerts": true,
    "alert_threshold_percent": 90
  },
  "audit": {
    "enabled": true,
    "log_all_assignments": true,
    "log_all_status_changes": true,
    "retention_days": 90,
    "max_audit_entries": 10000
  }
}
EOF

log_success "Configuration created: ${COORDINATION_CONFIG_DIR}/coordination-config.json"
step_ok+=1

# ============================================================================
# STEP 3: Create team coordination environment variables
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create team coordination environment variables"

cat > "${OUTPUT_ROOT}/.env.team-coordination" << 'EOF'
# Team Coordination Configuration
# P2 #1539 Phase 7: Advanced team orchestration and task distribution

TEAM_COORDINATION_ENABLED=true
AUTO_ASSIGNMENT_ENABLED=true
AUTO_ASSIGNMENT_STRATEGY=load_balancing
SKILL_MATCHING_ENABLED=true
TIMEZONE_AWARE_ENABLED=true

# Workflow settings
WORKFLOW_AUTOMATION_ENABLED=true
MAX_WORKFLOWS=50
CRITICAL_ESCALATION_ENABLED=true

# Monitoring
CAPACITY_MONITORING_INTERVAL_SECONDS=300
WORKLOAD_ALERT_THRESHOLD=90
UTILIZATION_REPORT_ENABLED=true

# Audit logging
AUDIT_LOG_PATH=./logs/team-coordination.log
AUDIT_MAX_ENTRIES=10000
AUDIT_RETENTION_DAYS=90
EOF

log_success "Environment file created: ${OUTPUT_ROOT}/.env.team-coordination"
step_ok+=1

# ============================================================================
# STEP 4: Create team coordination audit logging schema
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create team coordination audit logging schema"

SCHEMA_DIR="${OUTPUT_ROOT}/schemas"
mkdir -p "${SCHEMA_DIR}"

cat > "${SCHEMA_DIR}/team-coordination-audit-schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Team Coordination Audit Log Entry",
  "type": "object",
  "properties": {
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "When the event occurred (ISO 8601)"
    },
    "userId": {
      "type": "string",
      "description": "User performing the action"
    },
    "action": {
      "type": "string",
      "enum": [
        "register_team",
        "create_task",
        "assign_task",
        "assign_task_manual",
        "task_status_update",
        "create_workflow",
        "workflow_execution",
        "escalate_task",
        "member_availability_update"
      ],
      "description": "Type of action performed"
    },
    "details": {
      "type": "object",
      "description": "Action-specific details",
      "properties": {
        "taskId": { "type": "string" },
        "teamId": { "type": "string" },
        "memberId": { "type": "string" },
        "workflowId": { "type": "string" },
        "oldStatus": { "type": "string" },
        "newStatus": { "type": "string" },
        "priority": { "type": "string" },
        "method": { "type": "string" },
        "reason": { "type": "string" }
      }
    },
    "severity": {
      "type": "string",
      "enum": ["info", "warning", "error", "critical"],
      "default": "info"
    }
  },
  "required": ["timestamp", "userId", "action", "details"]
}
EOF

log_success "Schema created: ${SCHEMA_DIR}/team-coordination-audit-schema.json"
step_ok+=1

# ============================================================================
# STEP 5: Create team coordination notification templates
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create team coordination notification templates"

TEMPLATE_DIR="${COORDINATION_CONFIG_DIR}"

cat > "${TEMPLATE_DIR}/notification-templates.json" << 'EOF'
{
  "task_assigned": {
    "title": "New Task Assignment",
    "template": "Task '{title}' has been assigned to you. Priority: {priority}, Estimate: {estimatedHours}h, Due: {dueDate}"
  },
  "task_overdue": {
    "title": "Task Overdue",
    "template": "Task '{title}' is now overdue. Please update status or let your manager know of blockers."
  },
  "team_at_capacity": {
    "title": "Team Capacity Alert",
    "template": "Team is at {utilization}% capacity. Consider deferring non-critical work."
  },
  "critical_task_created": {
    "title": "Critical Task",
    "template": "Critical task '{title}' created. Requires immediate attention."
  },
  "workflow_stage_complete": {
    "title": "Workflow Progress",
    "template": "Workflow '{workflowName}' has completed stage '{stageName}'. {nextAction}"
  },
  "member_unavailable": {
    "title": "Member Unavailable",
    "template": "Team member {memberName} is now unavailable. Redistributing tasks if needed."
  }
}
EOF

log_success "Notification templates created: ${TEMPLATE_DIR}/notification-templates.json"
step_ok+=1

# ============================================================================
# STEP 6: Create initial audit logs directory
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create initial audit logs"

LOGS_DIR="${OUTPUT_ROOT}/logs"
mkdir -p "${LOGS_DIR}"

{
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [INFO] Team coordination audit log initialized"
} >> "${LOGS_DIR}/team-coordination.log"

log_success "Audit logging initialized: ${LOGS_DIR}/team-coordination.log"
step_ok+=1

# ============================================================================
# STEP 7: Verification
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verification"

CONFIG_FILES=$(find "${COORDINATION_CONFIG_DIR}" -type f 2>/dev/null | wc -l)
SOURCE_FILES=$(find "${PROJECT_ROOT}/apps/extensions/team-hub/src" \( -name "*orchestrator*" -o -name "*coordination*" \) -type f 2>/dev/null | wc -l)
SCHEMA_FILES=$(find "${SCHEMA_DIR}" -type f \( -name "*coordination*" -o -name "*audit*" \) 2>/dev/null | wc -l)

log_info "  ✓ Configuration files: ${CONFIG_FILES}"
log_info "  ✓ Source files: ${SOURCE_FILES}"
log_info "  ✓ Schema files: ${SCHEMA_FILES}"

step_ok+=1

# ============================================================================
# Summary
# ============================================================================

log_info ""
log_info "=== Setup Complete ==="
log_info "Steps completed: $step_ok / $step_count"
log_info ""
log_info "✅ Advanced Team Coordination Ready (P2 #1539 Phase 7)"
log_info ""
log_info "Next Steps:"
log_info "  1. TypeScript compilation: pnpm build"
log_info "  2. Extension activation: code-server restart"
log_info "  3. Verify logs: tail -f logs/team-coordination.log"
log_info ""
log_info "Features:"
log_info "  - Distributed task assignment with load balancing"
log_info "  - Real-time team capacity monitoring"
log_info "  - Workflow automation and orchestration"
log_info "  - Skill-based member matching"
log_info "  - Timezone and work-hours awareness"
log_info "  - Comprehensive audit logging"
log_info ""
log_info "Configuration Files:"
log_info "  - config/team-coordination/coordination-config.json"
log_info "  - config/team-coordination/notification-templates.json"
log_info "Environment File:"
log_info "  - ${OUTPUT_ROOT}/.env.team-coordination"
log_info "Schema File:"
log_info "  - ${SCHEMA_DIR}/team-coordination-audit-schema.json"
log_info ""
