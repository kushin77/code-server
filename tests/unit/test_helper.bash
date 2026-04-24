#!/usr/bin/env bash
# @file        tests/unit/test_helper.bash
# @module      tests/unit
# @description Shared helper functions for bats-core shell library tests.
#

setup_test_env() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_TMPDIR="$(mktemp -d)"
    TEST_BIN_DIR="$TEST_TMPDIR/bin"
    TEST_FIXTURE_DIR="$TEST_TMPDIR/fixtures"

    mkdir -p "$TEST_BIN_DIR" "$TEST_FIXTURE_DIR"
    PATH="$TEST_BIN_DIR:$PATH"
    hash -r

    export REPO_ROOT TEST_TMPDIR TEST_BIN_DIR TEST_FIXTURE_DIR PATH
}

teardown_test_env() {
    if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

stub_command() {
    local name="$1"
    local script_path="$TEST_BIN_DIR/$name"

    mkdir -p "$(dirname "$script_path")"
    cat > "$script_path"
    chmod +x "$script_path"
    hash -r
}

write_file() {
    local path="$1"
    shift

    mkdir -p "$(dirname "$path")"
    printf '%s' "$*" > "$path"
}
