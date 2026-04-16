#!/bin/bash
# EXECUTE-NOW: Phase 7c Disaster Recovery Test Suite
# This script executes Phase 7c on the production host automatically

set -euo pipefail

echo "======================================================================"
echo "PHASE 7C EXECUTION SCRIPT - Disaster Recovery Test Suite"
echo "======================================================================"
echo ""
echo "This script will:"
echo "  1. SSH to production host (192.168.168.31)"
echo "  2. Execute Phase 7c disaster recovery tests"
echo "  3. Capture results and update GitHub issue #315"
echo ""
echo "Expected duration: 2-3 hours"
echo "Expected result: 15/15 tests PASS, RTO <5min, RPO <1hour"
echo ""

# Configuration
readonly PRODUCTION_HOST="192.168.168.31"
readonly PRODUCTION_USER="akushnir"
readonly REPO_PATH="code-server-enterprise"
readonly SCRIPT_NAME="phase-7c-disaster-recovery-test.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✅ SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[❌ ERROR]${NC} $*"; }

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v ssh &> /dev/null; then
    log_error "ssh not found in PATH"
    exit 1
fi

if ! ssh-keygen -F "$PRODUCTION_HOST" &> /dev/null; then
    log_info "Adding host to known_hosts..."
    ssh-keyscan "$PRODUCTION_HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
fi

log_success "Prerequisites verified"
echo ""

# Execute Phase 7c
log_info "Connecting to $PRODUCTION_HOST..."
log_info "Running Phase 7c disaster recovery tests..."
echo ""

ssh -o ConnectTimeout=10 "$PRODUCTION_USER@$PRODUCTION_HOST" bash <<'REMOTE_SCRIPT'
set -euo pipefail

cd code-server-enterprise

# Show current status
echo "======================================================================"
echo "PRE-EXECUTION STATUS"
echo "======================================================================"
docker-compose ps
echo ""

# Execute Phase 7c tests
echo "======================================================================"
echo "EXECUTING PHASE 7C DISASTER RECOVERY TESTS"
echo "======================================================================"
bash scripts/phase-7c-disaster-recovery-test.sh

# Show results
echo ""
echo "======================================================================"
echo "POST-EXECUTION STATUS"
echo "======================================================================"
docker-compose ps
echo ""

# Show logs
if ls /tmp/phase-7c-dr-test-*.log 1> /dev/null 2>&1; then
    echo "======================================================================"
    echo "TEST RESULTS (Last 50 lines)"
    echo "======================================================================"
    tail -50 /tmp/phase-7c-dr-test-*.log
fi

REMOTE_SCRIPT

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    log_success "Phase 7c execution completed"
    echo ""
    log_info "Next steps:"
    log_info "  1. Review the test results above"
    log_info "  2. Update GitHub issue #315 with results:"
    log_info "     https://github.com/kushin77/code-server/issues/315"
    log_info "  3. If tests PASS:"
    log_info "     - Phase 7d (load balancing) becomes UNBLOCKED"
    log_info "     - Phase 7e (chaos testing) becomes UNBLOCKED"
    log_info "     - Phase 8 (security hardening) can continue in parallel"
    log_info "  4. Begin Phase 8 #348 (Cloudflare Tunnel) deployment"
    log_info "     - See: START-HERE-PHASE-7C-EXECUTION.md"
else
    log_error "Phase 7c execution failed with exit code $EXIT_CODE"
    log_info "Troubleshooting:"
    log_info "  1. Check SSH connection: ssh akushnir@192.168.168.31"
    log_info "  2. Check services: docker-compose ps"
    log_info "  3. Check replication: docker-compose exec postgres psql -U codeserver -d codeserver -c 'SELECT * FROM pg_stat_replication;'"
    exit 1
fi

log_success "Phase 7c ready for GitHub issue update"
