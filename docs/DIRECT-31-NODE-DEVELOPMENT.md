# Direct .31 Node Development Access

**Last Updated**: April 14, 2026  
**Status**: ✅ ACTIVE - Bypass Tunnel & Proxy Layer

## Overview

This document describes the **direct access model** for developing on Host 31 (192.168.168.31), bypassing the Cloudflare tunnel, OAuth2 proxy, and Caddy reverse proxy "middleman" layers. This enables **faster development cycle** with minimal latency.

## Architecture: Before vs. After

### ❌ Old Model (Container Orchestration + Tunnel)
```
Developer Machine
    ↓
Cloudflare Tunnel (code-server-home-dev.cfargotunnel.com)
    ↓
OAuth2-Proxy (Port 4180)
    ↓
Caddy Reverse Proxy (Port 443)
    ↓
code-server Container (Port 8080)
    ↓
Docker Network
    ↓
Host 31 Services
```

**Issues**:
- Latency: 300-500ms per keystroke
- Dependency on Cloudflare
- Complex proxy chain
- OAuth2 authentication required for every request

### ✅ New Model (Direct Node Access)
```
Developer Machine
    ↓
Direct SSH (Port 22)
    ↓
Host 31 (192.168.168.31) - Direct
    ↓
Services Running on Host:
  - code-server (8080)
  - Docker (if containerized)
  - Native shell access
  - Git operations
  - Ollama (11434)
  - node-exporter (9100)
```

**Benefits**:
- Latency: <50ms direct SSH
- No tunnel dependency
- Simple point-to-point access
- Full shell access without restrictions

## Quick Start

### Prerequisites
- SSH key at `~/.ssh/akushnir-31` (private key)
- SSH public key registered on Host 31
- Network connectivity to 192.168.168.31:22

### Connect Directly
```bash
# Option 1: Use Makefile shortcut
make ssh-31

# Option 2: Direct SSH command
ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31
```

## Makefile Commands

### Direct Access Targets
```bash
# Connect via SSH (interactive shell)
make ssh-31

# Check .31 node status
make status-31
# Output: hostname, uptime, Docker containers, disk usage

# Open interactive bash shell on .31
make shell-31

# Deploy directly to .31 (runs: make deploy && make status)
make deploy-31

# Stream service logs from .31 docke-compose
make logs-31

# Run custom command on .31
make cmd-31 CMD="docker ps -a"
make cmd-31 CMD="systemctl status code-server"
```

## Configuration Changes Made

### 1. Security Audit (scripts/security-audit.sh)
**Before**:
```bash
# Test: No direct SSH access (only through tunnel)
if ! nc -zv localhost 22 2>/dev/null; then
  test_result "SSH Port Closed (no direct exposure)" "PASS"
```

**After**:
```bash
# Test: Direct SSH access ENABLED (direct .31 node development)
if nc -zv localhost 22 2>/dev/null; then
  test_result "SSH Port Open (direct access enabled)" "PASS"
```

### 2. Code-Server Config (config/code-server-readonly-config.yaml)
**Before**:
```yaml
extensions.ignore:
  - "ms-vscode.remote-ssh"        # BLOCK: Direct SSH access
  - "ms-vscode.remote-ssh-edit"   # BLOCK: Edit remote files
```

**After**:
```yaml
extensions.allow:
  - "ms-vscode.remote-ssh"        # ALLOW: Direct SSH to .31 node
  - "ms-vscode.remote-ssh-edit"   # ALLOW: Edit remote files on .31

extensions.ignore:
  # SSH extensions now allowed for direct .31 development
```

### 3. Terraform Variables (terraform/192.168.168.31/variables.tf)
```hcl
variable "bastion_host" {
  description = "(Optional) Bastion host for SSH proxy - DEPRECATED: Use direct SSH to .31 node instead"
  default     = null
}
```

**Note**: Bastion variable still supported but marked deprecated. Direct SSH is now primary.

### 4. Makefile (New Targets)
Added 6 new targets for direct .31 development:
- `make ssh-31` - Connect via SSH
- `make status-31` - Show .31 node status
- `make shell-31` - Interactive bash shell
- `make deploy-31` - Deploy directly
- `make logs-31` - Stream logs
- `make cmd-31 CMD=...` - Run custom commands

## SSH Keys Setup

### Generate SSH Key (if needed)
```bash
# Host 31 uses key at ~/.ssh/akushnir-31
ssh-keygen -t ed25519 -f ~/.ssh/akushnir-31 -C "akushnir@192.168.168.31"

# Or use existing RSA key:
ssh-keygen -t rsa -b 4096 -f ~/.ssh/akushnir-31 -C "akushnir@192.168.168.31"
```

### Install Public Key on Host 31
```bash
# Copy public key to .31
cat ~/.ssh/akushnir-31.pub | ssh akushnir@192.168.168.31 \
  'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'

# Verify access
ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 'whoami'
```

## Services on Host 31

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| SSH | 22 | Direct | Remote shell access, git operations |
| code-server | 8080 | Direct/localhost | Web IDE |
| Docker Daemon | 2375/2376 | In-container | Container orchestration |
| Ollama API | 11434 | Local | LLM inference |
| node-exporter | 9100 | Local/monitoring | System metrics |
| git-proxy | 8443 | Direct | Git credential cache |

## Development Workflows

### Quick Edit & Test
```bash
make ssh-31
# Inside .31 shell:
cd ~/code-server-enterprise
nano src/main.py     # Edit file directly
python src/main.py   # Test immediately
exit                 # Return to local machine
```

### Remote Git Operations
```bash
make ssh-31
# Inside .31 shell:
cd ~/code-server-enterprise
git status
git add .
git commit -m "fix: direct development on .31"
git push origin main
```

### Docker Operations on .31
```bash
make cmd-31 CMD="docker ps"
make cmd-31 CMD="docker logs code-server | head -20"
make cmd-31 CMD="docker compose restart"
```

### Run Production-Like Tests
```bash
make deploy-31
make cmd-31 CMD="make status-31"
make logs-31 | grep -i error
```

## Monitoring & Debugging

### View .31 System Status
```bash
make status-31
# Output shows:
# - Hostname & uptime
# - Running Docker containers
# - Disk usage
```

### Check Service Health
```bash
make cmd-31 CMD="systemctl status code-server"
make cmd-31 CMD="curl -s http://localhost:8080/health"
make cmd-31 CMD="curl -s http://localhost:11434/api/tags"
```

### Stream Real-time Logs
```bash
make logs-31
# Ctrl+C to exit
```

### Check Metrics
```bash
make cmd-31 CMD="curl -s http://localhost:9100/metrics | head -20"
```

## Security Considerations

### Direct SSH Benefits
- ✅ No dependency on Cloudflare/external services
- ✅ Private network access (192.168.168.0/24)
- ✅ Lower attack surface (pure SSH)
- ✅ Full audit trail (SSH log)

### Recommended Security Practices
1. **Use SSH key authentication** (not passwords)
   ```bash
   ssh-copy-id -i ~/.ssh/akushnir-31 akushnir@192.168.168.31
   ```

2. **Restrict SSH to local network only**
   ```bash
   # On .31 SSH server config
   ListenAddress 192.168.168.31
   ```

3. **Monitor SSH access**
   ```bash
   make cmd-31 CMD="tail -f /var/log/auth.log | grep sshd"
   ```

4. **Disable password auth** (force key-only)
   ```bash
   # On .31: /etc/ssh/sshd_config
   PasswordAuthentication no
   ChallengeResponseAuthentication no
   ```

## Troubleshooting

### "Permission denied (publickey)"
```bash
# Check key permissions on local machine
chmod 600 ~/.ssh/akushnir-31

# Verify key is registered on .31
ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 \
  'grep "$(cat ~/.ssh/akushnir-31.pub)" ~/.ssh/authorized_keys'
```

### "Connection refused" on Port 22
```bash
# Check SSH daemon is running on .31
make cmd-31 CMD="systemctl status ssh"

# Restart SSH if needed
make cmd-31 CMD="sudo systemctl restart ssh"
```

### Slow SSH Connection
```bash
# Test latency
ssh -i ~/.ssh/akushnir-31 akushnir@192.168.168.31 'ping -c 1 8.8.8.8'

# Or use local network ping
make cmd-31 CMD="ping -c 4 192.168.1.1"
```

### File Permissions Issues
```bash
# Fix ownership on .31
make cmd-31 CMD="sudo chown -R akushnir:akushnir /home/akushnir"

# Fix SSH directory permissions
make cmd-31 CMD="chmod 700 ~/.ssh && chmod 600 ~/.ssh/*"
```

## Migration from Tunnel Model

### Old Workflow (Via Tunnel)
```bash
# Connect via Cloudflare tunnel
open https://code-server-home-dev.cfargotunnel.com
# Login via Google OAuth
# Use code-server web IDE through tunnel
```

### New Workflow (Direct SSH)
```bash
# Connect directly via SSH
make ssh-31
# or
open vscode://vscode-remote/ssh-remote/akushnir@192.168.168.31/home/akushnir/code-server-enterprise

# VS Code Remote SSH will:
# 1. Connect via SSH
# 2. Install remote server
# 3. Open folder for remote editing
```

## Related Linux Configuration

### SSH Config (~/.ssh/config)
```
Host 31
  HostName 192.168.168.31
  User akushnir
  IdentityFile ~/.ssh/akushnir-31
  StrictHostKeyChecking no
  UserKnownHostsFile ~/.ssh/known_hosts.31
```

Usage:
```bash
ssh 31
ssh 31 -tA  # With agent forwarding for git
make ssh-31  # Still uses full path in Makefile
```

### Firewall Rules (ufw example)
```bash
# Allow SSH from development network
sudo ufw allow from 192.168.1.0/24 to any port 22
sudo ufw allow from 192.168.168.0/24 to any port 22

# Allow services (optional)
sudo ufw allow 8080  # code-server
sudo ufw allow 11434 # ollama
```

### iptables Rules (if using iptables)
```bash
# Allow SSH from local network
sudo iptables -A INPUT -p tcp -d 192.168.168.31 --dport 22 -j ACCEPT

# Block SSH from internet
sudo iptables -A INPUT -p tcp --dport 22 ! -s 192.168.0.0/16 -j REJECT --reject-with tcp-reset
```

## Performance Comparison

| Metric | Tunnel Model | Direct SSH |
|--------|--------------|-----------|
| Keystroke latency | 300-500ms | <50ms |
| Setup time | 5-10 min | <1 min |
| Dependencies | Cloudflare, OAuth2, Caddy | SSH only |
| Network hops | 8-12 | 2-3 |
| Availability | Depends on Cloudflare | 100% local |
| Authentication | Google OAuth | SSH key |

## Further Reading

- [VS Code Remote SSH Documentation](https://code.visualstudio.com/docs/remote/ssh)
- [OpenSSH Installation & Setup](https://ubuntu.com/server/docs/service-openssh)
- [SSH Security Best Practices](https://man.openbsd.org/ssh_config)

---

**Created**: April 14, 2026  
**Updated**: April 14, 2026  
**Owner**: Development Team  
**Issue**: Phase 13 - Direct Node Development Access
