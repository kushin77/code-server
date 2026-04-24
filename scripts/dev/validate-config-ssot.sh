#!/usr/bin/env bash
# @file        scripts/dev/validate-config-ssot.sh
# @module      dev/validation
# @description Wrapper for the canonical configuration SSOT validator.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../validate-config-ssot.sh" "$@"
