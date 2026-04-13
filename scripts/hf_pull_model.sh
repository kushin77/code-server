#!/usr/bin/env bash
# hf_pull_model.sh — Pull a GGUF model from HuggingFace and register it in Ollama
#
# Usage:
#   ./scripts/hf_pull_model.sh <hf_repo> <hf_file> <ollama_name>
#
# Environment variables:
#   HF_TOKEN        — HuggingFace API token (required for gated models)
#   OLLAMA_BASE_URL — Ollama API base URL (default: http://localhost:11434)
#
# Example:
#   HF_TOKEN=hf_xxx ./scripts/hf_pull_model.sh \
#     Qwen/Qwen2.5-Coder-32B-Instruct-GGUF \
#     qwen2.5-coder-32b-instruct-q4_k_m.gguf \
#     qwen2.5-coder:32b-instruct-q4_K_M

set -euo pipefail

HF_REPO="${1:?Usage: $0 <hf_repo> <hf_file> <ollama_name>}"
HF_FILE="${2:?Usage: $0 <hf_repo> <hf_file> <ollama_name>}"
OLLAMA_NAME="${3:?Usage: $0 <hf_repo> <hf_file> <ollama_name>}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
CACHE_DIR="${HF_CACHE_DIR:-/tmp/hf-model-cache}"
HF_TOKEN="${HF_TOKEN:-}"

HF_BASE="https://huggingface.co"
DOWNLOAD_URL="${HF_BASE}/${HF_REPO}/resolve/main/${HF_FILE}"
LOCAL_PATH="${CACHE_DIR}/${HF_REPO//\//__}__${HF_FILE}"

mkdir -p "$CACHE_DIR"

echo "==> Model   : ${OLLAMA_NAME}"
echo "==> HF repo : ${HF_REPO}"
echo "==> HF file : ${HF_FILE}"
echo "==> Ollama  : ${OLLAMA_BASE_URL}"

# ── Download with resume support ─────────────────────────────────────────────
if [[ -f "$LOCAL_PATH" ]]; then
    echo "==> Found cached GGUF at ${LOCAL_PATH}"
else
    echo "==> Downloading from HuggingFace…"
    CURL_ARGS=(-L --progress-bar --continue-at - -o "$LOCAL_PATH" "$DOWNLOAD_URL")
    if [[ -n "$HF_TOKEN" ]]; then
        CURL_ARGS+=(-H "Authorization: Bearer ${HF_TOKEN}")
    fi
    curl "${CURL_ARGS[@]}"
fi

# ── Check Ollama is up ────────────────────────────────────────────────────────
if ! curl -sf "${OLLAMA_BASE_URL}/api/tags" > /dev/null; then
    echo "ERROR: Ollama not reachable at ${OLLAMA_BASE_URL}" >&2
    exit 1
fi

# ── Already registered? ───────────────────────────────────────────────────────
EXISTING=$(curl -sf "${OLLAMA_BASE_URL}/api/tags" | grep -c "\"${OLLAMA_NAME}\"" || true)
if [[ "$EXISTING" -gt "0" ]]; then
    echo "==> ${OLLAMA_NAME} already registered in Ollama — skipping import."
    exit 0
fi

# ── Build transient Modelfile and create model ────────────────────────────────
MODELFILE_PATH="$(mktemp --suffix=.Modelfile)"
trap 'rm -f "$MODELFILE_PATH"' EXIT

cat > "$MODELFILE_PATH" <<EOF
FROM ${LOCAL_PATH}
PARAMETER num_ctx 32768
PARAMETER stop "<|im_end|>"
PARAMETER stop "<|endoftext|>"
EOF

echo "==> Registering with Ollama using: ollama create ${OLLAMA_NAME}"
ollama create "${OLLAMA_NAME}" -f "${MODELFILE_PATH}"
echo "==> Done: ${OLLAMA_NAME} is ready."
