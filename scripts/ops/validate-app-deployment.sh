#!/bin/bash
# Validate application deployment readiness
# Checks all requirements before deploying to platform

set -e
trap 'echo "❌ Validation failed"; exit 1' ERR

APP_DIR=$1
VERBOSE=${2:-false}

if [[ -z "$APP_DIR" ]]; then
  echo "Usage: $0 <app-directory> [verbose]"
  exit 1
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "❌ Application directory not found: $APP_DIR"
  exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Application Deployment Readiness Validation               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

VALIDATION_PASS=0
VALIDATION_FAIL=0

# Helper functions
check_file() {
  local file=$1
  local description=$2
  
  if [[ -f "$APP_DIR/$file" ]]; then
    echo "  ✓ $description ($file)"
    VALIDATION_PASS+=1
    return 0
  else
    echo "  ✗ $description ($file) - MISSING"
    VALIDATION_FAIL+=1
    return 1
  fi
}

check_command() {
  local cmd=$1
  local description=$2
  
  if command -v "$cmd" &> /dev/null; then
    echo "  ✓ $description ($cmd)"
    VALIDATION_PASS+=1
    return 0
  else
    echo "  ✗ $description ($cmd) - NOT INSTALLED"
    VALIDATION_FAIL+=1
    return 1
  fi
}

# Check required files
echo "Checking required files..."
check_file "Dockerfile" "Dockerfile"
check_file "docker-compose.yml" "docker-compose configuration"
check_file ".env.example" "Environment template"
check_file "README.md" "Documentation"

# Check source code
echo ""
echo "Checking source code..."
if [[ -f "$APP_DIR/src/main.py" ]] || [[ -f "$APP_DIR/src/server.js" ]]; then
  echo "  ✓ Source code found"
  VALIDATION_PASS+=1
else
  echo "  ✗ Source code not found (src/main.py or src/server.js)"
  VALIDATION_FAIL+=1
fi

# Check for health checks
echo ""
echo "Checking health check implementation..."
grep -r "health" "$APP_DIR/src" >/dev/null 2>&1 && {
  echo "  ✓ Health check endpoints implemented"
  VALIDATION_PASS+=1
} || {
  echo "  ⚠️  Health checks not found"
  VALIDATION_PASS+=1
}

# Check for tests
echo ""
echo "Checking test coverage..."
if [[ -d "$APP_DIR/tests" ]] && [[ -n "$(find "$APP_DIR/tests" -name "test_*.py" -o -name "*.test.js")" ]]; then
  echo "  ✓ Test files found"
  VALIDATION_PASS+=1
else
  echo "  ⚠️  No test files found"
fi

# Check Docker configuration
echo ""
echo "Checking Docker configuration..."
if [[ -f "$APP_DIR/docker-compose.yml" ]]; then
  # Validate YAML syntax
  if command -v docker-compose &> /dev/null; then
    cd "$APP_DIR"
    docker-compose config >/dev/null 2>&1 && {
      echo "  ✓ docker-compose.yml syntax valid"
      VALIDATION_PASS+=1
    } || {
      echo "  ✗ docker-compose.yml syntax invalid"
      VALIDATION_FAIL+=1
    }
    cd - >/dev/null
  fi
fi

# Check Dockerfile
echo ""
echo "Checking Dockerfile..."
grep -q "HEALTHCHECK" "$APP_DIR/Dockerfile" && {
  echo "  ✓ Health check defined"
  VALIDATION_PASS+=1
} || {
  echo "  ⚠️  No HEALTHCHECK in Dockerfile"
}

grep -q "EXPOSE" "$APP_DIR/Dockerfile" && {
  echo "  ✓ Port exposed"
  VALIDATION_PASS+=1
} || {
  echo "  ⚠️  No EXPOSE directive"
}

# Check build capability
echo ""
echo "Checking build capability..."
if command -v docker &> /dev/null; then
  cd "$APP_DIR"
  if docker build --dry-run . >/dev/null 2>&1; then
    echo "  ✓ Dockerfile buildable"
    VALIDATION_PASS+=1
  else
    echo "  ✗ Dockerfile build would fail"
    VALIDATION_FAIL+=1
  fi
  cd - >/dev/null
else
  echo "  ⚠️  Docker not installed - skipping build check"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Validation Summary"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Passed: $VALIDATION_PASS"
echo "  Failed: $VALIDATION_FAIL"
echo ""

if [[ $VALIDATION_FAIL -eq 0 ]]; then
  echo "✅ Application is ready for deployment"
  exit 0
else
  echo "❌ Application has $VALIDATION_FAIL validation issues"
  exit 1
fi
