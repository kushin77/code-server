# SSH Recovery on .42 - Workaround for sudo I/O Error

## Problem
You got: `-bash: /usr/bin/sudo: Input/output error`

This means sudo is broken at the system level, but you have shell access to .42.

## Solution Options

### Option 1: Restart SSH Directly (If you're root or in wheel/sudoers)
```bash
# Check if you can run systemctl without sudo:
systemctl restart ssh

# Verify:
systemctl status ssh
ps aux | grep sshd
```

### Option 2: Manual SSH Key Regeneration (No sudo needed for some steps)
```bash
# Check if you can access ssh keys:
ls -l /etc/ssh/ssh_host_*

# If you can write to /etc/ssh, try:
ssh-keygen -A

# Then restart SSH:
systemctl restart ssh
```

### Option 3: Emergency - Run Commands Without Sudo
```bash
# First, check if you're already root:
whoami
id

# If you ARE root, just remove "sudo" from commands:
systemctl restart ssh        # Instead of: sudo systemctl restart ssh
ssh-keygen -A                # Instead of: sudo ssh-keygen -A
```

### Option 4: Check If This is a Filesystem Issue
```bash
# This might tell you what's wrong:
dmesg | tail -20             # Kernel messages
df -h                        # Disk space
mount | grep /usr            # Check /usr mount

# If /usr is mounted via NFS and having issues:
umount /usr  # (Only if /usr is a separate mount!)
mount -o remount /usr
```

### Option 5: Try Installing sudo from Source
```bash
# If sudo binary is corrupted, try reinstalling:
apt-get install --reinstall sudo

# Or use the su command:
su -                         # Switch to root
systemctl restart ssh
exit
```

## Quick Workaround - Restart SSH Now

Since you have shell access to .42 right now, try this immediately:

```bash
# Just run it without sudo:
systemctl restart ssh

# If that doesn't work, try:
/usr/sbin/sshd -f /etc/ssh/sshd_config

# Check if it's running:
ps aux | grep sshd
```

## Then Test From .31

Once you've restarted SSH on .42, from your local workstation or .31:

```bash
ssh akushnir@192.168.168.42 'echo SSH_RECOVERED'
```

---

## What Caused the sudo I/O Error?

The `-bash: /usr/bin/sudo: Input/output error` usually means:
1. **Filesystem corruption** on the partition holding `/usr/bin`
2. **NFS mount issue** if `/usr` is on NFS
3. **Disk space full** (unlikely but possible)
4. **sudo binary corrupted** (partial file, bad permissions, or bitrot)
5. **System under severe memory pressure**

## Recovery Steps (In Priority Order)

1. **Try SSH restart without sudo** (takes 10 seconds)
2. **Check filesystem**: `df -h` and `dmesg | tail -20`
3. **Try reinstalling sudo**: `apt-get install --reinstall sudo`
4. **Try systemctl directly without sudo path**: `systemctl restart ssh`
5. **As last resort**: `reboot` (if you can)

---

## If All Else Fails

If the sudo error persists and blocks everything:

```bash
# Try switching to root shell:
su -
systemctl restart ssh

# Or try direct daemon command:
/usr/sbin/sshd -f /etc/ssh/sshd_config

# Or via pkill:
pkill -9 sshd          # Kill old daemon
/usr/sbin/sshd         # Start new one
```

Let me know which of these commands works and what the output is!
