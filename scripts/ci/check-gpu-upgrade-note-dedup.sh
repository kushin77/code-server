#!/usr/bin/env bash
# @file        scripts/ci/check-gpu-upgrade-note-dedup.sh
# @module      ci/governance
# @description Prevent duplicate GPU upgrade action note content across canonical and archive paths.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CANONICAL_FILE="$REPO_ROOT/docs/configs/GPU-UPGRADE-ACTION-NEEDED.txt"
ARCHIVE_FILE="$REPO_ROOT/docs/archives/legacy-archive/gpu-attempts/GPU-UPGRADE-ACTION-NEEDED.txt"

require_file "$CANONICAL_FILE"
require_file "$ARCHIVE_FILE"

canonical_hash="$(sha256sum "$CANONICAL_FILE" | awk '{print $1}')"
archive_hash="$(sha256sum "$ARCHIVE_FILE" | awk '{print $1}')"

if [[ "$canonical_hash" == "$archive_hash" ]]; then
  log_error "Duplicate content detected between canonical and archive GPU action files"
  log_error "Canonical: $CANONICAL_FILE"
  log_error "Archive:   $ARCHIVE_FILE"
  log_error "Expected archive file to be a pointer, not a content mirror"
  exit 1
fi

if ! grep -q "docs/configs/GPU-UPGRADE-ACTION-NEEDED.txt" "$ARCHIVE_FILE"; then
  log_error "Archive pointer missing canonical reference"
  log_error "Expected to find: docs/configs/GPU-UPGRADE-ACTION-NEEDED.txt"
  exit 1
fi

log_success "GPU upgrade note dedup guard passed"
