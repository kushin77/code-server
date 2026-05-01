# SSH Service Repair Guide - 192.168.168.42
**Date:** April 25, 2026  
**Issue:** SSH daemon on Replica 2 (.42) broken - resets all new connections during key exchange  
**Status:** Requires host-level access (console/IMPI/direct)

## Problem Summary
- ✅ Network: Operational (ping works)
- ✅ TCP port 22: Listening and accepting connections  
- ❌ SSH handshake: **Connection reset by peer** during key exchange
- ❌ Cannot SSH into .42 to execute repairs

## Diagnostic Evidence
```bash
# From .31 or local workstation:
$ ssh -vvv akushnir@192.168.168.42
OpenSSH_9.6p1
debug1: Connection established
debug1: Local version string SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.15
kex_exchange_identification: read: Connection reset by peer
Connection reset by 192.168.168.42 port 22
```

## Root Cause Analysis
The SSH daemon is:
1. Running and listening on port 22
2. Accepting TCP connections
3. **Failing during SSH protocol key exchange**

This pattern indicates:
- **Most likely**: Corrupted SSH host keys (`/etc/ssh/ssh_host_*`)
- **Also possible**: SSH daemon crash, OOM condition, or kernel reset

## Repair Procedures

### Option 1: Restart SSH Service (Recommended First Try)
Requires: Console, IPMI/BMC, or remote management access

```bash
# SSH to .42 via console/IPMI:
ssh akushnir@192.168.168.42

# Or via direct terminal if you have IPMI/console:
sudo systemctl restart ssh

# Verify:
sudo systemctl status ssh
ps aux | grep sshd

# Test from another host:
ssh -v akushnir@192.168.168.42 'echo SSH_RESTORED'
```

### Option 2: Regenerate SSH Host Keys
If restart doesn't work, the host keys are likely corrupted:

```bash
# Via console/IPMI:
sudo ssh-keygen -A  # Regenerates all missing/corrupted host keys

# Or manually:
sudo rm /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server
sudo systemctl restart ssh

# Verify keys exist:
ls -lh /etc/ssh/ssh_host_*
```

### Option 3: Full SSH Daemon Reset
If regenerating keys doesn't work:

```bash
# Via console/IPMI:
sudo apt-get install --reinstall openssh-server

# Or purge and reinstall:
sudo apt-get purge openssh-server
sudo apt-get install openssh-server

# Start service:
sudo systemctl start ssh
sudo systemctl enable ssh

# Verify:
sudo systemctl status ssh
```

### Option 4: Reboot Host (Last Resort)
If above steps fail:

```bash
# Via console/IPMI:
sudo systemctl reboot

# Or via systemctl:
sudo reboot

# Wait ~2 minutes for full restart, then test:
ssh akushnir@192.168.168.42 'echo SSH_ALIVE'
```

## Verification Steps

After applying any repair, verify from .31 or local workstation:

```bash
# 1. Network connectivity
ping -c 2 192.168.168.42

# 2. TCP port 22 open
nc -zv 192.168.168.42 22

# 3. SSH service responding
ssh-keyscan -T 5 192.168.168.42

# 4. SSH authentication
ssh -v akushnir@192.168.168.42 'echo SSH_WORKS'

# 5. From .31, test chain:
ssh akushnir@192.168.168.31 'ssh akushnir@192.168.168.42 id'
```

## Expected Output - SSH Service Healthy

```
# ssh-keyscan output should show banner:
# 192.168.168.42 SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.15

# SSH login should succeed:
$ ssh akushnir@192.168.168.42 'id'
uid=1000(akushnir) gid=1000(akushnir) groups=1000(akushnir),4(adm),27(sudo),117(docker)
```

## Post-Repair Verification

Once SSH is working:

```bash
# 1. Verify service is stable:
ssh akushnir@192.168.168.42 'uptime'
ssh akushnir@192.168.168.42 'docker ps' # Should show running containers

# 2. Sync latest code if needed:
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git pull origin main'

# 3. Check cluster parity:
ssh akushnir@192.168.168.42 'docker-compose --version && docker-compose config --quiet'

# 4. Verify replication cluster status:
ssh akushnir@192.168.168.31 'ssh akushnir@192.168.168.42 docker ps | grep -E "postgres|redis|caddy"'
```

## Failure Escalation

If none of the above work, SSH service is critically broken and requires:
1. **Physical host access** - Power cycle via PDU
2. **IPMI/BMC reset** - If available
3. **Host rebuild** - Redeploy OS image if available
4. **Contact infrastructure team** - Host may need hardware diagnostics

## Related Issues

- **#1645**: Previous SSH/.42 replica issue (CLOSED - all prior fixes applied)
- **Epic #1616**: Multi-replica cluster parity (depends on this fix)

## Session Info
- User report: April 25, 2026 - existing connections alive but new connections blocked
- Diagnosis date: April 25, 2026
- Diagnostic method: SSH verbose testing from .31, port scanning, service probing
