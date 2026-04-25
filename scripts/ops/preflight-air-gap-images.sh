#!/usr/bin/env bash
# @governance: Air-gap image preflight — pre-pull digest-pinned images for offline deployment
# Purpose: Pre-pull digest-pinned images for an air-gapped Terraform deployment
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1531 (Infrastructure as Code)

set -euo pipefail

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
