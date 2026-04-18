#!/usr/bin/env bash
# @file        scripts/code-server-entrypoint.sh
# @module      operations
# @description code server entrypoint — on-prem code-server
# @owner       platform
# @status      active
set -eu

# ── Patch product.json ────────────────────────────────────────────────────────
# Remove defaultChatAgent (causes Copilot Chat install-loop) and ensure both
# github.copilot and github.copilot-chat are in trustedExtensionAuthAccess

PRODUCT_JSON=$(find /usr/lib/code-server -name "product.json" -type f | head -1)
if [ -n "$PRODUCT_JSON" ] && [ -f "$PRODUCT_JSON" ]; then
  /usr/bin/node -e "const fs = require('fs'); const product = JSON.parse(fs.readFileSync('$PRODUCT_JSON', 'utf8')); delete product.defaultChatAgent; const trusted = Array.isArray(product.trustedExtensionAuthAccess) ? product.trustedExtensionAuthAccess : []; product.trustedExtensionAuthAccess = [...new Set([...trusted, 'github.copilot', 'github.copilot-chat'])]; fs.writeFileSync('$PRODUCT_JSON', JSON.stringify(product, null, 2) + '\n');" 2>/dev/null || echo "[entrypoint] WARNING: Could not patch product.json"
fi

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

if command -v git >/dev/null 2>&1 && command -v git-credential-gsm >/dev/null 2>&1; then
  git config --global credential.helper gsm >/dev/null 2>&1 || true
  git config --global credential.https://github.com.helper gsm >/dev/null 2>&1 || true
fi

# ── Canonical auth environment contract (#651) ──────────────────────────────
export GSM_PROJECT="gcp-eiq"
export GSM_SECRET_NAME="github-token"
export GIT_CREDENTIAL_GSM_CANONICAL_SECRET_NAME="github-token"
if [ -n "${GSM_GITHUB_TOKEN_SECRET:-}" ]; then
  echo "[entrypoint] WARNING: GSM_GITHUB_TOKEN_SECRET is deprecated and will be unset to avoid env drift"
  unset GSM_GITHUB_TOKEN_SECRET
fi

if command -v code-server-auth >/dev/null 2>&1; then
  if ! code-server-auth doctor; then
    echo "[entrypoint] WARNING: auth doctor detected environment drift; canonical values were enforced"
  fi
fi

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
if [ -d /opt/extensions/ollama-chat ] && [ -f /opt/extensions/ollama-chat/package.json ]; then
  mkdir -p "$EXT_DIR/enterprise.ollama-chat"
  cp -r /opt/extensions/ollama-chat/* "$EXT_DIR/enterprise.ollama-chat/" 2>/dev/null || true
  echo "[entrypoint] Ollama Chat extension registered"
fi

# ── Validate git-credential-gsm availability ─────────────────────────────────
# Emit warning early if git-credential-gsm is missing so deployment errors are
# caught at startup rather than at first git credential use (#638)
if [ ! -f "/usr/local/bin/git-credential-gsm" ]; then
  echo "[entrypoint] WARNING: /usr/local/bin/git-credential-gsm not found — GSM-backed git auth will not work. Check Dockerfile COPY step."
else
  echo "[entrypoint] git-credential-gsm present at /usr/local/bin/git-credential-gsm"
fi

# ── Merge enterprise settings into user settings ─────────────────────────────
# Applies enterprise defaults on every launch without overwriting user-owned
# T2/T3 preferences. Locked T1 keys remain enterprise-controlled.
SETTINGS_DIR="/home/coder/.local/share/code-server/User"
MERGE_SCRIPT="/usr/local/lib/code-server/merge-settings.js"
mkdir -p "$SETTINGS_DIR"
if [ -f /etc/code-server/settings.json ]; then
  if [ -f "$MERGE_SCRIPT" ]; then
    TMP_SETTINGS=$(mktemp)
    if [ -f "$SETTINGS_DIR/settings.json" ]; then
      echo "[entrypoint] Merging enterprise settings into $SETTINGS_DIR/settings.json"
    else
      echo "[entrypoint] Seeding enterprise settings into $SETTINGS_DIR/settings.json"
      printf '{}\n' > "$SETTINGS_DIR/settings.json"
    fi

    if /usr/bin/node "$MERGE_SCRIPT" /etc/code-server/settings.json "$SETTINGS_DIR/settings.json" "$TMP_SETTINGS"; then
      mv "$TMP_SETTINGS" "$SETTINGS_DIR/settings.json"
    else
      rm -f "$TMP_SETTINGS"
      echo "[entrypoint] WARNING: enterprise settings merge failed; preserving existing user settings"
    fi
  elif [ ! -f "$SETTINGS_DIR/settings.json" ]; then
    echo "[entrypoint] WARNING: merge-settings.js missing; falling back to one-time seed"
    cp /etc/code-server/settings.json "$SETTINGS_DIR/settings.json"
  else
    echo "[entrypoint] WARNING: merge-settings.js missing; existing user settings left unchanged"
  fi
fi

# ── Workspace credential provisioning (passwordless, session-scoped) ──────────
if command -v workspace-provision >/dev/null 2>&1; then
  workspace-provision || echo "[entrypoint] WARNING: workspace-provision had warnings (non-fatal)"
fi

# ── Start auth keepalive daemon (single-instance, background) ─────────────────
if command -v auth-keepalive >/dev/null 2>&1; then
  echo "[entrypoint] starting auth-keepalive daemon"
  auth-keepalive start || echo "[entrypoint] WARNING: auth-keepalive failed to start"
fi

# ── Start code-server (background so trap can catch SIGTERM) ─────────────────
/usr/bin/code-server "$@" &
CS_PID=$!
wait "$CS_PID"