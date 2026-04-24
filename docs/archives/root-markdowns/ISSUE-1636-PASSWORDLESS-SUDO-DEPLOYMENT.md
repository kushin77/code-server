# Issue #1636: Configure Passwordless Sudo for Deployment Operations

**Status**: IMPLEMENTATION READY  
**Priority**: P1 (Infrastructure Blocker)  
**Date**: April 23, 2026

## Problem

SSH non-interactive deployment commands fail when sudo requires password prompt:

```bash
sudo: a terminal is required to read the password; either use the -S option to read from standard input
```

This blocks:
- ✗ Automated failover operations (Issue #1641 reboot blocked)
- ✗ Scripted deployments via CI/CD
- ✗ Health check automation
- ✗ Infrastructure recovery scripts

## Root Cause

The `akushnir` user lacks `NOPASSWD` sudo configuration in `/etc/sudoers.d/`

## Solution

Add passwordless sudo entry for `akushnir` user on both replicas:

### Affected Hosts
- **Replica 1**: 192.168.168.31
- **Replica 2**: 192.168.168.42

### Implementation Steps

#### Step 1: Manual Deployment (First Time Only)

**On Replica 1 (192.168.168.31):**

```bash
ssh akushnir@192.168.168.31
# At password prompt, enter your sudo password

# Create sudoers.d entry
sudo bash -c 'cat > /etc/sudoers.d/akushnir << EOF
# Passwordless sudo for deployment automation
akushnir ALL=(ALL) NOPASSWD: ALL
EOF'

# Fix permissions (required by sudoers)
sudo chmod 0440 /etc/sudoers.d/akushnir

# Verify configuration works
sudo -n true && echo "✅ Passwordless sudo working" || echo "❌ Failed"

# Exit SSH
exit
```

**On Replica 2 (192.168.168.42):**

```bash
ssh akushnir@192.168.168.42
# At password prompt, enter your sudo password

# Create sudoers.d entry
sudo bash -c 'cat > /etc/sudoers.d/akushnir << EOF
# Passwordless sudo for deployment automation
akushnir ALL=(ALL) NOPASSWD: ALL
EOF'

# Fix permissions
sudo chmod 0440 /etc/sudoers.d/akushnir

# Verify
sudo -n true && echo "✅ Passwordless sudo working" || echo "❌ Failed"

# Exit SSH
exit
```

#### Step 2: Automated Deployment (After Initial Setup)

Once passwordless sudo is configured, run:

```bash
# From local machine (Windows, Linux, Mac with git bash)
bash scripts/ops/configure-passwordless-sudo.sh
```

This will verify and maintain passwordless sudo configuration on both replicas.

#### Step 3: Verification

Test passwordless sudo on both replicas:

```bash
ssh akushnir@192.168.168.31 "sudo reboot"  # Should execute without prompt
ssh akushnir@192.168.168.42 "sudo -n true" # Should return exit code 0
```

## Files Delivered

1. **scripts/ops/configure-passwordless-sudo.sh** (NEW)
   - Automated verification and configuration script
   - Tests connectivity before attempting configuration
   - Provides detailed logging of each step

2. **etc/sudoers.d/akushnir** (NEW)
   - Sudoers configuration template
   - Ready to be deployed to both replicas
   - Includes security notes for production hardening

## Security Considerations

### Current Configuration (Permissive)
```bash
akushnir ALL=(ALL) NOPASSWD: ALL
```

**Risk**: Full unrestricted sudo without password  
**Mitigation**: Restrict to specific commands for production:

```bash
akushnir ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/docker-compose, \
    /bin/systemctl, /sbin/reboot, /sbin/poweroff, \
    /bin/journalctl, /usr/bin/cgroups-ls
```

### Recommended Production Hardening

Restrict `akushnir` to only commands needed for deployments:

```bash
# Core deployment commands
akushnir ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/docker-compose

# System operations
akushnir ALL=(ALL) NOPASSWD: /bin/systemctl, /sbin/reboot, /sbin/poweroff, /sbin/shutdown

# Diagnostics and logging
akushnir ALL=(ALL) NOPASSWD: /bin/journalctl, /usr/bin/systemctl

# Network operations (if needed)
akushnir ALL=(ALL) NOPASSWD: /sbin/ip, /sbin/iptables, /usr/bin/netstat
```

## Deployment Impact

### Unlocks Automation
✅ Issue #1641 (Replica 2 reboot automation)  
✅ Failover automation (automatic host restart)  
✅ Health check scripts  
✅ Scripted deployments

### No Service Downtime
- Configuration change does not affect running containers
- No restart required
- Changes take effect immediately

## Rollback Procedure

If needed, revert passwordless sudo:

```bash
ssh akushnir@192.168.168.31 "sudo rm /etc/sudoers.d/akushnir"
ssh akushnir@192.168.168.42 "sudo rm /etc/sudoers.d/akushnir"
```

## Testing

### Test 1: Verify sudo works without password

```bash
ssh akushnir@192.168.168.31 "sudo -n true"
echo $?  # Should return 0 (success)
```

### Test 2: Execute privileged command

```bash
ssh akushnir@192.168.168.31 "sudo docker ps"
# Should list containers without password prompt
```

### Test 3: Reboot automation (Issue #1641 blocker removal)

```bash
# This should now work without prompting for password
ssh akushnir@192.168.168.42 "sudo reboot"
```

## Closes Issues

- ✅ #1636 - Configure passwordless sudo for deployment operations
- ✅ Unblocks #1641 - Allows automated Replica 2 reboot
- ✅ Unblocks #1637 - Enables scripted /etc/fstab sync

## Next Steps

1. **Manual Setup** (First time):
   - SSH into each replica (192.168.168.31, .42)
   - Execute sudoers configuration steps above
   - Verify with sudo -n test

2. **Verify Unblocking**:
   - Test Replica 2 reboot automation (Issue #1641)
   - Run infrastructure sync script (Issue #1637)
   - Verify cluster parity achievable

3. **Close Issue**:
   - Add verification evidence to GitHub issue comment
   - Mark issue as CLOSED

---

**Priority**: This is a MUST-HAVE for cluster operations automation. Configure immediately to unblock failover and infrastructure management.
