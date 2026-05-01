# USER ACTION CARD - REPLICA 2 RECOVERY HANDOFF
**Date:** April 25, 2026
**Status:** Awaiting operations team & user action
**Issue:** #1784

## CURRENT SITUATION
✅ Investigation complete - root cause identified as filesystem corruption  
✅ All user-executable recovery attempts failed - documented  
✅ Operations escalation created - IPMI reboot required  
⏳ **YOU HAVE ACTIVE SHELL ON .42 - DO NOT CLOSE IT YET**  

## YOUR ROLE NOW

### 1. KEEP SHELL ACTIVE ON .42
**Why:** After operations team power cycles .42, the machine will reboot. Your current shell will disconnect, but having the hostname and knowing the system is alive is useful for verification.

**Action:** Keep the terminal open on .42. Do nothing for now.

### 2. WHEN OPERATIONS EXECUTES IPMI REBOOT
Operations team will:
- Power cycle 192.168.168.42 via IPMI
- Wait for system to boot (~90 seconds)
- Notify you that recovery is underway

**What you'll see:** Your shell on .42 will disconnect with message like:
```
Write failed: Broken pipe
```

This is NORMAL and expected.

### 3. AFTER IPMI REBOOT COMPLETES (~2 minutes)
From 192.168.168.31, run these verification commands:

```bash
# Test 1: Can you SSH to .42?
ssh akushnir@192.168.168.42 'echo "SSH works!"'

# Test 2: Are filesystems healthy?
ssh akushnir@192.168.168.42 'mount | grep /usr'

# Test 3: Is NAS still mounted?
ssh akushnir@192.168.168.42 'df -h /nas'

# Test 4: Is Docker running?
ssh akushnir@192.168.168.42 'docker ps --format "table {{.Names}}\t{{.Status}}" | head -5'

# Test 5: Is SSH daemon healthy?
ssh akushnir@192.168.168.42 'systemctl status ssh'
```

If all return without errors → Recovery succeeded!

### 4. IF RECOVERY SUCCEEDED
```bash
# Restart all services on .42
ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose --profile all up -d'

# Wait 30 seconds for services to start
sleep 30

# Verify cluster is operational again
ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}\t{{.Status}}"'
```

### 5. IF RECOVERY FAILS
Commands still return I/O error:
1. Report this in GitHub issue #1784
2. Operations team will investigate disk hardware health
3. May require physical server repair or replacement

## ESCALATION DOCUMENTATION

**For operations team:**
→ [operations-escalation-replica2-filesystem-corruption-apr25-2026.md](./operations-escalation-replica2-filesystem-corruption-apr25-2026.md)

**For cluster recovery:**
→ [SSH-RECOVERY-INDEX.md](./SSH-RECOVERY-INDEX.md)

## TIMELINE EXPECTATIONS

| Time | Action | Who |
|------|--------|-----|
| NOW | Keep shell open on .42 | You |
| ~10 min | Operations executes IPMI reboot | Ops team |
| +1 min | System boots (expect shell disconnect) | Hardware |
| +2 min | Run SSH verification tests | You |
| +3 min | Run docker-compose restart | You |
| +5 min | Verify cluster health | You |

## CRITICAL REMINDERS

- ✅ **Keep shell open** - It's your only window into .42 right now
- ✅ **Don't reboot/shutdown** - Operations will do this via IPMI
- ✅ **Don't close terminal** - You need it for verification after reboot
- ✅ **Document results** - Update issue #1784 with success/failure status
- ❌ **Don't attempt manual fsck** - Filesystem check requires offline boot
- ❌ **Don't force unmount NFS** - Could corrupt mounted data on NAS

## QUESTIONS?

1. **"What if my shell disconnects naturally?"** → Normal, can reconnect after IPMI reboot
2. **"Can I run other commands on .42 now?"** → No, all /usr/bin commands fail. Only bash built-ins work
3. **"How long will reboot take?"** → ~90 seconds for power cycle, 2-3 minutes for full boot
4. **"What if SSH verification fails?"** → Report in issue #1784, escalate to disk hardware investigation
5. **"Do I need to do anything with NAS?"** → No, but operations team will verify NAS connectivity

---

**Status:** Awaiting operations team IPMI reboot execution  
**Your Next Action:** Keep shell open, monitor for Ops team notification  
**Issue Tracking:** #1784 (update with post-recovery results)
