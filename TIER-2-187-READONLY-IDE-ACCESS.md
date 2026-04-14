# Tier 2 #187: Read-Only IDE Access Implementation

**Status:** In Progress  
**Effort:** 4 hours  
**Dependencies:** #185 (Cloudflare Tunnel) ✅ COMPLETED  
**Owner:** Platform Team  
**Target Completion:** April 15, 2026

## Overview

Implement read-only access mode for code-server IDE that allows developers to:
- ✅ Edit and create files in project directories
- ✅ Run code and tests within the IDE
- ✅ Use git via secure proxy (no SSH keys locally)
- ❌ Execute arbitrary system commands
- ❌ Escape the sandbox to access sensitive system areas
- ❌ Download or exfiltrate data via curl/wget

### Security Model

Developers work in a **sandboxed IDE** with:
- Restricted shell (no dangerous commands)
- Whitelisted file paths (only ~/projects, ~/dev)
- No privilege escalation (no sudo/su)
- No network escapes (nc, netcat blocked)
- All operations logged and audited
- SSH key never exposed to developer machine

```
Developer                Code-Server IDE              Linux Filesystem
(remote)          (Restricted Shell)                 (Protected)
   |                    |                                 |
   +-- Cloudflare ----->+                                 |
   |   Tunnel        Edit Code ✅                         |
   |  (encrypted)        |---> Read ~/projects/  ✅      |
   |               Run Tests ✅                           |
   |               Run Code ✅                      Read-only
   |               Git (via proxy) ✅              /etc, /sys, /var
   |                    |                           |
   |               Block wget ❌                    Protected
   |               Block scp ❌             (no exfiltration)
   |               Block sudo ❌
   |               Block docker ❌
   +-------- Audit Log ---------> /var/log/ide-access-audit.log
```

## Implementation Steps

### Step 1: Create Restricted Shell Wrapper

**File:** `scripts/ide-access-restrictions.sh`  
**Status:** ✅ CREATED

Features:
- Blocks 20+ dangerous commands (wget, curl, scp, sudo, nc, etc.)
- Whitelist filesystem access (only ~/projects, ~/dev)
- Bash DEBUG trap to intercept command execution
- Comprehensive audit logging
- User-friendly error messages with explanations

Restricted Commands:
```
wget, curl, fetch           - File downloads
scp, sftp, rcp             - File transfers
nc, netcat, socat, ssh-keyscan - Network operations
sudo, su                   - Privilege escalation
apt, yum, pacman, brew     - Package installation
docker, podman             - Container execution
gpg, openssl               - Cryptographic operations
nmap, netstat, ss          - Network reconnaissance
strace, ltrace, gdb        - Process introspection
```

### Step 2: Configure Code-Server Shell Integration

**File:** Create `code-server-restricted-shell.sh`

```bash
#!/usr/bin/env bash
# code-server shell wrapper

# Source the restricted shell environment
source /opt/ide-access/ide-access-restrictions.sh

# Configure for code-server
export CODE_SERVER_SESSION=1
export SHELL=/opt/ide-access/ide-access-restrictions.sh

# Optional: Mount read-only namespaces (requires unshare)
# This is stronger security at the cost of complexity
# For MVP, software restrictions are sufficient

# Start code-server with restricted shell
exec code-server \
    --auth=none \
    --bind-addr=127.0.0.1:8080 \
    --extensions-dir=/home/dev/.vscode/extensions \
    --user-data-dir=/home/dev/.vscode \
    "$@"
```

### Step 3: Integrate with Cloudflare Tunnel

**Update:** `Caddyfile`

```caddyfile
ide.dev.yourdomain.com {
    # Restrict to authenticated users
    forward_auth 127.0.0.1:23500 {
        uri /verify
        copy_headers Cf-Access-Jwt-Assertion
    }
    
    reverse_proxy 127.0.0.1:8080 {
        header_uri / /
        websocket
    }
}
```

### Step 4: Deploy and Configure

**Installation:**

```bash
# Copy script to home server
sudo cp scripts/ide-access-restrictions.sh /opt/ide-access/ide-access-restrictions.sh
sudo chmod 755 /opt/ide-access/ide-access-restrictions.sh

# Create log directory
sudo mkdir -p /var/log
sudo touch /var/log/ide-access-audit.log
sudo chmod 666 /var/log/ide-access-audit.log

# Create code-server wrapper
sudo cp scripts/code-server-restricted-shell.sh /usr/local/bin/code-server-restricted
sudo chmod 755 /usr/local/bin/code-server-restricted

# Update systemd service
sudo systemctl edit code-server-ide.service
```

**Systemd Service:**

```ini
[Unit]
Description=Code-Server IDE with Restricted Shell
After=network.target cloudflared.service
Wants=cloudflared.service

[Service]
Type=simple
User=dev
ExecStart=/usr/local/bin/code-server-restricted

# Security hardening
PrivateTmp=yes
NoNewPrivileges=true
ReadWritePaths=/home/dev/projects /home/dev/dev /tmp

# Restart policy
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Security Layers

### Layer 1: Shell Restrictions (Software)

- Bash DEBUG trap intercepts every command
- Checks against restricted command list
- Blocks with error message + audit log
- Allows legitimate operations (git, grep, ls, etc.)

### Layer 2: Filesystem Restrictions (Whitelist)

- Only allow writes to: `~/projects/`, `~/dev/`, `/tmp/code-server-pid`
- Only allow reads from: code files, config files, /usr/share (system), /etc/hostname
- Block access to: SSH keys, credentials, system files, other users' data

### Layer 3: Process Isolation (Optional - Phase 2)

- Use `unshare` to create kernel namespace
- Mount home directory read-only except whitelisted paths
- Fully filesystem-level enforcement (stronger but more complex)

```bash
# Phase 2 enhancement:
sudo unshare --mount --ipc --pid -- \
    bash -c 'mount --rbind /home/dev/projects /home/dev/projects
             mount --rbind /tmp /tmp
             mount -o remount,ro /
             exec code-server'
```

### Layer 4: Network Isolation

- No direct network access (all traffic via Cloudflare)
- DNS resolver restricted
- Can't open raw sockets or create tunnels
- Can only make outbound connections via proxy

## Testing

### Test 1: Restricted Commands Are Blocked

```bash
# SSH into dev machine
ssh dev@192.168.168.31

# Try blocked commands (all should fail with helpful error)
wget https://example.com
# ❌ Error: Command 'wget' is not allowed in read-only IDE mode

sudo whoami
# ❌ Error: Command 'sudo' is not allowed in read-only IDE mode

curl http://example.com
# ❌ Error: Command 'curl' is not allowed in read-only IDE mode

nc -l 4444
# ❌ Error: Command 'nc' is not allowed in read-only IDE mode
```

### Test 2: Allowed Operations Work

```bash
# Edit code
code ~/projects/code-server/src/index.ts

# Run git
git push origin feature-branch
# ✅ Proxied through git-proxy-server with audit

# Run tests
npm test
# ✅ Runs within sandbox

# Grep and find
grep -r "function foo" .
# ✅ Works normally

# Create/edit files
cat > readme.md << 'EOF'
# My Project
EOF
# ✅ Works in allowed directories
```

### Test 3: File Access Restrictions

```bash
# Allowed: Write to projects
touch ~/projects/test.txt
# ✅ Success

# Blocked: Write to system files
touch /etc/my-config
# ❌ Error: Cannot modify '/etc/my-config'

# Allowed: Read config
cat /etc/hostname
# ✅ Returns hostname

# Allowed: Read system info
cat /proc/cpuinfo | grep "cpu cores"
# ✅ Returns CPU info
```

### Test 4: Audit Logging

```bash
# Check audit log after test operations
tail -50 /var/log/ide-access-audit.log

# Expected output:
# 2026-04-15T10:30:45Z | dev | 203.0.113.42 | wget | BLOCKED
# 2026-04-15T10:30:46Z | dev | 203.0.113.42 | git push | ALLOWED
# 2026-04-15T10:30:47Z | dev | 203.0.113.42 | npm test | ALLOWED
```

### Test 5: Interactive IDE Test

```bash
# Access via Cloudflare Tunnel
open https://ide.dev.yourdomain.com

# In VS Code terminal:
1. Try to create file: /etc/passwd
   # ❌ Permission denied

2. Try to git push
   # ✅ Works via proxy

3. Try npm test
   # ✅ Test runs successfully

4. Try to create ~/projects/test.ts
   # ✅ File created successfully
```

## Rollback Plan

If restrictions cause issues:

```bash
# 1. Disable restrictions
sudo systemctl stop code-server-ide.service
sudo mv /opt/ide-access/ide-access-restrictions.sh /opt/ide-access/ide-access-restrictions.sh.disabled

# 2. Use unrestricted code-server (temporary - not for production)
code-server --auth=none --bind-addr=127.0.0.1:8080

# 3. Investigate audit logs
tail -200 /var/log/ide-access-audit.log

# 4. Re-enable after fixes
sudo mv /opt/ide-access/ide-access-restrictions.sh.disabled /opt/ide-access/ide-access-restrictions.sh
sudo systemctl start code-server-ide.service
```

## Success Metrics

✅ **Completion Criteria:**
- [x] Restricted shell wrapper script created
- [x] 20+ dangerous commands blocked effectively
- [x] Filesystem whitelist enforced
- [ ] Code-server integration tested by 2+ developers
- [ ] Zero successful escapes from sandbox in 24 hours
- [ ] Audit logs generated correctly for all operations
- [ ] Performance impact <5% vs unrestricted IDE

## Documentation

**For Developers:**
- Getting started guide for code-server IDE access
- Supported operations and limitations
- How to use git proxy for push/pull
- Common error messages and solutions

**For Admins:**
- Troubleshooting guide for escape attempts
- How to analyze audit logs
- Procedure for adding developers
- Procedure for emergency access (if needed)

## Related Issues

### Phase 2: Enhanced Security (Future)

- [ ] #188: Kernel namespace isolation (mount ns, ipc ns)
- [ ] #189: Container-based IDE sandboxing (stricter)
- [ ] #190: Network monitoring and alerting
- [ ] #191: Automated security testing (pentest)

## Related Documents

- [ADR-001: Cloudflare Tunnel Architecture](../ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md)
- [Tier 2 #184: Git Proxy Implementation](../TIER-2-184-GIT-PROXY-IMPLEMENTATION.md)
- [Developer Onboarding](../DEV_ONBOARDING.md)
