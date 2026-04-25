# IMMEDIATE FIX - Copy & Paste These Commands

You're on .42 right now. Your sudo is broken but you have shell access.

## TRY THESE IN ORDER:

### 1. FIRST - Try without sudo (run as-is):
```bash
systemctl restart ssh
sleep 2
systemctl status ssh
```

### 2. If that fails, try this:
```bash
ps aux | grep sshd
ls -l /etc/ssh/ssh_host_*
```

### 3. If you see "sudo: Input/output error" again, it's a filesystem issue. Try:
```bash
df -h
dmesg | tail -20
mount | grep -E "^/dev.*on /usr"
```

### 4. Try becoming root directly:
```bash
su -
# (Enter root password if prompted)
systemctl restart ssh
exit
```

### 5. If su doesn't work, try reboot:
```bash
reboot
# (Wait 2-3 minutes, then test from .31)
```

### 6. If all else fails, check if sshd daemon is actually running:
```bash
ps aux | grep -E "\[sshd\]|sshd: "
netstat -tlnp | grep :22
```

---

## AFTER RESTART - Test from your workstation or .31:

```bash
ssh akushnir@192.168.168.31 'ssh akushnir@192.168.168.42 id'
```

If that works, SSH is FIXED! 

---

## THE PROBLEM

Your `sudo` binary has an I/O error. This is usually:
- Filesystem corruption
- NFS mount issue
- Disk problem

But SSH restart might still work if:
- `systemctl` doesn't depend on sudo
- Or if you can use `su` to become root

---

## COPY-PASTE THIS ENTIRE BLOCK TO .42:

```
whoami
echo "---"
systemctl restart ssh
echo "SSH restart exit code: $?"
sleep 2
systemctl status ssh | head -5
ps aux | grep sshd | head -3
```

Do this NOW while you have the shell open, then report what you see!
