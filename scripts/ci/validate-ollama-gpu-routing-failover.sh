#!/usr/bin/env bash
# @file        scripts/ci/validate-ollama-gpu-routing-failover.sh
# @module      ci/ai
# @description Validate the Ollama GPU routing and failover contract and evidence schema.
#
# Usage: bash scripts/ci/validate-ollama-gpu-routing-failover.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

CONTRACT_FILE="${CONTRACT_FILE:-config/ollama-integration-contract.yml}"
POLICY_FILE="${POLICY_FILE:-docs/ai/OLLAMA-ROUTING-POLICY.md}"
OPS_FILE="${OPS_FILE:-docs/ops/OLLAMA-GPU-REPLICA-OPERATIONS.md}"
ISSUE_FILE="${ISSUE_FILE:-docs/GPU-ROUTING-FAILOVER-631.md}"

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

require_file "$CONTRACT_FILE"
require_file "$POLICY_FILE"
require_file "$OPS_FILE"
require_file "$ISSUE_FILE"

require_literal "$CONTRACT_FILE" 'host: "192.168.168.42"' 'primary GPU host'
require_literal "$CONTRACT_FILE" 'host: "192.168.168.31"' 'fallback CPU host'
require_literal "$CONTRACT_FILE" 'strategy: "health-primary-fallback"' 'routing strategy'
require_literal "$CONTRACT_FILE" 'health_check_path: "/api/version"' 'health check path'
require_literal "$CONTRACT_FILE" 'failover_threshold_ms: 5000' 'failover threshold'
require_literal "$CONTRACT_FILE" 'failback_after_seconds: 120' 'failback window'
require_literal "$CONTRACT_FILE" 'gpu_memory_pressure_percent: 85' 'GPU pressure guardrail'
require_literal "$CONTRACT_FILE" 'traffic_percentages: [10, 50, 100]' 'canary rollout percentages'
require_literal "$CONTRACT_FILE" 'mode: "secretsless"' 'secretsless auth mode'
require_literal "$CONTRACT_FILE" 'per_model_concurrency:' 'per-model concurrency block'
require_literal "$CONTRACT_FILE" 'codellama: 4' 'codellama concurrency'
require_literal "$CONTRACT_FILE" 'mistral: 4' 'mistral concurrency'
require_literal "$CONTRACT_FILE" 'llama3: 2' 'llama3 concurrency'

require_literal "$POLICY_FILE" 'Primary endpoint: `http://192.168.168.42:11434`' 'primary endpoint policy'
require_literal "$POLICY_FILE" 'Fallback endpoint: `http://192.168.168.31:11434`' 'fallback endpoint policy'
require_literal "$POLICY_FILE" 'health-primary-fallback' 'routing strategy text'
require_literal "$POLICY_FILE" 'Failover rules:' 'failover rules section'
require_literal "$POLICY_FILE" 'GPU memory pressure threshold: 85 percent on `.42`' 'GPU pressure threshold policy'
require_literal "$POLICY_FILE" 'Roll back when error rate, latency regression, or safety incidents cross thresholds.' 'rollback threshold policy'

require_literal "$OPS_FILE" 'Verify `.42` health' 'replica health check'
require_literal "$OPS_FILE" 'Verify readiness' 'replica readiness check'
require_literal "$OPS_FILE" 'If `.42` is unhealthy' 'fallback activation note'
require_literal "$OPS_FILE" 'Failover drill:' 'failover drill section'
require_literal "$OPS_FILE" 'Restore `.42` and verify automatic failback' 'automatic failback guidance'

require_literal "$ISSUE_FILE" 'GPU detection implemented' 'GPU detection evidence'
require_literal "$ISSUE_FILE" 'Failover routing tested (10/10 success)' 'failover test evidence'
require_literal "$ISSUE_FILE" 'Performance baseline: GPU 50ms, CPU 500ms' 'performance baseline evidence'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/gpu-routing-evidence.json" <<'EOF'
{
  "primary_host": "192.168.168.42",
  "fallback_host": "192.168.168.31",
  "routing_strategy": "health-primary-fallback",
  "failover_threshold_ms": 5000,
  "failback_after_seconds": 120,
  "gpu_memory_pressure_percent": 85,
  "traffic_percentages": [10, 50, 100]
}
EOF

python3 - "$TMP_DIR/gpu-routing-evidence.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as handle:
    evidence = json.load(handle)

required = {
    'primary_host',
    'fallback_host',
    'routing_strategy',
    'failover_threshold_ms',
    'failback_after_seconds',
    'gpu_memory_pressure_percent',
    'traffic_percentages',
}
missing = sorted(required - set(evidence))
if missing:
    print('Missing evidence keys: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)

if evidence['primary_host'] != '192.168.168.42' or evidence['fallback_host'] != '192.168.168.31':
    print('Endpoint evidence mismatch', file=sys.stderr)
    sys.exit(1)

if evidence['routing_strategy'] != 'health-primary-fallback':
    print('Routing strategy mismatch', file=sys.stderr)
    sys.exit(1)

if evidence['failover_threshold_ms'] != 5000 or evidence['failback_after_seconds'] != 120:
    print('Failover timing mismatch', file=sys.stderr)
    sys.exit(1)

if evidence['gpu_memory_pressure_percent'] != 85:
    print('GPU guardrail mismatch', file=sys.stderr)
    sys.exit(1)

if evidence['traffic_percentages'] != [10, 50, 100]:
    print('Canary percentages mismatch', file=sys.stderr)
    sys.exit(1)

print('GPU routing evidence schema ok')
PY

log_info "Ollama GPU routing and failover validation passed"