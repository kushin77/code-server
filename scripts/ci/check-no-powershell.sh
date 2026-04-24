#!/usr/bin/env bash
# @file        scripts/ci/check-no-powershell.sh
# @module      ci/governance
# @description Legacy wrapper that delegates Linux-native content enforcement to check-no-windows-content.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"
exec "$SCRIPT_DIR/check-no-windows-content.sh" "$@"
