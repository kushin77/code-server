#!/usr/bin/env bash
# Wrapper to run PostgreSQL replication setup with correct paths

set -euo pipefail

WORK_DIR="/tmp/postgres-replication-setup"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Copy necessary files
cp /tmp/setup-postgres-replication.sh . 2>/dev/null || true
cp -r /tmp/_common . 2>/dev/null || true

# Create a minimal init.sh if it doesn't exist
if [ ! -f _common/init.sh ]; then
    mkdir -p _common
    cat > _common/init.sh << 'EOF'
#!/usr/bin/env bash
# Minimal init.sh for script execution

set -euo pipefail

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
log_fatal() { echo "[FATAL] $*"; exit 1; }
log_debug() { [ "${DEBUG:-0}" = "1" ] && echo "[DEBUG] $*" || true; }

require_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log_fatal "Required command not found: $cmd"
    fi
}

export -f log_info log_warn log_error log_fatal log_debug require_command
EOF
fi

# Fix the script's source path
sed -i 's|source "${SCRIPT_DIR}/scripts/_common/init.sh"|source "./_common/init.sh"|g' setup-postgres-replication.sh

# Run the setup
bash setup-postgres-replication.sh "$@"
