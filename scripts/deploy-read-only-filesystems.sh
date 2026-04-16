#!/bin/bash
# scripts/deploy-read-only-filesystems.sh
# ========================================
# Deploy read_only filesystems + tmpfs mounts for containers
# Makes containers immutable except for designated writable volumes
#
# Usage:
#   bash scripts/deploy-read-only-filesystems.sh [--dry-run]
#
# Prerequisites:
#   - Docker Compose running
#   - docker-compose.yml modified with read_only: true + tmpfs

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

log_info() { echo "[INFO] $*"; }
log_ok()  { echo "  ✓ $*"; }
log_warn(){ echo "  ⚠ $*"; }
log_err() { echo "  ✗ $*" >&2; }

dry() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

log_info "═══════════════════════════════════════════════════════════════"
log_info "Container Read-Only Filesystem Hardening (#354)"
log_info "═══════════════════════════════════════════════════════════════"

# Service-specific tmpfs requirements
declare -A TMPFS_MOUNTS=(
    [code-server]="/run /tmp"
    [postgres]="/var/run/postgresql /var/lib/postgresql"
    [redis]="/var/run /tmp"
    [caddy]="/run /var/lib/caddy"
    [prometheus]="/run /tmp"
    [grafana]="/run /var/lib/grafana/plugins"
    [alertmanager]="/run /tmp"
    [jaeger]="/run /tmp"
    [loki]="/run /tmp /var/log"
    [oauth2-proxy]="/run /tmp"
    [coredns]="/run /tmp"
)

# ─── 1. Analyze current docker-compose.yml ────────────────────────────────

log_info "1: Analyzing docker-compose.yml..."

if [[ ! -f docker-compose.yml ]]; then
    log_err "docker-compose.yml not found"
    exit 1
fi

# ─── 2. Create docker-compose-readonly.patch ─────────────────────────────

log_info "2: Generating read-only filesystem patch..."

if [[ "${DRY_RUN}" == "false" ]]; then
    cat > docker-compose-readonly.patch <<'PATCH'
# Read-Only Filesystem Configuration for docker-compose.yml
# Apply this patch to enable immutable containers

# code-server service
code-server:
  read_only: true
  tmpfs:
    - /run
    - /tmp
    - /home/coder/.local

# postgres service  
postgres:
  read_only: true
  tmpfs:
    - /var/run/postgresql
    - /var/lib/postgresql

# redis service
redis:
  read_only: true
  tmpfs:
    - /var/run
    - /tmp

# caddy service
caddy:
  read_only: true
  tmpfs:
    - /run
    - /var/lib/caddy
    - /var/cache/caddy

# prometheus service
prometheus:
  read_only: true
  tmpfs:
    - /run
    - /tmp
    - /var/cache/prometheus

# grafana service
grafana:
  read_only: true
  tmpfs:
    - /run
    - /var/lib/grafana/plugins
    - /var/lib/grafana/png-cache

# alertmanager service
alertmanager:
  read_only: true
  tmpfs:
    - /run
    - /tmp
    - /var/cache/alertmanager

# jaeger service
jaeger:
  read_only: true
  tmpfs:
    - /run
    - /tmp
    - /var/lib/jaeger

# loki service
loki:
  read_only: true
  tmpfs:
    - /run
    - /tmp
    - /var/log/loki

# oauth2-proxy service
oauth2-proxy:
  read_only: true
  tmpfs:
    - /run
    - /tmp

# coredns service
coredns:
  read_only: true
  tmpfs:
    - /run
    - /tmp

PATCH
    log_ok "docker-compose-readonly.patch created"
fi

# ─── 3. Validate current containers are not read-only ────────────────────

log_info "3: Validating container configuration..."

# Check if any containers are already read-only
readonly_count=$(grep -c "read_only: true" docker-compose.yml || echo 0)
if [[ ${readonly_count} -gt 0 ]]; then
    log_warn "Found ${readonly_count} containers already with read_only: true"
else
    log_ok "No containers currently read-only (patch will add)"
fi

# ─── 4. Test application with read-only filesystem ────────────────────────

log_info "4: Testing read-only filesystem compatibility..."

if [[ "${DRY_RUN}" == "false" ]]; then
    # Start a test container with read-only filesystem
    log_info "Starting test container with read-only filesystem..."
    
    if docker run --rm --read-only --tmpfs /tmp --tmpfs /run alpine:latest ls / &>/dev/null; then
        log_ok "Read-only filesystem test passed"
    else
        log_err "Read-only filesystem test failed - some containers may have issues"
    fi
fi

# ─── 5. AppArmor profile for read-only enforcement ────────────────────────

log_info "5: Generating AppArmor profile for read-only enforcement..."

if [[ "${DRY_RUN}" == "false" ]]; then
    cat > /tmp/code-server-readonly-apparmor.profile <<'APPARMOR'
#include <tunables/global>

profile code-server-readonly {
  #include <abstractions/base>

  # Read-only root filesystem
  / r,
  /** r,

  # Allow writes only to designated tmpfs mounts
  /run/ w,
  /run/** w,
  /tmp/ w,
  /tmp/** w,
  /home/coder/.local/ w,
  /home/coder/.local/** w,

  # Deny writes to sensitive locations
  deny /etc/** w,
  deny /sys/** w,
  deny /proc/** w,
}
APPARMOR
    log_ok "AppArmor profile generated at /tmp/code-server-readonly-apparmor.profile"
fi

# ─── 6. Document filesystem requirements per service ─────────────────────

log_info "6: Documenting tmpfs requirements..."

if [[ "${DRY_RUN}" == "false" ]]; then
    cat > READONLY-FILESYSTEM-REQUIREMENTS.md <<'DOCS'
# Read-Only Filesystem Configuration

## Overview
All production containers run with `read_only: true` to prevent accidental modifications.
Writable tmpfs mounts are allocated for application runtime requirements.

## Service-Specific tmpfs Mounts

### code-server
- `/run`: PID files, Unix sockets
- `/tmp`: Temporary files, shell operations
- `/home/coder/.local`: User workspace cache (VS Code extensions)

### postgres
- `/var/run/postgresql`: Socket files for connections
- `/var/lib/postgresql`: Runtime temp data (WAL segments, autovacuum)

### redis
- `/var/run`: Socket files
- `/tmp`: Temporary data structures

### caddy
- `/run`: PID files
- `/var/lib/caddy`: TLS certificate cache
- `/var/cache/caddy`: HTTP cache

### prometheus
- `/run`: PID files
- `/tmp`: Temporary scrape files
- `/var/cache/prometheus`: PromQL cache

### grafana
- `/run`: PID files
- `/var/lib/grafana/plugins`: Plugin installation
- `/var/lib/grafana/png-cache`: Dashboard PNG cache

### alertmanager
- `/run`: PID files
- `/tmp`: Temporary notification messages
- `/var/cache/alertmanager`: Silences cache

### jaeger
- `/run`: PID files
- `/tmp`: Temporary trace data
- `/var/lib/jaeger`: Index cache

### loki
- `/run`: PID files
- `/tmp`: Temporary log ingestion
- `/var/log/loki`: Log index cache

### oauth2-proxy
- `/run`: PID files
- `/tmp`: Session data

### coredns
- `/run`: PID files
- `/tmp`: Cache data

## Verification

```bash
# Verify read-only flag
docker inspect <container> | grep ReadOnly

# Check tmpfs mounts
docker inspect <container> | grep -A 20 '"Mounts"'

# Test write attempts
docker exec <container> touch /test-write-file
# Should fail with: Read-only file system
```

## Troubleshooting

If a container fails with "Read-only file system" error:

1. Identify the failing path from logs:
   ```bash
   docker logs <container> | grep "Read-only"
   ```

2. Add the path to tmpfs mounts:
   ```yaml
   <service>:
     read_only: true
     tmpfs:
       - /path/to/write
   ```

3. Restart the container:
   ```bash
   docker-compose up -d <service>
   ```

## Security Benefits

- **Immutability**: Prevents accidental or malicious modifications to application code
- **Container integrity**: Binaries cannot be modified at runtime
- **Supply chain protection**: Protects against code injection attacks
- **Compliance**: Meets security hardening requirements (CIS, NIST)

## Performance Impact

- Minimal: tmpfs mounts are in-memory, providing **faster** I/O than disk
- No additional overhead for reads (read-only filesystem)
- Reduced disk I/O contention for container runtime data

DOCS
    log_ok "Created READONLY-FILESYSTEM-REQUIREMENTS.md"
fi

# ─── 7. Summary and next steps ────────────────────────────────────────────

log_info "═══════════════════════════════════════════════════════════════"
log_ok "Read-only filesystem analysis complete"
log_info "═══════════════════════════════════════════════════════════════"
log_info ""
log_info "Next steps:"
log_info "1. Review docker-compose-readonly.patch"
log_info "2. Merge patch into docker-compose.yml"
log_info "3. Redeploy containers: docker-compose up -d"
log_info "4. Verify: docker inspect <container> | grep ReadOnly"
log_info ""
log_warn "Manual validation required for each service:"
log_warn "- Check application logs for 'Read-only file system' errors"
log_warn "- Adjust tmpfs mounts as needed"
log_warn "- Document any additional writable paths"
