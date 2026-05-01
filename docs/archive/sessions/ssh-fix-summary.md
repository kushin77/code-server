# SSH Connectivity Issue - Investigation Complete

**Date**: April 25, 2026  
**Status**: Investigation & Documentation Complete - Remediation Prepared  
**GitHub Issue**: #1784 (P1 - SSH service broken on Replica 2)

---

## Executive Summary

Your SSH connection to **192.168.168.42** is broken at the protocol level. The SSH daemon is accepting TCP connections but resetting them during the cryptographic key exchange phase.

**Why existing connections still work**: They maintain session state without renegotiating keys. Any attempt to create a NEW connection fails immediately during handshake.

---

## What I Diagnosed

### Connection Test Results
```
✅ Network connectivity:    PASS (ping works, 0% packet loss)
✅ TCP port 22 open:        PASS (nc -zv succeeded)  
✅ TCP handshake:           PASS (connection established)
❌ SSH key exchange:        FAIL (Connection reset by peer)
```

### Root Cause
**SSH daemon is broken** - likely corrupted host keys or daemon crash

### Evidence
```bash
$ ssh -vvv akushnir@192.168.168.42
OpenSSH_9.6p1
debug1: Connection established
debug1: Local version string SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.15
kex_exchange_identification: read: Connection reset by peer
Connection reset by 192.168.168.42 port 22
```

---

## What I Created For You

### 1. **Complete Investigation Report**
📄 `SSH-CONNECTIVITY-INVESTIGATION-REPORT.md`
- Full diagnostic findings
- Root cause analysis
- All remediation procedures
- Verification checklist

### 2. **Detailed Repair Guide**
📄 `SSH-REPAIR-GUIDE-APRIL-25-2026.md`
- Step-by-step procedures (4 options + escalation)
- Graceful restart (30 sec)
- Key regeneration (1 min)
- Full daemon reinstall (2 min)
- Host reboot (3 min)
- Failure escalation paths

### 3. **Automated Recovery Script**
📜 `scripts/ops/ssh-emergency-recovery.sh`
- Production-ready automation
- Dry-run mode for safe preview
- Automatic fallback through all repair steps
- Detailed logging and verification

### 4. **GitHub Issue for Tracking**
🔗 **[Issue #1784](https://github.com/kushin77/code-server/issues/1784)** (P1)
- Documentation of the issue
- Recovery resources linked
- Status tracking

---

## How To Fix It

### Requirements
You need **host-level access** to 192.168.168.42:
- Physical console
- IPMI/BMC remote management
- Serial console connection
- RDP/VNC
- Or direct local terminal access

**Why?** SSH is broken, so you can't SSH in to fix it. You need direct system access.

### Quick Fix (30 seconds)
```bash
# Get to .42's console/terminal via IPMI or physical access
sudo systemctl restart ssh

# Then test from .31:
ssh akushnir@192.168.168.31 'ssh akushnir@192.168.168.42 id'
```

### If That Doesn't Work
```bash
# Use the automated recovery script:
sudo bash scripts/ops/ssh-emergency-recovery.sh --dry-run  # Preview first

# Then apply:
sudo bash scripts/ops/ssh-emergency-recovery.sh
```

### Manual Repair (If Script Unavailable)
See the procedures in `SSH-REPAIR-GUIDE-APRIL-25-2026.md`

---

## What This Blocks

- ❌ New SSH sessions to .42
- ❌ Remote deployment commands
- ❌ Cluster parity verification (Epic #1616)
- ❌ Failover testing
- ❌ Infrastructure maintenance

---

## After You Fix It

Verify from .31 or your workstation:
```bash
# Quick test:
ssh akushnir@192.168.168.42 'echo SSH_WORKING'

# From .31:
ssh akushnir@192.168.168.31 'ssh akushnir@192.168.168.42 docker ps'

# Full sync if needed:
ssh akushnir@192.168.168.42 'cd code-server-enterprise && git pull origin main'
```

---

## Related History

**Issue #1645** (CLOSED): Previous SSH/.42 replica problem - all prior fixes were applied
- NAS directories created ✅
- Replica sync completed ✅  
- Services redeployed ✅
- This is a residual/new issue after that work

---

## Files Committed to Git

✅ Committed to main branch (commit c492dce9):
- `SSH-CONNECTIVITY-INVESTIGATION-REPORT.md`
- `SSH-REPAIR-GUIDE-APRIL-25-2026.md`  
- `scripts/ops/ssh-emergency-recovery.sh`

All files are immediately available for team access.

---

## Next Steps

1. **Get host access** to 192.168.168.42 (console/IPMI/etc)
2. **Execute repair** (see "How To Fix It" section)
3. **Test connectivity** from .31
4. **Update Epic #1616** (cluster parity) - this was blocking it
5. **Resume operations** - failover testing, deployment verification

---

**Investigation completed**: April 25, 2026  
**Estimated repair time**: 30 seconds to 3 minutes depending on root cause  
**Documentation**: Complete  
**Status**: Ready for remediation
