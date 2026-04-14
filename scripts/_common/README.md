# Shared Libraries - scripts/_common/

**Overview**: Reusable shell functions for standardized script behavior across the codebase.

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
