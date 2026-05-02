#!/bin/bash
# @file phase-54-crypto-asset-inventory.sh
# @description Phase 54 — Cryptographic Asset Inventory & Key Lifecycle Management
# @since 2026-05-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHON_CMD="python3"
[[ -f "${PROJECT_ROOT}/.venv/bin/python3" ]] && PYTHON_CMD="${PROJECT_ROOT}/.venv/bin/python3"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..." >&2; rm -f /tmp/p54*.tmp 2>/dev/null || true' EXIT

MODE="${1:-demo}"

cmd_demo() {
    log_info "Phase 54 — Cryptographic Asset Inventory & Key Lifecycle Management"
    log_info "Initialising demo inventory..."
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from datetime import timedelta, datetime
from security_ai.crypto_asset_inventory import (
    CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy
)

engine = CryptoAssetInventoryEngine()

assets = [
    make_asset("db-master-password",     AssetType.SECRET,        "database-team",   RotationPolicy.MONTHLY,   expires_in_days=45),
    make_asset("api-gateway-tls-cert",   AssetType.TLS_CERT,      "platform-ops",    RotationPolicy.ANNUAL,    expires_in_days=180),
    make_asset("jwt-signing-key",        AssetType.SIGNING_KEY,   "auth-service",    RotationPolicy.QUARTERLY, expires_in_days=4),
    make_asset("redis-auth-token",       AssetType.API_TOKEN,     "cache-service",   RotationPolicy.MONTHLY,   expires_in_days=-5),
    make_asset("ssh-deploy-key",         AssetType.SSH_KEY,       "ci-cd",           RotationPolicy.ANNUAL,    expires_in_days=300),
    make_asset("vault-unseal-key",       AssetType.SYMMETRIC_KEY, "security-team",   RotationPolicy.QUARTERLY, expires_in_days=60),
    make_asset("s3-access-key",          AssetType.API_TOKEN,     "storage-service", RotationPolicy.MONTHLY,   expires_in_days=3),
    make_asset("code-signing-cert",      AssetType.CERTIFICATE,   "release-team",    RotationPolicy.ANNUAL,    expires_in_days=250),
]

for a in assets:
    engine.register_asset(a)

scan = engine.scan()
score = engine.phase54_score()
print(f"[Phase 54] Assets registered : {engine.asset_count()}")
print(f"[Phase 54] Active            : {scan['active']}")
print(f"[Phase 54] Expiring soon     : {scan['expiring']}")
print(f"[Phase 54] Expired           : {scan['expired']}")
print(f"[Phase 54] Overdue rotation  : {scan['overdue']}")
print(f"[Phase 54] Gate score        : {score}/25")
print(f"[Phase 54] Status            : {'PASS' if score >= 20 else 'REVIEW'}")
PYEOF
}

cmd_summary() {
    "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy

engine = CryptoAssetInventoryEngine()
for name, atype, owner, policy, days in [
    ("db-master-password",   "secret",        "db-team",   "monthly",   45),
    ("api-tls-cert",         "tls_cert",      "ops",       "annual",    180),
    ("jwt-signing-key",      "signing_key",   "auth",      "quarterly", 4),
]:
    engine.register_asset(make_asset(name, AssetType(atype), owner, RotationPolicy(policy), expires_in_days=days))

print(json.dumps(engine.summary(), indent=2))
PYEOF
}

cmd_report() {
    "$PYTHON_CMD" - <<PYEOF
import sys, json
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy

engine = CryptoAssetInventoryEngine()
for name, atype, owner, policy, days in [
    ("db-master-password",   "secret",        "db-team",   "monthly",   45),
    ("api-tls-cert",         "tls_cert",      "ops",       "annual",    180),
    ("jwt-signing-key",      "signing_key",   "auth",      "quarterly", 4),
]:
    engine.register_asset(make_asset(name, AssetType(atype), owner, RotationPolicy(policy), expires_in_days=days))

r = engine.generate_report()
print(json.dumps(r.to_dict(), indent=2))
PYEOF
}

cmd_persist() {
    "$PYTHON_CMD" - <<PYEOF
import sys
sys.path.insert(0, '${PROJECT_ROOT}/apps')
from security_ai.crypto_asset_inventory import CryptoAssetInventoryEngine, make_asset, AssetType, RotationPolicy

engine = CryptoAssetInventoryEngine()
engine.register_asset(make_asset("demo-key", AssetType.SYMMETRIC_KEY, "platform", RotationPolicy.MONTHLY, 30))
path = engine.persist_state('${PROJECT_ROOT}/artifacts/phase54/crypto-inventory.json')
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
