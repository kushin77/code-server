# Replica Node (192.168.168.42) Sync Status Report

## Current Status: BLOCKED ⛔
**Date**: April 25, 2026  
**Issue**: SSH Connection Reset by Peer  
**Severity**: P1 - Blocks failover and cluster redundancy

## Diagnosis
- **Network Connectivity**: PASS (ping responds)
- **SSH Port**: OPEN (port 22 responds)
- **SSH Handshake**: FAIL (Connection reset by peer during SSH protocol exchange)
- **Probable Causes**:
  1. SSH service not running on replica host
  2. SSH configuration corrupted (`/etc/ssh/sshd_config`)
  3. Host firewall or fail2ban blocking connection attempts
  4. SSH authorized_keys missing or corrupted

## Required Actions

### Immediate (Requires Local Access to .42 Host)
```bash
# 1. SSH to console/IPMI directly (not via SSH from .31)
# 2. Check SSH service status
systemctl status ssh

# 3. Check SSH configuration
sshd -t

# 4. Check authorized_keys
cat ~/.ssh/authorized_keys

# 5. Review fail2ban logs if applicable
grep ssh /var/log/fail2ban.log
```

### Recovery Steps
1. Restart SSH service: `systemctl restart ssh`
2. Restore SSH config: `ssh-keygen -A`
3. Reload SSH: `systemctl reload ssh`
4. Verify: `ssh -i ~/.ssh/id_rsa_onprem_wsl akushnir@192.168.168.42 "hostname"`

### Prevention (For IaC)
Once recovered, add to Terraform:
```hcl
# Replicate SSH hardening config to both hosts
# Add SSH monitoring and auto-recovery checks
# Implement periodic SSH connectivity validation
```

## Follow-up
- [ ] Schedule manual console access to .42 host
- [ ] Implement SSH health check in monitoring
- [ ] Document SSH recovery procedure in playbooks/
- [ ] Add SSH key backup to NAS (192.168.168.56)

---
**Tracker**: See GITHUB ISSUE tracking synchronization delays due to SSH outage
**Managed By**: Terraform (IaC) + Manual Console Access (required)
