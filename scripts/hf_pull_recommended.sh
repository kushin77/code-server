#!/usr/bin/env bash
# hf_pull_recommended.sh — Pull all models defined in config/recommended-models.yaml
#
# Usage:
#   HF_TOKEN=hf_xxx ./scripts/hf_pull_recommended.sh [category]
#
# Arguments:
#   category  (optional) Filter by model category: coding | fast | embedding | vision
#              Default: pull ALL models in the file.
#
# Environment variables:
#   HF_TOKEN        — HuggingFace API token
#   OLLAMA_BASE_URL — Ollama base URL (default: http://localhost:11434)
#   CONFIG_FILE     — Path to recommended-models.yaml (default: config/recommended-models.yaml)
#   SKIP_VRAM_CHECK — Set to "1" to skip VRAM gating (useful in CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${REPO_ROOT}/config/recommended-models.yaml}"
CATEGORY_FILTER="${1:-}"
HF_TOKEN="${HF_TOKEN:-}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
SKIP_VRAM_CHECK="${SKIP_VRAM_CHECK:-0}"

# ── Dependency checks ─────────────────────────────────────────────────────────
for dep in curl yq ollama; do
    if ! command -v "$dep" &>/dev/null; then
        echo "ERROR: '$dep' not found. Install it before running this script." >&2
        exit 1
    fi
done

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}" >&2
    exit 1
fi

# ── VRAM detection (Linux only, best-effort) ──────────────────────────────────
AVAILABLE_VRAM_GB=999
if [[ "$SKIP_VRAM_CHECK" == "0" ]] && command -v nvidia-smi &>/dev/null; then
    AVAILABLE_VRAM_GB=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits \
        | awk '{sum+=$1} END {printf "%d", sum/1024}')
    echo "==> Detected free VRAM: ${AVAILABLE_VRAM_GB} GB"
fi

# ── Ollama connectivity ───────────────────────────────────────────────────────
if ! curl -sf "${OLLAMA_BASE_URL}/api/tags" > /dev/null; then
    echo "ERROR: Ollama not reachable at ${OLLAMA_BASE_URL}" >&2
    exit 1
fi

# ── Iterate models ────────────────────────────────────────────────────────────
MODEL_COUNT=$(yq eval '.models | length' "$CONFIG_FILE")
SUCCESS=0
SKIPPED=0
FAILED=0

echo "==> Pulling ${MODEL_COUNT} model(s) from ${CONFIG_FILE}"
[[ -n "$CATEGORY_FILTER" ]] && echo "==> Category filter: ${CATEGORY_FILTER}"

for i in $(seq 0 $((MODEL_COUNT - 1))); do
    NAME=$(yq eval ".models[${i}].name" "$CONFIG_FILE")
    HF_REPO=$(yq eval ".models[${i}].hf_repo" "$CONFIG_FILE")
    HF_FILE=$(yq eval ".models[${i}].hf_file" "$CONFIG_FILE")
    CATEGORY=$(yq eval ".models[${i}].category" "$CONFIG_FILE")
    VRAM_GB=$(yq eval ".models[${i}].vram_gb" "$CONFIG_FILE")
    DESC=$(yq eval ".models[${i}].description" "$CONFIG_FILE")

    # Apply category filter
    if [[ -n "$CATEGORY_FILTER" && "$CATEGORY" != "$CATEGORY_FILTER" ]]; then
        continue
    fi

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  Model    : ${NAME}"
    echo "  Category : ${CATEGORY}"
    echo "  Desc     : ${DESC}"
    echo "  VRAM req : ${VRAM_GB} GB"

    # VRAM gate
    if [[ "$SKIP_VRAM_CHECK" == "0" && "$VRAM_GB" -gt "$AVAILABLE_VRAM_GB" ]]; then
        echo "  [SKIP] Not enough free VRAM (need ${VRAM_GB} GB, have ${AVAILABLE_VRAM_GB} GB)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    export HF_TOKEN OLLAMA_BASE_URL
    if "${SCRIPT_DIR}/hf_pull_model.sh" "$HF_REPO" "$HF_FILE" "$NAME"; then
        SUCCESS=$((SUCCESS + 1))
    else
        echo "  [FAIL] hf_pull_model.sh exited non-zero for ${NAME}"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Pull complete: ${SUCCESS} succeeded, ${SKIPPED} skipped, ${FAILED} failed"
echo "════════════════════════════════════════════════════════"

[[ "$FAILED" -gt 0 ]] && exit 1 || exit 0
