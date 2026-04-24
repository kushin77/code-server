#!/usr/bin/env bash
# @file        scripts/ci/validate-revocation-broker.sh
# @module      ci/security
# @description Validate the strict revocation broker contract, test coverage, and operational revoke entrypoints
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_FILE="${1:-$ROOT_DIR/artifacts/security/revocation-broker-report.json}"

FILES=(
  "$ROOT_DIR/src/services/revocation-broker/index.ts"
  "$ROOT_DIR/src/services/revocation-broker/types.ts"
  "$ROOT_DIR/tests/unit/revocation-broker/enforcement.spec.ts"
  "$ROOT_DIR/docs/strict-revocation-path-757.md"
  "$ROOT_DIR/Makefile"
)

require_command "python3" "python3 is required"
for file in "${FILES[@]}"; do
  require_file "$file"
done

mkdir -p "$(dirname "$REPORT_FILE")"

python3 - "$REPORT_FILE" "${FILES[@]}" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

report_path = sys.argv[1]
paths = [Path(p) for p in sys.argv[2:]]
contents = {path.name: path.read_text(encoding='utf-8') for path in paths}

index_ts = contents['index.ts']
types_ts = contents['types.ts']
tests_ts = contents['enforcement.spec.ts']
revocation_doc = contents['strict-revocation-path-757.md']
makefile = contents['Makefile']

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

service_checks = [
    'export class RevocationBroker implements IRevocationBroker',
    'async revoke(options: RevokeOptions): Promise<RevokeResult>',
    'async checkRevocation(options: RevocationCheckOptions): Promise<RevocationCheckResult>',
    'async checkPrivilegedOperation(context: PrivilegedOperationContext): Promise<PrivilegedOperationResult>',
    'async restoreRevocation(revocationId: string, actor: string, correlationId: string): Promise<RevokeResult>',
    'async startRevocationDrill(options: RevocationDrillOptions): Promise<RevocationDrillResult>',
    'async getStatistics(): Promise<RevocationStats>',
    'async shutdown(): Promise<void>',
    'DEFAULTS TO DENY',
    'p95 SLO target: 5000ms',
]

for item in service_checks:
    require(has(index_ts, item), f'revocation broker service missing: {item}')

type_checks = [
    'export enum RevocationStatus',
    'export enum RevocationScope',
    'export enum RevocationReason',
    'export enum UnknownRevocationBehavior',
    'DENY = "deny"',
    'export interface RevocationEntry',
    'export interface RevocationCheckOptions',
    'export interface RevocationCheckResult',
    'export interface RevokeOptions',
    'export interface RevokeResult',
    'export interface RevocationDrillOptions',
    'export interface RevocationDrillResult',
    'export interface RevocationStats',
    'export interface RevocationAuditEvent',
    'export interface PrivilegedOperationContext',
    'export interface PrivilegedOperationResult',
    'export interface RevocationBrokerConfig',
    'export interface HostRevocationState',
    'export interface IRevocationBroker',
    'break_glass',
    'sloTargetMs: number',
]

for item in type_checks:
    require(has(types_ts, item), f'revocation broker types missing: {item}')

test_sections = [
    '1. Targeted User Revocation (No Global Restart)',
    '2. Targeted Session Revocation',
    '3. Privilege Revocation',
    '4. Unknown Revocation State = DENY (Fail-Safe)',
    '5. Emergency Revocation (<5s SLO)',
    '8. Revocation Drill - SLO Validation',
    '11. Caching & Performance',
    '12. Error Handling & Recovery',
    'should revoke user without global restart',
    'should deny operations after user revocation',
    'should auto-restore revocation after expiry',
    'should execute revocation drill within SLO',
    'should invalidate cache when revocation is applied',
]

for item in test_sections:
    require(has(tests_ts, item), f'revocation broker test coverage missing: {item}')

doc_checks = [
    '**Status**: ✅ Implementation Complete',
    'Unknown revocation state **defaults to DENY**',
    'p95 propagation SLO: 5000ms',
    'Module: `src/services/revocation-broker/`',
    'RevocationBroker class implementing IRevocationBroker',
]

for item in doc_checks:
    require(has(revocation_doc, item), f'revocation path doc missing: {item}')

make_checks = [
    'revoke-access:',
    './scripts/developer-revoke "$(EMAIL)" "$$REASON" || exit 1',
]

for item in make_checks:
    require(has(makefile, item), f'Makefile missing revocation entrypoint: {item}')

warn(has(index_ts, 'propagationPromise.catch'), 'normal revocation propagation is asynchronous by design; verify emergency paths with drill evidence')

summary = {
    'file_count': len(paths),
    'error_count': len(errors),
    'warning_count': len(warnings),
    'validated_surface': [
        'src/services/revocation-broker/index.ts',
        'src/services/revocation-broker/types.ts',
        'tests/unit/revocation-broker/enforcement.spec.ts',
        'docs/strict-revocation-path-757.md',
        'Makefile',
    ],
}

report = {
    'generated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'summary': summary,
    'errors': errors,
    'warnings': warnings,
}

Path(report_path).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

print(f'Revocation broker report: {report_path}')
print(f'Errors: {len(errors)}')
print(f'Warnings: {len(warnings)}')

if errors:
    sys.exit(1)
PY

log_info "Revocation broker contract validated"
log_info "Report written: $REPORT_FILE"