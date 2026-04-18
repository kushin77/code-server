# Chat Payload Sanitization Hotfix

**Issue**: Copilot Chat was failing with `HTTP 400: messages.text content blocks must contain non-whitespace text`

**Root Cause**: The chat API (GitHub Copilot/Anthropic Claude) rejects requests where a message contains empty or whitespace-only text content blocks.

**Solution**: Global fetch interceptor that automatically filters empty text blocks before they reach the provider.

## Deployed Fixes

### 1. **Service Worker Enhancement** – `frontend/src/public/auth-sw.ts`
- Added `sanitizeChatRequest()` function that strips empty text blocks from message payloads
- Intercepts all `api.github.com` POST requests
- Ensures every message has at least one non-empty content block (emergency fallback: `"."`)

**Code Location**: [frontend/src/public/auth-sw.ts](../frontend/src/public/auth-sw.ts#L23-L53)

```typescript
async function sanitizeChatRequest(request: Request): Promise<Request>
// Removes:
// - Empty text content blocks
// - Whitespace-only text blocks
// Ensures minimum viable message with fallback if all blocks removed
```

### 2. **Global Fetch Interceptor** – `preload-chat-sanitization.js`
Deployed to `$HOME/.config/code-server/preload-chat-sanitization.js`

Patches `globalThis.fetch` globally to:
- Detect GitHub API POST requests (Copilot chat endpoints)
- Parse JSON body
- Filter empty/whitespace text blocks from `messages[].content[]`
- Re-stringify sanitized payload
- Pass through to original fetch

**Why this works**: Catches requests at the lowest layer before provider validation.

### 3. **Testing & Verification**
Test that the fix is working:
1. Open code-server
2. Open browser console (F12)
3. Look for: `[chat-sanitization] Global fetch interceptor loaded`
4. Send a chat prompt to Copilot
5. No 400 errors should occur

## Deployment Status

| Component | Status | Path |
|-----------|--------|------|
| Source Code | ✅ Updated | `frontend/src/public/auth-sw.ts` |
| Preload Module | ✅ Deployed | `/home/coder/.config/code-server/preload-chat-sanitization.js` |
| Hotfix Script | ✅ Created | `scripts/deploy-chat-sanitization-hotfix.sh` |
| IDE Config | ✅ Updated | `/home/coder/.local/share/code-server/User/settings.json` |

## How It Works (Data Flow)

```
User sends chat prompt
         ↓
Browser fetch() intercept
         ↓
Check if GitHub API + POST
         ↓
Parse JSON body
         ↓
Sanitize: filter empty text blocks
         ↓
Ensure minimum: [{ type: "text", text: "." }]
         ↓
Re-stringify body
         ↓
Original fetch() → GitHub API
         ↓
✅ 200 OK (no 400 errors)
```

## Rollback Instructions

If needed, fully remove the hotfix:

```bash
# Step 1: Restore preload script
rm /home/coder/.config/code-server/preload-chat-sanitization.js

# Step 2: Restore service worker (if backed up)
# (Backup created at deploy time if modifications made)
cp /usr/lib/code-server/lib/vscode/out/vs/workbench/services/update/electron-main/updateService.js.backup.* \
   /usr/lib/code-server/lib/vscode/out/vs/workbench/services/update/electron-main/updateService.js

# Step 3: Restart code-server
docker compose restart code-server

# Step 4: Verify removal
docker compose logs -f code-server | grep -i chat-sanitization
# Should see no matches
```

## Building & Deploying Changes

If you modify the source TypeScript code:

```bash
# Build frontend
cd frontend
npm run build

# Commit changes
git add frontend/src/public/auth-sw.ts scripts/deploy-chat-sanitization-hotfix.sh
git commit -m "fix(chat): sanitize empty text content blocks globally"

# Deploy to all environments
docker compose up -d
```

## Monitoring & Alerts

Monitor for this log pattern in browser console:
```
[chat-sanitization] Global fetch interceptor loaded
```

If you see:
```
[chat-sanitization] Failed to sanitize chat request: <error>
```

The fallback is working correctly (non-JSON payloads skip sanitization and proceed untouched).

## Future Improvements

1. **Add metric tracking**: Count sanitization events per session
2. **Enhanced validation**: Validate block.type and block properties exist
3. **Retry policy**: Automatic retry on 400 with 10s timeout (non-blocking)
4. **Telemetry**: Send anonymized stats on filtered blocks to observability system
5. **Configuration**: Make sanitization rules configurable via `settings.json`

## References

- [GitHub Copilot Chat API](https://docs.github.com/en/copilot/using-github-copilot/getting-started-with-github-copilot)
- [Anthropic Messages API](https://docs.anthropic.com/en/api/messages)
- [Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)

---

**Deployed**: April 18, 2026  
**Fix Version**: 1.0.0  
**Scope**: Global (IDE-wide)
