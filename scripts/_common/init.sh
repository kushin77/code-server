#!/usr/bin/env bash
# @file scripts/_common/init.sh
# @description Common initialization and utility functions for infrastructure scripts

set -euo pipefail

# Error handling (Required by pre-commit hooks)
trap 'log_error "Common init failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Verify dependencies
check_dep() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Dependency '$1' is required but not installed."
        exit 1
    fi
}

# Ensure artifacts directory exists
ARTIFACTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../artifacts" && pwd)"
mkdir -p "$ARTIFACTS_DIR"

export ARTIFACTS_DIR
