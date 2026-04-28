#!/bin/bash
################################################################################
# Consolidated Test Utilities for Code Server Enterprise
# Source this file in shell scripts to get access to testing functions
################################################################################

set -euo pipefail

# Colors (matches Python logging module, but check if already defined via init.sh)
[[ -z "${RED:-}" ]] && readonly RED="\033[91m" || true
[[ -z "${GREEN:-}" ]] && readonly GREEN="\033[92m" || true
[[ -z "${YELLOW:-}" ]] && readonly YELLOW="\033[93m" || true
[[ -z "${BLUE:-}" ]] && readonly BLUE="\033[94m" || true
[[ -z "${MAGENTA:-}" ]] && readonly MAGENTA="\033[95m" || true
[[ -z "${CYAN:-}" ]] && readonly CYAN="\033[96m" || true
[[ -z "${GRAY:-}" ]] && readonly GRAY="\033[90m" || true
[[ -z "${RESET:-}" ]] && readonly RESET="\033[0m" || true
[[ -z "${BOLD:-}" ]] && readonly BOLD="\033[1m" || true

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test state
CURRENT_TEST=""
CURRENT_SUITE=""

################################################################################
# Test Suite Management
################################################################################

test_suite() {
    # Create a new test suite.
    CURRENT_SUITE="$1"
    echo -e "${CYAN}${BOLD}Test Suite: $CURRENT_SUITE${RESET}"
    echo "─────────────────────────────────────────────────"
}

test_end_suite() {
    # Print test suite summary.
    echo ""
    echo "Suite Results: ${GREEN}$TESTS_PASSED passed${RESET}, ${RED}$TESTS_FAILED failed${RESET}, ${YELLOW}$TESTS_SKIPPED skipped${RESET} (Total: $TESTS_RUN)"
    echo ""
}

################################################################################
# Test Assertions
################################################################################

assert_true() {
    # Assert that command/expression succeeds.
    local test_name="$1"
    local command="${2:-$1}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if eval "$command" &>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    Command: $command"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_false() {
    # Assert that command/expression fails.
    local test_name="$1"
    local command="${2:-$1}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if ! eval "$command" &>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} $test_name (should fail)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name (expected to fail but succeeded)"
        echo -e "    Command: $command"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_equals() {
    # Assert that two values are equal.
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    Expected: $expected"
        echo -e "    Got:      $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_not_equals() {
    # Assert that two values are NOT equal.
    local test_name="$1"
    local not_expected="$2"
    local actual="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if [[ "$not_expected" != "$actual" ]]; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    Should not be: $not_expected"
        echo -e "    Got:           $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    # Assert that file exists.
    local test_name="$1"
    local filepath="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if [[ -f "$filepath" ]]; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    File not found: $filepath"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_not_exists() {
    # Assert that file does NOT exist.
    local test_name="$1"
    local filepath="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if [[ ! -f "$filepath" ]]; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    File should not exist: $filepath"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_directory_exists() {
    # Assert that directory exists.
    local test_name="$1"
    local dirpath="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if [[ -d "$dirpath" ]]; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    Directory not found: $dirpath"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    # Assert that string contains substring.
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    Expected substring: $needle"
        echo -e "    In string:          $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_not_contains() {
    # Assert that string does NOT contain substring.
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    Substring should not be present: $needle"
        echo -e "    In string:                       $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_matches() {
    # Assert that string matches regex pattern.
    local test_name="$1"
    local string="$2"
    local pattern="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$test_name"
    
    if [[ "$string" =~ $pattern ]]; then
        echo -e "  ${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${RESET} $test_name"
        echo -e "    Pattern: $pattern"
        echo -e "    String:  $string"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

################################################################################
# Test Fixtures & Setup/Teardown
################################################################################

setup_test_env() {
    # Setup temporary test environment.
    TEST_DIR=$(mktemp -d)
    export TEST_DIR
    trap 'cleanup_test_env' EXIT
}

cleanup_test_env() {
    # Clean up test environment.
    if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

setup_docker_test() {
    # Setup Docker test environment.
    # Check Docker is available
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}⚠${RESET} Docker not available, skipping Docker tests"
        return 1
    fi
    return 0
}

################################################################################
# Mock/Stub Utilities
################################################################################

mock_command() {
    # Create a mock command that returns specified output.
    local cmd_name="$1"
    local mock_output="$2"
    local mock_exit_code="${3:-0}"
    
    eval "$cmd_name() { echo '$mock_output'; return $mock_exit_code; }"
}

mock_file() {
    # Create a mock file with specified content.
    local filepath="$1"
    local content="$2"
    
    mkdir -p "$(dirname "$filepath")"
    echo "$content" > "$filepath"
}

################################################################################
# Test Report Generation
################################################################################

test_report() {
    # Generate test report.
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    local pass_rate=0
    
    if [[ $total -gt 0 ]]; then
        pass_rate=$((TESTS_PASSED * 100 / total))
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "Test Report: ${CURRENT_SUITE:-Tests}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "Total:   $total"
    echo -e "Passed:  ${GREEN}$TESTS_PASSED${RESET}"
    echo -e "Failed:  ${RED}$TESTS_FAILED${RESET}"
    echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${RESET}"
    echo -e "Rate:    ${pass_rate}%"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Return exit code based on test results
    if [[ $TESTS_FAILED -gt 0 ]]; then
        return 1
    fi
    return 0
}

################################################################################
# Test Context Utilities
################################################################################

skip_test() {
    # Skip the current test.
    local reason="${1:-No reason provided}"
    echo -e "  ${YELLOW}⊘${RESET} $CURRENT_TEST (skipped: $reason)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

fail_fast() {
    # Fail immediately and exit.
    local message="$1"
    echo -e "${RED}${BOLD}FATAL: $message${RESET}"
    exit 1
}

test_info() {
    # Print test info message.
    local message="$1"
    echo -e "  ${BLUE}ℹ${RESET} $message"
}

test_warn() {
    # Print test warning message.
    local message="$1"
    echo -e "  ${YELLOW}⚠${RESET} $message"
}
