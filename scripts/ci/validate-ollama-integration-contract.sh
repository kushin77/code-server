#!/usr/bin/env bash
# @file        scripts/ci/validate-ollama-integration-contract.sh
# @module      ci/ai
# @description Validate the Ollama integration contract and release handshake.
#
# Usage: bash scripts/ci/validate-ollama-integration-contract.sh

set -euo pipefail

CONTRACT_FILE="${CONTRACT_FILE:-config/ollama-integration-contract.yml}"

require_line() {
  local pattern="$1"
  local description="$2"

  if grep -qF "$pattern" "$CONTRACT_FILE"; then
    echo "[ollama-contract] OK: $description"
  else
    echo "[ollama-contract] FATAL: missing $description" >&2
    exit 1
  fi
}

echo "[ollama-contract] validating $CONTRACT_FILE"

require_line 'version: "1"' 'contract version'
require_line 'contract_id: "code-server-ollama-v1"' 'contract identifier'
require_line 'host: "192.168.168.42"' 'primary GPU endpoint'
require_line 'host: "192.168.168.31"' 'fallback CPU endpoint'
require_line 'strategy: "health-primary-fallback"' 'routing strategy'
require_line 'health_check_path: "/api/version"' 'health check path'
require_line 'default:' 'default compatibility matrix entry'
require_line 'name: "codellama:7b"' 'default model'
require_line 'optional:' 'optional compatibility matrix entries'
require_line 'name: "llama3"' 'GPU-only model entry'
require_line 'name: "mistral"' 'fallback-capable model entry'
require_line 'require_model_promotion_gate: true' 'upgrade gate'
require_line 'release_handshake:' 'release handshake block'
require_line 'version_bump_required: true' 'version bump requirement'
require_line 'contract_validation_required: true' 'contract validation requirement'
require_line 'matrix_verification_required: true' 'matrix verification requirement'
require_line 'production_approval_required: true' 'production approval requirement'
require_line 'gpu_memory_pressure_percent: 85' 'capacity guardrail'
require_line 'traffic_percentages: [10, 50, 100]' 'canary rollout percentages'
require_line 'mode: "secretsless"' 'secretsless auth mode'

echo "[ollama-contract] contract validation passed"