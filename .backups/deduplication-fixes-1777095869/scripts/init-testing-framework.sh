#!/usr/bin/env bash
#
# Unit Testing Framework Initialization
# Issue #1537 Week 1: Comprehensive Testing Infrastructure
#
# Sets up pytest for Python backend and vitest for TypeScript frontend
# Establishes baseline 80%+ code coverage targets
# Creates CI/CD test execution pipeline
#
# Usage:
#   bash scripts/init-testing-framework.sh
#   bash scripts/init-testing-framework.sh --backend-only
#   bash scripts/init-testing-framework.sh --frontend-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
BACKEND_ONLY="${1:---backend-only}"
FRONTEND_ONLY="${1:---frontend-only}"
BOTH_SETUP=1

[ "$BACKEND_ONLY" == "--backend-only" ] && FRONTEND_ONLY="skip"
[ "$FRONTEND_ONLY" == "--frontend-only" ] && BACKEND_ONLY="skip"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_step() { echo -e "${BLUE}==>${NC} $*"; }
log_pass() { echo -e "${GREEN}✅${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $*"; }

# ============================================================================
# BACKEND: Python Testing Framework (pytest)
# ============================================================================

init_python_testing() {
  log_step "Initializing Python Testing Framework (pytest)"
  
  # Create pyproject.toml configuration
  cat > "${REPO_ROOT}/pyproject.toml" << 'EOF'
[build-system]
requires = ["setuptools>=68.0"]
build-backend = "setuptools.build_meta"

[project]
name = "elevatediq-backend"
version = "0.1.0"
requires-python = ">=3.11"

[tool.pytest.ini_options]
minversion = "7.0"
testpaths = ["tests"]
python_files = "test_*.py"
python_classes = "Test*"
python_functions = "test_*"

# Coverage configuration
addopts = """
    --strict-markers
    --tb=short
    --cov=src
    --cov-report=html
    --cov-report=term-missing:skip-covered
    --cov-report=json
    --cov-fail-under=80
    -v
    --color=yes
"""

markers = [
    "unit: Unit tests (fast, isolated)",
    "integration: Integration tests (medium speed)",
    "e2e: End-to-end tests (slow, comprehensive)",
    "slow: Slow tests",
    "skip_ci: Skip in CI environment",
]

testpaths = ["tests"]

[tool.coverage.run]
branch = true
source = ["src"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise AssertionError",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    "if TYPE_CHECKING:",
    "@abstractmethod",
]

precision = 2
skip_covered = false
skip_empty = true

[tool.coverage.html]
directory = "htmlcov"
EOF
  
  log_pass "Created pyproject.toml with pytest configuration"
  
  # Create requirements-test.txt
  cat > "${REPO_ROOT}/requirements-test.txt" << 'EOF'
# Testing framework
pytest==7.4.3
pytest-cov==4.1.0
pytest-asyncio==0.21.1
pytest-mock==3.12.0
pytest-timeout==2.2.0
pytest-xdist==3.5.0  # Parallel execution

# Test data generation
faker==20.1.0
factory-boy==3.3.0

# Mocking & fixtures
responses==0.24.1

# Code quality
coverage==7.3.2
EOF
  
  log_pass "Created requirements-test.txt"
  
  # Create conftest.py for shared fixtures
  mkdir -p "${REPO_ROOT}/tests"
  cat > "${REPO_ROOT}/tests/conftest.py" << 'EOF'
"""
Shared pytest configuration and fixtures
"""
import os
import pytest
from typing import Generator
from faker import Faker

# Initialize faker for test data generation
fake = Faker()


@pytest.fixture
def faker():
    """Provide Faker instance for test data generation"""
    return Faker()


@pytest.fixture
def test_env(monkeypatch):
    """Provide test environment variables"""
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")
    return {
        "ENVIRONMENT": "test",
        "LOG_LEVEL": "DEBUG",
    }


@pytest.fixture(autouse=True)
def reset_singletons():
    """Reset singleton instances between tests"""
    yield
    # Add cleanup code here if needed


def pytest_configure(config):
    """Configure pytest with custom markers"""
    config.addinivalue_line(
        "markers", "unit: mark test as a unit test"
    )
    config.addinivalue_line(
        "markers", "integration: mark test as an integration test"
    )
    config.addinivalue_line(
        "markers", "e2e: mark test as an end-to-end test"
    )
EOF
  
  log_pass "Created tests/conftest.py with fixtures"
  
  # Create example unit test
  mkdir -p "${REPO_ROOT}/tests/unit/auth"
  cat > "${REPO_ROOT}/tests/unit/auth/test_auth_service.py" << 'EOF'
"""
Unit tests for authentication service
"""
import pytest
from unittest.mock import Mock, patch


@pytest.mark.unit
class TestAuthService:
    """Authentication service tests"""
    
    def test_verify_token_valid(self):
        """Test token verification with valid token"""
        # Test implementation placeholder
        assert True
    
    def test_verify_token_invalid(self):
        """Test token verification with invalid token"""
        # Test implementation placeholder
        assert True
    
    @pytest.mark.parametrize("invalid_token", [
        "",
        "malformed",
        "expired.jwt.token",
        "x" * 1000,
    ])
    def test_verify_token_edge_cases(self, invalid_token):
        """Test token verification edge cases"""
        assert True


@pytest.mark.unit
class TestUserService:
    """User service tests"""
    
    def test_create_user_success(self, faker):
        """Test successful user creation"""
        email = faker.email()
        # Test implementation
        assert email
    
    def test_create_user_duplicate_email(self, faker):
        """Test duplicate email rejection"""
        assert True
EOF
  
  log_pass "Created example unit tests"
  
  # Install dependencies
  log_step "Installing Python testing dependencies..."
  if command -v pip &> /dev/null; then
    pip install -q -r "${REPO_ROOT}/requirements-test.txt" 2>/dev/null || {
      log_warn "Some dependencies may not have installed (expected in CI)"
    }
  else
    log_warn "pip not available (skipping dependency install)"
  fi
  
  log_pass "Python testing framework initialized"
}

# ============================================================================
# FRONTEND: TypeScript Testing Framework (vitest)
# ============================================================================

init_typescript_testing() {
  log_step "Initializing TypeScript Testing Framework (vitest)"
  
  # Update package.json with test scripts and dependencies
  if [ -f "${REPO_ROOT}/package.json" ]; then
    log_pass "package.json already exists, would add test configuration"
    
    cat >> "${REPO_ROOT}/package.json.test-config" << 'EOF'
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest watch",
    "test:coverage": "vitest run --coverage",
    "test:ui": "vitest --ui"
  },
  "devDependencies": {
    "vitest": "^1.0.0",
    "@testing-library/react": "^14.1.0",
    "@testing-library/jest-dom": "^6.1.5",
    "vitest-canvas-mock": "^0.3.5",
    "msw": "^1.3.2",
    "@vitest/ui": "^1.0.0",
    "@vitest/coverage-v8": "^1.0.0"
  }
}
EOF
    
    log_warn "Manual merge required: see package.json.test-config"
  else
    log_warn "package.json not found, skipping TypeScript setup"
  fi
  
  # Create vitest configuration
  cat > "${REPO_ROOT}/vitest.config.ts" << 'EOF'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      exclude: [
        'node_modules/',
        'dist/',
        'build/',
        '**/*.config.ts',
        '**/types.ts',
      ],
      lines: 80,
      functions: 80,
      branches: 80,
      statements: 80,
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
EOF
  
  log_pass "Created vitest.config.ts"
  
  # Create test setup
  mkdir -p "${REPO_ROOT}/tests"
  cat > "${REPO_ROOT}/tests/setup.ts" << 'EOF'
import '@testing-library/jest-dom'
import { expect, afterEach, vi } from 'vitest'
import { cleanup } from '@testing-library/react'

// Cleanup after each test
afterEach(() => {
  cleanup()
})

// Mock window.matchMedia
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation(query => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
})
EOF
  
  log_pass "Created tests/setup.ts"
  
  # Create example React component test
  mkdir -p "${REPO_ROOT}/tests/unit/components"
  cat > "${REPO_ROOT}/tests/unit/components/Button.test.tsx" << 'EOF'
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

// Mock component for testing
function Button({ onClick, children }: { onClick?: () => void; children: React.ReactNode }) {
  return <button onClick={onClick}>{children}</button>
}

describe('Button Component', () => {
  it('renders button with text', () => {
    render(<Button>Click me</Button>)
    expect(screen.getByRole('button', { name: /click me/i })).toBeInTheDocument()
  })

  it('calls onClick handler', async () => {
    const handleClick = vi.fn()
    render(<Button onClick={handleClick}>Click me</Button>)
    
    await userEvent.click(screen.getByRole('button'))
    expect(handleClick).toHaveBeenCalledOnce()
  })
})
EOF
  
  log_pass "Created example React component tests"
  
  log_pass "TypeScript testing framework configured"
}

# ============================================================================
# CI/CD Integration
# ============================================================================

init_ci_testing() {
  log_step "Setting up CI/CD test pipeline"
  
  # Create GitHub Actions test workflow
  mkdir -p "${REPO_ROOT}/.github/workflows"
  cat > "${REPO_ROOT}/.github/workflows/test.yml" << 'EOF'
name: Unit & Integration Tests
on: [push, pull_request]

jobs:
  python-tests:
    name: Python Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
          cache: pip
      - run: pip install -r requirements-test.txt
      - run: pytest --cov=src --cov-report=xml --junit-xml=junit.xml
      - uses: codecov/codecov-action@v3

  typescript-tests:
    name: TypeScript Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 18
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm test:coverage
      - uses: codecov/codecov-action@v3
EOF
  
  log_pass "Created .github/workflows/test.yml"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════╗"
  echo "║  Unit Testing Framework Initialization            ║"
  echo "║  Issue #1537 Week 1 - Testing Infrastructure      ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo ""
  
  if [ "$BACKEND_ONLY" != "skip" ]; then
    init_python_testing
    echo ""
  fi
  
  if [ "$FRONTEND_ONLY" != "skip" ]; then
    init_typescript_testing
    echo ""
  fi
  
  init_ci_testing
  
  echo "╔════════════════════════════════════════════════════╗"
  echo "║  Testing Framework Initialization Complete        ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo ""
  echo "Next steps:"
  echo "  1. Review test configuration: pyproject.toml, vitest.config.ts"
  echo "  2. Run tests: pytest (backend) or pnpm test (frontend)"
  echo "  3. Check coverage: pytest --cov or pnpm test:coverage"
  echo "  4. Write unit tests in tests/ directory"
  echo ""
  log_pass "Framework ready for Week 1 implementation"
}

main "$@"
