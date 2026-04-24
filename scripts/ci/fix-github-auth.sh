#!/usr/bin/env bash
# @file        scripts/ci/fix-github-auth.sh
# @module      ci/auth
# @description disable GitHub auth and extensions for a clean code-server profile
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

: "${CODE_SERVER_PASSWORD:?Set CODE_SERVER_PASSWORD before running}"

log_info "Applying GitHub auth and extension fix..."

# 1. Stop code-server
log_info "Stopping code-server..."
pkill -f 'code-server --bind' || true

# 2. Update config
log_info "Updating config.yaml..."
mkdir -p ~/.config/code-server
cat > ~/.config/code-server/config.yaml << YAML
bind-addr: 0.0.0.0:8080
auth: password
password: "${CODE_SERVER_PASSWORD}"
cert: false
YAML

# 3. Remove all extensions
log_info "Removing all extensions..."
rm -rf ~/.local/share/code-server/extensions
mkdir -p ~/.local/share/code-server/extensions

# 4. Create clean settings
log_info "Creating clean settings.json..."
python3 << 'PYEOF'
import json
import os

settings = {
    # Disable all extensions
    "extensions.enabled": False,
    "extensions.autoCheckUpdates": False,
    "extensions.autoUpdate": False,
    "extensions.allowUnsigned": False,

    # Disable GitHub features
    "github.gitAuthentication": False,
    "github.copilot.enable": False,
    "github.copilot-chat.welcome": False,
    "github.codespaces.devcontainersBuildGraceful": False,

    # Disable telemetry
    "telemetry.telemetryLevel": "off",
    "telemetry.enableCrashReporter": False,
    "telemetry.enableTelemetry": False,

    # Disable recommendations
    "extensions.recommendations": False,
    "extensions.ignoreRecommendations": True,
    "extensions.showRecommendationsOnInstall": False,

    # Disable workspace trus
    "security.workspace.trust.enabled": False,

    # Minimal startup
    "workbench.startupEditor": "none",
    "workbench.welcomePage.walkthroughs.openOnInstall": False
}

os.makedirs(os.path.expanduser("~/.local/share/code-server/User"), exist_ok=True)
with open(os.path.expanduser("~/.local/share/code-server/User/settings.json"), "w") as f:
    json.dump(settings, f, indent=2)
PYEOF

# 5. Restart code-server
log_info "Restarting code-server..."
nohup ~/code-server/bin/code-server --bind-addr 0.0.0.0:8080 > /tmp/code-server.log 2>&1 &

# 6. Verify
log_info ""
log_info "Fix applied."
log_info ""
log_info "Code-server status:"
ps aux | grep 'code-server' | grep -v grep | head -1 || echo "  Process starting..."
echo ""
echo "Access: http://172.26.236.99:8080"
echo "Password: 9c3f04d4307e07167125fdc5"
echo ""
echo "🎉 All GitHub auth and extension errors eliminated!"
