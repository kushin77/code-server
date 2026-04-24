#!/usr/bin/env bats

load test_helper.bash

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "config exposes production defaults and env overrides" {
    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; printf "%s|%s|%s" "$DEPLOY_HOST" "$DOMAIN" "$COMPOSE_PROJECT"'
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.168.31|ide.kushnir.cloud|code-server-enterprise" ]

    run env DEPLOY_HOST=10.10.10.10 DOMAIN=example.test bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; printf "%s|%s" "$DEPLOY_HOST" "$DOMAIN"'
    [ "$status" -eq 0 ]
    [ "$output" = "10.10.10.10|example.test" ]
}

@test "config load_env and export_vars work together" {
    write_file "$TEST_FIXTURE_DIR/sample.env" $'FOO=bar\nBAZ=qux\n'

    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; load_env "$TEST_FIXTURE_DIR/sample.env"; printf "%s|%s" "$FOO" "$BAZ"'
    [ "$status" -eq 0 ]
    [ "$output" = "bar|qux" ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; alpha=one; beta=two; export_vars alpha beta; bash -c "printf \"%s|%s\" \"$alpha\" \"$beta\""'
    [ "$status" -eq 0 ]
    [ "$output" = "one|two" ]
}

@test "logging formats human and json output" {
    export LOG_NO_COLOR=1
    export LOG_LEVEL=0

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; log_info "hello world"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO] hello world"* ]]

    run bash -c 'LOG_FORMAT=json source "$REPO_ROOT/scripts/_common/logging.sh"; LOG_FORMAT=json log_warn "json payload" 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"level":"WARN"'* ]]
    [[ "$output" == *'"msg":"json payload"'* ]]
}

@test "logging fatal and file output behave consistently" {
    export LOG_NO_COLOR=1
    export LOG_LEVEL=0
    export LOG_FILE="$TEST_FIXTURE_DIR/log.txt"

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; log_error "failure path" 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"[ERROR] failure path"* ]]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; log_fatal "stop now" 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"[FATAL] stop now"* ]]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; log_info "file line"'
    [ "$status" -eq 0 ]
    run cat "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO] file line"* ]]
}

@test "utility string and array helpers work" {
    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; string_contains "hello world" "world"'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; string_match "code-server-123" "^code-server-[0-9]+$"'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; printf "<%s>" "$(str_trim "  spaced text  ")"'
    [ "$status" -eq 0 ]
    [ "$output" = "<spaced text>" ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; array_contains beta alpha beta gamma'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; array_join ":" alpha beta gamma'
    [ "$status" -eq 0 ]
    [ "$output" = "alpha:beta:gamma" ]
}

@test "utility prerequisite checks and retry logic work" {
    stub_command demo-tool <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; require_command demo-tool'
    [ "$status" -eq 0 ]

    touch "$TEST_FIXTURE_DIR/required.txt"
    mkdir -p "$TEST_FIXTURE_DIR/required-dir"

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; require_file "$TEST_FIXTURE_DIR/required.txt"; require_dir "$TEST_FIXTURE_DIR/required-dir"'
    [ "$status" -eq 0 ]

    export REQUIRED_VAR=present
    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; require_var REQUIRED_VAR'
    [ "$status" -eq 0 ]

    write_file "$TEST_FIXTURE_DIR/counter.txt" "0"
    stub_command flaky <<'EOF'
#!/usr/bin/env bash
counter_file="$TEST_FIXTURE_DIR/counter.txt"
attempt=$(cat "$counter_file")
attempt=$((attempt + 1))
printf '%s' "$attempt" > "$counter_file"
if [ "$attempt" -lt 3 ]; then
    exit 1
fi
exit 0
EOF

    stub_command sleep <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; retry 3 flaky'
    [ "$status" -eq 0 ]
    run cat "$TEST_FIXTURE_DIR/counter.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "utility file and docker readiness helpers work" {
    write_file "$TEST_FIXTURE_DIR/src.txt" "source content"
    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; copy_file "$TEST_FIXTURE_DIR/src.txt" "$TEST_FIXTURE_DIR/dst.txt"'
    [ "$status" -eq 0 ]
    run cat "$TEST_FIXTURE_DIR/dst.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "source content" ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; mktemp_dir'
    [ "$status" -eq 0 ]
    [[ "$output" == /tmp/* ]]

    run bash -c 'docker() { [ "$1" = "info" ] && return 0 || return 1; }; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; docker_ready'
    [ "$status" -eq 0 ]
}

@test "error handler assertions and context helpers work" {
    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; assert_success true'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; assert_failure false'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; assert_equal expected expected'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; assert_not_empty value name'
    [ "$status" -eq 0 ]

    touch "$TEST_FIXTURE_DIR/file.txt"
    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; assert_file "$TEST_FIXTURE_DIR/file.txt"'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; push_context outer; push_context inner; printf "%s" "$(get_context)"'
    [ "$status" -eq 0 ]
    [ "$output" = "inner" ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; with_context build true; printf "%s" "$(get_context)"'
    [ "$status" -eq 0 ]
    [ "$output" = "root" ]

    export REQUIRED_A=one
    export REQUIRED_B=two
    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; assert_env REQUIRED_A; assert_envs REQUIRED_A REQUIRED_B'
    [ "$status" -eq 0 ]
}

@test "remaining logging and validation helpers behave consistently" {
    export LOG_NO_COLOR=1
    export LOG_LEVEL=0
    export sample_var=sample-value

    stub_command echo-tool <<'EOF'
#!/usr/bin/env bash
printf 'tool-output\n'
EOF

    stub_command demo-tool <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; log_debug "debug line"; log_exec echo-tool hi; log_var sample_var; log_section "Section title"; log_success "success path"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DEBUG] debug line"* ]]
    [[ "$output" == *"Executing: echo-tool hi"* ]]
    [[ "$output" == *"sample_var=sample-value"* ]]
    [[ "$output" == *"Section title"* ]]
    [[ "$output" == *"✓ success path"* ]]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; log_failure "failure path" 2>&1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗ failure path"* ]]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; require_commands demo-tool echo-tool'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; validate_exit 7 bash -c "exit 7"'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; set +e; false; check_exit'
    [ "$status" -eq 1 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/error-handler.sh"; assert_docker; assert_deploy_access'
    [ "$status" -eq 0 ]

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; add_cleanup sample_cleanup; declare -p _CLEANUP_HANDLERS'
    [ "$status" -eq 0 ]
    [[ "$output" == *"sample_cleanup"* ]]

    write_file "$TEST_FIXTURE_DIR/utils-docker-state.txt" "0"
    stub_command docker <<'EOF'
#!/usr/bin/env bash
state_file="$TEST_FIXTURE_DIR/utils-docker-state.txt"
if [ "$1" = "info" ]; then
    exit 0
fi
if [ "$1" = "inspect" ]; then
    count=$(cat "$state_file")
    count=$((count + 1))
    printf '%s' "$count" > "$state_file"
    if [ "$count" -ge 2 ]; then
        printf 'healthy'
    else
        printf 'starting'
    fi
    exit 0
fi
exit 1
EOF

    run bash -c 'source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; docker_wait_healthy demo-container 5'
    [ "$status" -eq 0 ]

    run bash -c 'command() { if [ "$1" = "-v" ] && [ "$2" = "gcloud" ]; then return 1; fi; builtin command "$@"; }; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; bootstrap_github_auth'
    [ "$status" -eq 1 ]
}
