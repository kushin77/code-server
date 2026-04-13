# Code-Server Enterprise: Deployment to 192.168.168.32

**Status**: Enhanced for remote SSH-based deployment  
**Default Target**: `192.168.168.32`  
**Updated**: April 14, 2026

---

## Prerequisites

### Local Development Machine
- Docker & Docker Compose
- SSH client with key-based authentication
- bash or PowerShell 7+
- Git

### Remote Host (192.168.168.32)
- Ubuntu 22.04 LTS (tested)
- Docker & Docker Compose pre-installed
- SSH daemon running (port 22)
- User: `akushnir` (or configured user)
- SSH key at: `/home/akushnir/.ssh/id_ed25519`
- Outbound internet access for image pulls
- Ports available: 22, 80, 443, 8080, 11434, 3000+

---

## Quick Deploy (Recommended)

### Option 1: Default (Remote to 192.168.168.32)

**Bash:**
```bash
cd /code-server-enterprise
./deploy-iac.sh
# Equivalent to: ./deploy-iac.sh --host 192.168.168.32 --user akushnir
```

**PowerShell:**
```powershell
cd C:\code-server-enterprise
pwsh .\deploy-iac.ps1
# Equivalent to: .\deploy-iac.ps1 -Host 192.168.168.32 -User akushnir
```

### Option 2: Custom Remote Host

**Bash:**
```bash
./deploy-iac.sh --host 192.168.168.32 --user akushnir --key ~/.ssh/id_ed25519 --port 22
```

**PowerShell:**
```powershell
.\deploy-iac.ps1 -Host 192.168.168.32 -User akushnir -KeyPath "$home\.ssh\id_ed25519" -Port 22
```

### Option 3: Local Development (No Remote)

**Bash:**
```bash
./deploy-iac.sh --local
```

**PowerShell:**
```powershell
.\deploy-iac.ps1 -Local
```

---

## Configuration

### Environment Variables (.env)

Create `.env` from template:
```bash
cp .env.template .env
```

**Key variables for 192.168.168.32 deployment:**

```env
# Domain for TLS/DNS
DOMAIN=ide.kushnir.cloud

# Default deployment target — change this to switch hosts
DEPLOY_HOST=192.168.168.32

# SSH credentials
DEPLOY_SSH_USER=akushnir
DEPLOY_SSH_KEY_PATH=/home/akushnir/.ssh/id_ed25519
DEPLOY_SSH_PORT=22

# OAuth2
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret
OAUTH2_PROXY_COOKIE_SECRET=auto-generated

# Security
CODE_SERVER_PASSWORD=change-me-in-prod
GITHUB_TOKEN=your-github-pat

# Workspace
WORKSPACE_PATH=/home/akushnir/workspace
```

---

## Deployment Flow

### Phase 1: Pre-flight Checks
- SSH connectivity verification
- Remote host Docker availability
- Network reachability

### Phase 2: Package & Upload
- Create deployment package locally
- `scp` all files to remote: `/home/{user}/code-server-deploy/`
- Verify file integrity

### Phase 3: Remote Execution
- SSH into 192.168.168.32
- Stop existing containers: `docker-compose down`
- Start fresh stack: `docker-compose up -d`
- Validate services: `docker-compose ps`

### Phase 4: Post-Deployment
- Service health checks
- Dashboard access validation
- Monitoring stack verification

---

## Architecture After Deployment

### Network Isolation
- **Caddy** (Reverse Proxy): Listens on 0.0.0.0:80, 0.0.0.0:443
- **OAuth2-Proxy**: Internal only (docker bridge 172.17.0.0/16)
- **Code-Server**: Internal only, accessed via oauth2-proxy
- **Services**: All internal except reverse proxy

### Access Methods
```
User Browser
    ↓
[202.168.168.32]:443 (Caddy/TLS)
    ↓
OAuth2-Proxy:4180 (Google Auth)
    ↓
Code-Server:8080 (Internal)
    ↓
Ollama:11434, Extensions, Fonts, etc.
```

### Proxy Domains (code-server-config.yaml)
```yaml
proxy-domain:
  - localhost              # Local development
  - 127.0.0.1             # Local development
  - 192.168.168.32        # Remote host
  - 192.168.168.31        # Legacy host
  - ide.kushnir.cloud     # DNS-based access
```

---

## Verification

### After Deployment Completes

**Via SSH:**
```bash
ssh akushnir@192.168.168.32
cd code-server-deploy
docker-compose ps
curl http://localhost:8080/healthz
```

**From Browser:**
```
https://ide.kushnir.cloud
  → Google OAuth redirect
  → Code-Server IDE
```

**Monitoring Dashboards:**
- Grafana: `http://localhost:3000/d/phase-15-slo` (port-forward if needed)
- Prometheus: `http://localhost:9090`
- AlertManager: `http://localhost:9093`

---

## Troubleshooting

### SSH Connection Fails
```bash
# Test SSH
ssh -i ~/.ssh/id_ed25519 akushnir@192.168.168.32 "echo OK"

# Verify key permissions
chmod 600 ~/.ssh/id_ed25519
chmod 700 ~/.ssh

# Check remote host SSH daemon
# ssh akushnir@192.168.168.32 "sudo systemctl status ssh"
```

### Docker Compose Upload Fails
```bash
# Ensure path exists on remote
ssh akushnir@192.168.168.32 "mkdir -p /home/akushnir/code-server-deploy"

# Verify disk space
ssh akushnir@192.168.168.32 "df -h /home"
```

### Containers Won't Start
```bash
# Check remote logs
ssh akushnir@192.168.168.32 "cd code-server-deploy && docker-compose logs -f"

# Verify environment variables
ssh akushnir@192.168.168.32 "cat code-server-deploy/.env"
```

### Google OAuth Not Working
- Verify `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `.env`
- Check Cloudflare Tunnel configuration
- Ensure domain DNS points to 192.168.168.32

---

## Security Recommendations

### Pre-Production
- [ ] Change `CODE_SERVER_PASSWORD` to strong value
- [ ] Rotate `OAUTH2_PROXY_COOKIE_SECRET`
- [ ] Update `GITHUB_TOKEN` (use classic PAT with minimal scopes)
- [ ] Restrict 192.168.168.32 inbound to known IPs (firewall)
- [ ] Enable SSH key-only authentication (disable passwords)
- [ ] Implement network segmentation (VPC, security groups)

### Runtime
- [ ] Monitor container logs for errors
- [ ] Set up log rotation for docker-compose output
- [ ] Enable Grafana alerts for SLO breaches
- [ ] Regular backup of `coder-data` volume
- [ ] Weekly security patches for base images

### Deployment
- [ ] Never commit `.env` to version control
- [ ] Use Git Secrets scanning for credentials
- [ ] Implement GitOps for configuration management
- [ ] Maintain deployment playbooks in private repo

---

## Rollback Procedure

If deployment fails and you need to restore previous state:

```bash
# SSH to remote host
ssh akushnir@192.168.168.32

# Backup current state
cd code-server-deploy
docker-compose down
mv docker-compose.yml docker-compose.yml.failed-backup

# Restore from last known-good state
git checkout docker-compose.yml  # If tracked in git
# OR
cp docker-compose.yml.previous docker-compose.yml

# Restart with previous configuration
docker-compose up -d
docker-compose ps
```

---

## Performance Tuning

### For 192.168.168.32 (8-core, 16GB RAM)

Update `docker-compose.yml`:
```yaml
code-server:
  deploy:
    resources:
      limits:
        memory: 6g
        cpus: '3.0'
      reservations:
        memory: 2g
        cpus: '0.5'

ollama:
  environment:
    OLLAMA_NUM_THREAD: 6
    OLLAMA_NUM_GPU: 0  # Set to 1 if GPU available
```

### Node.js Optimization
```env
NODE_OPTIONS=--enable-source-maps --max-old-space-size=4096 --max-http-header-size=16384
```

---

## Support & Escalation

### Common Commands (Remote)

```bash
# SSH into deployment
ssh akushnir@192.168.168.32

# Check service status
docker-compose -f ~/code-server-deploy/docker-compose.yml ps

# View logs
docker-compose -f ~/code-server-deploy/docker-compose.yml logs -f caddy
docker-compose -f ~/code-server-deploy/docker-compose.yml logs -f code-server

# Restart services
docker-compose -f ~/code-server-deploy/docker-compose.yml restart

# Full redeploy
cd ~/code-server-deploy
docker-compose down
docker-compose pull
docker-compose up -d
```

### Contact
- **Team**: infrastructure@kushnir.cloud
- **Issues**: https://github.com/kushin77/code-server/issues
- **Status**: https://status.kushnir.cloud

---

**Last Updated**: April 14, 2026  
**Maintained By**: Platform Engineering  
**Next Review**: May 14, 2026
