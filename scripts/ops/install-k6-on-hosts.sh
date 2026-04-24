#!/usr/bin/env bash
# @file        scripts/ops/install-k6-on-hosts.sh
# @module      operations/deployment
# @description Install k6 load testing CLI on production hosts for performance validation
# @owner       Kushnir
# @status      Production
#
# Usage:
#   Local install:  bash scripts/ops/install-k6-on-hosts.sh --local
#   Remote deploy:  bash scripts/ops/install-k6-on-hosts.sh --host 192.168.168.31 --host 192.168.168.42
#   All hosts:      bash scripts/ops/install-k6-on-hosts.sh --all-replicas

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# Initialize repo context and load shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || { echo "Failed to source init.sh"; exit 1; }

# Configuration
HOSTS_TO_INSTALL=()
INSTALL_LOCAL=false
INSTALL_ALL_REPLICAS=false
DRY_RUN=false
FORCE_INSTALL=false

# K6 installation settings
K6_GITHUB_REPO="grafana/k6"
K6_VERSION="${K6_VERSION:-latest}"
K6_LINUX_AMD64_URL="https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz"
K6_INSTALL_DIR="/usr/local/bin"
K6_TEMP_DIR="/tmp/k6-install-$$"

# Production replica IPs
REPLICA_1="192.168.168.31"
REPLICA_2="192.168.168.42"
REPLICA_USER="${REPLICA_USER:-akushnir}"

# Logging helpers from shared library (via init.sh)
# log_info, log_warn, log_error, log_fatal already available

#────────────────────────────────────────────────────────────────────────────
# FUNCTION: parse_arguments
#────────────────────────────────────────────────────────────────────────────
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local)
                INSTALL_LOCAL=true
                shift
                ;;
            --host)
                HOSTS_TO_INSTALL+=("$2")
                shift 2
                ;;
            --all-replicas)
                INSTALL_ALL_REPLICAS=true
                HOSTS_TO_INSTALL=("$REPLICA_1" "$REPLICA_2")
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --version)
                K6_VERSION="$2"
                shift 2
                ;;
            --help)
                print_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done
}

#────────────────────────────────────────────────────────────────────────────
# FUNCTION: print_help
#────────────────────────────────────────────────────────────────────────────
print_help() {
    cat << 'EOF'
Usage: bash scripts/ops/install-k6-on-hosts.sh [OPTIONS]

OPTIONS:
  --local                Install k6 on local machine (current environment)
  --host <IP>            Install on specific host (can be used multiple times)
  --all-replicas         Install on all production replicas (192.168.168.31, 192.168.168.42)
  --dry-run              Show what would be done without executing
  --force                Force reinstall even if k6 already exists
  --version <VERSION>    Specify k6 version (default: latest)
  --help                 Show this help message

EXAMPLES:
  # Install locally
  bash scripts/ops/install-k6-on-hosts.sh --local

  # Install on specific hosts
  bash scripts/ops/install-k6-on-hosts.sh --host 192.168.168.31 --host 192.168.168.42

  # Install on all production replicas
  bash scripts/ops/install-k6-on-hosts.sh --all-replicas

  # Dry-run to see what would happen
  bash scripts/ops/install-k6-on-hosts.sh --all-replicas --dry-run

  # Force reinstall with specific version
  bash scripts/ops/install-k6-on-hosts.sh --local --force --version v0.50.0
EOF
}

#────────────────────────────────────────────────────────────────────────────
# FUNCTION: check_k6_installed
# Returns 0 if k6 is installed and in PATH, 1 otherwise
#────────────────────────────────────────────────────────────────────────────
check_k6_installed() {
    if command -v k6 &> /dev/null; then
        local version
        version=$(k6 version 2>&1 || echo "unknown")
        log_info "k6 already installed: $version"
        return 0
    else
        log_info "k6 not found in PATH"
        return 1
    fi
}

#────────────────────────────────────────────────────────────────────────────
# FUNCTION: install_k6_locally
# Install k6 on the current local machine
#────────────────────────────────────────────────────────────────────────────
install_k6_locally() {
    log_info "Installing k6 locally..."

    # Check if already installed
    if check_k6_installed && [ "$FORCE_INSTALL" != "true" ]; then
        log_warn "k6 already installed. Use --force to reinstall."
        return 0
    fi

    # Detect OS and architecture
    local os kernel arch
    kernel=$(uname -s)
    arch=$(uname -m)

    log_info "Detected OS: $kernel, Architecture: $arch"

    case "$kernel" in
        Linux)
            install_k6_linux "$arch"
            ;;
        Darwin)
            install_k6_macos "$arch"
            ;;
        *)
            log_error "Unsupported OS: $kernel"
            return 1
            ;;
    esac
}

#────────────────────────────────────────────────────────────────────────────
# FUNCTION: install_k6_linux
#────────────────────────────────────────────────────────────────────────────
install_k6_linux() {
    local arch=$1

    # Map uname arch to k6 release names
    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
    esac

    local url="https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-${arch}.tar.gz"

    log_info "Downloading k6 from: $url"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would download and extract: $url"
        return 0
    fi

    # Download k6
    mkdir -p "$K6_TEMP_DIR"
    cd "$K6_TEMP_DIR"
    curl -sSL "$url" | tar xz

    # Check if k6 binary exists
    if [ ! -f "k6" ]; then
        log_error "Failed to extract k6 binary"
        rm -rf "$K6_TEMP_DIR"
        return 1
    fi

    # Install with sudo if needed
    if [ -w "$K6_INSTALL_DIR" ]; then
        mv k6 "$K6_INSTALL_DIR/k6"
    else
        sudo mv k6 "$K6_INSTALL_DIR/k6"
    fi

    # Verify installation
    if ! command -v k6 &> /dev/null; then
        log_error "k6 installation failed - k6 command not found after install"
        rm -rf "$K6_TEMP_DIR"
        return 1
    fi

    log_info "k6 successfully installed: $(k6 version)"
    rm -rf "$K6_TEMP_DIR"
    return 0
}

#────────────────────────────────────────────────────────────────────────────
# FUNCTION: install_k6_macos
#────────────────────────────────────────────────────────────────────────────
install_k6_macos() {
    log_info "macOS detected - using brew to install k6"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would run: brew install k6"
        return 0
    fi

    if ! command -v brew &> /dev/null; then
        log_error "brew not found. Please install Homebrew first."
        return 1
    fi

    brew install k6
    log_info "k6 successfully installed via brew: $(k6 version)"
    return 0
}

#────────────────────────────────────────────────────────────────────────────
# FUNCTION: install_k6_on_remote_host
# SSH to remote host and install k6
#────────────────────────────────────────────────────────────────────────────
install_k6_on_remote_host() {
    local host=$1
    local user=${2:-$REPLICA_USER}

    log_info "Installing k6 on remote host: $user@$host"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would SSH to $user@$host and install k6"
        return 0
    fi

    # Create inline installation script
    local remote_script="
set -euo pipefail
echo 'Installing k6 on $(hostname)...'

# Check if already installed
if command -v k6 &> /dev/null; then
    echo 'k6 already installed: '
    k6 version
    exit 0
fi

# Create temp directory
TEMP_DIR=\$(mktemp -d)
cd \"\$TEMP_DIR\"

# Download and extract k6
curl -sSL 'https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz' | tar xz

# Install k6
if [ -f k6 ]; then
    sudo mv k6 /usr/local/bin/k6 || mv k6 /usr/local/bin/k6
    sudo chmod +x /usr/local/bin/k6
    echo 'k6 installed successfully: '
    k6 version
else
    echo 'ERROR: Failed to extract k6 binary'
    exit 1
fi

# Cleanup
cd /tmp
rm -rf \"\$TEMP_DIR\"
"

    # Execute on remote host via SSH
    if ! ssh -o ConnectTimeout=10 "$user@$host" bash << 'EOFSCRIPT'
set -euo pipefail
echo 'Installing k6 on $(hostname)...'

# Check if already installed
if command -v k6 &> /dev/null; then
    echo 'k6 already installed: '
    k6 version
    exit 0
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download and extract k6
echo "Downloading k6..."
curl -sSL 'https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz' | tar xz

# Install k6
if [ -f k6 ]; then
    echo "Moving k6 to /usr/local/bin..."
    sudo mv k6 /usr/local/bin/k6 || mv k6 /usr/local/bin/k6
    sudo chmod +x /usr/local/bin/k6
    echo "k6 installed successfully!"
    k6 version
else
    echo "ERROR: Failed to extract k6 binary"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup
cd /tmp
rm -rf "$TEMP_DIR"
EOFSCRIPT
    then
        log_error "Failed to connect to $user@$host or installation failed"
        return 1
    fi

    log_info "k6 successfully installed on $host"
    return 0
}

#────────────────────────────────────────────────────────────────────────────
# FUNCTION: verify_k6_installation
# Verify k6 is working by running a test
#────────────────────────────────────────────────────────────────────────────
verify_k6_installation() {
    local host=${1:-local}

    log_info "Verifying k6 installation..."

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would verify k6 installation"
        return 0
    fi

    if [ "$host" = "local" ]; then
        if ! command -v k6 &> /dev/null; then
            log_error "k6 verification failed - not in PATH"
            return 1
        fi
        k6 version
    else
        local user=${REPLICA_USER}
        ssh -o ConnectTimeout=10 "$user@$host" "k6 version" || {
            log_error "k6 verification failed on $host"
            return 1
        }
    fi

    log_info "k6 verification successful!"
    return 0
}

#────────────────────────────────────────────────────────────────────────────
# MAIN
#────────────────────────────────────────────────────────────────────────────
main() {
    log_info "K6 Installation Script - Production Load Testing"
    log_info "=================================================="

    # Parse arguments
    parse_arguments "$@"

    # Validate at least one target
    if [ "$INSTALL_LOCAL" != "true" ] && [ ${#HOSTS_TO_INSTALL[@]} -eq 0 ]; then
        log_error "No installation targets specified. Use --local, --host, or --all-replicas"
        print_help
        exit 1
    fi

    # Show what we're about to do
    if [ "$DRY_RUN" = "true" ]; then
        log_warn "DRY-RUN MODE - no changes will be made"
    fi

    log_info "Installation targets:"
    [ "$INSTALL_LOCAL" = "true" ] && log_info "  - Local machine"
    for host in "${HOSTS_TO_INSTALL[@]}"; do
        log_info "  - Remote host: $host"
    done

    # Execute installations
    local failed=0

    if [ "$INSTALL_LOCAL" = "true" ]; then
        install_k6_locally || ((failed++))
        verify_k6_installation "local" || ((failed++))
    fi

    for host in "${HOSTS_TO_INSTALL[@]}"; do
        install_k6_on_remote_host "$host" "$REPLICA_USER" || ((failed++))
        verify_k6_installation "$host" || ((failed++))
    done

    # Final summary
    if [ $failed -eq 0 ]; then
        log_info "✅ k6 installation completed successfully!"
        log_info "Next step: Run load tests with:"
        log_info "  bash scripts/loadtest/run-performance-tests.sh"
        return 0
    else
        log_error "❌ k6 installation completed with errors"
        return 1
    fi
}

# Run main function
main "$@"
