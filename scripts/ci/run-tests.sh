#!/bin/bash
# Comprehensive test execution script with coverage reporting
# Runs all test types and generates coverage reports

trap 'log_error "Test script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleaning up test artifacts..."; rm -rf .pytest_cache htmlcov .coverage* 2>/dev/null || true' EXIT

# Source logging utilities
source scripts/_common/init.sh

log_info "Starting comprehensive test suite"

# Configuration
COVERAGE_THRESHOLD=75
TEST_TIMEOUT=300

# 1. Run unit tests with coverage
log_info "Running unit tests..."
python3 -m pytest apps/ \
    -m "not (integration or e2e or performance)" \
    -v \
    --tb=short \
    --cov=apps \
    --cov-report=term-missing \
    --timeout=$TEST_TIMEOUT \
    --junit-xml=test-results-unit.xml || {
    log_error "Unit tests failed"
    exit 1
}

# 2. Run integration tests (if dependencies available)
if command -v docker &> /dev/null && docker ps &> /dev/null; then
    log_info "Running integration tests..."
    python3 -m pytest apps/ \
        -m "integration" \
        -v \
        --tb=short \
        --timeout=$TEST_TIMEOUT \
        --junit-xml=test-results-integration.xml || {
        log_error "Integration tests failed"
        exit 1
    }
else
    log_warn "Docker not available, skipping integration tests"
fi

# 3. Run E2E tests (if test environment available)
if [ -n "$RUN_E2E_TESTS" ]; then
    log_info "Running E2E tests..."
    python3 -m pytest apps/ \
        -m "e2e" \
        -v \
        --tb=short \
        --timeout=$TEST_TIMEOUT \
        --junit-xml=test-results-e2e.xml || {
        log_error "E2E tests failed"
        exit 1
    }
fi

# 4. Generate coverage report
log_info "Generating coverage report..."
python3 -m pytest apps/ \
    --cov=apps \
    --cov-report=html:htmlcov \
    --cov-report=term-missing \
    --cov-report=xml \
    --cov-branch || true

# 5. Check coverage threshold
coverage_percent=$(python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('coverage.xml')
    root = tree.getroot()
    coverage = float(root.get('line-rate', 0)) * 100
    print(f'{coverage:.1f}')
except:
    print('0')
")

log_info "Overall test coverage: $coverage_percent%"

if (( $(echo "$coverage_percent < $COVERAGE_THRESHOLD" | bc -l) )); then
    log_warn "Coverage below threshold ($coverage_percent% < $COVERAGE_THRESHOLD%)"
else
    log_success "Coverage meets threshold"
fi

# 6. Summary
log_success "Test execution complete"
log_info "Test results:"
echo "  - Unit tests: test-results-unit.xml"
[ -f test-results-integration.xml ] && echo "  - Integration tests: test-results-integration.xml"
[ -f test-results-e2e.xml ] && echo "  - E2E tests: test-results-e2e.xml"
echo "  - Coverage report: htmlcov/index.html"
echo "  - Coverage XML: coverage.xml"
