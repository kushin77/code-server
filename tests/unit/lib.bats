#!/usr/bin/env bats

load test_helper.bash

setup() {
    setup_test_env

    : > "$TEST_FIXTURE_DIR/audit.log"
    : > "$TEST_FIXTURE_DIR/curl.log"
    : > "$TEST_FIXTURE_DIR/policy.yml"
    : > "$TEST_FIXTURE_DIR/inventory.yml"
}

teardown() {
    teardown_test_env
}

@test "inventory loader populates host metadata and derived accessors" {
    write_file "$TEST_FIXTURE_DIR/environments/production/hosts.yml" $'hosts:\n  primary:\n    ip: 192.168.168.31\n    fqdn: primary.prod.internal\n    ssh_user: akushnir\n    ssh_port: 22\n  replica:\n    ip: 192.168.168.42\n    fqdn: replica.prod.internal\n    ssh_user: akushnir\n    ssh_port: 22\nvip:\n  ip: 192.168.168.30\n  fqdn: prod.internal\ncluster_name: code-server-enterprise\ndomain_internal: prod.internal\ndomain_external: kushnir.cloud\n'

    export PROJECT_DIR="$TEST_FIXTURE_DIR"
    export REAL_PYTHON3="$(command -v python3)"
    : > "$TEST_FIXTURE_DIR/ssh-args.txt"
    stub_command python3 <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-" ]; then
    cat <<'OUT'
PRIMARY_IP=192.168.168.31
PRIMARY_FQDN=primary.prod.internal
PRIMARY_SSH_USER=akushnir
PRIMARY_SSH_PORT=22
REPLICA_IP=192.168.168.42
REPLICA_FQDN=replica.prod.internal
REPLICA_SSH_USER=akushnir
REPLICA_SSH_PORT=22
VIP_IP=192.168.168.30
VIP_FQDN=prod.internal
CLUSTER_NAME=code-server-enterprise
DOMAIN_INTERNAL=prod.internal
DOMAIN_EXTERNAL=kushnir.cloud
OUT
    exit 0
fi
exec "$REAL_PYTHON3" "$@"
EOF

    stub_command ssh <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_FIXTURE_DIR/ssh-args.txt"
exit 0
EOF

    run env INVENTORY_PYTHON_BIN="$TEST_BIN_DIR/python3" bash -c 'source "$REPO_ROOT/scripts/lib/inventory-loader.sh"; inventory_load_production; ssh_to_host primary "uptime"; printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" "$PRIMARY_IP" "$PRIMARY_FQDN" "$REPLICA_IP" "$REPLICA_FQDN" "$VIP_IP" "$VIP_FQDN" "$CLUSTER_NAME" "$DOMAIN_INTERNAL" "$DOMAIN_EXTERNAL" "$(get_host_ip primary)" "$(get_host_fqdn replica)" "$(get_vip_ip)" "$(get_ssh_command primary)" "$(get_ssh_user primary)" "$(get_ssh_port replica)" "$(get_vip_fqdn)" "$(list_all_hosts)"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"192.168.168.31|primary.prod.internal|192.168.168.42|replica.prod.internal|192.168.168.30|prod.internal|code-server-enterprise|prod.internal|kushnir.cloud|192.168.168.31|replica.prod.internal|192.168.168.30|ssh -p 22 akushnir@192.168.168.31|akushnir|22|prod.internal|primary replica"* ]]

    run cat "$TEST_FIXTURE_DIR/ssh-args.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"akushnir@192.168.168.31 uptime"* ]]
}

@test "inventory export and validation helpers use the loaded topology" {
    write_file "$TEST_FIXTURE_DIR/environments/production/hosts.yml" "inventory"

    export PROJECT_DIR="$TEST_FIXTURE_DIR"
    export REAL_PYTHON3="$(command -v python3)"
    stub_command python3 <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-" ]; then
    cat <<'OUT'
PRIMARY_IP=192.168.168.31
PRIMARY_FQDN=primary.prod.internal
PRIMARY_SSH_USER=akushnir
PRIMARY_SSH_PORT=22
REPLICA_IP=192.168.168.42
REPLICA_FQDN=replica.prod.internal
REPLICA_SSH_USER=akushnir
REPLICA_SSH_PORT=22
VIP_IP=192.168.168.30
VIP_FQDN=prod.internal
CLUSTER_NAME=code-server-enterprise
DOMAIN_INTERNAL=prod.internal
DOMAIN_EXTERNAL=kushnir.cloud
OUT
    exit 0
fi
exec "$REAL_PYTHON3" "$@"
EOF

    stub_command ping <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    run env INVENTORY_PYTHON_BIN="$TEST_BIN_DIR/python3" bash -c 'source "$REPO_ROOT/scripts/lib/inventory-loader.sh"; export_inventory_vars; validate_inventory; printf "%s|%s|%s|%s|%s|%s|%s" "$PRIMARY_IP" "$PRIMARY_FQDN" "$REPLICA_IP" "$REPLICA_FQDN" "$VIP_IP" "$VIP_FQDN" "$(list_all_hosts)"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"192.168.168.31|primary.prod.internal|192.168.168.42|replica.prod.internal|192.168.168.30|prod.internal|primary replica"* ]]
}

@test "policy bundle cache and fail-safe modes behave as expected" {
    write_file "$TEST_FIXTURE_DIR/policy-cache.json" '{"policy":"cached"}'
    touch "$TEST_FIXTURE_DIR/policy-cache.json"

    run env POLICY_BUNDLE_CACHE="$TEST_FIXTURE_DIR/policy-cache.json" POLICY_CACHE_TTL=300 bash -c 'source "$REPO_ROOT/scripts/lib/policy-bundle.sh"; policy_bundle_load alice@example.com'
    [ "$status" -eq 0 ]

    stub_command curl <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

    run env POLICY_BUNDLE_CACHE="$TEST_FIXTURE_DIR/policy-cache.json" POLICY_CACHE_TTL=0 POLICY_FAIL_SAFE=deny-all bash -c 'source "$REPO_ROOT/scripts/lib/policy-bundle.sh"; policy_bundle_load alice@example.com'
    [ "$status" -eq 2 ]
}

@test "policy bundle fetches portal responses when the cache is stale" {
    stub_command curl <<'EOF'
#!/usr/bin/env bash
printf '{"policy":"fresh"}'
EOF

    run env POLICY_BUNDLE_CACHE="$TEST_FIXTURE_DIR/policy-cache.json" POLICY_CACHE_TTL=0 bash -c 'source "$REPO_ROOT/scripts/lib/policy-bundle.sh"; policy_bundle_load alice@example.com'
    [ "$status" -eq 0 ]

    run cat "$TEST_FIXTURE_DIR/policy-cache.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"policy":"fresh"'* ]]
}

@test "policy bundle revocation checks and assertions honor portal responses" {
    stub_command curl <<'EOF'
#!/usr/bin/env bash
printf '{"revoked":false}'
EOF

    run env POLICY_PORTAL_URL=https://policy.example bash -c 'source "$REPO_ROOT/scripts/lib/policy-bundle.sh"; policy_bundle_check_revocation alice@example.com'
    [ "$status" -eq 0 ]

    stub_command curl <<'EOF'
#!/usr/bin/env bash
printf '{"revoked":true}'
EOF

    run env POLICY_PORTAL_URL=https://policy.example bash -c 'source "$REPO_ROOT/scripts/lib/policy-bundle.sh"; policy_bundle_assert_not_revoked alice@example.com'
    [ "$status" -eq 1 ]
}

@test "automation policy gate allows, audits, and blocks according to repo policy" {
    write_file "$TEST_FIXTURE_DIR/policy.yml" $'repos:\n  kushin77/code-server:\n    allow: true\n'

    run env AUTOMATION_POLICY_FILE="$TEST_FIXTURE_DIR/policy.yml" AUTOMATION_AUDIT_LOG="$TEST_FIXTURE_DIR/audit.log" bash -c 'source "$REPO_ROOT/scripts/lib/automation-policy-gate.sh"; policy_gate_check kushin77/code-server mutating; policy_gate_require kushin77/code-server mutating'
    [ "$status" -eq 0 ]

    run env AUTOMATION_POLICY_FILE="$TEST_FIXTURE_DIR/policy.yml" AUTOMATION_AUDIT_LOG="$TEST_FIXTURE_DIR/audit.log" DRY_RUN=1 bash -c 'source "$REPO_ROOT/scripts/lib/automation-policy-gate.sh"; policy_gate_check other/repo mutating'
    [ "$status" -eq 1 ]

    run env AUTOMATION_POLICY_FILE="$TEST_FIXTURE_DIR/policy.yml" AUTOMATION_AUDIT_LOG="$TEST_FIXTURE_DIR/audit.log" AUTOMATION_POLICY_BREAK_GLASS=1 BREAK_GLASS_REASON="incident" bash -c 'source "$REPO_ROOT/scripts/lib/automation-policy-gate.sh"; policy_gate_check other/repo mutating'
    [ "$status" -eq 0 ]

    run env AUTOMATION_POLICY_FILE="$TEST_FIXTURE_DIR/policy.yml" AUTOMATION_AUDIT_LOG="$TEST_FIXTURE_DIR/audit.log" bash -c 'source "$REPO_ROOT/scripts/lib/automation-policy-gate.sh"; policy_gate_check other/repo read'
    [ "$status" -eq 0 ]

    run cat "$TEST_FIXTURE_DIR/audit.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo=kushin77/code-server"* ]]
    [[ "$output" == *"allowed"* ]]
    [[ "$output" == *"dry_run_skip"* ]]
    [[ "$output" == *"BREAK_GLASS=1"* ]]
}
