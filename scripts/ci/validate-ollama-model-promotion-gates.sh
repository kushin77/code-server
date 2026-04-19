#!/usr/bin/env bash
# @file        scripts/ci/validate-ollama-model-promotion-gates.sh
# @module      ci/ai
# @description Validate the Ollama model promotion gates contract and policy evidence format.
#
# Usage: bash scripts/ci/validate-ollama-model-promotion-gates.sh

set -euo pipefail

GATES_FILE="${GATES_FILE:-config/ollama-model-promotion-gates.yml}"
POLICY_FILE="${POLICY_FILE:-docs/AI-MODEL-PROMOTION-GATES-630.md}"

require_line() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"

  if grep -qF -- "$pattern" "$file_path"; then
    echo "[ollama-model-promotion-gates] OK: $description"
  else
    echo "[ollama-model-promotion-gates] FATAL: missing $description in $file_path" >&2
    exit 1
  fi
}

echo "[ollama-model-promotion-gates] validating $GATES_FILE"
require_line "$GATES_FILE" 'version: "1"' 'contract version'
require_line "$GATES_FILE" 'stages:' 'lifecycle stages block'
require_line "$GATES_FILE" '- candidate' 'candidate stage'
require_line "$GATES_FILE" '- canary' 'canary stage'
require_line "$GATES_FILE" '- default' 'default stage'
require_line "$GATES_FILE" 'required_metrics:' 'required metrics block'
require_line "$GATES_FILE" 'accuracy_score' 'accuracy metric'
require_line "$GATES_FILE" 'safety_score' 'safety metric'
require_line "$GATES_FILE" 'latency_ms' 'latency metric'
require_line "$GATES_FILE" 'token_cost_estimate' 'token cost metric'
require_line "$GATES_FILE" 'canary:' 'canary rollout block'
require_line "$GATES_FILE" 'percentage: 10' 'canary percentage'
require_line "$GATES_FILE" 'duration_hours: 24' 'canary duration'
require_line "$GATES_FILE" 'rollback_thresholds:' 'rollback thresholds block'
require_line "$GATES_FILE" 'error_rate_percent: 5' 'rollback error rate threshold'
require_line "$GATES_FILE" 'latency_regression_percent: 20' 'rollback latency threshold'
require_line "$GATES_FILE" 'safety_incidents: 1' 'rollback safety threshold'
require_line "$GATES_FILE" 'promotion:' 'promotion approval block'
require_line "$GATES_FILE" 'require_human_approval: true' 'human approval requirement'
require_line "$GATES_FILE" 'approvers:' 'approver list'
require_line "$GATES_FILE" '- platform' 'platform approver'
require_line "$GATES_FILE" 'require_artifacts:' 'artifact requirements'
require_line "$GATES_FILE" 'evaluation_report.json' 'evaluation report artifact'
require_line "$GATES_FILE" 'canary_results.json' 'canary results artifact'
require_line "$GATES_FILE" 'rollback:' 'rollback block'
require_line "$GATES_FILE" 'command: "git revert"' 'rollback command'
require_line "$GATES_FILE" 'restore_previous_default: true' 'previous default restore'

echo "[ollama-model-promotion-gates] validating $POLICY_FILE"
require_line "$POLICY_FILE" 'Canary Evidence Format' 'canary evidence format section'
require_line "$POLICY_FILE" 'Postmortem Loop' 'postmortem loop section'
require_line "$POLICY_FILE" 'CI Enforcement' 'ci enforcement section'
require_line "$POLICY_FILE" 'scripts/ci/validate-ollama-model-promotion-gates.sh' 'validator reference'
require_line "$POLICY_FILE" 'evaluation_report.json' 'evaluation report evidence'
require_line "$POLICY_FILE" 'canary_results.json' 'canary results evidence'
require_line "$POLICY_FILE" 'promotion_decision.md' 'decision evidence'

echo "[ollama-model-promotion-gates] contract validation passed"