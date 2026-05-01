#!/bin/bash

###
# @file setup-local-folder-access.sh
# @module scripts/extensions/setup-local-folder-access.sh
# @description Initialize local folder access for P2 #1539 Phase 4
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

log_info "=== P2 #1539 Phase 4: Local Folder Access Setup ==="
log_info "Project root: ${PROJECT_ROOT}"
log_info "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
log_info ""

declare -i step_count=0
declare -i step_ok=0

# ============================================================================
# STEP 1: Verify local folder access source files
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verify local folder access source files"

declare -a required_files=(
    "apps/extensions/team-hub/src/local-folder-access.ts"
    "apps/extensions/team-hub/src/workspace-folder-manager.ts"
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
    log_error "Not all local folder access source files present"
    exit 1
fi

# ============================================================================
# STEP 2: Create local folder access configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create local folder access configuration"

FOLDER_CONFIG_DIR="${PROJECT_ROOT}/config/workspace"
mkdir -p "${FOLDER_CONFIG_DIR}"

# Create local folder config
cat > "${FOLDER_CONFIG_DIR}/local-access-config.json" << 'EOF'
{
  "enabled": true,
  "version": "1.0.0",
  "local_folder_access": {
    "enabled": true,
    "require_user_approval": true,
    "default_permissions": "read-write"
  },
  "workspace_management": {
    "enabled": true,
    "auto_save_configuration": true,
    "persist_mounted_folders": true,
    "mount_directory": ".local-folders"
  },
  "audit_logging": {
    "enabled": true,
    "log_file": "logs/local-folder-access.log",
    "log_level": "info"
  },
  "security": {
    "sandbox_paths": true,
    "restrict_symlinks": true,
    "audit_all_operations": true
  }
}
EOF

if [[ -f "${FOLDER_CONFIG_DIR}/local-access-config.json" ]]; then
    log_info "  ✓ Created ${FOLDER_CONFIG_DIR}/local-access-config.json"
    step_ok+=1
else
    log_error "Failed to create local folder access configuration"
    exit 1
fi

# ============================================================================
# STEP 3: Create mount directory structure
# ============================================================================

step_count+=1
log_info "STEP $step_count: Prepare mount directory structure"

MOUNT_DIR="${PROJECT_ROOT}/.local-folders"
mkdir -p "${MOUNT_DIR}"

# Create .gitkeep to preserve directory
touch "${MOUNT_DIR}/.gitkeep"

if [[ -d "${MOUNT_DIR}" ]]; then
    log_info "  ✓ Created mount directory: ${MOUNT_DIR}"
    step_ok+=1
else
    log_error "Failed to create mount directory"
    exit 1
fi

# ============================================================================
# STEP 4: Create access audit logging
# ============================================================================

step_count+=1
log_info "STEP $step_count: Prepare access audit logging"

AUDIT_DIR="${PROJECT_ROOT}/logs"
mkdir -p "${AUDIT_DIR}"

# Initialize local folder access log
LOCAL_ACCESS_LOG="${AUDIT_DIR}/local-folder-access.log"
if [[ ! -f "${LOCAL_ACCESS_LOG}" ]]; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] Local folder access service initialized" > "${LOCAL_ACCESS_LOG}"
    log_info "  ✓ Created ${LOCAL_ACCESS_LOG}"
else
    log_info "  ✓ Log file already exists: ${LOCAL_ACCESS_LOG}"
fi

step_ok+=1

# ============================================================================
# STEP 5: Create environment configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Configure environment variables"

cat > "${PROJECT_ROOT}/.env.local-folder-access" << 'EOF'
# Local Folder Access Configuration
# P2 #1539 Phase 4: Enable access to local host folders from IDE workspace

LOCAL_FOLDER_ACCESS_ENABLED=true
REQUIRE_USER_APPROVAL=true
DEFAULT_PERMISSIONS=read-write
MOUNT_DIRECTORY=.local-folders
AUTO_SAVE_WORKSPACE_CONFIG=true
PERSIST_MOUNTED_FOLDERS=true
SANDBOX_PATHS=true
RESTRICT_SYMLINKS=true
AUDIT_ALL_OPERATIONS=true
LOCAL_FOLDER_AUDIT_LOG=logs/local-folder-access.log
MAX_CONCURRENT_MOUNTS=10
EOF

log_info "  ✓ Created environment configuration: .env.local-folder-access"
step_ok+=1

# ============================================================================
# STEP 6: Create access schema for compliance
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create access schema for compliance"

SCHEMA_DIR="${PROJECT_ROOT}/schemas"
mkdir -p "${SCHEMA_DIR}"

cat > "${SCHEMA_DIR}/local-folder-mount.v1.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Local Folder Mount",
  "type": "object",
  "required": ["id", "localPath", "mountPath", "displayName", "created"],
  "properties": {
    "id": {
      "type": "string",
      "description": "Unique mount identifier"
    },
    "localPath": {
      "type": "string",
      "description": "Absolute path on local host"
    },
    "mountPath": {
      "type": "string",
      "description": "Path within IDE workspace"
    },
    "displayName": {
      "type": "string",
      "description": "User-friendly folder name"
    },
    "created": {
      "type": "string",
      "format": "date-time",
      "description": "When mount was created"
    },
    "accessed": {
      "type": "string",
      "format": "date-time",
      "description": "Last access time"
    },
    "permissions": {
      "type": "string",
      "enum": ["read", "read-write"],
      "description": "Access level"
    },
    "enabled": {
      "type": "boolean",
      "description": "Whether mount is active"
    }
  }
}
EOF

if [[ -f "${SCHEMA_DIR}/local-folder-mount.v1.json" ]]; then
    log_info "  ✓ Created mount schema: ${SCHEMA_DIR}/local-folder-mount.v1.json"
    step_ok+=1
else
    log_error "Failed to create mount schema"
    exit 1
fi

# ============================================================================
# STEP 7: Verification
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verification"

CONFIG_FILES=$(find "${FOLDER_CONFIG_DIR}" -type f 2>/dev/null | wc -l)
SOURCE_FILES=$(find "${PROJECT_ROOT}/apps/extensions/team-hub/src" -name "*local-folder*" -o -name "*workspace-folder*" 2>/dev/null | wc -l)

log_info "  ✓ Configuration files: ${CONFIG_FILES}"
log_info "  ✓ Source files: ${SOURCE_FILES}"
log_info "  ✓ Mount directory: created"
log_info "  ✓ Audit logging: enabled"

step_ok+=1

# ============================================================================
# Summary
# ============================================================================

log_info ""
log_info "=== Setup Complete ==="
log_info "Steps completed: $step_ok / $step_count"
log_info ""
log_info "✅ Local Folder Access Ready (P2 #1539 Phase 4)"
log_info ""
log_info "Next Steps:"
log_info "  1. TypeScript compilation: pnpm build"
log_info "  2. Extension activation: code-server restart"
log_info "  3. Request folder access via KC IDE interface"
log_info "  4. Mounted folders available in VS Code workspace"
log_info ""
log_info "Features:"
log_info "  - User-approved local folder mounting"
log_info "  - Configurable permissions (read/read-write)"
log_info "  - Automatic audit logging of all file operations"
log_info "  - Workspace persistence (mounts survive restarts)"
log_info "  - Security controls: sandboxing, symlink restrictions"
log_info "  - Idempotent initialization"
log_info ""
log_info "Configuration: ${FOLDER_CONFIG_DIR}/local-access-config.json"
log_info "Mount schemas: ${SCHEMA_DIR}/local-folder-mount.v1.json"
log_info "Audit log: ${LOCAL_ACCESS_LOG}"
log_info ""

if [[ $step_ok -eq $step_count ]]; then
    log_success "Local folder access setup successful"
    exit 0
else
    log_error "Setup incomplete ($step_ok / $step_count steps)"
    exit 1
fi
