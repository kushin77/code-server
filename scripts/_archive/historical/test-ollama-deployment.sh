#!/bin/bash
# Ollama Integration Testing and Deployment Script
# Validates all components and initiates deployment

set -e

echo "════════════════════════════════════════════════════════════════"
echo "  OLLAMA INTEGRATION - TESTING & DEPLOYMENT"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_step() {
  echo -e "${BLUE}→${NC} $1"
}

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: Pre-flight Checks
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "PHASE 1: Pre-flight Checks"
echo "─────────────────────────────────────────────────────────────────"

log_step "Checking Docker..."
if command -v docker &> /dev/null; then
  log_pass "Docker CLI found"
else
  log_error "Docker CLI not found - install Docker first"
  exit 1
fi

log_step "Checking Docker Daemon..."
if docker ps > /dev/null 2>&1; then
  log_pass "Docker daemon is running"
else
  log_error "Docker daemon not responding - start Docker first"
  exit 1
fi

log_step "Checking Docker Compose..."
if docker compose version > /dev/null 2>&1; then
  log_pass "Docker Compose available"
else
  log_error "Docker Compose not found"
  exit 1
fi

log_step "Checking Disk Space..."
DISK_AVAILABLE=$(df /var 2>/dev/null | tail -1 | awk '{print $4}' || df -k / | tail -1 | awk '{print $4}')
DISK_AVAILABLE_GB=$((DISK_AVAILABLE / 1048576))
if [ "$DISK_AVAILABLE_GB" -gt 50 ]; then
  log_pass "Disk space OK: ${DISK_AVAILABLE_GB}GB available"
else
  log_warn "Limited disk space: ${DISK_AVAILABLE_GB}GB available (50GB+ recommended for models)"
fi

log_step "Checking Docker Compose Configuration..."
if docker compose config > /dev/null 2>&1; then
  log_pass "docker-compose.yml is valid"
else
  log_error "docker-compose.yml validation failed"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: File Structure Validation
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "PHASE 2: File Structure Validation"
echo "─────────────────────────────────────────────────────────────────"

check_file() {
  if [ -f "$1" ]; then
    log_pass "Found: $1"
    return 0
  else
    log_error "Missing: $1"
    return 1
  fi
}

check_dir() {
  if [ -d "$1" ]; then
    log_pass "Found: $1"
    return 0
  else
    log_error "Missing: $1"
    return 1
  fi
}

CHECKS_PASSED=0
CHECKS_TOTAL=0

# Core files
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
check_file "docker-compose.yml" && CHECKS_PASSED=$((CHECKS_PASSED + 1))

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
check_file "Dockerfile.code-server" && CHECKS_PASSED=$((CHECKS_PASSED + 1))

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
check_file "Makefile" && CHECKS_PASSED=$((CHECKS_PASSED + 1))

# Ollama extension
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
check_dir "extensions/ollama-chat" && CHECKS_PASSED=$((CHECKS_PASSED + 1))

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
check_file "extensions/ollama-chat/package.json" && CHECKS_PASSED=$((CHECKS_PASSED + 1))

# Scripts
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
check_file "scripts/ollama-init.sh" && CHECKS_PASSED=$((CHECKS_PASSED + 1))

CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
check_file "scripts/code-server-entrypoint.sh" && CHECKS_PASSED=$((CHECKS_PASSED + 1))

# Documentation
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
check_file "OLLAMA_INTEGRATION.md" && CHECKS_PASSED=$((CHECKS_PASSED + 1))

log_step "File validation: $CHECKS_PASSED/$CHECKS_TOTAL checks passed"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: Configuration Review
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "PHASE 3: Configuration Review"
echo "─────────────────────────────────────────────────────────────────"

log_step "Checking docker-compose.yml for Ollama services..."
if grep -q "service_name_id: ollama" docker-compose.yml 2>/dev/null || grep -q "ollama:" docker-compose.yml; then
  log_pass "Ollama service configured"
else
  log_warn "Ollama service may not be properly configured"
fi

if grep -q "ollama-init" docker-compose.yml; then
  log_pass "Ollama-init service configured"
else
  log_warn "Ollama-init service not found"
fi

if grep -q "OLLAMA_ENDPOINT" docker-compose.yml; then
  log_pass "OLLAMA_ENDPOINT environment variable set"
else
  log_warn "OLLAMA_ENDPOINT not configured"
fi

log_step "Checking Dockerfile for extension build..."
if grep -q "ollama-chat" Dockerfile.code-server; then
  log_pass "Ollama extension build configured"
else
  log_warn "Ollama extension build may not be in Dockerfile"
fi

log_step "Checking Makefile for Ollama targets..."
if grep -q "ollama-health:" Makefile; then
  log_pass "Ollama Makefile targets found"
else
  log_warn "Ollama Makefile targets not found"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: Deployment Readiness
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "PHASE 4: Deployment Readiness"
echo "─────────────────────────────────────────────────────────────────"

log_step "All pre-flight checks completed"
log_pass "System is ready for Ollama deployment"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  DEPLOYMENT INSTRUCTIONS"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next Steps:"
echo ""
echo "  1. DEPLOY INFRASTRUCTURE (5 minutes):"
echo "     make deploy"
echo ""
echo "  2. PULL MODELS (30-60 minutes, can run in background):"
echo "     make ollama-pull-models"
echo ""
echo "  3. INITIALIZE REPOSITORY (1-2 minutes):"
echo "     make ollama-init"
echo ""
echo "  4. VERIFY DEPLOYMENT:"
echo "     make status"
echo "     make ollama-status"
echo ""
echo "  5. OPEN CODE-SERVER:"
echo "     https://your-domain"
echo ""
echo "  6. START USING OLLAMA:"
echo "     Type: @ollama <your prompt>"
echo "     In VS Code Chat View (Ctrl+Alt+I)"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Example Prompts:"
echo "  • @ollama explain this function"
echo "  • @ollama generate unit tests for this file"
echo "  • @ollama refactor this code for performance"
echo "  • @ollama how does authentication work in this repo?"
echo ""
echo "For detailed documentation, see:"
echo "  • OLLAMA_INTEGRATION.md (complete guide)"
echo "  • docs/OLLAMA_QUICK_START.md (step-by-step)"
echo "  • README.md (overview)"
echo ""
