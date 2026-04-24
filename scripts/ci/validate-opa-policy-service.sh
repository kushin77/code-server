#!/usr/bin/env bash
# @file        scripts/ci/validate-opa-policy-service.sh
# @module      ci/governance
# @description Validate the OPA policy service rollout contract, conformance coverage, and bundle metadata
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_FILE="${1:-$ROOT_DIR/artifacts/security/opa-policy-service-report.json}"

FILES=(
  "$ROOT_DIR/src/services/opa-policy-service/index.ts"
  "$ROOT_DIR/src/services/opa-policy-service/types.ts"
  "$ROOT_DIR/tests/unit/opa-policy-service/conformance.spec.ts"
  "$ROOT_DIR/config/policy-bundles/bundle-catalog.json"
  "$ROOT_DIR/config/policy-bundles/bundle-schema.json"
)

require_command "python3" "python3 is required"
for file in "${FILES[@]}"; do
  require_file "$file"
done

mkdir -p "$(dirname "$REPORT_FILE")"

python3 - "$REPORT_FILE" "${FILES[@]}" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

report_path = sys.argv[1]
paths = [Path(p) for p in sys.argv[2:]]
contents = {p.name: p.read_text(encoding='utf-8') for p in paths}

index_ts = contents['index.ts']
types_ts = contents['types.ts']
tests_ts = contents['conformance.spec.ts']
catalog = json.loads(contents['bundle-catalog.json'])
schema = json.loads(contents['bundle-schema.json'])

errors = []
warnings = []

def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

def warn(condition: bool, message: str) -> None:
    if not condition:
        warnings.append(message)

def has(text: str, needle: str) -> bool:
    return needle in text

def regex(text: str, pattern: str) -> bool:
    return re.search(pattern, text, re.MULTILINE) is not None

required_methods = [
    'loadCatalog()',
    'saveCatalog(catalog: BundleCatalog): void',
    'setDistributionContract(contract: DistributionContract): void',
    'resolveBundle(repo: string): ResolvedPolicyBundle',
    'simulateDecision(input: PolicyDecisionInput): PolicyDecisionResult',
    'logDecision(input: PolicyDecisionInput, result: PolicyDecisionResult, policyDomain = "governance"): DecisionLogEvent',
    'queryDecisionLogs(query: DecisionQuery = {}): DecisionLogEvent[]',
    'promoteBundle(channel: PolicyChannel, version: string, bundleManifest: string): PromotionAuditEvent',
    'rollbackBundle(channel: PolicyChannel, version: string, bundleManifest: string, reason: string): PromotionAuditEvent',
]

for method in required_methods:
    require(has(index_ts, method), f'OPA policy service must expose {method}')

required_types = [
    'export type PolicyChannel = "stable" | "canary" | "rollback"',
    'export interface BundleCatalog',
    'export interface DistributionContract',
    'export interface ResolvedPolicyBundle',
    'export interface PolicyDecisionInput',
    'export interface PolicyDecisionResult',
    'export interface DecisionLogEvent',
    'export interface DecisionQuery',
    'export interface PolicyServiceConfig',
    'export interface PromotionAuditEvent',
]

for item in required_types:
    require(has(types_ts, item), f'OPA policy service types must define {item}')

required_tests = [
    'resolves stable channel by default',
    'routes repo to canary when distribution contract matches',
    'denies mutating action on rollback channel in simulation',
    'logs and queries decision events by correlation id',
    'prunes old decision logs according to retention',
    'writes promotion audit event',
    'requires reason for rollback',
]

for title in required_tests:
    require(has(tests_ts, title), f'OPA policy service conformance test missing: {title}')

require(isinstance(catalog, dict), 'bundle catalog must be a JSON object')
channels = catalog.get('channels', {}) if isinstance(catalog, dict) else {}
require(isinstance(channels, dict), 'bundle catalog channels must be an object')
for channel in ('stable', 'canary', 'rollback'):
    require(channel in channels, f'bundle catalog missing channel: {channel}')
    pointer = channels.get(channel, {})
    require(isinstance(pointer, dict), f'bundle catalog pointer for {channel} must be an object')
    if isinstance(pointer, dict):
        require(isinstance(pointer.get('version'), str) and pointer['version'].strip(), f'bundle catalog {channel} version must be set')
        require(isinstance(pointer.get('bundle_manifest'), str) and pointer['bundle_manifest'].strip(), f'bundle catalog {channel} bundle_manifest must be set')

require(isinstance(schema, dict), 'bundle schema must be a JSON object')
required_schema_keys = ['bundle_id', 'version', 'channel', 'generated_at', 'expires_at', 'policies', 'signature']
for key in required_schema_keys:
    require(key in schema.get('required', []), f'bundle schema missing required field: {key}')

warn(has(index_ts, 'pruneDecisionLog()'), 'OPA policy service pruning is implementation-defined; verify retention policy in deployment reviews')

summary = {
    'file_count': len(paths),
    'error_count': len(errors),
    'warning_count': len(warnings),
    'validated_surface': [
        'src/services/opa-policy-service/index.ts',
        'src/services/opa-policy-service/types.ts',
        'tests/unit/opa-policy-service/conformance.spec.ts',
        'config/policy-bundles/bundle-catalog.json',
        'config/policy-bundles/bundle-schema.json',
    ],
}

report = {
    'generated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'summary': summary,
    'errors': errors,
    'warnings': warnings,
}

Path(report_path).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

print(f'OPA policy service report: {report_path}')
print(f'Errors: {len(errors)}')
print(f'Warnings: {len(warnings)}')

if errors:
    sys.exit(1)
PY

log_info "OPA policy service contract validated"
log_info "Report written: $REPORT_FILE"