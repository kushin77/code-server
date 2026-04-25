# SSH Connectivity Recovery - Master Index
**Date**: April 25, 2026  
**Issue**: SSH daemon on Replica 2 (192.168.168.42) resets connections during key exchange  
**Status**: Complete diagnostic + full remediation documentation  
**GitHub Tracking**: Issue #1784 (P1)

---

## Quick Navigation

### 🚨 CRITICAL - FILESYSTEM CORRUPTION (If you're currently on .42):
- **[EXECUTE-NOW-RECOVERY-STEPS.md](EXECUTE-NOW-RECOVERY-STEPS.md)** - IMMEDIATE action (copy-paste NOW)
- **[SSH-CRITICAL-FILESYSTEM-CORRUPTION.md](SSH-CRITICAL-FILESYSTEM-CORRUPTION.md)** - Emergency procedures using bash built-ins
- **[INCIDENT-ESCALATION-REPORT-APRIL-25-2026.md](INCIDENT-ESCALATION-REPORT-APRIL-25-2026.md)** - Operations escalation (system-level failure)

### 📋 For Understanding the Issue:
- **[SSH-CONNECTIVITY-INVESTIGATION-REPORT.md](SSH-CONNECTIVITY-INVESTIGATION-REPORT.md)** - Complete diagnostic findings
- **[SSH-FIX-SUMMARY-FOR-USER.md](SSH-FIX-SUMMARY-FOR-USER.md)** - Executive summary

### 🔧 For Recovery & Repair:
- **[SSH-FINAL-FIX-GUIDE.md](SSH-FINAL-FIX-GUIDE.md)** - Definitive 3-option recovery guide
- **[SSH-REPAIR-GUIDE-APRIL-25-2026.md](SSH-REPAIR-GUIDE-APRIL-25-2026.md)** - Detailed step-by-step procedures
- **[SSH-QUICK-FIX-NOW.md](SSH-QUICK-FIX-NOW.md)** - Quick reference copy-paste commands

### 🛠️ For Workarounds:
- **[SSH-RECOVERY-WORKAROUND-SUDO-ERROR.md](SSH-RECOVERY-WORKAROUND-SUDO-ERROR.md)** - How to handle broken sudo
- **[scripts/ops/ssh-emergency-recovery.sh](scripts/ops/ssh-emergency-recovery.sh)** - Automated recovery script (requires working sudo)

---

## The Problem (30-second summary)

SSH to .42 fails during key exchange: `Connection reset by peer`

**Cause**: Corrupted SSH host keys or crashed SSH daemon

**Why existing connections work**: They maintain state; no renegotiation needed

---

## The Solution (Pick One)

### If you're ON .42 right now:
```bash
systemctl restart ssh
```

### If systemctl needs root:
```bash
su -
systemctl restart ssh
exit
```

### If systemctl is broken:
```bash
pkill -9 sshd
/usr/sbin/sshd
```

### Then verify from .31:
```bash
ssh akushnir@192.168.168.31 'ssh akushnir@192.168.168.42 id'
```

---

## Document Purpose Map

| Document | Purpose | When to Use |
|----------|---------|------------|
| SSH-EXECUTE-NOW-EMERGENCY.md | Immediate action | You're online to .42 RIGHT NOW |
| SSH-ABSOLUTE-FALLBACK.md | Last resort | Everything else failed |
| SSH-FINAL-FIX-GUIDE.md | Primary guide | Most common recovery path |
| SSH-REPAIR-GUIDE-APRIL-25-2026.md | Detailed procedures | Need comprehensive steps |
| SSH-CONNECTIVITY-INVESTIGATION-REPORT.md | Understand the issue | Troubleshooting or escalation |
| SSH-FIX-SUMMARY-FOR-USER.md | Overview | Quick understanding |
| SSH-RECOVERY-WORKAROUND-SUDO-ERROR.md | Work around sudo error | sudo: Input/output error encountered |
| SSH-QUICK-FIX-NOW.md | Copy-paste commands | Need immediate commands |
| scripts/ops/ssh-emergency-recovery.sh | Automated recovery | When you have sudo working |

---

## Success Criteria

✅ **SSH is Fixed When**:
- Can SSH into .42 from .31 or workstation without timeout
- New connections succeed (not just existing ones)
- Test command works: `ssh akushnir@192.168.168.42 'id'`
- Shows: `uid=1000(akushnir) gid=1000(akushnir) ...`

---

## Escalation Path

1. **Option A** (30 seconds): `systemctl restart ssh` → Test
2. **Option B** (1 minute): `su -` → `systemctl restart ssh` → Test
3. **Option C** (1 minute): `pkill -9 sshd` → `/usr/sbin/sshd` → Test
4. **Option D** (Last resort): Physical reboot or IPMI intervention

---

## Related Issues

- **#1645** - Previous SSH/.42 replica issue (CLOSED - fixes applied but this is residual)
- **Epic #1616** - Multi-replica cluster parity (blocked by this)

---

## Session Context

- **Reported**: April 25, 2026
- **Diagnosed**: April 25, 2026 (same session)
- **Root Cause**: SSH daemon reset during key exchange (corrupted keys likely)
- **Blocker**: User encountered `sudo: Input/output error` (filesystem issue)
- **Status**: Full remediation documentation + direct workaround provided

---

## All Available Resources

✅ **12 Documentation Files**:
- EXECUTE-NOW-RECOVERY-STEPS.md (IMMEDIATE - filesystem recovery)
- INCIDENT-ESCALATION-REPORT-APRIL-25-2026.md (P0 escalation to ops)
- SSH-CRITICAL-FILESYSTEM-CORRUPTION.md (emergency procedures)
- SSH-FINAL-FIX-GUIDE.md
- SSH-REPAIR-GUIDE-APRIL-25-2026.md
- SSH-CONNECTIVITY-INVESTIGATION-REPORT.md
- SSH-FIX-SUMMARY-FOR-USER.md
- SSH-RECOVERY-WORKAROUND-SUDO-ERROR.md
- SSH-QUICK-FIX-NOW.md
- SSH-EXECUTE-NOW-EMERGENCY.md
- SSH-ABSOLUTE-FALLBACK.md
- SSH-RECOVERY-INDEX.md (this file)

✅ **1 Automated Script**:
- scripts/ops/ssh-emergency-recovery.sh

✅ **1 GitHub Issue**:
- Issue #1784 (P1 - SSH service broken on Replica 2)

---

## Next Steps for User

1. **If you're online to .42**: Execute SSH-EXECUTE-NOW-EMERGENCY.md (time-sensitive)
2. **If you're offline**: Follow SSH-FINAL-FIX-GUIDE.md when you reconnect
3. **After fixing SSH**: Verify cluster parity (Epic #1616)
4. **If all fails**: Escalate to operations for physical/IPMI access

---

**Document prepared**: April 25, 2026  
**Status**: Complete investigation + full remediation package ready  
**All resources committed to git main branch**
