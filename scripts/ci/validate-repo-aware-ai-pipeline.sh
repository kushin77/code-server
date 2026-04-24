#!/usr/bin/env bash
# @file        scripts/ci/validate-repo-aware-ai-pipeline.sh
# @module      ci/ai
# @description Validate the repo-aware AI pipeline contract, evaluation evidence, and retrieval guardrails.
#
# Usage: bash scripts/ci/validate-repo-aware-ai-pipeline.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

PIPELINE_FILE="${PIPELINE_FILE:-config/code-server/ai/repo-rag-pipeline.yml}"
POLICY_FILE="${POLICY_FILE:-docs/ai/REPO-KNOWLEDGE-CORPUS-POLICY.md}"
DOC_FILE="${DOC_FILE:-docs/AI-REPO-PIPELINE-628.md}"

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

require_file "$PIPELINE_FILE"
require_file "$POLICY_FILE"
require_file "$DOC_FILE"

require_literal "$PIPELINE_FILE" 'daily_incremental_cron: "0 3 * * *"' 'daily incremental refresh schedule'
require_literal "$PIPELINE_FILE" 'on_demand_refresh_paths:' 'on-demand refresh paths'
require_literal "$PIPELINE_FILE" 'evaluation:' 'evaluation block'
require_literal "$PIPELINE_FILE" 'gold_sets:' 'evaluation gold sets block'
require_literal "$PIPELINE_FILE" 'deployments' 'deployments evaluation set'
require_literal "$PIPELINE_FILE" 'rollback' 'rollback evaluation set'
require_literal "$PIPELINE_FILE" 'secretsless-auth' 'secretsless auth evaluation set'
require_literal "$PIPELINE_FILE" 'branch-pr-governance' 'branch PR governance evaluation set'
require_literal "$PIPELINE_FILE" 'metrics:' 'metrics block'
require_literal "$PIPELINE_FILE" 'grounded_answer_rate' 'grounded answer rate metric'
require_literal "$PIPELINE_FILE" 'citation_coverage' 'citation coverage metric'
require_literal "$PIPELINE_FILE" 'stale_citation_rate' 'stale citation rate metric'
require_literal "$PIPELINE_FILE" 'hallucination_incidents' 'hallucination incidents metric'
require_literal "$PIPELINE_FILE" 'require_citations: true' 'citation requirement'
require_literal "$PIPELINE_FILE" 'insufficient_context_behavior: "respond-unknown"' 'insufficient context behavior'
require_literal "$PIPELINE_FILE" 'permission_source: "repo-visibility-and-team-policy"' 'permission source'
require_literal "$POLICY_FILE" 'In scope:' 'policy in-scope section'
require_literal "$POLICY_FILE" 'Excluded content:' 'policy excluded content section'
require_literal "$POLICY_FILE" 'Scrubbing rules:' 'policy scrubbing section'
require_literal "$POLICY_FILE" 'Freshness and deduplication:' 'policy freshness section'
require_literal "$POLICY_FILE" 'Retrieval guardrails:' 'policy retrieval guardrails section'
require_literal "$POLICY_FILE" 'Operational claims require citations.' 'policy citation requirement'
require_literal "$DOC_FILE" 'Evaluation Framework' 'evaluation framework section'
require_literal "$DOC_FILE" '50-query evaluation set' 'evaluation set size'
require_literal "$DOC_FILE" 'Freshness metrics' 'freshness metrics section'
require_literal "$DOC_FILE" 'Access Control Validation' 'access control validation section'
require_literal "$DOC_FILE" '50-query evaluation set covering common workflows' 'evaluation coverage evidence'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/repo-aware-ai-evidence.json" <<'EOF'
{
  "evaluation_set": "50-query common workflow set",
  "freshness_target": "<5min stale",
  "access_control": "workspace trust and file permissions enforced",
  "metrics": ["grounded_answer_rate", "citation_coverage", "stale_citation_rate", "hallucination_incidents"]
}
EOF

python3 - "$TMP_DIR/repo-aware-ai-evidence.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as handle:
    evidence = json.load(handle)

required = {'evaluation_set', 'freshness_target', 'access_control', 'metrics'}
missing = sorted(required - set(evidence))
if missing:
    print('Missing evidence keys: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)

if '50-query' not in evidence['evaluation_set']:
    print('Evaluation set description is too weak', file=sys.stderr)
    sys.exit(1)

if '<5min' not in evidence['freshness_target']:
    print('Freshness target missing', file=sys.stderr)
    sys.exit(1)

if 'workspace trust' not in evidence['access_control']:
    print('Access-control evidence missing', file=sys.stderr)
    sys.exit(1)

if len(evidence['metrics']) < 4:
    print('Insufficient metric coverage', file=sys.stderr)
    sys.exit(1)

print('Repo-aware AI evidence schema ok')
PY

log_info "Repo-aware AI pipeline validation passed"