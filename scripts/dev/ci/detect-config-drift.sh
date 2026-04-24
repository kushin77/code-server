#!/usr/bin/env bash
# @file        scripts/dev/ci/detect-config-drift.sh
# @module      dev/validation
# @description Wrapper for the canonical CI configuration drift detector.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../../ci/detect-config-drift.sh" "$@"
