#!/bin/bash
# @file phase-58-secrets-manager.sh
# @description Phase 58 — Secrets Management & Credential Rotation Engine
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..." >&2; rm -f /tmp/p58*.tmp 2>/dev/null || true' EXIT

MODE="${1:-demo}"

cmd_demo() {
    log_info "Phase 58 — Secrets Management & Credential Rotation Engine"
    log_info "Running demo vault scan..."
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.secrets_manager import (
    SecretsManager, SecretType, RotationPolicy, AccessOutcome,
    make_secret, make_access_event
)

mgr = SecretsManager()

# Register a mix of healthy, expiring, and expired secrets
mgr.register_secret(make_secret("auth-service-jwt-secret", SecretType.SERVICE_TOKEN,
                                 RotationPolicy.MONTHLY, "auth-service", days_since_rotation=5))
mgr.register_secret(make_secret("db-password-primary", SecretType.DATABASE_PASSWORD,
                                 RotationPolicy.QUARTERLY, "data-service", days_since_rotation=91))
mgr.register_secret(make_secret("tls-cert-edge", SecretType.TLS_CERTIFICATE,
                                 RotationPolicy.ANNUALLY, "edge-gateway", days_since_rotation=360))
mgr.register_secret(make_secret("stripe-api-key", SecretType.API_KEY,
                                 RotationPolicy.MONTHLY, "billing-service",
                                 is_encrypted_at_rest=False, days_since_rotation=2))
mgr.register_secret(make_secret("ssh-deploy-key", SecretType.SSH_KEY,
                                 RotationPolicy.QUARTERLY, "ci-cd", days_since_rotation=20))

secrets = mgr.secrets()
for s in secrets:
    print(f"  {s.name:35s}  status={s.status.value:8s}  risk={s.risk_level.value}")

# Rotate all expired
rotated = mgr.rotate_all_expired(triggered_by="demo")
print(f"\\n[Phase 58] Secrets registered : {len(secrets)}")
print(f"[Phase 58] Auto-rotated       : {len(rotated)}")
print(f"[Phase 58] Expired remaining  : {len(mgr.expired_secrets())}")
print(f"[Phase 58] Unencrypted        : {len(mgr.unencrypted_secrets())}")
print(f"[Phase 58] Gate score         : {mgr.phase58_score()}/25")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.secrets_manager import SecretsManager, RotationPolicy, SecretType, make_secret

mgr = SecretsManager()
mgr.register_secret(make_secret("svc-token-a", SecretType.SERVICE_TOKEN,
                                 RotationPolicy.MONTHLY, "svc-a", days_since_rotation=5))
mgr.register_secret(make_secret("api-key-b",   SecretType.API_KEY,
                                 RotationPolicy.WEEKLY,  "svc-b", days_since_rotation=8))
print(json.dumps(mgr.summary(), indent=2))
PYEOF
}

cmd_report() {
    "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.secrets_manager import SecretsManager, RotationPolicy, SecretType, make_secret

mgr = SecretsManager()
mgr.register_secret(make_secret("healthy-token", SecretType.SERVICE_TOKEN,
                                 RotationPolicy.MONTHLY, "svc-a", days_since_rotation=2))
mgr.register_secret(make_secret("expired-db-pw", SecretType.DATABASE_PASSWORD,
                                 RotationPolicy.MONTHLY, "svc-b", days_since_rotation=35))
report = mgr.generate_report()
print(json.dumps(report.to_dict(), indent=2))
PYEOF
}

cmd_persist() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.secrets_manager import SecretsManager, RotationPolicy, SecretType, make_secret

mgr = SecretsManager()
mgr.register_secret(make_secret("demo-secret", SecretType.API_KEY, RotationPolicy.MONTHLY, "demo"))
path = mgr.persist_state('${PROJECT_ROOT}/artifacts/phase58/secrets-state.json')
print(f"State persisted to: {path}")
PYEOF
}

case "$MODE" in
    demo)    cmd_demo    ;;
    summary) cmd_summary ;;
    report)  cmd_report  ;;
    persist) cmd_persist  ;;
    *)
        log_error "Unknown mode '$MODE'. Usage: $0 [demo|summary|report|persist]"
        exit 1
        ;;
esac
