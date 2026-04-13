# Code-Server Enterprise - Deployment Guide

**Status**: Enterprise IDE/AI/Agent system with comprehensive multi-service architecture

## 🎯 System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     INTERNET (HTTPS/TLS)                        │
│                    ide.kushnir.cloud:443                        │
└──────────────────────────┬──────────────────────────────────────┘
                            │
┌──────────────────────────▼──────────────────────────────────────┐
│                      Caddy Reverse Proxy                         │
│              (TLS/HTTPS, DNS-01 validation via GoDaddy)         │
└──────────────────────────┬──────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
   OAuth2-Proxy        code-server           Agent APIs
   (Auth Layer)        (IDE + Extensions)    (AI/Automation)
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
        ┌───────────────────┼───────────────────┬─────────────────┐
        ▼                   ▼                   ▼                 ▼
    Keycloak            Ollama            ChromaDB          Agent API
    (Identity)         (LLM Models)      (Vectors)        (LangGraph)
        │                   │                   │                 │
        └──────────────────┬┬──────────────────┬┬────────────────┘
                           ││                  ││
                   ┌───────┘└──────────┬───────┘└─────────┐
                   ▼                   ▼                   ▼
              PostgreSQL          Embeddings API    Computer-Use MCP
              (Keycloak DB)     (Vector Generation)  (Agent Control)
```

## 🚀 Prerequisites

### System Requirements
- **Docker & Docker Compose** (v24+)
- **32GB RAM minimum** (64GB+ recommended for full LLM support)
- **50GB free disk** (for LLM models and data)
- **Linux/macOS/WSL2** (Docker must use Linux containers)
- **Domain name** with DNS control (for SSL/TLS)

### Configuration Files
- Copy `.env.template` to `.env`
- Populate with:
  - `DOMAIN`: Your domain (e.g., `ide.kushnir.cloud`)
  - `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`: Google OAuth credentials
  - `GODADDY_KEY` / `GODADDY_SECRET`: DNS API credentials for Let's Encrypt
  - `CODE_SERVER_PASSWORD`: IDE access password
  - `KEYCLOAK_DB_PASSWORD` / `KEYCLOAK_ADMIN_PASSWORD`: Identity management

### GCP Secret Manager (Optional)
Pull secrets automatically from Google Secret Manager:
```bash
./scripts/fetch-gsm-secrets.sh
```

## 📦 Services & Deployment

### Core Infrastructure

| Service | Port | Purpose | Status |
|---------|------|---------|--------|
| **code-server** | 8080 | VS Code IDE in browser | ✅ Ready |
| **oauth2-proxy** | 4180 | Authentication/OIDC | ✅ Ready |
| **caddy** | 80/443 | Reverse proxy + TLS | ✅ Ready |
| **keycloak** | 8080 | Identity provider | ✅ Ready |
| **keycloak-db** | 5432 | Keycloak PostgreSQL | ✅ Ready |

### AI/Agents Services

| Service | Port | Purpose | Status |
|---------|------|---------|--------|
| **ollama** | 11434 | Local LLM inference | ✅ Ready |
| **chroma** | 8000 | Vector database | ✅ Ready |
| **embeddings** | 8002 | Vector generation | ✅ New |
| **agent-api** | 8001 | LangGraph agents | ✅ New |
| **computer-use-mcp** | 8010 | Agent computer control | ✅ New |

## 🚀 Quick Start

### 1. Configure Environment
```bash
# Create .env from template
cp .env.template .env

# Edit .env with your settings
nano .env  # or use your editor

# Key variables to set:
# - DOMAIN=your-domain.com
# - GOOGLE_CLIENT_ID=...
# - GOOGLE_CLIENT_SECRET=...
# - GODADDY_KEY=...
# - GODADDY_SECRET=...
```

### 2. Build & Start Services
```bash
# Alternative: Use Makefile
make deploy

# Or manual Docker Compose
docker-compose build
docker-compose up -d

# Monitor startup
docker-compose logs -f caddy
```

### 3. Verify Services
```bash
# Check all services running
docker-compose ps

# Verify core services alive
curl https://your-domain.com/health
curl http://localhost:8001/health         # Agent API
curl http://localhost:8002/api/v1/heartbeat  # Embeddings

# Check Ollama
curl http://localhost:11434/api/tags
```

### 4. Initialize LLM Models
```bash
# Pull elite LLM models (30-60 minutes)
# Models will be shared between Ollama + Agent API
ollama pull llama2:70b-chat    # Main reasoning model (31GB)
ollama pull qwen2.5-coder:32b  # Code-specialized (19GB)
ollama pull qwen2.5-coder:7b   # Fast model (4GB)

# Or use docker-compose (includes ollama-init service)
# Check docker-compose logs ollama-init
```

### 5. Access IDE
```
https://your-domain.com
Email: your-google-account@gmail.com
IDE opens in browser with Code Server
```

## 🔧 Configuration & Customization

### Environment Variables

**Domain & TLS**
```bash
DOMAIN=ide.kushnir.cloud
GODADDY_KEY=gd_key
GODADDY_SECRET=gd_secret
```

**Code Server**
```bash
CODE_SERVER_PASSWORD=your-strong-password
GITHUB_TOKEN=ghp_xxxx  # For Copilot extension
WORKSPACE_PATH=./workspace  # Where to mount code
```

**OAuth2 & Keycloak**
```bash
GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxx
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=secure-password
KEYCLOAK_DB_PASSWORD=secure-password
```

**AI/Agents**
```bash
OLLAMA_DEFAULT_MODEL=qwen2.5-coder:32b
OLLAMA_FAST_MODEL=qwen2.5-coder:7b
OLLAMA_NUM_GPU=1              # GPU layers (0=CPU only)
EMBED_MODEL_NAME=nomic-ai/nomic-embed-text-v1.5
HF_TOKEN=hf_xxx              # For embeddings model
```

### Agent Configuration
```bash
AGENT_MAX_ITERATIONS=3       # Max agent steps per task
HITL_STRICT=false            # Require human approval for actions
DEV_MODE=false               # Enable debug logging
```

## 🧠 AI Capabilities

### Available LLM Models

**Elite Tier** (Claude Opus-class)
- `llama2:70b-chat` - 31GB, exceptional reasoning & code
- `qwen2.5-coder:32b` - 19GB, code-specialized

**Fast Tier** (Real-time feedback)
- `qwen2.5-coder:7b` - 4GB, fast inference
- `mistral` - 4GB, lightweight reasoning

### Agent APIs

**SemanticSearchEngine** (Phase 4 ML)
- Code indexing with 768-dim embeddings
- Multi-repo code discovery
- Intent-based code queries

**AgentFarm** (Phase 1-3)
- CodeAgent: Refactoring & performance
- ReviewAgent: Security & quality audits
- ArchitectAgent: System design analysis
- TestAgent: Coverage & edge cases

**Computer-Use MCP**
- Mouse/keyboard control
- Screenshot capture
- Clipboard interaction
- Scroll operations

## 🔒 Security & Hardening

### Built-In Security
- ✅ OAuth2/OIDC (Google identity)
- ✅ TLS/HTTPS (automatic Let's Encrypt)
- ✅ JWT tokens (24h expiration, 15m refresh)
- ✅ RBAC (via Keycloak)
- ✅ Network isolation (Docker internal bridge)
- ✅ Container hardening (no-new-privileges, read-only root fs)
- ✅ Secrets management (via .env, GSM optional)

### Recommended Hardening
```bash
# Restrict allowed emails
echo "your-email@domain.com" > allowed-emails.txt

# Rotate passwords regularly
# Update KEYCLOAK_ADMIN_PASSWORD in .env

# Monitor security events
docker-compose logs -f keycloak | grep -i "error\|warn"

# Backup Keycloak realm
docker-compose exec keycloak-db \
  pg_dump -U keycloak keycloak > keycloak-backup.sql
```

## 📊 Monitoring & Debugging

### Health Checks
```bash
# Code Server
curl -f http://localhost:8080/healthz

# OAuth2 Proxy
curl -f http://localhost:4180/ping

# Keycloak
curl -f http://localhost:8080/auth/health/ready

# Ollama
curl -f http://localhost:11434/api/tags

# Agent API
curl -f http://localhost:8001/health

# Embeddings
curl -f http://localhost:8002/api/v1/heartbeat

# ChromaDB
curl -f http://localhost:8000/api/v1/heartbeat
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f code-server
docker-compose logs -f agent-api
docker-compose logs -f ollama

# Follow specific lines
docker-compose logs -f keycloak | grep -i error
```

### Performance Monitoring
```bash
# Resource usage
docker stats

# Ollama model info
curl http://localhost:11434/api/show -d '{"name": "llama2:70b-chat"}'

# Vector DB stats
curl http://localhost:8000/api/v1/heartbeat
```

## 🚨 Troubleshooting

### TLS/HTTPS Not Working
```bash
# Check Caddy logs
docker-compose logs caddy | grep -i error

# Verify DNS resolution
nslookup ide.kushnir.cloud

# Test ACME challenge
curl -I https://ide.kushnir.cloud/.well-known/acme-challenge/test
```

### OAuth2 Login Fails
```bash
# Check credentials
echo $GOOGLE_CLIENT_ID
echo $GOOGLE_CLIENT_SECRET

# View oauth2-proxy logs
docker-compose logs oauth2-proxy | grep -i error

# Test token endpoint
curl -X POST https://accounts.google.com/o/oauth2/token \
  -d "code=xxx&client_id=$GOOGLE_CLIENT_ID&..."
```

### LLM Models Not Available
```bash
# Check Ollama container running
docker-compose ps ollama

# Check model pull logs
docker-compose logs ollama-init

# Pull model manually
docker-compose exec ollama ollama pull llama2:70b-chat

# Monitor pull progress
watch docker stats ollama
```

### Agent API Not Starting
```bash
# Check Python dependencies
docker-compose logs agent-api | grep -i "import\|error"

# Verify all required services running
docker-compose up -d chroma keycloak ollama

# Wait for dependencies
docker-compose exec agent-api curl http://chroma:8000/api/v1/heartbeat
```

### High Memory Usage
```bash
# Check Ollama memory
docker stats ollama

# Adjust model memory
# Edit docker-compose.yml -> ollama.deploy.resources.limits.memory

# Use smaller models
OLLAMA_DEFAULT_MODEL=mistral docker-compose up -d
```

## 📝 Maintenance & Operations

### Daily Operations
```bash
# Monitor services
docker-compose ps

# Check logs for errors
docker-compose logs | grep -i error

# Backup data
tar -czf backup-$(date +%Y%m%d).tar.gz \
  caddy-data/ coder-data/ keycloak-db-data/ ollama-data/
```

### Model Management
```bash
# List installed models
curl http://localhost:11434/api/tags

# Remove unused model
curl -X DELETE http://localhost:11434/api/pull \
  -d '{"name": "mistral"}'

# Switch default model
# Edit .env -> OLLAMA_DEFAULT_MODEL
# Restart agent-api: docker-compose restart agent-api
```

### Scaling for Production

**Multi-GPU Setup**
```bash
# Edit docker-compose.yml
ollama:
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            count: 2        # Use 2 GPUs
            capabilities: [gpu]
```

**High Availability**
- Deploy multiple instances with load balancer
- Use managed PostgreSQL for Keycloak DB
- Shared volume for ChromaDB/embeddings data

## 🔄 CI/CD Integration

### GitHub Actions Workflow
See `.github/workflows/*.yml` for:
- Automated tests on code-server extensions
- Docker image builds & pushes
- Security scanning (Snyk)
- Deployment automation

### Deployment Pipeline
```bash
# Stage changes
git add .

# Commit with message
git commit -m "feat: Add new agent capability"

# Push to feature branch
git push origin feature/my-feature

# Create PR for review
# Automated tests run

# Merge to main
# Docker images built and pushed
# If needed: auto-deploy to production
```

## 📚 Additional Resources

- **VS Code**: https://code.visualstudio.com/docs
- **code-server**: https://coder.com/docs/code-server
- **Ollama**: https://ollama.ai
- **LangGraph**: https://langchain-ai.github.io/langgraph
- **Keycloak**: https://www.keycloak.org/documentation
- **MCP**: https://modelcontextprotocol.io

## 📞 Support & Issues

### Report Issues
1. Check troubleshooting guide above
2. Review service logs: `docker-compose logs [service]`
3. Open GitHub issue with:
   - Error logs
   - `docker-compose ps` output
   - Environment info (OS, Docker version, RAM)

### Community
- GitHub Discussions
- MCP Community: https://github.com/modelcontextprotocol
