# AI Features in Code-Server

## Available AI Extensions from Open VSX

Since **GitHub Copilot Chat is not available** in the Open VSX marketplace (code-server's extension store), here are the **best open-source AI alternatives**:

### 1. **Continue.dev** ⭐ (Recommended)
**Best for**: Seamless AI code completion & chat  
**Features**:
- Works with local or cloud models
- Free tier with Claude API integration
- Can run offline with local models (Ollama, LM Studio, etc.)
- Context-aware code completion

**Installation**:
1. In code-server, open **Extensions** (Ctrl+Shift+X)
2. Search: `Continue`
3. Click **Install**
4. Configure in `.continue/config.json` with your API key or local setup

**Setup with Ollama (Free, Local)**:
```bash
# In your terminal
ollama pull mistral  # or any model
# Then configure Continue to use localhost:11434
```

---

### 2. **Cody by Sourcegraph**
**Best for**: Enterprise-grade AI with local options  
**Features**:
- VS Code native integration
- Works with self-hosted Sourcegraph instances
- Code search + AI combined
- Privacy-focused (on-prem option)

**Installation**:
1. Extensions → Search "Cody"
2. Install
3. Sign in with Sourcegraph account (free tier available)

---

### 3. **Tabnine**
**Best for**: AI autocomplete (like Copilot)  
**Features**:
- Real-time code completion
- Free tier available
- Works in code-server
- Trains on your codebase

**Installation**:
1. Extensions → Search "Tabnine"
2. Install & Sign up (free)

---

### 4. **LocalAI + VS Code Extension**
**Best for**: 100% offline, fully private  
**Features**:
- Run AI locally without cloud services
- Multiple models supported
- Privacy guaranteed
- Slower but deterministic

**Setup**:
```bash
# Install LocalAI
docker run -p 8080:8080 localai/localai

# Then in Extensions search "LocalAI"
```

---

## Quick Comparison

| Tool | Cost | Privacy | Speed | Setup |
|------|------|---------|-------|-------|
| **Continue** | Free (with limits) | Cloud by default | Fast | Easy |
| **Cody** | Free tier | Self-hosted option | Fast | Easy |
| **Tabnine** | Free + paid | Cloud | Fast | Easiest |
| **LocalAI** | Free | 100% private | Slow | Complex |

---

## Recommended Setup

### Option A: Continue.dev + Ollama (Recommended for Self-Hosted)
1. Install Ollama: https://ollama.ai
2. Pull a model: `ollama pull mistral`
3. Install **Continue** extension
4. Configure to use `http://localhost:11434`

**Result**: Free, offline, private AI with decent performance

### Option B: Continue.dev + Free API
1. Install **Continue** extension
2. Use free tier with Claude or other APIs
3. No setup needed, works immediately

**Result**: Better quality, requires internet, uses cloud services

### Option C: Tabnine (Easiest)
1. Search "Tabnine" in Extensions
2. Install & sign up
3. Done! Starts autocompleting immediately

**Result**: Works like Copilot, minimal setup

---

## Troubleshooting

### Extension won't install?
- Make sure extensions are enabled in settings (they are by default now)
- Try refreshing the Extensions view (Ctrl+Shift+X)
- Clear browser cache if needed

### Can't find extension?
- Ensure you're searching in the **Open VSX marketplace**
- Some enterprise extensions may not be available

### AI is slow?
- If using cloud APIs, check your internet connection
- If using LocalAI/Ollama, upgrade your local model or hardware

---

## GitHub Copilot Chat - Why It's Unavailable

GitHub Copilot Chat is a **proprietary Microsoft extension** only available in:
- Microsoft's VS Code Marketplace
- VS Code (not standard in other VS Code distributions)

**code-server uses Open VSX** (open-source alternative marketplace), so Copilot Chat is intentionally unavailable.

**Solution**: Use open-source alternatives above (many have similar or better features!)

---

## Additional Resources

- **Continue.dev**: https://continue.dev
- **Cody**: https://about.sourcegraph.com/cody
- **Tabnine**: https://www.tabnine.com
- **LocalAI**: https://localai.io
- **Ollama**: https://ollama.ai
- **Open VSX**: https://open-vsx.org (search for more AI extensions)

---

## Configuration Examples

### Continue.dev with Ollama
Save to `~/.continue/config.json`:
```json
{
  "models": [
    {
      "title": "Mistral",
      "provider": "ollama",
      "model": "mistral",
      "apiBase": "http://localhost:11434"
    }
  ]
}
```

### Tabnine Configuration
Settings → Search "Tabnine" → Configure API key (auto-configured with free account)

---

**Status**: ✅ Multiple free AI options available  
**Maintained**: Github repo at https://github.com/kushin77/code-server
