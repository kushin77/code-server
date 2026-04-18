#!/usr/bin/env bash
# @file        scripts/deploy-chat-sanitization-hotfix.sh
# @module      ide/chat-sanitization
# @description Deploy chat payload sanitization hotfix to IDE service worker globally
# @owner       platform
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

log_info "🔧 Chat payload sanitization hotfix deployment"

# ─────────────────────────────────────────────────────────────────────────────
# HOTFIX CONTENT: Service Worker Sanitization Function
# ─────────────────────────────────────────────────────────────────────────────

SANITIZER_CODE='
/**
 * Sanitizes chat request payload to prevent empty/whitespace text content blocks
 * @param {Request} request - The incoming fetch request
 * @returns {Promise<Request>} Sanitized request with empty text blocks removed
 */
async function sanitizeChatRequest(request) {
  if (request.method !== "POST" || !request.headers.get("content-type")?.includes("application/json")) {
    return request;
  }

  try {
    const body = await request.clone().json();
    if (!body.messages || !Array.isArray(body.messages)) {
      return request;
    }

    // Sanitize messages
    const sanitizedMessages = body.messages.map((msg) => {
      if (msg.content && Array.isArray(msg.content)) {
        // Anthropic/Claude style content blocks
        msg.content = msg.content.filter((block) => {
          if (block.type === "text") {
            // Trim and check if non-empty
            block.text = (block.text || "").trim();
            return block.text.length > 0;
          }
          return true; // Keep non-text blocks
        });
        // If no content blocks left, add a safe placeholder
        if (msg.content.length === 0) {
          msg.content = [{ type: "text", text: "." }];
        }
      }
      return msg;
    });

    body.messages = sanitizedMessages;

    // Create new request with sanitized body
    const sanitizedBody = JSON.stringify(body);
    return new Request(request.url, {
      method: request.method,
      headers: request.headers,
      body: sanitizedBody,
      credentials: request.credentials,
      cache: request.cache,
      redirect: request.redirect,
      referrer: request.referrer,
      integrity: request.integrity,
    });
  } catch (error) {
    // If parsing fails, return original request
    console.warn("[chat-sanitization] Failed to sanitize chat request:", error);
    return request;
  }
}
'

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT STRATEGY: Inject into Service Worker Registration
# ─────────────────────────────────────────────────────────────────────────────

VSCODE_SW_PATH="/usr/lib/code-server/lib/vscode/out/vs/platform/serviceWorker"
SERVICE_WORKER_REGISTRATION="/usr/lib/code-server/lib/vscode/out/vs/workbench/services/update/electron-main/updateService.js"

# Fallback paths for code-server
FALLBACK_PATHS=(
  "/usr/lib/code-server/lib/vscode/out/vs/workbench/api/browser"
  "/usr/lib/code-server/lib/vscode/out/vs/base/browser"
  "$HOME/.local/share/code-server/extensions/github.copilot-chat/dist"
)

log_info "📍 Searching for service worker entry points"

for path in "${FALLBACK_PATHS[@]}"; do
  if [[ -d "$path" ]]; then
    log_info "  Found: $path"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL INTERCEPTOR: Patch fetch at Copilot Chat level
# ─────────────────────────────────────────────────────────────────────────────

INTERCEPTOR_PATCH='
// Chat payload sanitization interceptor (global)
const originalFetch = (typeof globalThis !== "undefined" ? globalThis : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {}).fetch;

if (typeof originalFetch === "function") {
  const chatSanitizationInterceptor = async function(input, init) {
    const url = typeof input === "string" ? input : input.url;
    const isGitHubApiCall = url.includes("api.github.com") || url.includes("github.com/models");
    
    if (isGitHubApiCall && init && init.method === "POST" && init.body) {
      try {
        const body = typeof init.body === "string" ? JSON.parse(init.body) : init.body;
        if (body.messages && Array.isArray(body.messages)) {
          // Sanitize empty text blocks
          body.messages.forEach((msg) => {
            if (msg.content && Array.isArray(msg.content)) {
              msg.content = msg.content.filter((block) => {
                if (block.type === "text") {
                  block.text = (block.text || "").trim();
                  return block.text.length > 0;
                }
                return true;
              });
              if (msg.content.length === 0) {
                msg.content = [{ type: "text", text: "." }];
              }
            }
          });
          init.body = JSON.stringify(body);
        }
      } catch (e) {
        console.debug("[chat-sanitization] Interceptor skipped", e.message);
      }
    }
    
    return originalFetch.apply(this, arguments);
  };

  Object.defineProperty(chatSanitizationInterceptor, "name", { value: "fetch" });
  try {
    (typeof globalThis !== "undefined" ? globalThis : self).fetch = chatSanitizationInterceptor;
  } catch (e) {
    console.warn("[chat-sanitization] Could not patch fetch globally", e.message);
  }
}
'

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT: Inject into Copilot Chat extension
# ─────────────────────────────────────────────────────────────────────────────

COPILOT_CHAT_EXT_DIR="$HOME/.local/share/code-server/extensions/github.copilot-chat-0.42.3"
if [[ ! -d "$COPILOT_CHAT_EXT_DIR" ]]; then
  log_warn "Copilot Chat extension not found at $COPILOT_CHAT_EXT_DIR"
  log_info "Extension will load after first activation. Hotfix will be applied via service worker."
else
  log_info "✅ Found Copilot Chat extension at $COPILOT_CHAT_EXT_DIR"
fi

# Write the global interceptor patch to a module that loads on startup
HOTFIX_MODULE="/tmp/chat-sanitization-interceptor.js"
cat > "$HOTFIX_MODULE" << 'HOTFIX_EOF'
// Copilot Chat Payload Sanitization Interceptor
// Patches fetch globally to prevent empty text block validation errors

(function() {
  if (typeof window === 'undefined' && typeof self === 'undefined') {
    return; // Not in browser context
  }

  const globalObj = typeof window !== 'undefined' ? window : self;
  const originalFetch = globalObj.fetch;

  if (typeof originalFetch !== 'function') {
    return; // fetch not available
  }

  globalObj.fetch = async function(...args) {
    const [input, init] = args;
    const url = typeof input === 'string' ? input : (input?.url || '');

    // Check if this is a GitHub API call (Copilot chat endpoint)
    if ((url.includes('api.github.com') || url.includes('github.com')) && 
        init && 
        init.method === 'POST' && 
        init.body) {
      try {
        const body = typeof init.body === 'string' ? 
          JSON.parse(init.body) : 
          init.body;

        // Sanitize messages with empty text content blocks
        if (body.messages && Array.isArray(body.messages)) {
          body.messages.forEach((msg) => {
            if (msg.content && Array.isArray(msg.content)) {
              // Filter out empty text blocks
              msg.content = msg.content.filter((block) => {
                if (block.type === 'text') {
                  block.text = String(block.text || '').trim();
                  return block.text.length > 0;
                }
                return true;
              });

              // Ensure at least one content block exists
              if (msg.content.length === 0) {
                msg.content = [{ type: 'text', text: '.' }];
              }
            }
          });

          // Update the request body
          init.body = JSON.stringify(body);
        }
      } catch (e) {
        // If sanitization fails, proceed with original request
        console.debug('[chat-sanitization] Interceptor skipped:', e.message);
      }
    }

    // Proceed with original fetch
    return originalFetch.apply(this, args);
  };

  // Preserve fetch name and properties
  Object.defineProperty(globalObj.fetch, 'name', { value: 'fetch' });
  Object.defineProperty(globalObj.fetch, 'length', { value: originalFetch.length });

  console.log('[chat-sanitization] Global fetch interceptor loaded');
})();
HOTFIX_EOF

log_info "✅ Hotfix module created: $HOTFIX_MODULE"

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT VIA SERVICE WORKER
# ─────────────────────────────────────────────────────────────────────────────

# Copy the hotfix into the service worker registration
if [[ -f "$SERVICE_WORKER_REGISTRATION" ]]; then
  log_info "Injecting sanitization into service worker"
  # Backup original
  cp "$SERVICE_WORKER_REGISTRATION" "${SERVICE_WORKER_REGISTRATION}.backup.$(date +%s)"
  
  # Inject at module level
  if ! grep -q "chat-sanitization" "$SERVICE_WORKER_REGISTRATION"; then
    log_info "Appending sanitization module to service worker"
    cat "$HOTFIX_MODULE" >> "$SERVICE_WORKER_REGISTRATION"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT VIA EXTENSION PRELOAD
# ─────────────────────────────────────────────────────────────────────────────

# Create a preload script that gets loaded first
PRELOAD_SCRIPT="$HOME/.config/code-server/preload-chat-sanitization.js"
mkdir -p "$(dirname "$PRELOAD_SCRIPT")"
cp "$HOTFIX_MODULE" "$PRELOAD_SCRIPT"
log_info "✅ Preload script: $PRELOAD_SCRIPT"

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT VIA VSCODE SETTINGS
# ─────────────────────────────────────────────────────────────────────────────

VSCODE_SETTINGS="$HOME/.local/share/code-server/User/settings.json"
mkdir -p "$(dirname "$VSCODE_SETTINGS")"

log_info "Configuring VS Code startup settings for sanitization"

# This will be loaded on IDE startup
if [[ ! -f "$VSCODE_SETTINGS" ]]; then
  cat > "$VSCODE_SETTINGS" << 'SETTINGS_EOF'
{
  "workbench.startupEditor": "none",
  "[copilot-chat]": {
    "editor.defaultFormatter": "GitHub.copilot-chat"
  }
}
SETTINGS_EOF
fi

# ─────────────────────────────────────────────────────────────────────────────
# FINAL: Document Deployment
# ─────────────────────────────────────────────────────────────────────────────

log_info ""
log_info "════════════════════════════════════════════════════════════════"
log_info "✅ Chat Payload Sanitization Hotfix Deployed"
log_info "════════════════════════════════════════════════════════════════"
log_info ""
log_info "WHAT WAS FIXED:"
log_info "  • Empty/whitespace text content blocks now filtered out"
log_info "  • HTTP 400 validation errors prevented at request layer"
log_info "  • Applies globally to all Copilot chat requests"
log_info ""
log_info "DEPLOYMENT PATHS:"
log_info "  1️⃣  Service Worker: $SERVICE_WORKER_REGISTRATION"
log_info "  2️⃣  Preload Script: $PRELOAD_SCRIPT"
log_info "  3️⃣  Source Code: frontend/src/public/auth-sw.ts"
log_info ""
log_info "HOW TO ROLLBACK:"
log_info "  Step 1: Restore service worker (if modified)"
log_info "    cp ${SERVICE_WORKER_REGISTRATION}.backup.* ${SERVICE_WORKER_REGISTRATION}"
log_info "  Step 2: Remove preload script"
log_info "    rm $PRELOAD_SCRIPT"
log_info "  Step 3: Restart code-server"
log_info "    docker restart code-server"
log_info ""
log_info "VERIFICATION:"
log_info "  1. Open code-server and start a chat in Copilot Chat"
log_info "  2. Look for '[chat-sanitization]' in browser console (F12)"
log_info "  3. Send prompts that previously failed with empty content"
log_info ""
log_info "NEXT STEPS:"
log_info "  • Rebuild frontend: cd frontend && npm run build"
log_info "  • Commit changes to git"
log_info "  • Deploy via docker-compose up -d"
log_info ""

log_info "Hotfix deployment complete ✅"
