#!/usr/bin/env bash
# @file        scripts/nas-workspace-health.sh
# @module      operations/storage
# @description Validate NAS-backed workspace mounts and emit health metrics.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

NAS_PRIMARY_MOUNT="${NAS_PRIMARY_MOUNT:-/mnt/nas-56}"
NAS_EXPORT_MOUNT="${NAS_EXPORT_MOUNT:-/mnt/nas-export}"
NAS_WORKSPACE_PATH="${NAS_WORKSPACE_PATH:-/mnt/nas-56/kushin77/applications/code-server-enterprise}"
CODER_DATA_PATH="${CODER_DATA_PATH:-/mnt/nas-56/code-server}"
OLLAMA_DATA_PATH="${OLLAMA_DATA_PATH:-/mnt/nas-56/ollama}"
NODE_EXPORTER_TEXTFILE_DIR="${NODE_EXPORTER_TEXTFILE_DIR:-}"
OPTIONAL_WRITE_LABELS="${OPTIONAL_WRITE_LABELS:-ollama}"

failed=0
metrics_file="$(mktemp)"
trap 'rm -f "$metrics_file"' EXIT

emit_metric() {
    local name="$1"
    local labels="$2"
    local value="$3"
    printf '%s{%s} %s\n' "$name" "$labels" "$value" >> "$metrics_file"
}

check_mount() {
    local mount_path="$1"
    local label="$2"

    if mountpoint -q "$mount_path"; then
        log_success "NAS mount active: $mount_path"
        emit_metric "nas_workspace_mount_up" "name=\"$label\",path=\"$mount_path\"" 1
    else
        log_error "NAS mount missing: $mount_path"
        emit_metric "nas_workspace_mount_up" "name=\"$label\",path=\"$mount_path\"" 0
        failed=1
    fi
}

check_directory() {
    local directory_path="$1"
    local label="$2"

    if [[ -d "$directory_path" ]]; then
        log_success "Directory present: $directory_path"
        emit_metric "nas_workspace_path_exists" "name=\"$label\",path=\"$directory_path\"" 1
    else
        log_error "Directory missing: $directory_path"
        emit_metric "nas_workspace_path_exists" "name=\"$label\",path=\"$directory_path\"" 0
        failed=1
    fi
}

check_writable() {
    local directory_path="$1"
    local label="$2"
    local probe_file

    probe_file="$directory_path/.nas-health-$$"
    if touch "$probe_file" 2>/dev/null && rm -f "$probe_file" 2>/dev/null; then
        log_success "Directory writable: $directory_path"
        emit_metric "nas_workspace_path_writable" "name=\"$label\",path=\"$directory_path\"" 1
    else
        if [[ ",$OPTIONAL_WRITE_LABELS," == *",$label,"* ]]; then
            log_warn "Directory not writable by current user: $directory_path"
        else
            log_error "Directory not writable: $directory_path"
            failed=1
        fi
        emit_metric "nas_workspace_path_writable" "name=\"$label\",path=\"$directory_path\"" 0
    fi
}

check_capacity() {
    local mount_path="$1"
    local label="$2"
    local available_kb
    local used_percent

    available_kb="$(df -k "$mount_path" | awk 'NR==2 {print $4}')"
    used_percent="$(df -k "$mount_path" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"

    emit_metric "nas_workspace_available_kb" "name=\"$label\",path=\"$mount_path\"" "$available_kb"
    emit_metric "nas_workspace_used_percent" "name=\"$label\",path=\"$mount_path\"" "$used_percent"

    if [[ "$used_percent" -lt 85 ]]; then
        log_success "Capacity healthy on $mount_path: ${used_percent}% used"
    else
        log_warn "Capacity high on $mount_path: ${used_percent}% used"
    fi
}

log_info "Checking NAS-backed workspace health"

check_mount "$NAS_PRIMARY_MOUNT" "primary"
check_mount "$NAS_EXPORT_MOUNT" "export"

check_directory "$NAS_WORKSPACE_PATH" "workspace"
check_directory "$CODER_DATA_PATH" "coder_home"
check_directory "$OLLAMA_DATA_PATH" "ollama"

check_writable "$NAS_WORKSPACE_PATH" "workspace"
check_writable "$CODER_DATA_PATH" "coder_home"
check_writable "$OLLAMA_DATA_PATH" "ollama"

check_capacity "$NAS_PRIMARY_MOUNT" "primary"
check_capacity "$NAS_EXPORT_MOUNT" "export"

if [[ -n "$NODE_EXPORTER_TEXTFILE_DIR" ]]; then
    install -d "$NODE_EXPORTER_TEXTFILE_DIR"
    cp "$metrics_file" "$NODE_EXPORTER_TEXTFILE_DIR/nas_workspace_health.prom"
    log_info "Wrote Prometheus metrics to $NODE_EXPORTER_TEXTFILE_DIR/nas_workspace_health.prom"
else
    cat "$metrics_file"
fi

if [[ "$failed" -eq 0 ]]; then
    log_success "NAS workspace health checks passed"
else
    log_error "NAS workspace health checks failed"
    exit 1
fi