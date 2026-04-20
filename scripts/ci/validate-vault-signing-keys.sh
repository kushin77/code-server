#!/usr/bin/env bash
# @file        scripts/ci/validate-vault-signing-keys.sh
# @module      ci/security
# @description Validate the vault-backed signing key contract used for policy bundle rotation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTRACT_FILE="${1:-$ROOT_DIR/config/vault-signing-keys.json}"
REPORT_FILE="${2:-$ROOT_DIR/artifacts/security/vault-signing-keys-report.json}"

require_file "$CONTRACT_FILE"
require_command "python3" "python3 is required"

mkdir -p "$(dirname "$REPORT_FILE")"

python3 - "$CONTRACT_FILE" "$REPORT_FILE" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone

contract_path = sys.argv[1]
report_path = sys.argv[2]

with open(contract_path, 'r', encoding='utf-8') as handle:
    contract = json.load(handle)

errors = []
warnings = []

def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

def warn(condition: bool, message: str) -> None:
    if not condition:
        warnings.append(message)

def parse_utc(value: str):
    try:
        return datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    except Exception:
        return None

require(isinstance(contract, dict), 'contract root must be an object')
if not isinstance(contract, dict):
    contract = {}

require(contract.get('schema_version') == '1.0', 'schema_version must be 1.0')
require(isinstance(contract.get('description'), str) and contract['description'].strip(), 'description must be a non-empty string')
require(contract.get('vault_path') == 'secret/policy/signing-keys', 'vault_path must point at secret/policy/signing-keys')

key_versions = contract.get('key_versions')
require(isinstance(key_versions, dict), 'key_versions must be an object')
if not isinstance(key_versions, dict):
    key_versions = {}

for label in ('current', 'previous'):
    key = key_versions.get(label)
    require(isinstance(key, dict), f'key_versions.{label} must be an object')
    if not isinstance(key, dict):
        continue

    key_id = key.get('key_id')
    require(isinstance(key_id, str) and re.match(r'^policy-signing-v[0-9]+$', key_id or ''), f'key_versions.{label}.key_id must match policy-signing-vN')

    vault_version = key.get('vault_version')
    require(isinstance(vault_version, int) and vault_version >= 1, f'key_versions.{label}.vault_version must be a positive integer')

    algorithm = key.get('algorithm')
    require(isinstance(algorithm, str) and algorithm.strip(), f'key_versions.{label}.algorithm must be a non-empty string')

    rotation_date = key.get('rotation_date')
    expiry_date = key.get('expiry_date')
    rotation_dt = parse_utc(rotation_date) if isinstance(rotation_date, str) else None
    expiry_dt = parse_utc(expiry_date) if isinstance(expiry_date, str) else None
    require(rotation_dt is not None, f'key_versions.{label}.rotation_date must be UTC RFC3339')
    require(expiry_dt is not None, f'key_versions.{label}.expiry_date must be UTC RFC3339')
    if rotation_dt is not None and expiry_dt is not None:
        require(expiry_dt > rotation_dt, f'key_versions.{label}.expiry_date must be after rotation_date')

    status = key.get('status')
    require(isinstance(status, str) and status.strip(), f'key_versions.{label}.status must be a non-empty string')

current = key_versions.get('current', {}) if isinstance(key_versions.get('current', {}), dict) else {}
previous = key_versions.get('previous', {}) if isinstance(key_versions.get('previous', {}), dict) else {}

require(current.get('status') == 'active', 'current key status must be active')
require(previous.get('status') == 'valid-for-verification-only', 'previous key status must be valid-for-verification-only')
require(current.get('algorithm') == 'RS256', 'current key algorithm must be RS256')
warn(previous.get('algorithm') in {'sha256-hmac', 'RS256'}, 'previous key algorithm should be sha256-hmac or RS256 during migration')

rotation_policy = contract.get('rotation_policy')
require(isinstance(rotation_policy, dict), 'rotation_policy must be an object')
if not isinstance(rotation_policy, dict):
    rotation_policy = {}

require(rotation_policy.get('enabled') is True, 'rotation_policy.enabled must be true')
require(rotation_policy.get('interval_days') == 90, 'rotation_policy.interval_days must be 90')
require(rotation_policy.get('retention_versions') == 2, 'rotation_policy.retention_versions must be 2')
require(rotation_policy.get('auto_rotate_on_expiry') is True, 'rotation_policy.auto_rotate_on_expiry must be true')
require(rotation_policy.get('audit_trail_required') is True, 'rotation_policy.audit_trail_required must be true')

verification_rules = contract.get('verification_rules')
require(isinstance(verification_rules, dict), 'verification_rules must be an object')
if not isinstance(verification_rules, dict):
    verification_rules = {}

require(verification_rules.get('accept_current') is True, 'verification_rules.accept_current must be true')
require(verification_rules.get('accept_previous_valid_versions') is True, 'verification_rules.accept_previous_valid_versions must be true')
require(verification_rules.get('reject_expired') is True, 'verification_rules.reject_expired must be true')
require(verification_rules.get('reject_unknown_key_ids') is True, 'verification_rules.reject_unknown_key_ids must be true')
require(verification_rules.get('key_version_mismatch_action') in {'warn', 'deny'}, 'verification_rules.key_version_mismatch_action must be warn or deny')

summary = {
    'schema_version': contract.get('schema_version'),
    'vault_path': contract.get('vault_path'),
    'current_key_id': current.get('key_id'),
    'previous_key_id': previous.get('key_id'),
    'rotation_enabled': rotation_policy.get('enabled'),
    'audit_trail_required': rotation_policy.get('audit_trail_required'),
    'error_count': len(errors),
    'warning_count': len(warnings),
}

report = {
    'generated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'contract_file': contract_path,
    'summary': summary,
    'errors': errors,
    'warnings': warnings,
}

with open(report_path, 'w', encoding='utf-8') as handle:
    json.dump(report, handle, indent=2)
    handle.write('\n')

print(f'Vault signing key contract report: {report_path}')
print(f'Errors: {len(errors)}')
print(f'Warnings: {len(warnings)}')

if errors:
    sys.exit(1)
PY

log_info "Vault signing key contract validated: $CONTRACT_FILE"
log_info "Report written: $REPORT_FILE"