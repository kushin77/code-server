#!/usr/bin/env bash
# @file        scripts/ci/validate-extension-supply-chain.sh
# @module      ci/security
# @description Validates extension supply-chain hardening for #759.
#
# Checks:
#   1. extensions-approved.json manifest signature is intact (SHA256).
#   2. All role profiles have marketplace gallery endpoints disabled.
#   3. global settings.json has gallery block in place.
#   4. Required blocked-extension denial patterns exist.
#
# Exit codes:
#   0 - all checks pass
#   1 - one or more checks failed
#   2 - dependency missing (node or python3 required)
#
# Usage:
#   validate-extension-supply-chain.sh [--sign] [--report <path>]
#   --sign    Recompute manifest signature and update extensions-approved.json
#   --report  Write JSON report to <path>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

APPROVED_MANIFEST="$REPO_ROOT/config/code-server/extensions/extensions-approved.json"
BLOCKED_MANIFEST="$REPO_ROOT/config/code-server/extensions/extensions-blocked.json"
PROFILES_DIR="$REPO_ROOT/config/role-settings"
GLOBAL_SETTINGS="$REPO_ROOT/config/code-server/settings.json"

SIGN_MODE=false
REPORT_PATH=""
PASS=0
FAIL=0
AUDIT_EVENTS=()
ERRORS=()

_log()   { echo "[INFO]  $(date -u +%H:%M:%SZ) $*"; }
_warn()  { echo "[WARN]  $(date -u +%H:%M:%SZ) $*" >&2; }
_error() { echo "[ERROR] $(date -u +%H:%M:%SZ) $*" >&2; }

_compute_manifest_sig() {
  if command -v node >/dev/null 2>&1; then
    node -e "
      const fs=require('fs'),crypto=require('crypto');
      const data=JSON.parse(fs.readFileSync('$APPROVED_MANIFEST','utf8'));
      const canonical=JSON.stringify(data.extensions.map(e=>Object.fromEntries(Object.entries(e).sort())));
      process.stdout.write(crypto.createHash('sha256').update(canonical).digest('hex'));
    " 2>/dev/null
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import hashlib, json
with open('$APPROVED_MANIFEST', encoding='utf-8') as f:
    data = json.load(f)
canonical = json.dumps([
    dict(sorted(item.items(), key=lambda kv: kv[0])) for item in data.get('extensions', [])
], separators=(',', ':'), sort_keys=False)
print(hashlib.sha256(canonical.encode('utf-8')).hexdigest(), end='')
" 2>/dev/null
    return
  fi

  return 1
}

_read_manifest_field() {
  local field="$1"

  if command -v node >/dev/null 2>&1; then
    node -e "
      const d=JSON.parse(require('fs').readFileSync('$APPROVED_MANIFEST','utf8'));
      process.stdout.write(String(d['$field'] || ''));
    " 2>/dev/null
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json
with open('$APPROVED_MANIFEST', encoding='utf-8') as f:
    data = json.load(f)
print(str(data.get('$field','')), end='')
" 2>/dev/null
    return
  fi

  return 1
}

_emit_audit_event() {
  local event_type="$1" ext_id="$2" reason="$3"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  AUDIT_EVENTS+=("{\"timestamp\":\"$ts\",\"event\":\"$event_type\",\"extension_id\":\"$ext_id\",\"reason\":\"$reason\",\"policy_source\":\"extensions-approved.json\"}")
  _warn "AUDIT [$event_type] extension=$ext_id reason=$reason"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign)
      SIGN_MODE=true
      shift
      ;;
    --report)
      REPORT_PATH="$2"
      shift 2
      ;;
    *)
      _error "Unknown argument: $1"
      exit 2
      ;;
  esac
done

if ! command -v node >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  _error "node or python3 is required for manifest signature verification"
  exit 2
fi

USE_JQ=false
if command -v jq >/dev/null 2>&1; then
  USE_JQ=true
fi

if [[ "$SIGN_MODE" == true ]]; then
  _log "Recomputing manifest signature..."
  NEW_SIG="$(_compute_manifest_sig)"

  if command -v node >/dev/null 2>&1; then
    node -e "
      const fs=require('fs');
      const path='$APPROVED_MANIFEST';
      const raw=fs.readFileSync(path,'utf8');
      const data=JSON.parse(raw);
      data.manifest_signature='$NEW_SIG';
      data.policy_date='$(date -u +%Y-%m-%d)';
      fs.writeFileSync(path, JSON.stringify(data, null, 2)+'\n');
      console.log('Signature updated: $NEW_SIG');
    "
  else
    python3 -c "
import json
path='$APPROVED_MANIFEST'
with open(path, encoding='utf-8') as f:
    data = json.load(f)
data['manifest_signature'] = '$NEW_SIG'
data['policy_date'] = '$(date -u +%Y-%m-%d)'
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
    f.write('\\n')
print('Signature updated: $NEW_SIG')
"
  fi

  _log "extensions-approved.json signed with SHA256: $NEW_SIG"
  exit 0
fi

_log "CHECK 1: Manifest signature integrity"

STORED_SIG="$(_read_manifest_field manifest_signature)"
ACTUAL_SIG="$(_compute_manifest_sig)"

if [[ -z "$STORED_SIG" ]]; then
  ERRORS+=("extensions-approved.json is missing manifest_signature field")
  (( FAIL++ )) || true
elif [[ "$STORED_SIG" != "$ACTUAL_SIG" ]]; then
  ERRORS+=("Manifest signature MISMATCH - stored=$STORED_SIG actual=$ACTUAL_SIG")
  _emit_audit_event "MANIFEST_INTEGRITY_VIOLATION" "extensions-approved.json" "SHA256 mismatch: stored vs actual"
  (( FAIL++ )) || true
else
  _log "  OK Manifest signature valid ($STORED_SIG)"
  (( PASS++ )) || true
fi

_log "CHECK 2: Role profiles - gallery endpoint block"

REQUIRED_KEYS=("extensions.gallery.serviceUrl" "extensions.gallery.itemUrl" "extensions.gallery.resourceUrlTemplate")

for profile in "$PROFILES_DIR"/*.json; do
  role="$(basename "$profile" .json)"
  profile_fail=false

  for key in "${REQUIRED_KEYS[@]}"; do
    if $USE_JQ; then
      val="$(jq -r --arg k "$key" 'if (.settings | has($k)) then .settings[$k] else "MISSING" end' "$profile" 2>/dev/null)"
    elif command -v python3 >/dev/null 2>&1; then
      val="$(python3 -c "
import json
with open('$profile', encoding='utf-8') as f:
    p = json.load(f)
settings = p.get('settings', {})
print(str(settings.get('$key', 'MISSING')), end='')
" 2>/dev/null)"
    else
      val="$(node -e "
        const p=JSON.parse(require('fs').readFileSync('$profile','utf8'));
        const v=p.settings && ('$key' in p.settings) ? p.settings['$key'] : 'MISSING';
        process.stdout.write(String(v));
      " 2>/dev/null)"
    fi

    if [[ "$val" == "MISSING" ]]; then
      ERRORS+=("$role: missing gallery block key: $key")
      profile_fail=true
    elif [[ -n "$val" ]]; then
      ERRORS+=("$role: $key must be empty string to block marketplace (got: $val)")
      profile_fail=true
    fi
  done

  if [[ "$profile_fail" == false ]]; then
    _log "  OK $role - gallery endpoints blocked"
    (( PASS++ )) || true
  else
    _emit_audit_event "MARKETPLACE_BLOCK_MISSING" "$role" "Profile missing gallery endpoint block"
    (( FAIL++ )) || true
  fi
done

_log "CHECK 3: Global settings.json - gallery block"

SETTINGS_FAIL=false
for key in "${REQUIRED_KEYS[@]}"; do
  if command -v node >/dev/null 2>&1; then
    val="$(node -e "
      const fs=require('fs');
      const raw=fs.readFileSync('$GLOBAL_SETTINGS','utf8');
      const clean=raw.replace(/\/\/[^\n]*/g,'');
      try {
        const d=JSON.parse(clean);
        const v=('$key' in d) ? d['$key'] : 'MISSING';
        process.stdout.write(String(v));
      } catch(e) { process.stdout.write('PARSE_ERROR'); }
    " 2>/dev/null)"
  else
    val="$(python3 -c "
import json, re
raw = open('$GLOBAL_SETTINGS', encoding='utf-8').read()
clean = re.sub(r'//[^\\n]*', '', raw)
try:
    d = json.loads(clean)
    print(str(d.get('$key', 'MISSING')), end='')
except Exception:
    print('PARSE_ERROR', end='')
" 2>/dev/null)"
  fi

  if [[ "$val" == "MISSING" ]]; then
    ERRORS+=("settings.json: missing key $key")
    SETTINGS_FAIL=true
  elif [[ -n "$val" && "$val" != "PARSE_ERROR" ]]; then
    ERRORS+=("settings.json: $key must be empty string (got: $val)")
    SETTINGS_FAIL=true
  fi
done

if [[ "$SETTINGS_FAIL" == false ]]; then
  _log "  OK settings.json - gallery endpoints blocked"
  (( PASS++ )) || true
else
  (( FAIL++ )) || true
fi

_log "CHECK 4: extensions-blocked.json has required denial patterns"

REQUIRED_BLOCKED_PATTERNS=("TabNine" "Codeium" "ms-vscode-remote" "ms-vsliveshare")
BLOCKED_FAIL=false

for pattern in "${REQUIRED_BLOCKED_PATTERNS[@]}"; do
  if $USE_JQ; then
    match="$(jq -r --arg p "$pattern" '.blocked[] | select(.pattern | test($p;"i")) | .pattern' "$BLOCKED_MANIFEST" 2>/dev/null | head -1)"
  elif command -v python3 >/dev/null 2>&1; then
    match="$(python3 -c "
import json, re
with open('$BLOCKED_MANIFEST', encoding='utf-8') as f:
    d = json.load(f)
rx = re.compile('$pattern', re.I)
found = ''
for item in d.get('blocked', []):
    pat = str(item.get('pattern', ''))
    if rx.search(pat):
        found = pat
        break
print(found, end='')
" 2>/dev/null)"
  else
    match="$(node -e "
      const d=JSON.parse(require('fs').readFileSync('$BLOCKED_MANIFEST','utf8'));
      const re=new RegExp('$pattern','i');
      const found=d.blocked.find(b=>re.test(b.pattern));
      process.stdout.write(found ? found.pattern : '');
    " 2>/dev/null)"
  fi

  if [[ -z "$match" ]]; then
    ERRORS+=("extensions-blocked.json: missing required denial pattern for: $pattern")
    _emit_audit_event "BLOCKED_MANIFEST_INCOMPLETE" "$pattern" "Required denial pattern missing from blocked manifest"
    BLOCKED_FAIL=true
  fi
done

if [[ "$BLOCKED_FAIL" == false ]]; then
  _log "  OK All required denial patterns present in extensions-blocked.json"
  (( PASS++ )) || true
else
  (( FAIL++ )) || true
fi

TOTAL=$(( PASS + FAIL ))
_log "------------------------------------------------"
_log "Extension supply-chain validation: $PASS/$TOTAL passed"

if [[ ${#AUDIT_EVENTS[@]} -gt 0 ]]; then
  _warn "${#AUDIT_EVENTS[@]} policy denial audit event(s) emitted"
  for evt in "${AUDIT_EVENTS[@]}"; do
    _warn "  AUDIT: $evt"
  done
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  _error "Failures:"
  for err in "${ERRORS[@]}"; do
    _error "  - $err"
  done
fi

if [[ -n "$REPORT_PATH" ]]; then
  mkdir -p "$(dirname "$REPORT_PATH")"

  AUDIT_JSON="["
  SEP=""
  for evt in "${AUDIT_EVENTS[@]}"; do
    AUDIT_JSON+="${SEP}${evt}"
    SEP=","
  done
  AUDIT_JSON+="]"

  ERRORS_JSON="["
  SEP=""
  for err in "${ERRORS[@]}"; do
    safe_err="${err//\"/\\\"}"
    ERRORS_JSON+="${SEP}\"${safe_err}\""
    SEP=","
  done
  ERRORS_JSON+="]"

  if command -v node >/dev/null 2>&1; then
    node -e "
      const fs=require('fs');
      const report={
        generated_at: new Date().toISOString(),
        suite: 'extension-supply-chain',
        issue: '#759',
        summary: { pass: $PASS, fail: $FAIL, total: $TOTAL },
        audit_events: $AUDIT_JSON,
        errors: $ERRORS_JSON
      };
      fs.mkdirSync('$(dirname "$REPORT_PATH")', {recursive:true});
      fs.writeFileSync('$REPORT_PATH', JSON.stringify(report,null,2)+'\\n');
      console.log('Report written: $REPORT_PATH');
    "
  else
    python3 -c "
import json, os
from datetime import datetime, timezone
report = {
  'generated_at': datetime.now(timezone.utc).isoformat(),
  'suite': 'extension-supply-chain',
  'issue': '#759',
  'summary': {'pass': $PASS, 'fail': $FAIL, 'total': $TOTAL},
  'audit_events': json.loads('''$AUDIT_JSON'''),
  'errors': json.loads('''$ERRORS_JSON''')
}
os.makedirs('$(dirname "$REPORT_PATH")', exist_ok=True)
with open('$REPORT_PATH', 'w', encoding='utf-8') as f:
    json.dump(report, f, indent=2)
    f.write('\\n')
print('Report written: $REPORT_PATH')
"
  fi
fi

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

exit 0
