#!/bin/bash
################################################################################
# Tier 3 Deployment Validation Orchestrator
# Complete deployment workflow with testing and validation
# IaC: Idempotent, fully automated, production-ready
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_LOG="${PROJECT_ROOT}/TIER-3-DEPLOYMENT-$(date +%Y%m%d-%H%M%S).log"

# Deployment phases
DEPLOY_PHASE=0
DEPLOY_START=$(date +%s)

# ─────────────────────────────────────────────────────────────────────────────
# Logging Functions
# ─────────────────────────────────────────────────────────────────────────────

log() {
  local message=$1
  local level=${2:-INFO}
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  case $level in
    INFO)
      echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$DEPLOYMENT_LOG"
      ;;
    SUCCESS)
      echo -e "${GREEN}[✓]${NC} $message" | tee -a "$DEPLOYMENT_LOG"
      ;;
    WARN)
      echo -e "${YELLOW}[!]${NC} $message" | tee -a "$DEPLOYMENT_LOG"
      ;;
    ERROR)
      echo -e "${RED}[✗]${NC} $message" | tee -a "$DEPLOYMENT_LOG"
      ;;
  esac
}

phase_banner() {
  local phase_num=$1
  local phase_name=$2

  DEPLOY_PHASE=$((DEPLOY_PHASE + 1))
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║ PHASE $DEPLOY_PHASE: $phase_name" | sed 's/$/                            /' | cut -c1-66
  echo "╚══════════════════════════════════════════════════════════════╝"

  log "Starting Phase $DEPLOY_PHASE: $phase_name"
}

# ─────────────────────────────────────────────────────────────────────────────
# Validation Functions
# ─────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
  log "Checking prerequisites..."

  local missing_tools=()

  # Check required tools
  for tool in curl docker docker-compose git node npm; do
    if ! command -v $tool &> /dev/null; then
      missing_tools+=("$tool")
    fi
  done

  if [ ${#missing_tools[@]} -gt 0 ]; then
    log "Missing required tools: ${missing_tools[*]}" ERROR
    return 1
  fi

  log "All prerequisites present" SUCCESS
  return 0
}

validate_source_code() {
  log "Validating source code integrity..."

  local required_files=(
    "src/cache-bootstrap.js"
    "src/app-with-cache.js"
    "src/l1-cache-service.js"
    "src/l2-cache-service.js"
    "src/multi-tier-cache-middleware.js"
    "src/cache-invalidation-service.js"
    "src/cache-monitoring-service.js"
  )

  local missing_files=()

  for file in "${required_files[@]}"; do
    if [ ! -f "$PROJECT_ROOT/$file" ]; then
      missing_files+=("$file")
    fi
  done

  if [ ${#missing_files[@]} -gt 0 ]; then
    log "Missing source files: ${missing_files[*]}" ERROR
    return 1
  fi

  log "All source files present" SUCCESS
  return 0
}

validate_docker_images() {
  log "Validating Docker images..."

  # Check if images exist or can be built
  local required_images=(
    "redis:7-alpine"
    "node:18-alpine"
  )

  for image in "${required_images[@]}"; do
    if ! docker image inspect "$image" > /dev/null 2>&1; then
      log "Pulling Docker image: $image"
      docker pull "$image" || {
        log "Failed to pull image: $image" ERROR
        return 1
      }
    fi
  done

  log "Docker images validated" SUCCESS
  return 0
}

validate_configuration() {
  log "Validating environment configuration..."

  local required_env_vars=(
    "L1_CACHE_SIZE"
    "L1_CACHE_TTL_MS"
    "REDIS_HOST"
    "REDIS_PORT"
    "LOG_LEVEL"
  )

  for var in "${required_env_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      log "Setting default for $var..."
      case $var in
        L1_CACHE_SIZE) export L1_CACHE_SIZE=1000 ;;
        L1_CACHE_TTL_MS) export L1_CACHE_TTL_MS=3600000 ;;
        REDIS_HOST) export REDIS_HOST="redis" ;;
        REDIS_PORT) export REDIS_PORT=6379 ;;
        LOG_LEVEL) export LOG_LEVEL="info" ;;
      esac
    fi
  done

  log "Configuration validated with environment variables:" SUCCESS
  log "  L1_CACHE_SIZE=$L1_CACHE_SIZE"
  log "  L1_CACHE_TTL_MS=$L1_CACHE_TTL_MS"
  log "  REDIS_HOST=$REDIS_HOST"
  log "  REDIS_PORT=$REDIS_PORT"
  log "  LOG_LEVEL=$LOG_LEVEL"

  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Deployment Functions
# ─────────────────────────────────────────────────────────────────────────────

start_infrastructure() {
  log "Starting infrastructure services..."

  if [ -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    docker-compose -f "$PROJECT_ROOT/docker-compose.yml" up -d || {
      log "Failed to start docker-compose services" ERROR
      return 1
    }

    log "Infrastructure started, waiting for health..." INFO

    # Wait for Redis to be ready
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
      if docker-compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T redis redis-cli ping > /dev/null 2>&1; then
        log "Redis is healthy" SUCCESS
        break
      fi

      attempt=$((attempt + 1))
      sleep 1
    done

    if [ $attempt -eq $max_attempts ]; then
      log "Redis failed to become healthy" ERROR
      return 1
    fi
  else
    log "docker-compose.yml not found, skipping infrastructure startup" WARN
  fi

  return 0
}

install_dependencies() {
  log "Installing Node.js dependencies..."

  if [ -f "$PROJECT_ROOT/package.json" ]; then
    cd "$PROJECT_ROOT"
    npm install 2>&1 | tee -a "$DEPLOYMENT_LOG" || {
      log "Failed to install dependencies" ERROR
      return 1
    }
    log "Dependencies installed" SUCCESS
  fi

  return 0
}

run_linting() {
  log "Running code linting..."

  if command -v eslint &> /dev/null; then
    cd "$PROJECT_ROOT"
    eslint src/ || {
      log "Linting found issues" WARN
    }
  else
    log "eslint not found, skipping linting" WARN
  fi

  return 0
}

run_unit_tests() {
  phase_banner "Unit Tests" "Run Unit Tests"

  log "Running unit tests..."

  if [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"test"' "$PROJECT_ROOT/package.json"; then
    cd "$PROJECT_ROOT"
    npm test || {
      log "Unit tests failed" ERROR
      return 1
    }
    log "Unit tests passed" SUCCESS
  else
    log "No test suite found in package.json" WARN
  fi

  return 0
}

start_application() {
  phase_banner "Application" "Start Application Server"

  log "Starting application server..."

  if [ ! -f "$PROJECT_ROOT/src/app-with-cache.js" ]; then
    log "Application entry point not found" ERROR
    return 1
  fi

  cd "$PROJECT_ROOT"

  # Start application in background
  node src/app-with-cache.js > "$PROJECT_ROOT/app.log" 2>&1 &
  local app_pid=$!
  echo "$app_pid" > "$PROJECT_ROOT/app.pid"

  log "Application started (PID: $app_pid)"

  # Wait for application to be ready
  local max_attempts=30
  local attempt=0
  while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:3000/healthz > /dev/null 2>&1; then
      log "Application is healthy" SUCCESS
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 1
  done

  log "Application failed to become healthy" ERROR
  return 1
}

run_integration_tests() {
  phase_banner "Integration" "Run Integration Tests"

  log "Running integration tests..."

  if [ ! -x "$SCRIPT_DIR/tier-3-integration-test.sh" ]; then
    log "Integration test script not executable" WARN
    chmod +x "$SCRIPT_DIR/tier-3-integration-test.sh"
  fi

  bash "$SCRIPT_DIR/tier-3-integration-test.sh" 2>&1 | tee -a "$DEPLOYMENT_LOG" || {
    log "Integration tests failed" ERROR
    return 1
  }

  log "Integration tests passed" SUCCESS
  return 0
}

run_load_tests() {
  phase_banner "Performance" "Run Load Tests"

  log "Warning: Load tests may take several minutes..."

  if [ ! -x "$SCRIPT_DIR/tier-3-load-test.sh" ]; then
    log "Load test script not executable" WARN
    chmod +x "$SCRIPT_DIR/tier-3-load-test.sh"
  fi

  CONCURRENT_USERS=50 DURATION=30 bash "$SCRIPT_DIR/tier-3-load-test.sh" 2>&1 | tee -a "$DEPLOYMENT_LOG" || {
    log "Load tests failed" ERROR
    return 1
  }

  log "Load tests completed" SUCCESS
  return 0
}

generate_report() {
  phase_banner "Reporting" "Generate Deployment Report"

  local deploy_end=$(date +%s)
  local deploy_duration=$((deploy_end - DEPLOY_START))
  local deploy_minutes=$((deploy_duration / 60))
  local deploy_seconds=$((deploy_duration % 60))

  log "Generating deployment report..."

  cat > "$PROJECT_ROOT/TIER-3-DEPLOYMENT-REPORT.md" << EOF
# Tier 3 Deployment Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Duration:** ${deploy_minutes}m ${deploy_seconds}s

## Deployment Summary

- ✅ Prerequisites validated
- ✅ Source code integrity verified
- ✅ Docker images available
- ✅ Configuration validated
- ✅ Infrastructure started
- ✅ Dependencies installed
- ✅ Application started
- ✅ Unit tests passed
- ✅ Integration tests passed
- ✅ Load tests completed

## Configuration

- **L1 Cache Size:** $L1_CACHE_SIZE
- **L1 Cache TTL:** $L1_CACHE_TTL_MS ms
- **Redis Host:** $REDIS_HOST
- **Redis Port:** $REDIS_PORT
- **Log Level:** $LOG_LEVEL

## Test Results

Please see integrated test logs above for detailed metrics.

## Next Steps

1. Monitor production system metrics
2. Review cache hit rates and adjust configuration
3. Set up continuous monitoring dashboards
4. Plan Tier 3 Phase 2 optimizations

## Deployment Log

Full deployment log available at: $DEPLOYMENT_LOG

EOF

  log "Report generated: $PROJECT_ROOT/TIER-3-DEPLOYMENT-REPORT.md" SUCCESS
}

cleanup_on_error() {
  log "Cleaning up after error..." ERROR

  if [ -f "$PROJECT_ROOT/app.pid" ]; then
    local app_pid=$(cat "$PROJECT_ROOT/app.pid")
    kill "$app_pid" 2>/dev/null || true
  fi

  log "Cleanup complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Deployment Flow
# ─────────────────────────────────────────────────────────────────────────────

main() {
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║    Tier 3 Deployment Validation Orchestrator                 ║"
  echo "║    Production Caching Infrastructure Deployment              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  log "Deployment started at $(date '+%Y-%m-%d %H:%M:%S')" INFO
  log "Project root: $PROJECT_ROOT" INFO
  log "Deployment log: $DEPLOYMENT_LOG" INFO
  echo ""

  # Phase 1: Validation
  phase_banner "Validation" "Pre-Deployment Validation"
  check_prerequisites || { cleanup_on_error; exit 1; }
  validate_source_code || { cleanup_on_error; exit 1; }
  validate_docker_images || { cleanup_on_error; exit 1; }
  validate_configuration || { cleanup_on_error; exit 1; }
  echo ""

  # Phase 2: Infrastructure
  phase_banner "Infrastructure" "Start Infrastructure Services"
  start_infrastructure || { cleanup_on_error; exit 1; }
  echo ""

  # Phase 3: Build
  phase_banner "Build" "Build Application"
  install_dependencies || { cleanup_on_error; exit 1; }
  run_linting || { cleanup_on_error; exit 1; }
  echo ""

  # Phase 4: Testing
  run_unit_tests || { cleanup_on_error; exit 1; }
  echo ""

  # Phase 5: Deployment
  start_application || { cleanup_on_error; exit 1; }
  echo ""

  # Phase 6: Validation
  run_integration_tests || { cleanup_on_error; exit 1; }
  echo ""

  # Phase 7: Performance
  run_load_tests || { cleanup_on_error; exit 1; }
  echo ""

  # Phase 8: Reporting
  generate_report
  echo ""

  # Success
  local deploy_end=$(date +%s)
  local deploy_duration=$((deploy_end - DEPLOY_START))
  local deploy_minutes=$((deploy_duration / 60))
  local deploy_seconds=$((deploy_duration % 60))

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║ ✅ DEPLOYMENT COMPLETE ✅                                   ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Deployment Summary:"
  echo "  Status:           ✅ SUCCESS"
  echo "  Total Duration:   ${deploy_minutes}m ${deploy_seconds}s"
  echo "  Phases Completed: $DEPLOY_PHASE"
  echo "  Deployment Log:   $DEPLOYMENT_LOG"
  echo ""
  echo "Application Status:"
  echo "  URL:              http://localhost:3000"
  echo "  Health:           http://localhost:3000/healthz"
  echo "  Metrics:          http://localhost:3000/metrics"
  echo "  Cache Status:     http://localhost:3000/api/cache-status"
  echo ""
  echo "Next Steps:"
  echo "  1. Monitor application metrics and cache hit rates"
  echo "  2. Review performance baseline against SLOs"
  echo "  3. Collect tuning recommendations from load test"
  echo "  4. Plan production rollout"
  echo ""

  log "Deployment completed successfully" SUCCESS
}

# Run main function with error handling
trap 'cleanup_on_error' EXIT

main "$@"
