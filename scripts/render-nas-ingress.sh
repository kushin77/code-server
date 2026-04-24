#!/usr/bin/env bash
# @file        scripts/render-nas-ingress.sh
# @module      k8s/ingress
# @description Render and optionally apply the NAS ingress manifest using a DNS-based backend host.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

TEMPLATE_FILE="${TEMPLATE_FILE:-$SCRIPT_DIR/nas-ingress.yaml}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
APPLY="${APPLY:-false}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"
IDE_WINDOWS_BACKEND_HOST="${IDE_WINDOWS_BACKEND_HOST:-}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/render-nas-ingress.sh [--output <file>] [--apply] [--context <kubectl-context>]

Environment:
  IDE_WINDOWS_BACKEND_HOST   DNS name for the Windows-backed IDE target (required)
  TEMPLATE_FILE              Ingress template to render (default: scripts/nas-ingress.yaml)
  OUTPUT_FILE                Optional rendered output file path
  APPLY                      When true, apply the rendered manifest with kubectl
  KUBECTL_CONTEXT            Optional kubectl context when applying
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY="true"
      shift
      ;;
    --context)
      KUBECTL_CONTEXT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_fatal "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$IDE_WINDOWS_BACKEND_HOST" ]]; then
  log_fatal "IDE_WINDOWS_BACKEND_HOST is required"
fi

require_file "$TEMPLATE_FILE"
require_command python3

render_template() {
  python3 - "$TEMPLATE_FILE" "$IDE_WINDOWS_BACKEND_HOST" <<'PY'
from pathlib import Path
import sys

template_path = Path(sys.argv[1])
backend_host = sys.argv[2]
content = template_path.read_text(encoding="utf-8")
content = content.replace("${IDE_WINDOWS_BACKEND_HOST}", backend_host)
print(content, end="")
PY
}

if [[ -n "$OUTPUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  render_template > "$OUTPUT_FILE"
  log_info "Rendered NAS ingress template to $OUTPUT_FILE"
elif [[ "$APPLY" == "true" ]]; then
  require_command kubectl
  if [[ -n "$KUBECTL_CONTEXT" ]]; then
    render_template | kubectl --context "$KUBECTL_CONTEXT" apply -f -
  else
    render_template | kubectl apply -f -
  fi
  log_info "Applied rendered NAS ingress template"
else
  render_template
fi