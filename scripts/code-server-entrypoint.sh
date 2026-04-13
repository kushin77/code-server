#!/bin/sh
set -eu

# ── Graceful shutdown ─────────────────────────────────────────────────────────
# Forward SIGTERM to code-server so open files are flushed, sessions saved,
# and extensions get a chance to deactivate cleanly before the container stops.
_shutdown() {
  echo "[entrypoint] SIGTERM received -- shutting down code-server gracefully"
  [ -n "${CS_PID:-}" ] && kill -TERM "$CS_PID" 2>/dev/null || true
  wait "${CS_PID:-}" 2>/dev/null || true
}
trap _shutdown TERM INT

EXT_DIR="/home/coder/.local/share/code-server/extensions"
mkdir -p "$EXT_DIR"

# ── Install Copilot extensions from pre-cached VSIX ──────────────────────────
if ! /usr/bin/code-server --list-extensions --extensions-dir "$EXT_DIR" 2>/dev/null | grep -qi '^github.copilot$'; then
  echo "[entrypoint] Installing github.copilot from /opt/vsix/..."
  /usr/bin/code-server --install-extension /opt/vsix/github-copilot.vsix \
    --extensions-dir "$EXT_DIR" --force >/tmp/copilot-install.log 2>&1 || true
fi

if ! /usr/bin/code-server --list-extensions --extensions-dir "$EXT_DIR" 2>/dev/null | grep -qi '^github.copilot-chat$'; then
  echo "[entrypoint] Installing github.copilot-chat from /opt/vsix/..."
  /usr/bin/code-server --install-extension /opt/vsix/github-copilot-chat.vsix \
    --extensions-dir "$EXT_DIR" --force >/tmp/copilot-chat-install.log 2>&1 || true
fi

# ── Register Ollama Chat extension (custom local extension) ──────────────────
mkdir -p "$EXT_DIR/enterprise.ollama-chat"
if [ -d /opt/extensions/ollama-chat ]; then
  cp -r /opt/extensions/ollama-chat/* "$EXT_DIR/enterprise.ollama-chat/" 2>/dev/null || true
  echo "[entrypoint] Ollama Chat extension registered"
fi

# ── Seed enterprise settings on first launch ─────────────────────────────────
# Copies /etc/code-server/settings.json (bind-mounted from config/settings.json)
# ONLY if the user has no existing settings -- never overwrites customizations.
SETTINGS_DIR="/home/coder/.local/share/code-server/User"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_DIR/settings.json" ] && [ -f /etc/code-server/settings.json ]; then
  echo "[entrypoint] Seeding enterprise settings into $SETTINGS_DIR/settings.json"
  cp /etc/code-server/settings.json "$SETTINGS_DIR/settings.json"
fi

# ── Start code-server (background so trap can catch SIGTERM) ─────────────────
/usr/bin/code-server "$@" &
CS_PID=$!
wait "$CS_PID"