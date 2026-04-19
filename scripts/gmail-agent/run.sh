#!/bin/bash
# @file        scripts/gmail-agent/run.sh
# @module      tools/gmail-agent
# @description Gmail Agent runner - activates venv and executes agent
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Create venv if it doesn't exist
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate venv
source venv/bin/activate

# Run the CLI
python3 -m src.main "$@"
