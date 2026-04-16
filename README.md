# Enterprise Code-Server Deployment

Production-grade VS Code IDE with **elite local LLM (Ollama)**, OAuth2 authentication, and enterprise security.

> **🌐 Access Your IDE**: `https://ide.kushnir.cloud`
> **Auth**: Google OAuth2
> **📖 Domain Configuration**: See [DOMAIN_CONFIGURATION.md](./DOMAIN_CONFIGURATION.md)

## 🚀 Quick Start

### Prerequisites
- Docker & Docker Compose installed
- 32GB RAM (recommended for full LLM support)
- 50GB disk space (for LLM models)

### Deploy Everything

```bash
# Clone and navigate
cd code-server-enterprise

# Start all services (code-server + Ollama + OAuth2 + Caddy)
make deploy

# Pull elite LLM models (takes 30-60 minutes)
make ollama-pull-models

# Initialize repository indexing
make ollama-init

# Monitor status
make status
```

## ✨ What You Get

### 🏆 Enterprise Code-Server
- ✅ Full VS Code IDE in the browser
- ✅ GitHub Copilot integration (both chat & code completion)
- ✅ Persistent workspace volumes
- ✅ OAuth2 authentication (Google/GitHub)
- ✅ Reverse proxy with HTTPS/TLS (Caddy)
- ✅ WebSocket support for real-time features
- ✅ Container isolation & security hardening

### 🧠 Elite Local LLM (Ollama)
- ✅ **llama2:70b-chat** - Claude Opus-class reasoning (31GB)
- ✅ **codegemma** - Code-specialized model (9GB)
- ✅ **neural-chat** - Fast & capable (13GB)
- ✅ **mistral** - Ultra-lightweight (4GB)
- ✅ Repository context learning & indexing
- ✅ Semantic search across codebase
- ✅ 100% local - no external API calls
- ✅ Native VS Code integration via `@ollama`## 💬 Using the LLM

Open VS Code Chat (Ctrl+Alt+I) and chat with Ollama:

```
@ollama explain this function
@ollama generate unit tests with >95% coverage for this file
@ollama refactor this code for performance
@ollama how does the authentication system work in this repo?
@ollama generate API documentation with examples
```

## 📚 Full Documentation

| Document | Purpose |
|----------|---------|
| [LHF-TRIAGE-SYSTEM-MASTER-INDEX.md](LHF-TRIAGE-SYSTEM-MASTER-INDEX.md) | **Issue triage by Low Hanging Fruit** |
| [OLLAMA_INTEGRATION.md](OLLAMA_INTEGRATION.md) | Complete Ollama setup & usage guide |
| [QUICK_START.md](QUICK_START.md) | Getting started with code-server |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design & components |
| [CODE_SECURITY_HARDENING.md](CODE_SECURITY_HARDENING.md) | Security features & hardening |

### 🎯 Project Management & Planning

| Document | Purpose |
|----------|---------|
| [LHF-TRIAGE-SYSTEM-MASTER-INDEX.md](LHF-TRIAGE-SYSTEM-MASTER-INDEX.md) | Triage methodology and issue prioritization |
| [TRIAGE-STRATEGY.md](TRIAGE-STRATEGY.md) | LHF Score formula and framework |
| [TRIAGE-REPORT.md](TRIAGE-REPORT.md) | All issues scored and tiered |
| [LHF-EXECUTION-DASHBOARD.md](LHF-EXECUTION-DASHBOARD.md) | Sprint execution plan (Week 1-3) |## 🛠️ Management Commands

```bash
# Ollama Management
make ollama-health              # Check if Ollama is responding
make ollama-pull-models         # Pull all 4 elite models
make ollama-list                # Show available models
make ollama-init                # Full init (pull + index)
make ollama-status              # Show service status
make ollama-logs                # Stream Ollama logs

# Deployment
make deploy                     # Deploy everything
make destroy                    # Destroy all resources
make status                     # Show status
make logs                       # Stream logs
make shell                      # SSH into code-server

# Aliases
make om                         # ollama-status
make oi                         # ollama-init
make op                         # ollama-pull-models
make d                          # deploy
make s                          # status
```

Run `make help` for all available commands.

## 🔗 Access Points

| Service | URL | Purpose |
|---------|-----|---------|
| **Code-Server** | https://ide.kushnir.cloud | Main IDE interface |
| **Ollama API** | http://localhost:11434 | LLM inference endpoint (internal) |
| **OAuth2 Proxy** | http://localhost:4180 | Auth sidecar (internal) |
| **Caddy** | https://ide.kushnir.cloud | Reverse proxy & TLS termination |## 📦 Architecture

```
┌─── Code-Server (VS Code) ───────────────────┐
│  • Copilot Chat (GitHub)                    │
│  • Ollama Chat (@ollama) [LOCAL LLM]        │
│  • Repository Indexing (semantic search)    │
└──────────────┬──────────────────────────────┘
               │          docker network
               │
┌──────────────v──────────────────────────────┐
│  Ollama Server (LLM Inference)              │
│  • llama2:70b-chat (31GB)                   │
│  • codegemma (9GB)                          │
│  • neural-chat (13GB)                       │
│  • mistral (4GB)                            │
└─────────────────────────────────────────────┘
```

## 🔐 Security Features

✅ OAuth2 authentication (Google/GitHub)
✅ HTTPS/TLS encryption (Caddy)
✅ Container isolation (Docker)
✅ No-new-privileges security option
✅ Capability dropping
✅ Read-only mounts where possible
✅ Persistent volumes with encryption support
✅ Network segmentation

## 📊 Resource Requirements

| Component | Minimum | Recommended | Maximum |
|-----------|---------|-------------|---------|
| RAM | 8GB | 32GB | 64GB+ |
| CPU | 4 cores | 8 cores | 16+ cores |
| Disk | 20GB | 50-100GB | 200GB+ |
| GPU | None (CPU ok) | NVIDIA (optional) | A100/H100 |

**Note**: Models are downloaded on-demand the first time they're pulled.

## 🚀 Next Steps

1. **Deploy**: `make deploy`
2. **Pull Models**: `make ollama-pull-models` (first time only)
3. **Index Repository**: `make ollama-init`
4. **Open Code-Server**: Visit https://ide.kushnir.cloud
5. **Start Chatting**: Type `@ollama` in the Chat view

For detailed setup, see [OLLAMA_INTEGRATION.md](OLLAMA_INTEGRATION.md).

## 📖 Learn More

- [Ollama Documentation](https://ollama.ai)
- [Code-Server Docs](https://coder.com/docs/code-server)
- [VS Code Chat Extension API](https://code.visualstudio.com/api)
- [Docker Compose Docs](https://docs.docker.com/compose/)

## 🛠️ Troubleshooting

### Ollama not responding?

```bash
make ollama-health      # Check connectivity
make ollama-logs        # View logs
docker compose restart ollama
```

### Need to pull models manually?

```bash
docker compose exec ollama ollama pull llama2:70b-chat
docker compose exec ollama ollama pull codegemma
```

### Out of memory?

- Reduce to faster models: `mistral` or `neural-chat`
- Reduce context window: Set `ollama.contextWindow = 2048`
- Add swap space or increase RAM

See [OLLAMA_INTEGRATION.md](OLLAMA_INTEGRATION.md#troubleshooting) for detailed troubleshooting.

## 📄 License

- code-server: MIT
- Ollama: MIT
- VS Code: Microsoft License
- Models: Various (see individual model pages)

---

**Status**: ✅ Production Ready
**Last Updated**: 2026-04-12
**Version**: 4.115.0 (code-server) + 1.0.0 (Ollama integration)

---

## Security Checklist

- [ ] Change default passwords in docker-compose.yml
- [ ] Set up GitHub OAuth app (Settings → Developer Settings)
- [ ] Configure firewall rules (only allow 80/443 from trusted IPs)
- [ ] Enable audit logging in code-server config
- [ ] Set resource limits in docker-compose
- [ ] Backup volumes regularly
- [ ] Rotate passwords monthly

---

## Troubleshooting

**Can't access HTTPS?**
- Caddy generates self-signed cert on first run
- Browser will show security warning (expected for self-signed)
- Click "Advanced" → "Proceed" to bypass

**WebSocket errors?**
- Verify `websocket` directive in Caddyfile
- Check code-server logs: `docker logs code-server-enterprise-code-server-1`

**Permission denied?**
- Ensure WSL volumes have correct permissions
- Run: `chmod 755 ~/code-server-enterprise/workspaces`

