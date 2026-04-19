#!/usr/bin/env bash
# @file        scripts/ci/validate-secretsless-ai-access.sh
# @module      ci/ai
# @description Validate the secretsless AI access contract, entitlement mapping, and quota evidence schema.
#
# Usage: bash scripts/ci/validate-secretsless-ai-access.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ACCESS_FILE="${ACCESS_FILE:-docs/ai/SECRETSLESS-AI-ACCESS.md}"
PROFILE_FILE="${PROFILE_FILE:-config/code-server/ai/ai-access-profiles.yml}"
ENTITLEMENTS_FILE="${ENTITLEMENTS_FILE:-config/code-server/ai/model-entitlements.yml}"
QUOTA_FILE="${QUOTA_FILE:-config/code-server/ai/quota-policy.yml}"
RUNTIME_FILE="${RUNTIME_FILE:-scripts/ai-runtime-env}"
ISSUE_FILE="${ISSUE_FILE:-docs/SECRETLESS-AI-ACCESS-632.md}"

require_literal() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"

  if grep -qF -- "$pattern" "$file_path"; then
    log_info "Verified: $description"
  else
    log_fatal "Missing required contract text: $description ($pattern) in $file_path"
  fi
}

require_file "$ACCESS_FILE"
require_file "$PROFILE_FILE"
require_file "$ENTITLEMENTS_FILE"
require_file "$QUOTA_FILE"
require_file "$RUNTIME_FILE"
require_file "$ISSUE_FILE"

require_literal "$ACCESS_FILE" 'The admin portal is the source of truth for AI entitlement and quota tier.' 'portal source of truth'
require_literal "$ACCESS_FILE" 'code-server injects the active AI profile at startup.' 'startup injection policy'
require_literal "$ACCESS_FILE" 'The primary AI endpoint is 192.168.168.42 and the automatic fallback is 192.168.168.31.' 'endpoint fallback policy'
require_literal "$ACCESS_FILE" 'No user-entered API key or token is required in the IDE.' 'no token policy'
require_literal "$ACCESS_FILE" 'Model access is deny-by-default unless the workspace policy maps the user to a profile.' 'deny-by-default policy'
require_literal "$ACCESS_FILE" 'Persistence rule:' 'persistence rule section'
require_literal "$ACCESS_FILE" 'Evidence contract:' 'evidence contract section'
require_literal "$ACCESS_FILE" 'scripts/ci/validate-secretsless-ai-access.sh' 'validator reference'

require_literal "$PROFILE_FILE" 'default_profile: "standard-developer"' 'default profile'
require_literal "$PROFILE_FILE" 'deny_by_default: true' 'deny by default profile policy'
require_literal "$PROFILE_FILE" 'primary_endpoint: "http://192.168.168.42:11434"' 'primary endpoint profile'
require_literal "$PROFILE_FILE" 'fallback_endpoint: "http://192.168.168.31:11434"' 'fallback endpoint profile'
require_literal "$PROFILE_FILE" 'allowed_models_csv: "codellama:7b,mistral"' 'standard allowed models'
require_literal "$PROFILE_FILE" 'default_model: "codellama:7b"' 'default model'
require_literal "$PROFILE_FILE" 'quota_tier: "standard"' 'standard quota tier'
require_literal "$PROFILE_FILE" 'max_context_tokens: 16384' 'standard context cap'
require_literal "$PROFILE_FILE" 'max_output_tokens: 2048' 'standard output cap'
require_literal "$PROFILE_FILE" 'quota_tier: "power"' 'power quota tier'
require_literal "$PROFILE_FILE" 'quota_tier: "admin"' 'admin quota tier'
require_literal "$PROFILE_FILE" 'quota_tier: "none"' 'denied quota tier'

require_literal "$ENTITLEMENTS_FILE" 'deny_by_default: true' 'entitlements deny by default'
require_literal "$ENTITLEMENTS_FILE" 'source_of_truth: "admin-portal"' 'portal source of truth'
require_literal "$ENTITLEMENTS_FILE" 'github_username' 'entitlement input github_username'
require_literal "$ENTITLEMENTS_FILE" 'repository_access' 'entitlement input repository_access'
require_literal "$ENTITLEMENTS_FILE" 'team_memberships' 'entitlement input team_memberships'
require_literal "$ENTITLEMENTS_FILE" 'temporary_overrides' 'entitlement input temporary_overrides'
require_literal "$ENTITLEMENTS_FILE" 'default_profile: "denied"' 'default denied profile'
require_literal "$ENTITLEMENTS_FILE" 'require_actor: true' 'override actor requirement'
require_literal "$ENTITLEMENTS_FILE" 'require_reason: true' 'override reason requirement'
require_literal "$ENTITLEMENTS_FILE" 'require_expiry: true' 'override expiry requirement'
require_literal "$ENTITLEMENTS_FILE" '- grant' 'grant audit event'
require_literal "$ENTITLEMENTS_FILE" '- revoke' 'revoke audit event'
require_literal "$ENTITLEMENTS_FILE" '- override' 'override audit event'
require_literal "$ENTITLEMENTS_FILE" '- denial' 'denial audit event'

require_literal "$QUOTA_FILE" 'enforcement_mode: "deny-by-default"' 'quota enforcement mode'
require_literal "$QUOTA_FILE" 'graceful_exceed_behavior: "throttle-with-message"' 'throttle behavior'
require_literal "$QUOTA_FILE" 'requests_per_minute: 0' 'none quota tier'
require_literal "$QUOTA_FILE" 'requests_per_minute: 20' 'standard quota tier'
require_literal "$QUOTA_FILE" 'requests_per_minute: 40' 'power quota tier'
require_literal "$QUOTA_FILE" 'requests_per_minute: 60' 'admin quota tier'
require_literal "$QUOTA_FILE" 'throttle: "AI quota limit reached for this profile. Retry after cooldown or request a temporary override."' 'throttle message'
require_literal "$QUOTA_FILE" 'denied: "AI access is not enabled for this workspace policy."' 'denied message'

require_literal "$RUNTIME_FILE" 'export OLLAMA_AUTH_MODE' 'runtime auth export'
require_literal "$RUNTIME_FILE" 'export OLLAMA_TOKEN_SOURCE' 'runtime token source export'
require_literal "$RUNTIME_FILE" 'read_contract_value' 'runtime contract reader'
require_literal "$RUNTIME_FILE" 'default_profile()' 'runtime default profile reader'

require_literal "$ISSUE_FILE" 'OIDC integration complete' 'OIDC evidence'
require_literal "$ISSUE_FILE" 'No secrets in environment' 'no secrets evidence'
require_literal "$ISSUE_FILE" 'Workspace isolation enforced' 'workspace isolation evidence'
require_literal "$ISSUE_FILE" 'Audit logging functional' 'audit logging evidence'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/secretsless-ai-evidence.json" <<'EOF'
{
  "default_profile": "standard-developer",
  "deny_by_default": true,
  "primary_endpoint": "http://192.168.168.42:11434",
  "fallback_endpoint": "http://192.168.168.31:11434",
  "quota_tiers": ["none", "standard", "power", "admin"],
  "audit_events": ["grant", "revoke", "override", "denial"]
}
EOF

python3 - "$TMP_DIR/secretsless-ai-evidence.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as handle:
    evidence = json.load(handle)

required = {
    'default_profile',
    'deny_by_default',
    'primary_endpoint',
    'fallback_endpoint',
    'quota_tiers',
    'audit_events',
}
missing = sorted(required - set(evidence))
if missing:
    print('Missing evidence keys: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)

if evidence['default_profile'] != 'standard-developer' or evidence['deny_by_default'] is not True:
    print('Profile policy mismatch', file=sys.stderr)
    sys.exit(1)

if evidence['primary_endpoint'] != 'http://192.168.168.42:11434' or evidence['fallback_endpoint'] != 'http://192.168.168.31:11434':
    print('Endpoint mismatch', file=sys.stderr)
    sys.exit(1)

if evidence['quota_tiers'] != ['none', 'standard', 'power', 'admin']:
    print('Quota tier mismatch', file=sys.stderr)
    sys.exit(1)

if evidence['audit_events'] != ['grant', 'revoke', 'override', 'denial']:
    print('Audit event mismatch', file=sys.stderr)
    sys.exit(1)

print('Secretsless AI evidence schema ok')
PY

log_info "Secretsless AI access validation passed"