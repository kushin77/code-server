# NAS Security Remediation Plan

**Date**: April 22, 2026  
**Priority**: P1 — Multiple critical security vulnerabilities  
**Affected Host**: 192.168.168.56 (kushnas)

---

## Executive Summary

NAS host has **4 critical security vulnerabilities**:
1. **NFS `no_root_squash`** — Any LAN host can mount as root and own all data
2. **28+ open ports** — 5 unknown world-exposed services
3. **3 undocumented Redis instances** — Unknown purpose, auth status unclear
4. **5 failed systemd units** — Recurring failures every 10 minutes
5. **Root disk 71% full** — 23G NFS export + 8G swap file consuming space

---

## Issue #1387 — NFS no_root_squash Vulnerability (P1)

### Current State

```bash
$ cat /etc/exports
/export *(rw,sync,no_subtree_check,no_root_squash)
```

**Risk**: Any host on LAN can mount `/export` as root and:
- Read PostgreSQL database files
- Steal TLS private keys from Caddy
- Destroy all NAS data
- Read entire code-server workspace

### Immediate Fix (5 min)

**SSH to NAS (192.168.168.56) and run**:

```bash
sudo bash -c 'cat > /etc/exports << EOF
/export 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export 192.168.168.42(rw,sync,no_subtree_check,root_squash)
EOF'

sudo exportfs -ra

# Verify
showmount -e 192.168.168.56
```

**Expected output**:
```
Export list for 192.168.168.56:
/export 192.168.168.31
/export 192.168.168.42
```

---

## Issue #1391 — Root Disk 71% Full (P1)

### Current State

```
Filesystem: /dev/mapper/ubuntu--vg--2-ubuntu--lv
Size: 99G
Used: 66G (71%)
Available: 28G
```

### Immediate Fixes (2 fixes, 5 min total)

**Fix 1: Remove unnecessary swap file**

```bash
sudo swapoff /swap.img
sudo rm /swap.img
sudo sed -i '/swap.img/d' /etc/fstab
free -h | grep Swap
```

Result: Frees 8GB immediately (71% → 63%)

**Fix 2: Enable cleanup automation**

```bash
sudo bash /export/scripts/nas-cleanup.sh --verbose
crontab -l | grep nas-cleanup
```

---

## Issue #1388 — Failed Systemd Units (P1)

### 5 Failed Units

1. **eiq-nas-drift-guard** — bash syntax error (every 10 min) ← FIXABLE
2. **eiq-nas-ssh-key-reconciliation** — wrong GCP project ← FIXABLE
3. **nas-alerting-engine** — exit code 1 (blocked on #1378)
4. **nas-alerting** — exit code 1 (blocked on #1378)
5. **nginx** — FAILED for 17 days ← FIXABLE

### Fix 1: eiq-nas-drift-guard.service

Create wrapper script and update systemd drop-in:

```bash
sudo bash -c 'cat > /usr/local/bin/nas-sanitize-portal-env.sh << '\''EOF'\''
#!/usr/bin/env bash
sed -i "s|^NAS_PORTAL_RECOVERY_CONFIRM_PHRASE=I UNDERSTAND\$|NAS_PORTAL_RECOVERY_CONFIRM_PHRASE='"'"'I UNDERSTAND'"'"'|" /etc/eiq-nas/portal.env || true
EOF'

sudo chmod +x /usr/local/bin/nas-sanitize-portal-env.sh

sudo bash -c 'cat > /etc/systemd/system/eiq-nas-drift-guard.service.d/portal-env-sanitize.conf << EOF
[Service]
ExecStartPre=/usr/local/bin/nas-sanitize-portal-env.sh
EOF'

sudo systemctl daemon-reload
sudo systemctl restart eiq-nas-drift-guard.service
```

### Fix 2: eiq-nas-ssh-key-reconciliation.service

Disable (appears obsolete):

```bash
sudo systemctl disable eiq-nas-ssh-key-reconciliation.service
sudo systemctl stop eiq-nas-ssh-key-reconciliation.service
```

### Fix 3: nginx.service

Disable (Caddy runs on .31):

```bash
sudo systemctl disable nginx.service
sudo systemctl stop nginx.service
```

---

## Remediation Checklist

### Immediate (This Session) — 15 min

- [ ] **#1387**: Update `/etc/exports` with `root_squash` + specific IPs
- [ ] **#1391**: Remove `/swap.img` (frees 8GB)
- [ ] **#1388**: Fix `eiq-nas-drift-guard` bash syntax
- [ ] **#1388**: Disable obsolete systemd units

### Short-term — 30 min

- [ ] **#1389**: Investigate Redis instances (orphaned or needed?)
- [ ] **#1393**: Identify port 8069 (Odoo check)
- [ ] **#1391**: Add NAS to Prometheus scrape config

### Long-term — Blocked on #1386

- [ ] Move `/export` to RAID array

