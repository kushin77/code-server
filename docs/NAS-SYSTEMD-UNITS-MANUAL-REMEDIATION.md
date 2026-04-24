# NAS Systemd Units Remediation — Manual Execution Steps

**Issue**: #1388  
**Status**: Scripts ready, manual execution steps documented below  
**Blocker**: Passwordless sudo not configured on NAS (192.168.168.56)  
**Workaround**: Execute steps manually with sudo password, or set up passwordless sudo for akushnir

## Prerequisites

```bash
# SSH to primary host first
ssh akushnir@192.168.168.31

# Then SSH to NAS from primary (passwordless)
ssh akushnir@192.168.168.56
```

## Fix 1: eiq-nas-drift-guard.service (Bash syntax error every 10 min)

**Problem**: Systemd drop-in has mangled quoting that breaks bash parsing

**Fix Steps**:
```bash
# Create wrapper script to avoid quoting hell
sudo tee /usr/local/bin/nas-sanitize-portal-env.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
sed -i "s|^NAS_PORTAL_RECOVERY_CONFIRM_PHRASE=I UNDERSTAND\$|NAS_PORTAL_RECOVERY_CONFIRM_PHRASE='I UNDERSTAND'|" /etc/eiq-nas/portal.env || true
EOF

sudo chmod +x /usr/local/bin/nas-sanitize-portal-env.sh

# Update the systemd drop-in to call wrapper instead of inline sed
sudo tee /etc/systemd/system/eiq-nas-drift-guard.service.d/portal-env-sanitize.conf > /dev/null <<'EOF'
[Service]
ExecStartPre=/usr/local/bin/nas-sanitize-portal-env.sh
EOF

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart eiq-nas-drift-guard.service

# Verify
sudo systemctl status eiq-nas-drift-guard.service
```

## Fix 2: eiq-nas-ssh-key-reconciliation.service (Wrong GCP project, obsolete)

**Problem**: References `nexusshield-prod` GCP project (wrong) and target host `192.168.168.55` (doesn't exist)

**Fix**: Disable the service (it's obsolete)
```bash
sudo systemctl disable eiq-nas-ssh-key-reconciliation.service
sudo systemctl stop eiq-nas-ssh-key-reconciliation.service
sudo systemctl mask eiq-nas-ssh-key-reconciliation.service

# Verify
sudo systemctl status eiq-nas-ssh-key-reconciliation.service
```

## Fix 3: nginx.service (Failed for 17 days, no longer needed)

**Problem**: Failed since April 5, not needed (Caddy runs on primary host)

**Fix**: Disable nginx
```bash
sudo systemctl disable nginx.service
sudo systemctl stop nginx.service
sudo systemctl mask nginx.service

# Verify
sudo systemctl status nginx.service
```

## Fix 4 & 5: nas-alerting.service + nas-alerting-engine.service (GCP auth expired #1378)

**Problem**: Both services fail due to expired GCP credentials (blocked on #1378)

**Workaround**: Temporarily disable until #1378 is fixed
```bash
sudo systemctl disable nas-alerting.service
sudo systemctl stop nas-alerting.service

sudo systemctl disable nas-alerting-engine.service
sudo systemctl stop nas-alerting-engine.service

# Verify
sudo systemctl status nas-alerting.service
sudo systemctl status nas-alerting-engine.service
```

**Note**: These will need to be re-enabled after #1378 (GCP auth) is fixed.

## Final Verification

After all fixes:
```bash
# Should show 0 failed units
sudo systemctl --failed

# Should show all 5 units as inactive
sudo systemctl status eiq-nas-drift-guard.service eiq-nas-ssh-key-reconciliation.service nginx.service nas-alerting.service nas-alerting-engine.service
```

## Expected Result

- ✅ eiq-nas-drift-guard: No more bash syntax errors (runs successfully every 10 min)
- ✅ eiq-nas-ssh-key-reconciliation: Disabled (no longer fails)
- ✅ nginx: Disabled (no longer fails)
- ✅ nas-alerting services: Disabled (no longer fail pending #1378)
- ✅ `systemctl --failed` shows 0 units

## Passwordless Sudo Setup (Optional, Automates Execution)

If you want to run the automated script without entering password each time:

```bash
# On NAS (192.168.168.56), add to sudoers:
sudo visudo  # or: sudo nano /etc/sudoers

# Add this line at the end:
akushnir ALL=(ALL) NOPASSWD: /usr/local/bin/nas-sanitize-portal-env.sh, /bin/systemctl, /bin/bash, /bin/tee, /bin/sed

# Then the script can run without password
```

---

**Time Estimate**: 5 minutes manual execution  
**Risk**: LOW (all changes are isolated to NAS systemd units, non-critical services)  
**Rollback**: `sudo systemctl unmask <service> && sudo systemctl enable <service>` to restore
