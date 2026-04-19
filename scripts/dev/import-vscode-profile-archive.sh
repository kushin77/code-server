#!/usr/bin/env bash
# @file        scripts/dev/import-vscode-profile-archive.sh
# @module      dev/migration
# @description import archived VS Code user profile into code-server user state
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<'EOF'
Usage:
  scripts/dev/import-vscode-profile-archive.sh <archive.tgz> [--restart]

Archive layout (expected):
  User/...
  extensions/...              (optional)

Examples:
  scripts/dev/import-vscode-profile-archive.sh /tmp/vscode-profile-20260417.tgz
  scripts/dev/import-vscode-profile-archive.sh /tmp/vscode-profile-20260417.tgz --restart
EOF
}

main() {
    local archive_path="${1:-}"
    local restart_after="${2:-}"

    if [[ -z "$archive_path" || "$archive_path" == "-h" || "$archive_path" == "--help" ]]; then
        usage
        return 2
    fi

    require_commands docker tar

    if [[ ! -f "$archive_path" ]]; then
        log_fatal "Archive not found: $archive_path"
    fi

    if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_CODE_SERVER"; then
        log_fatal "Container '$CONTAINER_CODE_SERVER' is not running"
    fi

    if [[ -f "$PWD/.github/copilot-instructions.md" ]]; then
        log_info "Found repository instruction rules at .github/copilot-instructions.md"
    else
        log_warn "Repository instruction rules file not found in current directory"
    fi

    local temp_dir
    temp_dir="$(mktemp_dir)"
    log_info "Extracting archive to temporary path"
    tar -xzf "$archive_path" -C "$temp_dir"

    if [[ ! -d "$temp_dir/User" ]]; then
        log_fatal "Archive is missing required 'User/' directory"
    fi

    local ts backup_path
    ts="$(date +%Y%m%d-%H%M%S)"
    backup_path="/home/coder/.migration-backups/pre-vscode-import-$ts.tgz"

    log_info "Backing up current code-server profile to $backup_path"
    docker exec "$CONTAINER_CODE_SERVER" sh -lc "set -eu; mkdir -p /home/coder/.migration-backups; tar -czf '$backup_path' -C /home/coder/.local/share/code-server User extensions 2>/dev/null || true"

    log_info "Importing VS Code User profile"
    docker exec "$CONTAINER_CODE_SERVER" sh -lc "mkdir -p /home/coder/.local/share/code-server/User"
    docker cp "$temp_dir/User/." "$CONTAINER_CODE_SERVER:/home/coder/.local/share/code-server/User/"

    if [[ -d "$temp_dir/extensions" ]]; then
        log_info "Importing extensions directory"
        docker exec "$CONTAINER_CODE_SERVER" sh -lc "mkdir -p /home/coder/.local/share/code-server/extensions"
        docker cp "$temp_dir/extensions/." "$CONTAINER_CODE_SERVER:/home/coder/.local/share/code-server/extensions/"
    else
        log_warn "No extensions directory in archive; extension import skipped"
    fi

    docker exec "$CONTAINER_CODE_SERVER" sh -lc "chown -R coder:coder /home/coder/.local/share/code-server"

    if [[ "$restart_after" == "--restart" ]]; then
        log_info "Restarting $CONTAINER_CODE_SERVER"
        docker restart "$CONTAINER_CODE_SERVER" >/dev/null
    fi

    log_info "Import complete"
    log_info "Pre-import backup is available at: $backup_path"
    log_info "Secrets are not modified by this script (.env/GSM/git helper untouched)"
}

main "$@"
