#!/usr/bin/env bash
# @file        scripts/ops/preflight-air-gap-images.sh
# @module      ops/terraform-drop-package
# @description Pre-pull digest-pinned images for an air-gapped Terraform deployment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <image> [image...]" >&2
  exit 1
fi

for image in "$@"; do
  if [[ "$image" != *@sha256:* ]]; then
    echo "Refusing non-digest-pinned image: $image" >&2
    exit 1
  fi

  echo "Pre-pulling $image"
  docker pull "$image"
done

echo "Air-gap image preflight complete."
