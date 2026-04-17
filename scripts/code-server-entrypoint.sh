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

# ── Merge enterprise settings at startup ─────────────────────────────────────
# User-defined values win so new enterprise defaults can be rolled out without
# overwriting existing customizations.
SETTINGS_DIR="/home/coder/.local/share/code-server/User"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_DIR/settings.json" ] && [ -f /etc/code-server/settings.json ]; then
  echo "[entrypoint] Seeding enterprise settings into $SETTINGS_DIR/settings.json"
  cp /etc/code-server/settings.json "$SETTINGS_DIR/settings.json"
elif [ -f "$SETTINGS_DIR/settings.json" ] && [ -f /etc/code-server/settings.json ]; then
  export CODE_SERVER_DEFAULT_SETTINGS=/etc/code-server/settings.json
  export CODE_SERVER_USER_SETTINGS="$SETTINGS_DIR/settings.json"
  /usr/bin/node <<'NODE'
const fs = require("fs");

const defaultPath = process.env.CODE_SERVER_DEFAULT_SETTINGS;
const userPath = process.env.CODE_SERVER_USER_SETTINGS;

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

const mergeDefaults = (current, defaults) => {
  if (Array.isArray(defaults)) {
    return Array.isArray(current) ? current : defaults;
  }

  if (isObject(defaults)) {
    const base = isObject(current) ? { ...current } : {};
    for (const [key, value] of Object.entries(defaults)) {
      if (!(key in base)) {
        base[key] = value;
        continue;
      }

      if (isObject(base[key]) && isObject(value)) {
        base[key] = mergeDefaults(base[key], value);
      }
    }
    return base;
  }

  return current === undefined ? defaults : current;
};

try {
  const defaults = JSON.parse(fs.readFileSync(defaultPath, "utf8"));
  const current = JSON.parse(fs.readFileSync(userPath, "utf8"));
  const merged = mergeDefaults(current, defaults);

  if (JSON.stringify(current) !== JSON.stringify(merged)) {
    fs.writeFileSync(userPath, JSON.stringify(merged, null, 2) + "\n");
    console.log(`[entrypoint] Merged enterprise defaults into ${userPath}`);
  }
} catch (error) {
  console.error(`[entrypoint] WARNING: Could not merge settings: ${error.message}`);
}
NODE
fi

# ── Start code-server (background so trap can catch SIGTERM) ─────────────────
/usr/bin/code-server "$@" &
CS_PID=$!
wait "$CS_PID"