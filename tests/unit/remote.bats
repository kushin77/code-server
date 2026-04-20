#!/usr/bin/env bats

load test_helper.bash

setup() {
    setup_test_env

    : > "$TEST_FIXTURE_DIR/ssh-args.txt"
    : > "$TEST_FIXTURE_DIR/ssh-stdin.txt"
    : > "$TEST_FIXTURE_DIR/scp-args.txt"
    : > "$TEST_FIXTURE_DIR/docker-ssh.log"
    : > "$TEST_FIXTURE_DIR/docker-compose.log"
    write_file "$TEST_FIXTURE_DIR/key.pem" "dummy-key"

    stub_command ssh <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_FIXTURE_DIR/ssh-args.txt"
if [ "${SSH_CAPTURE_STDIN:-0}" = "1" ]; then
    cat >> "$TEST_FIXTURE_DIR/ssh-stdin.txt"
fi
exit "${SSH_STUB_EXIT:-0}"
EOF

    stub_command scp <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_FIXTURE_DIR/scp-args.txt"
exit "${SCP_STUB_EXIT:-0}"
EOF

    stub_command timeout <<'EOF'
#!/usr/bin/env bash
shift
"$@"
EOF

    stub_command nc <<'EOF'
#!/usr/bin/env bash
exit "${NC_STUB_EXIT:-0}"
EOF

    stub_command sleep <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
}

teardown() {
    teardown_test_env
}

@test "ssh_exec and ssh_standby route commands to the configured hosts" {
    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; source "$REPO_ROOT/scripts/_common/ssh.sh"; ssh_exec "docker ps"; ssh_standby "hostname"'
    [ "$status" -eq 0 ]

    run cat "$TEST_FIXTURE_DIR/ssh-args.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"akushnir@192.168.168.31 docker ps"* ]]
    [[ "$output" == *"akushnir@192.168.168.42 hostname"* ]]
}

@test "ssh_exec_target ssh_stream and upload helpers capture the expected arguments" {
    write_file "$TEST_FIXTURE_DIR/key.pem" "dummy-key"
    write_file "$TEST_FIXTURE_DIR/upload.txt" "payload"
    mkdir -p "$TEST_FIXTURE_DIR/upload-dir"
    write_file "$TEST_FIXTURE_DIR/upload-dir/nested.txt" "nested"
    write_file "$TEST_FIXTURE_DIR/stream.sh" $'#!/usr/bin/env bash\necho streamed\n'

    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; source "$REPO_ROOT/scripts/_common/ssh.sh"; ssh_exec_target "example.org" "alice" "uptime" "$TEST_FIXTURE_DIR/key.pem"; ssh_upload "$TEST_FIXTURE_DIR/upload.txt" "/tmp/upload.txt"; ssh_upload_dir "$TEST_FIXTURE_DIR/upload-dir" "/tmp/upload-dir"'
    [ "$status" -eq 0 ]

    run env SSH_CAPTURE_STDIN=1 bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; source "$REPO_ROOT/scripts/_common/ssh.sh"; ssh_stream "$TEST_FIXTURE_DIR/stream.sh" alpha beta'
    [ "$status" -eq 0 ]

    run cat "$TEST_FIXTURE_DIR/ssh-args.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-i $TEST_FIXTURE_DIR/key.pem"* ]]
    [[ "$output" == *"alice@example.org uptime"* ]]
    [[ "$output" == *"bash -s -- alpha beta"* ]]

    run cat "$TEST_FIXTURE_DIR/ssh-stdin.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"echo streamed"* ]]

    run cat "$TEST_FIXTURE_DIR/scp-args.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_FIXTURE_DIR/upload.txt"* ]]
    [[ "$output" == *"$TEST_FIXTURE_DIR/upload-dir"* ]]
    [[ "$output" == *"-r"* ]]
}

@test "ssh connectivity and port checks honor timeout and nc wrappers" {
    export SSH_STUB_EXIT=0
    export NC_STUB_EXIT=0

    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; source "$REPO_ROOT/scripts/_common/ssh.sh"; assert_ssh_up example.org alice; assert_ssh_target example.org alice "$TEST_FIXTURE_DIR/key.pem"; assert_port_open 443 example.org'
    [ "$status" -eq 0 ]
}

@test "ssh_in_deploy_dir and ssh_compose build the remote compose command" {
    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; source "$REPO_ROOT/scripts/_common/ssh.sh"; ssh_in_deploy_dir "pwd"; ssh_compose "up -d code-server"'
    [ "$status" -eq 0 ]

    run cat "$TEST_FIXTURE_DIR/ssh-args.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cd /home/akushnir/code-server-enterprise && pwd"* ]]
    [[ "$output" == *"cd /home/akushnir/code-server-enterprise && docker compose up -d code-server"* ]]
}

@test "docker helpers surface container state and lifecycle commands" {
    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; source "$REPO_ROOT/scripts/_common/docker.sh"; ssh_exec() { printf "%s\n" "${SSH_EXEC_OUTPUT:-Up 4 hours (healthy)}"; printf "%s\n" "$*" >> "$TEST_FIXTURE_DIR/docker-ssh.log"; }; ssh_compose() { printf "%s\n" "$*" >> "$TEST_FIXTURE_DIR/docker-compose.log"; }; SSH_EXEC_OUTPUT="Up 4 hours (healthy)" docker_status code-server; SSH_EXEC_OUTPUT="Up 4 hours (healthy)" docker_is_running code-server; SSH_EXEC_OUTPUT="Up 4 hours (healthy)" docker_is_healthy code-server; SSH_EXEC_OUTPUT="200" assert_http_ok https://example.test 200'
    [ "$status" -eq 0 ]
}

@test "docker lifecycle commands and health waiting call the expected remotes" {
    run bash -c 'source "$REPO_ROOT/scripts/_common/config.sh"; source "$REPO_ROOT/scripts/_common/logging.sh"; source "$REPO_ROOT/scripts/_common/utils.sh"; source "$REPO_ROOT/scripts/_common/docker.sh"; state_file="$TEST_FIXTURE_DIR/container-state.txt"; printf "running" > "$state_file"; ssh_exec() { command="$1"; printf "%s\n" "$command" >> "$TEST_FIXTURE_DIR/docker-ssh.log"; case "$command" in *"docker ps -a"*) if grep -q healthy "$state_file"; then printf "Up 1 minute (healthy)\n"; else printf "Up 1 minute\n"; fi ;; *"docker logs"*) printf "logs for %s\n" "$command" ;; *"curl -sk"*) printf "200" ;; esac; }; ssh_compose() { printf "%s\n" "$*" >> "$TEST_FIXTURE_DIR/docker-compose.log"; }; docker_start code-server caddy; docker_restart caddy; docker_stop code-server; docker_exec_in code-server ls /home/coder; docker_logs code-server 12; printf "healthy" > "$state_file"; docker_status_all; docker_healthcheck_all; assert_container_healthy code-server; docker_wait_healthy code-server 1'
    [ "$status" -eq 0 ]

    run cat "$TEST_FIXTURE_DIR/docker-compose.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"up -d code-server caddy"* ]]

    run cat "$TEST_FIXTURE_DIR/docker-ssh.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"docker restart caddy"* ]]
    [[ "$output" == *"docker stop code-server 2>/dev/null || true"* ]]
    [[ "$output" == *"docker exec code-server ls /home/coder"* ]]
    [[ "$output" == *"docker logs code-server --tail 12 2>&1"* ]]
}
