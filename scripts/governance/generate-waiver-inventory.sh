#!/usr/bin/env bash
# @file        scripts/governance/generate-waiver-inventory.sh
# @module      governance/waivers
# @description Generate waiver inventory JSON and Markdown views from canonical registry
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REGISTRY_FILE=""
OUTPUT_JSON=""
OUTPUT_MD=""
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/generate-waiver-inventory.sh \
    --registry <path> \
    --output-json <path> \
    --output-md <path>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry)
      REGISTRY_FILE="$2"
      shift 2
      ;;
    --output-json)
      OUTPUT_JSON="$2"
      shift 2
      ;;
    --output-md)
      OUTPUT_MD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REGISTRY_FILE" || -z "$OUTPUT_JSON" || -z "$OUTPUT_MD" ]]; then
  log_error "Missing required flags"
  usage
  exit 1
fi

require_command "python3" "python3 is required"

if [[ ! -f "$REGISTRY_FILE" ]]; then
  log_error "Registry file not found: $REGISTRY_FILE"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_JSON")"
mkdir -p "$(dirname "$OUTPUT_MD")"

python3 - "$REGISTRY_FILE" "$OUTPUT_JSON" "$OUTPUT_MD" "$NOW_UTC" <<'EOF'
import json
import re
import sys

registry_file, output_json, output_md, now_utc = sys.argv[1:5]

with open(registry_file, 'r', encoding='utf-8') as f:
    parsed = json.load(f)

waivers = parsed.get('waivers', []) if isinstance(parsed, dict) else []
if not isinstance(waivers, list):
    waivers = []

sig_re = re.compile(r'^sha256:[a-f0-9]{64}$', re.IGNORECASE)

inventory_waivers = []
for w in waivers:
    approval = w.get('approval', {}) if isinstance(w.get('approval', {}), dict) else {}
    scope = w.get('scope', {}) if isinstance(w.get('scope', {}), dict) else {}
    repos = scope.get('repositories', []) if isinstance(scope.get('repositories', []), list) else []
    paths = scope.get('paths', []) if isinstance(scope.get('paths', []), list) else []
    inventory_waivers.append({
        'id': w.get('id'),
        'issue_number': w.get('issue_number'),
        'policy_id': w.get('policy_id'),
        'owner': w.get('owner'),
        'approver': w.get('approver'),
        'status': w.get('status'),
        'approved_at': approval.get('approved_at', ''),
        'expires_at': w.get('expires_at'),
        'signature': approval.get('signature', ''),
        'repositories': repos,
        'paths': paths,
        'rationale': w.get('rationale'),
    })

summary = {
    'total': len(inventory_waivers),
    'active': sum(1 for w in inventory_waivers if w.get('status') == 'active'),
    'revoked': sum(1 for w in inventory_waivers if w.get('status') == 'revoked'),
    'expired_status': sum(1 for w in inventory_waivers if w.get('status') == 'expired'),
    'invalid_signature': sum(1 for w in inventory_waivers if not sig_re.match(str(w.get('signature') or ''))),
}

out_json = {
    'generated_at': now_utc,
    'registry': registry_file,
    'summary': summary,
    'waivers': inventory_waivers,
}

with open(output_json, 'w', encoding='utf-8') as f:
    json.dump(out_json, f, indent=2)
    f.write('\n')

lines = []
lines.append('# Waiver Inventory')
lines.append('')
lines.append(f'Generated: {now_utc}')
lines.append(f'Registry: {registry_file}')
lines.append('')
lines.append('## Summary')
lines.append('')
lines.append('| Metric | Value |')
lines.append('|---|---:|')
lines.append(f"| total | {summary['total']} |")
lines.append(f"| active | {summary['active']} |")
lines.append(f"| revoked | {summary['revoked']} |")
lines.append(f"| expired_status | {summary['expired_status']} |")
lines.append(f"| invalid_signature | {summary['invalid_signature']} |")
lines.append('')
lines.append('## Entries')
lines.append('')
lines.append('| ID | Status | Owner | Approver | Expires | Issue | Policy | Repos |')
lines.append('|---|---|---|---|---|---:|---|---:|')

if not inventory_waivers:
    lines.append('| none | none | none | none | none | 0 | none | 0 |')
else:
    for w in inventory_waivers:
        lines.append(
            f"| {w.get('id') or ''} | {w.get('status') or ''} | {w.get('owner') or ''} | {w.get('approver') or ''} | {w.get('expires_at') or ''} | {w.get('issue_number') or 0} | {w.get('policy_id') or ''} | {len(w.get('repositories') or [])} |"
        )

with open(output_md, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
EOF

log_info "Generated waiver inventory JSON: $OUTPUT_JSON"
log_info "Generated waiver inventory Markdown: $OUTPUT_MD"
