# Ollama AI Code Migration

## Overview

As of this release, all Ollama and AI-related code has been migrated to a separate, dedicated repository: **[kushin77/ollama](https://github.com/kushin77/ollama)**

This migration achieves:

✅ **Separation of Concerns** - AI services are now independent from the IDE infrastructure  
✅ **Code Reuse** - Other projects can use the AI services independently  
✅ **Independent Versioning** - AI and IDE can be released separately  
✅ **Cleaner Architecture** - Each repository has a single, clear responsibility  
✅ **Better Team Collaboration** - AI development can happen independently  

## What Moved

### VS Code Extension: ollama-chat
- **Old Location**: `code-server-enterprise/extensions/ollama-chat/`
- **New Location**: `kushin77/ollama/extensions/ollama-chat/`
- **URL**: https://github.com/kushin77/ollama/tree/main/extensions/ollama-chat

Features:
- Elite local LLM chat integration
- Repository context learning via semantic indexing
- Code analysis, generation, testing, and documentation
- Full semantic search over codebase

### Backend AI Services
- **Old Location**: `code-server-enterprise/backend/src/services/ai/`
- **New Location**: `kushin77/ollama/backend/src/services/ai/`
- **URL**: https://github.com/kushin77/ollama/tree/main/backend/src/services/ai

Services:
- Semantic repository indexing with language-aware chunking
- Incremental async indexing with file watchers
- Retrieval quality metrics and benchmarking
- AI provider routing (Ollama + HuggingFace)

### Initialization Scripts
- **Old Location**: `code-server-enterprise/scripts/ollama-init.sh`
- **New Location**: `kushin77/ollama/scripts/ollama-init.sh`
- **URL**: https://github.com/kushin77/ollama/blob/main/scripts/ollama-init.sh

Functionality:
- Ollama server health checks
- Model pulling (fully idempotent)
- Repository context indexing
- Status reporting

## Integration

### For Developers

If you're extending or developing the Ollama integration:

```bash
# Clone the Ollama repository
git clone https://github.com/kushin77/ollama.git

# Install dependencies
cd ollama
npm install

# Build extension
cd extensions/ollama-chat
npm run compile

# Build backend services
cd ../../backend
npm run build
```

### For Users

The Ollama integration is still available to code-server-enterprise via:

1. **Pre-installed Extension** (if configured in docker-compose)
2. **Backend Services** (automatically available)
3. **Initialization Scripts** (called during startup)

No user-visible changes have been made - everything continues to work as before!

## Docker Compose Usage

```yaml
version: '3.9'
services:
  code-server:
    image: code-server-enterprise:latest
    environment:
      # Ollama configuration
      OLLAMA_ENDPOINT: http://ollama:11434
      AI_INDEXING_ENABLED: "true"
    depends_on:
      - ollama

  ollama:
    image: ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
    environment:
      OLLAMA_MODELS: "llama2:70b-chat codegemma neural-chat"

volumes:
  ollama-data:
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_ENDPOINT` | `http://ollama:11434` | Ollama server address |
| `AI_INDEXING_ENABLED` | `true` | Enable semantic indexing |
| `AI_EGRESS_ENABLED` | `false` | Allow HuggingFace integration (opt-in) |
| `HF_API_TOKEN` | `` | HuggingFace API token (if egress enabled) |
| `AI_INDEX_CHUNK_SIZE_TOKENS` | `800` | Semantic chunk size |
| `AI_INDEX_OVERLAP_TOKENS` | `120` | Context overlap between chunks |
| `AI_INDEX_QUEUE_SIZE` | `1000` | Async indexing queue size |

## Commands

### Start Ollama Integration

```bash
# Via make (if available in code-server)
make ollama-init

# Via docker-compose
docker-compose up -d ollama
docker-compose exec code-server /usr/local/bin/ollama-tools/ollama-init.sh
```

### Check Status

```bash
# Check Ollama health
curl http://ollama:11434/api/tags

# Check models
docker-compose exec ollama ollama list

# View logs
docker-compose logs ollama
docker-compose logs code-server | grep ollama
```

### Pull Models Manually

```bash
# Pull specific model
docker-compose exec ollama ollama pull llama2:70b-chat

# List available models
docker-compose exec ollama ollama list
```

## Troubleshooting

### "Ollama server not responding"

1. Verify ollama container is running:
   ```bash
   docker-compose ps | grep ollama
   ```

2. Check ollama logs:
   ```bash
   docker-compose logs ollama
   ```

3. Verify network connectivity:
   ```bash
   docker-compose exec code-server curl http://ollama:11434/api/tags
   ```

### Extension Not Loaded

1. Check if extension was built:
   ```bash
   ls -la extensions/ollama-chat/dist/
   ```

2. Restart VS Code:
   - Command Palette → Developer: Reload Window
   - Or restart code-server container

3. Check VS Code extension logs:
   - Help → Toggle Developer Tools
   - Check Console tab

### Semantic Indexing Slow

1. Check repository size:
   ```bash
   du -sh /workspace
   ```

2. Check index queue:
   ```bash
   docker-compose logs code-server | grep "queue"
   ```

3. Reduce context window:
   - VS Code Settings → `ollama.contextWindow` → reduce to 2048

## Performance Tips

1. **Use Smaller Models** for faster responses:
   ```bash
   # Not recommended: 70B model is slow
   ollama pull llama2:70b-chat
   
   # Better: Fast models
   ollama pull neural-chat
   ollama pull mistral
   ```

2. **Allocate Sufficient Resources**:
   - CPU: 8+ cores recommended
   - RAM: 32GB+ for 70B models
   - Disk: 100GB+ for multiple models

3. **Enable Caching**:
   ```yaml
   ollama:
     volumes:
      - ollama-data:/root/.ollama  # Cache models
      - .ollama-index:/workspace/.ollama-index  # Cache indexes
   ```

4. **Use Incremental Indexing**:
   - Enabled by default
   - Only re-indexes changed files
   - Watch events debounced at 80ms

## For Contributors

### Reporting Issues

- **Ollama/AI Issues** → [kushin77/ollama issues](https://github.com/kushin77/ollama/issues)
- **Integration Issues** → [kushin77/code-server issues](https://github.com/kushin77/code-server/issues) with `ai-integration` label
- **General Issues** → Current repository

### Development Setup

```bash
# 1. Clone both repositories
git clone https://github.com/kushin77/code-server.git code-server-enterprise
git clone https://github.com/kushin77/ollama.git

# 2. Link ollama into code-server workspace
cd code-server-enterprise
ln -s ../ollama extensions/ollama-chat-dev

# 3. Install dependencies
npm install

# 4. Development workflow
cd ../ollama/extensions/ollama-chat
npm run watch  # Watch mode

# In another terminal
cd code-server-enterprise
npm run dev
```

## Migration Checklist

If you were using Ollama in code-server-enterprise before:

- [ ] Review Ollama repository README: https://github.com/kushin77/ollama
- [ ] Verify docker-compose includes ollama service
- [ ] Check OLLAMA_ENDPOINT environment variable is set correctly
- [ ] Test extension loads: `@ollama` in VS Code chat
- [ ] Index repository: `Ollama: Index Repository` command
- [ ] Verify models are available: `Ollama: List Available Models`

All features continue to work - no action required unless you're actively developing the AI services!

## References

- **Ollama Repository**: https://github.com/kushin77/ollama
- **Migration Details**: [MIGRATION.md](https://github.com/kushin77/ollama/blob/main/MIGRATION.md)
- **Integration Guide**: [INTEGRATION.md](https://github.com/kushin77/ollama/blob/main/INTEGRATION.md)
- **Ollama Project**: https://ollama.ai

## Support

- For AI service questions: Open issue in [kushin77/ollama](https://github.com/kushin77/ollama)
- For code-server integration: Open issue in [kushin77/code-server](https://github.com/kushin77/code-server)
- For questions: Use GitHub Discussions in respective repository

---

**Migration Date**: April 2026  
**Migrated By**: GitHub Copilot  
**Status**: ✅ Complete
