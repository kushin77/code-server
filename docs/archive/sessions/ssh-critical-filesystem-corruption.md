# 🚨 CRITICAL - Filesystem Corruption Emergency Recovery

## Your Situation
All `/usr/bin` commands giving "Input/output error" = **Filesystem corruption or NFS unmount**

## BASH BUILT-IN COMMANDS (These will work - no /usr/bin needed)

### STEP 1: Check what's mounted (built-in test)
```bash
mount
```

Look for `/usr` in the output. If you see:
- `on /usr type nfs` - NFS mount is dead
- Not listed at all - `/usr` is unmounted

### STEP 2: If /usr is on NFS, remount it
```bash
mount -o remount /usr
```

### STEP 3: If remount fails, try umount + mount
```bash
umount /usr
mount /usr
```

### STEP 4: After remount, try systemctl again
```bash
/usr/bin/systemctl restart ssh
```

### STEP 5: If still broken, force kernel panic and reboot
```bash
echo 1 > /proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
```

(This does emergency reboot - computer will restart)

---

## ALTERNATIVE: Use Built-in Kill Signals

If you can't remount, try killing sshd directly:

```bash
# Find sshd process (ps might fail, but try)
ps aux | grep sshd

# If ps works, kill with PID:
kill -9 PROCESS_ID

# Or use killall if available:
killall -9 sshd
```

---

## ABSOLUTE LAST RESORT: Magic SysRq Reboot

If nothing works, force immediate reboot (computer will restart):

```bash
echo 1 > /proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
```

This bypasses everything and hard-reboots the system.

---

## WHAT TO TRY FIRST (In Order)

1. **Check mount**: `mount` (just type it)
2. **Remount /usr**: `mount -o remount /usr` 
3. **Try systemctl**: `/usr/bin/systemctl restart ssh`
4. **Force reboot**: `echo b > /proc/sysrq-trigger`

---

## If You See "Input/output error" On ALL Commands

Then the filesystem is severely corrupted and **you need physical intervention**:
- Power cycle via IPMI/PDU
- Physical power button
- Contact operations team

The server will need:
- fsck to repair filesystem
- Or NAS reconnection if NFS is down
- Or disk replacement if hardware failed
