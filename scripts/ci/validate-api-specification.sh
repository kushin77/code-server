#!/usr/bin/env bash
# @file        scripts/ci/validate-api-specification.sh
# @module      ci/governance
# @description validate checked-in OpenAPI 3.1 specifications for active HTTP services
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPEC_DIR="$REPO_ROOT/docs/api"

required_specs=(
  "session-broker.openapi.yaml"
  "token-microservice.openapi.yaml"
  "git-proxy-server.openapi.yaml"
)

for spec in "${required_specs[@]}"; do
  spec_path="$SPEC_DIR/$spec"
  if [[ ! -f "$spec_path" ]]; then
    log_fatal "Missing API spec: $spec_path"
  fi

  if ! grep -q '^openapi: 3\.1\.0[[:space:]]*$' "$spec_path"; then
    log_fatal "Spec does not declare OpenAPI 3.1.0: $spec_path"
  fi

  if ! grep -q '^paths:[[:space:]]*$' "$spec_path"; then
    log_fatal "Spec is missing a paths section: $spec_path"
  fi

  if ! grep -q '^components:[[:space:]]*$' "$spec_path"; then
    log_fatal "Spec is missing a components section: $spec_path"
  fi

  log_info "Validated API spec: $spec"
done

log_info "API specification validation passed"