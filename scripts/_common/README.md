# Shared Libraries — `scripts/_common/`

**The canonical source for all reusable shell functions.** Every script in `scripts/` must source from here — never define `log_info()`, `retry()`, or connection constants inline.

---

## Quick Start (one line per script)

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"   # ← This is the ONLY source line you need
```

For scripts one level down (e.g. `scripts/ci/`):
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"
```

---

## Module Reference

### `init.sh` ← **Start Here**
Single bootstrap entrypoint. Sources all modules below in the correct order.
- Loads: `config.sh` → `logging.sh` → `utils.sh` → `error-handler.sh`
- Auto-loads `docker.sh` and `ssh.sh` if present
- Sets `set -euo pipefail` for the calling script
- Guarded against double-sourcing

---

### `config.sh` — Environment Constants
**Single source of truth.** Do not hardcode any of these values in any script.

| Constant | Default | Override |
|---|---|---|
| `DEPLOY_HOST` | `192.168.168.31` | `export DEPLOY_HOST=...` |
| `DEPLOY_USER` | `akushnir` | `export DEPLOY_USER=...` |
| `DEPLOY_DIR` | `/home/akushnir/code-server-enterprise` | `export DEPLOY_DIR=...` |
| `STANDBY_HOST` | `192.168.168.30` | |
| `DOMAIN` | `ide.kushnir.cloud` | |
| `REPO` | `kushin77/code-server` | |
| `ENTERPRISE_NETWORK` | `code-server-enterprise_enterprise` | |
| `CONTAINER_CODE_SERVER` | `code-server` | |
| `CONTAINER_CADDY` | `caddy` | |
| `CONTAINER_OLLAMA` | `ollama` | |
| `PORT_CODE_SERVER` | `8080` | |
| `PORT_GRAFANA` | `3000` | |
| `PORT_PROMETHEUS` | `9090` | |
| `LOG_FORMAT` | `text` | Set `json` for Loki ingestion |

---

### `logging.sh` — Structured Logging

```bash
log_debug "verbose detail"          # gray,  LOG_LEVEL=0
log_info  "normal message"          # green, LOG_LEVEL=1
log_warn  "something off"           # yellow,LOG_LEVEL=2
log_error "non-fatal problem"       # red,   LOG_LEVEL=3
log_fatal "abort now"               # red,   LOG_LEVEL=4, exits 1
log_section "─── PHASE 1 ───"       # divider header
log_success "all checks passed"     # green ✓
log_exec   "docker compose up -d"   # log + execute
```

**JSON mode** (for Grafana Loki):
```bash
export LOG_FORMAT=json
# Output: {"ts":"2026-04-14T...","level":"INFO","script":"deploy.sh","msg":"..."}
```

**Environment variables:**
- `LOG_LEVEL` — 0=debug, 1=info (default), 2=warn, 3=error, 4=fatal
- `LOG_NO_COLOR=1` — disable ANSI colors (CI environments)
- `LOG_FILE=/path/to/file` — write to file in addition to stdout
- `LOG_FORMAT=json` — structured output for log aggregation

---

### `utils.sh` — Utility Functions

**Retry with exponential backoff:**
```bash
retry 3 docker pull myimage:tag
retry 5 curl -sf http://localhost:8080/health
```

**Prerequisite enforcement:**
```bash
require_command docker
require_commands docker curl jq ssh
require_file /etc/caddy/Caddyfile
require_dir /home/coder
```

**Cleanup handlers:**
```bash
add_cleanup "docker stop temp-container"
add_cleanup "rm -f /tmp/deploy.lock"
# handlers run automatically on EXIT
```

---

### `error-handler.sh` — Error Trapping

Automatically installed when sourced:
- `ERR` trap with exit code and line number
- Stack trace when `DEBUG=1`
- `assert_eq`, `assert_ne`, `assert_true` functions

```bash
# Enable verbose tracing
export DEBUG=1

# Assertions
assert_eq "$DEPLOY_HOST" "192.168.168.31" "Wrong host"
assert_true "$(docker_is_running code-server)" "code-server must be running"
```

---

### `ssh.sh` — Remote Execution

```bash
assert_ssh_up                          # confirm connectivity before work
ssh_exec "docker ps"                   # run on DEPLOY_HOST
ssh_standby "docker ps"                # run on STANDBY_HOST
ssh_stream ./scripts/deploy.sh         # pipe local script to remote bash
ssh_upload ./config.yml /remote/path   # scp wrapper
ssh_in_deploy_dir "docker compose ps"  # cd DEPLOY_DIR + exec
ssh_compose "up -d code-server"        # docker compose shortcut
assert_port_open 443                   # TCP reachability check
```

---

### `docker.sh` — Container Operations

```bash
docker_status code-server              # → "Up 2 hours (healthy)"
docker_is_running code-server          # → 0/1
docker_is_healthy prometheus           # → 0/1
docker_wait_healthy grafana 60         # wait up to 60s
assert_container_healthy alertmanager  # fatal if not healthy

docker_start code-server caddy         # compose up
docker_stop ollama                     # docker stop
docker_restart caddy                   # docker restart
docker_exec_in code-server "ls /home"  # docker exec
docker_logs caddy 50                   # last 50 lines

docker_status_all                      # formatted table all containers
docker_healthcheck_all                 # full health check, returns 1 on failure

assert_http_ok "http://localhost:8080/" 200   # HTTP endpoint check
```

---

## Governance

- **Violation**: defining `log_info()` inline in any script → blocked by pre-commit hook
- **Violation**: hardcoding `192.168.168.31` → `$DEPLOY_HOST` from `config.sh`
- **Audit**: `make lib-check` — shows all non-compliant scripts
- **Registry**: `scripts/MANIFEST.toml` — every script must be registered

## Deprecated (do not source)

| File | Replacement |
|---|---|
| `scripts/logging.sh` | `_common/logging.sh` (via `init.sh`) |
| `scripts/common-functions.sh` | `_common/utils.sh + error-handler.sh` (via `init.sh`) |

Both files now emit a deprecation warning at source time and forward to the correct implementation.


## Files

### logging.sh
Standardized logging with color output, levels, and file output.

**Functions**:
- `log_debug()` - Debug level messages (gray)
- `log_info()` - Info level messages (green)
- `log_warn()` - Warning level messages (yellow)
- `log_error()` - Error level messages (red), returns 1
- `log_fatal()` - Fatal level messages (red), exits with code 1
- `log_exec()` - Log and execute a command
- `log_section()` - Log a section header with divider
- `log_success()` - Log success message with ✓
- `log_failure()` - Log failure message with ✗

**Environment Variables**:
- `LOG_LEVEL` (0=debug, 1=info, 2=warn, 3=error, 4=fatal) — default: 1
- `LOG_NO_COLOR` (0/1) — disable colored output
- `LOG_FILE` (path) — write logs to file in addition to stdout

**Usage**:
```bash
#!/bin/bash
source "$(dirname "$0")/../_common/logging.sh"

log_info "Starting deployment..."
log_debug "Some debug info"
log_warn "Warning message"
log_error "Error occurred"
log_fatal "Fatal error - exiting"
```

---

### utils.sh
Common utility functions for retries, prerequisites, cleanup, and Docker operations.

**Functions**:

**Retry Logic**:
- `retry <max_attempts> <command>` - Retry with exponential backoff

**Prerequisite Checking**:
- `require_command <cmd>` - Check if command exists
- `require_commands <cmd1> [cmd2] ...` - Check multiple commands
- `require_file <path>` - Check if file exists
- `require_dir <path>` - Check if directory exists
- `require_var <VAR_NAME>` - Check if environment variable is set

**Cleanup**:
- `add_cleanup <function>` - Register cleanup function to run on exit
- `mktemp_dir` - Create temp directory with automatic cleanup

**File Operations**:
- `copy_file <src> <dst>` - Copy with verification

**String Utilities**:
- `string_contains <string> <substring>` - Check for substring
- `string_match <string> <regex>` - Match regex
- `str_trim <string>` - Trim whitespace

**Array Utilities**:
- `array_contains <element> <arr...>` - Check if array contains element
- `array_join <separator> <arr...>` - Join array with separator

**Docker Utilities**:
- `docker_ready` - Check if Docker is available
- `docker_wait_healthy <container> [timeout]` - Wait for container to be healthy

**Usage**:
```bash
#!/bin/bash
source "$(dirname "$0")/../_common/logging.sh"
source "$(dirname "$0")/../_common/utils.sh"

# Check prerequisites
require_commands docker curl
require_file ".env"

# Retry operation
retry 3 docker pull image:tag

# Cleanup handling
cleanup() {
    log_info "Cleaning up..."
    docker stop container
}
add_cleanup cleanup

# Docker operations
docker_ready || log_fatal "Docker not available"
docker_wait_healthy my-container 30
```

---

### error-handler.sh
Enhanced error handling with stack traces, assertions, and debugging.

**Functions**:

**Debug Control**:
- `enable_debug` - Enable debug mode (set -x)
- `disable_debug` - Disable debug mode
- `print_debug <message>` - Print debug message if enabled

**Assertions**:
- `assert_success <command>` - Assert command succeeds
- `assert_failure <command>` - Assert command fails
- `assert_equal <expected> <actual>` - Assert equality
- `assert_not_empty <value> [name]` - Assert value not empty
- `assert_file <path>` - Assert file exists and readable

**Validation**:
- `validate_exit <exit_code> <command>` - Validate exit code
- `check_exit` - Check if last command succeeded

**Context Stack** (for nested operations):
- `push_context <name>` - Enter context
- `pop_context` - Exit context
- `get_context` - Get current context name
- `with_context <name> <command>` - Run command in context

**Features**:
- Automatic error trapping with line numbers
- Stack traces in debug mode
- Context awareness for nested operations

**Usage**:
```bash
#!/bin/bash
source "$(dirname "$0")/../_common/logging.sh"
source "$(dirname "$0")/../_common/error-handler.sh"

# Enable debug for detailed output
if [ "${DEBUG:-0}" == "1" ]; then
    enable_debug
fi

# Assert requirements
assert_not_empty "$IMAGE_NAME" "IMAGE_NAME"
assert_file ".env"

# Validate operations
validate_exit 0 curl -f "http://localhost:8080"

# Use context for clarity
with_context "database-migration" ${
    log_info "Running migrations..."
    ./migrate.sh
}
```

---

## Integration Guide

### For New Scripts

1. **Source the libraries at the top**:
```bash
#!/bin/bash
source "$(dirname "$0")/../_common/logging.sh"
source "$(dirname "$0")/../_common/utils.sh"
source "$(dirname "$0")/../_common/error-handler.sh"
```

2. **Use logging throughout**:
```bash
log_info "Starting operation..."
log_warn "This took longer than expected"
log_error "Operation failed"
```

3. **Add error handling**:
```bash
require_commands docker docker-compose
docker_ready || log_fatal "Docker is not available"
```

4. **Register cleanup**:
```bash
cleanup() {
    log_info "Cleaning up resources..."
}
add_cleanup cleanup
```

### For Existing Scripts

Gradually migrate existing scripts to use the shared libraries:
1. Add library sources at top
2. Replace `echo` calls with `log_info`/`log_error`
3. Replace manual error checking with `require_*` functions
4. Replace cleanup logic with `add_cleanup`

---

## Examples

### Simple Deployment Script
```bash
#!/bin/bash
source "$(dirname "$0")/../_common/logging.sh"
source "$(dirname "$0")/../_common/utils.sh"

require_commands docker docker-compose

log_section "Deploying Application"

log_info "Pulling latest images..."
retry 3 docker-compose pull

log_info "Starting containers..."
docker-compose up -d

if docker_wait_healthy web 60; then
    log_success "Deployment complete"
else
    log_failure "Deployment failed - web container not healthy"
    exit 1
fi
```

### Backup Script with Cleanup
```bash
#!/bin/bash
source "$(dirname "$0")/../_common/logging.sh"
source "$(dirname "$0")/../_common/utils.sh"

BACKUP_DIR=$(mktemp_dir)
log_info "Using backup directory: $BACKUP_DIR"

cleanup() {
    if [ -d "$BACKUP_DIR" ]; then
        log_info "Removing temporary directory: $BACKUP_DIR"
        rm -rf "$BACKUP_DIR"
    fi
}
add_cleanup cleanup

log_info "Creating database backup..."
pg_dump mydb > "$BACKUP_DIR/backup.sql"

log_success "Backup complete: $BACKUP_DIR/backup.sql"
```

---

## Environment Configuration

Set these variables before sourcing the libraries to customize behavior:

```bash
# Logging configuration
export LOG_LEVEL=1        # 0=debug, 1=info, 2=warn, 3=error, 4=fatal
export LOG_NO_COLOR=0     # Set to 1 to disable colored output
export LOG_FILE="/var/log/deploy.log"  # Optional: write logs to file

# Debug mode
export DEBUG=1            # Enable detailed debug output

# Source libraries
source "$(dirname "$0")/../_common/logging.sh"
source "$(dirname "$0")/../_common/utils.sh"
source "$(dirname "$0")/../_common/error-handler.sh"
```

---

## Standards & Best Practices

1. **Always source in this order**:
   - logging.sh (required by others)
   - utils.sh
   - error-handler.sh

2. **Use appropriate log levels**:
   - `log_debug` - Internal state, variable values
   - `log_info` - Major operations, progress
   - `log_warn` - Unexpected but recoverable situations
   - `log_error` - Recoverable errors
   - `log_fatal` - Unrecoverable errors

3. **Validate prerequisites early**:
   ```bash
   require_commands docker docker-compose
   require_vars DATABASE_URL API_KEY
   ```

4. **Always register cleanup**:
   ```bash
   add_cleanup < cleanup_function_name
   ```

5. **Use meaningful log messages**:
   - Good: `log_info "Deploying service to production"`
   - Bad: `log_info "done"`

---

**Last Updated**: April 14, 2026  
**Maintained By**: DevOps Team  
**Status**: Phase 1, Task 1.6 Complete
