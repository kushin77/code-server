#!/usr/bin/env bash

set -euo pipefail

trap 'echo "Error: Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required" >&2
  exit 1
fi

state_list="$(terraform -chdir="${REPO_ROOT}/terraform/environments/private" state list)"

count_match() {
  local pattern="$1"
  printf '%s\n' "${state_list}" | grep -Ec "${pattern}" || true
}

has_match() {
  local pattern="$1"
  if printf '%s\n' "${state_list}" | grep -Eq "${pattern}"; then
    echo "present"
  else
    echo "missing"
  fi
}

cat <<EOF
# Gap Analysis Audit

Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')

## Terraform State

| Resource | Status |
|----------|--------|
| Jaeger UI | $(has_match 'jaeger') |
| Edge-Agent | $(has_match 'edge-agent') |
| Nexus image | $(has_match 'docker_image\.nexus') |
| Nexus volume | $(has_match 'docker_volume\.nexus_data') |
| MinIO | $(has_match 'minio') |

## Counts

| Metric | Value |
|--------|-------|
| Total state objects | $(printf '%s\n' "${state_list}" | sed '/^$/d' | wc -l | tr -d ' ') |
| MinIO matches | $(count_match 'minio') |
| Nexus matches | $(count_match 'nexus') |
| Edge-Agent matches | $(count_match 'edge-agent') |
| Jaeger matches | $(count_match 'jaeger') |

## Next Review

- Compare this output with [GAP_TRACKING.md](../../GAP_TRACKING.md)
- Update the open GitHub gap issues with the latest evidence
- Re-run after the next deployment pass
EOF
