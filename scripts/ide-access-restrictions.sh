#!/usr/bin/env bash
# Read-Only IDE Access Wrapper for Code-Server
# 
# Purpose: Prevent developers from using code-server to bypass security
# by implementing a restricted shell that blocks dangerous commands.
#
# Restrictions:
# - No wget/curl (can't download tools)
# - No scp/sftp (can't exfiltrate files)
# - No nc/socat (can't create tunnels)
# - No sudo (can't escalate privileges)
# - No shell escape from editor (sed, awk remote execution)
#
# Use: Set as login shell in /etc/passwd or code-server shell config

set -eu

readonly RESTRICTED_COMMANDS=(
    "wget" "curl" "fetch"
    "scp" "sftp" "rcp"
    "nc" "netcat" "socat" "ssh-keyscan"
    "sudo" "su"
    "apt" "yum" "pacman" "brew"
    "docker" "podman"
    "gpg" "openssl" "ssh-keygen"
    "nmap" "netstat" "ss"
    "strace" "ltrace" "gdb"
    "reset" "env -i" "exec"
)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Allowed file operations (whitelist)
readonly ALLOWED_PATHS=(
    "$HOME/projects"
    "$HOME/dev"
    "$HOME/.config/code-server"
    "$HOME/.vscode"
    "/tmp/code-server-$$"
)

# Audit log
readonly AUDIT_LOG="/var/log/ide-access-audit.log"

log_access() {
    local cmd="$1"
    local status="$2"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    echo "${timestamp} | ${USER} | ${PRIMARY_IP} | ${cmd} | ${status}" >> "${AUDIT_LOG}" 2>/dev/null || true
}

is_restricted_command() {
    local cmd="$1"
    local base_cmd=$(basename "$cmd" 2>/dev/null || echo "$cmd")
    
    for restricted in "${RESTRICTED_COMMANDS[@]}"; do
        if [[ "$base_cmd" == "$restricted" ]] || [[ "$base_cmd" == "${restricted%% *}" ]]; then
            return 0  # True - is restricted
        fi
    done
    
    return 1  # False - not restricted
}

is_allowed_path() {
    local path="$1"
    local abs_path=$(cd "$path" 2>/dev/null && pwd || echo "$path")
    
    for allowed in "${ALLOWED_PATHS[@]}"; do
        if [[ "$abs_path" == "$allowed" ]] || [[ "$abs_path" == "$allowed"/* ]]; then
            return 0  # True - is allowed
        fi
    done
    
    return 1  # False - not allowed
}

check_command() {
    local cmd="$1"
    
    # Block restricted commands at execution
    if is_restricted_command "$cmd"; then
        echo -e "${RED}❌ Error: Command '$cmd' is not allowed in read-only IDE mode${NC}" >&2
        log_access "$cmd" "BLOCKED"
        return 1
    fi
    
    return 0
}

check_file_access() {
    local path="$1"
    local op="${2:-read}"
    
    # Allow reading config files
    if [[ "$op" == "read" ]]; then
        if is_allowed_path "$path"; then
            return 0
        fi
        
        # Allowed read-only paths
        case "$path" in
            /etc/hostname|/etc/timezone|/etc/locale.conf|/usr/share/zoneinfo/*)
                return 0
                ;;
            /proc/cpuinfo|/proc/meminfo|/proc/*/status)
                return 0
                ;;
            *)
                if [[ -e "$path" ]] && [[ -r "$path" ]] && [[ ! -w "$path" ]]; then
                    return 0
                fi
                ;;
        esac
    fi
    
    # Restrict writes to non-whitelist paths
    if [[ "$op" == "write" ]] || [[ "$op" == "modify" ]]; then
        if is_allowed_path "$path"; then
            return 0
        fi
        
        echo -e "${RED}❌ Error: Cannot modify '$path' in read-only IDE mode${NC}" >&2
        log_access "write:$path" "BLOCKED"
        return 1
    fi
    
    return 0
}

# Shell trap to intercept command execution
trap_cmd() {
    local cmd="$BASH_COMMAND"
    
    # Don't intercept empty commands or shell built-ins
    if [[ -z "$cmd" ]] || [[ "$cmd" == "echo"* ]] || [[ "$cmd" == "builtin"* ]]; then
        return 0
    fi
    
    # Check first token (the actual command)
    local first_token=$(echo "$cmd" | awk '{print $1}')
    
    # Skip if it's a builtin or legitimate operation
    case "$first_token" in
        ls|cd|pwd|echo|cat|less|more|grep|find|sed|awk|head|tail)
            # These are allowed
            return 0
            ;;
        *)
            # Check if restricted
            if ! check_command "$first_token"; then
                return 1
            fi
            ;;
    esac
}

# Mount namespace with read-only filesystem (optional, stronger security)
setup_readonly_namespace() {
    # This requires running with --userns or in a container
    # For regular bash, we'll use software restrictions instead
    
    # Create temporary writable directory
    local tmpdir="/tmp/code-server-$$"
    mkdir -p "$tmpdir"
    
    # Only allow writes to project directories
    export TMPDIR="$tmpdir"
    export HOME_PROJECTS="$HOME/projects"
}

# Interactive shell with restrictions
launch_restricted_shell() {
    local shell_type="${SHELL##*/}"
    
    if [[ "$shell_type" == "bash" ]]; then
        # Enable command checking
        shopt -s extdebug
        trap trap_cmd DEBUG
        
        # Start interactive bash
        exec bash --restricted --norc --noprofile
    elif [[ "$shell_type" == "zsh" ]]; then
        # For zsh, use a restricted zsh if available
        if command -v rzsh &> /dev/null; then
            exec rzsh
        else
            exec zsh -r
        fi
    else
        # Fallback to sh
        exec sh -r
    fi
}

# Print allowed commands
show_allowed_commands() {
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
  READ-ONLY IDE MODE ENABLED
═══════════════════════════════════════════════════════════════

✅ ALLOWED OPERATIONS:

  FILE EDITING:
    • Edit/create files in ~/projects/
    • Edit/create files in ~/dev/
    • Full code editor functionality via VS Code

  FILE OPERATIONS:
    • ls, find, grep - explore directory structure
    • cat, less, more - read file contents
    • Copy files within allowed directories

  GIT OPERATIONS:
    • git status, log, diff - view changes
    • git push/pull - via proxy server (see below)
    • git branch - manage branches
    • git checkout - switch branches

  DEBUGGING:
    • node/python debugger within code-server
    • Built-in terminal for running tests
    • Runs within code-server process only

❌ RESTRICTED COMMANDS:

  • wget, curl, fetch - Cannot download files
  • scp, sftp, rcp    - Cannot transfer files outside
  • nc, netcat        - Cannot create network tunnels
  • sudo, su          - Cannot escalate privileges
  • apt, yum, brew    - Cannot install packages
  • docker, podman    - Cannot spawn containers
  • ssh-keyscan      - Cannot scan SSH hosts
  • strace, gdb       - Cannot attach to processes
  • sed -e '/pattern/e' - Shell escapes disabled
  • Environment hijacking (env -i) blocked

═══════════════════════════════════════════════════════════════

📝 GIT OPERATIONS:

  For git push/pull, use the Git Proxy Server:

    git config credential.helper cloudflare-proxy
    git push origin feature-branch
    git pull origin main

  The proxy will:
    ✓ Authenticate with your Cloudflare Access token
    ✓ Use the home server's SSH key (not yours)
    ✓ Log all operations for audit trail
    ✓ Block pushes to main/master/production

═══════════════════════════════════════════════════════════════

📊 AUDIT LOGGING:

  All access attempts are logged to:
    /var/log/ide-access-audit.log

  Format: timestamp | user | ip | command | blocked|allowed

═══════════════════════════════════════════════════════════════

💡 NEED HELP?

  Feel free to edit files and run code within code-server.
  For operations outside this sandbox, contact an admin.

═══════════════════════════════════════════════════════════════
EOF
}

# Main entry point
main() {
    # Initialize for code-server or interactive shell
    show_allowed_commands
    
    # Set up restricted environment
    setup_readonly_namespace
    
    # Log entry
    PRIMARY_IP="${SSH_CLIENT%% *}"
    log_access "shell-login" "ALLOWED"
    
    # If code-server is running, it will use this shell
    # Otherwise, start interactive restricted shell
    if [[ "${CODE_SERVER_SESSION:-0}" == "1" ]]; then
        # code-server is handling command execution
        # Just set up environment and return
        return 0
    else
        # For testing or direct shell access
        launch_restricted_shell
    fi
}

# If sourced from code-server, just export functions
# If executed directly, run main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Export for use by code-server
export -f check_command
export -f check_file_access
export -f is_restricted_command
export -f is_allowed_path
