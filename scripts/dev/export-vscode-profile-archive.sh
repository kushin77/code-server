#!/usr/bin/env bash
# @file        scripts/dev/export-vscode-profile-archive.sh
# @module      dev/migration
# @description export local VS Code profile into a portable archive for code-server import
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<'EOF'
Usage:
  scripts/dev/export-vscode-profile-archive.sh [output.tgz]

Defaults:
  output: ./vscode-profile-export-YYYYMMDD-HHMMSS.tgz

Optional environment overrides:
  VSCODE_USER_DIR         path to VS Code User directory
  VSCODE_EXTENSIONS_DIR   path to VS Code extensions directory

Examples:
  scripts/dev/export-vscode-profile-archive.sh
  scripts/dev/export-vscode-profile-archive.sh /tmp/vscode-profile-export.tgz
EOF
}

detect_user_dir() {
    if [[ -n "${VSCODE_USER_DIR:-}" ]]; then
        echo "$VSCODE_USER_DIR"
        return
    fi

    local candidates=(
        "$HOME/.config/Code/User"
        "$HOME/Library/Application Support/Code/User"
        "$APPDATA/Code/User"
    )

    local dir
    for dir in "${candidates[@]}"; do
        if [[ -n "$dir" && -d "$dir" ]]; then
            echo "$dir"
            return
        fi
    done

    echo ""
}

detect_extensions_dir() {
    if [[ -n "${VSCODE_EXTENSIONS_DIR:-}" ]]; then
        echo "$VSCODE_EXTENSIONS_DIR"
        return
    fi

    local candidates=(
        "$HOME/.vscode/extensions"
        "$USERPROFILE/.vscode/extensions"
    )

    local dir
    for dir in "${candidates[@]}"; do
        if [[ -n "$dir" && -d "$dir" ]]; then
            echo "$dir"
            return
        fi
    done

    echo ""
}

main() {
    local output_path="${1:-}"

    if [[ "$output_path" == "-h" || "$output_path" == "--help" ]]; then
        usage
        return 0
    fi

    require_commands tar

    local user_dir ext_dir
    user_dir="$(detect_user_dir)"
    ext_dir="$(detect_extensions_dir)"

    if [[ -z "$user_dir" || ! -d "$user_dir" ]]; then
        log_fatal "Could not find VS Code User directory. Set VSCODE_USER_DIR and retry."
    fi

    if [[ -z "$output_path" ]]; then
        output_path="$PWD/vscode-profile-export-$(date +%Y%m%d-%H%M%S).tgz"
    fi

    local temp_dir
    temp_dir="$(mktemp_dir)"

    log_info "Preparing export staging directory"
    mkdir -p "$temp_dir/User"
    cp -R "$user_dir/." "$temp_dir/User/"

    if [[ -n "$ext_dir" && -d "$ext_dir" ]]; then
        log_info "Including extensions from $ext_dir"
        mkdir -p "$temp_dir/extensions"
        cp -R "$ext_dir/." "$temp_dir/extensions/"
    else
        log_warn "Extensions directory not found; archive will contain User/ only"
    fi

    mkdir -p "$(dirname "$output_path")"
    tar -czf "$output_path" -C "$temp_dir" .

    log_info "Export complete: $output_path"
    log_info "Next step: transfer archive to 192.168.168.31 and run import-vscode-profile-archive.sh"
}

main "$@"
