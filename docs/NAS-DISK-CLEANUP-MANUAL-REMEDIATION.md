# NAS Disk Space Cleanup — Manual Remediation Steps

**Issue**: #1391  
**Status**: 73% utilization (27GB available), /swap.img consuming 8.1GB unnecessarily  
**Target**: Free 8GB disk space to extend NAS runway from ~120 days to 150+ days  
**Blocker**: Same as #1388 - passwordless sudo not configured

## Prerequisites

```bash
# SSH to primary host first
ssh akushnir@192.168.168.31

# Then SSH to NAS from primary
ssh akushnir@192.168.168.56
```

## Step 1: Verify Swap Usage

NAS has 54GB RAM with minimal swap usage (0% currently). The /swap.img file is **not being used**.

```bash
# Check swap status
free -h
swapon --show

# Output should show: No swap active, or very low swap usage
```

## Step 2: Remove /swap.img (8.1 GB freed)

```bash
# Check current state
ls -lh /swap.img

# Disable swap if active
sudo swapoff /swap.img 2>/dev/null || true

# Remove the unused swap file
sudo rm -f /swap.img

# Verify removal
ls -lh /swap.img 2>/dev/null && echo "Still exists" || echo "✓ Removed successfully"

# Check new disk usage
df -h /
```

**Expected result**: Disk usage drops from 73% to ~63% (freed 8GB)

## Step 3: Verify Cleanup Automation is Running

Check that the NAS cleanup cron job is running to prevent accumulation:

```bash
# Check if cleanup cron is installed
sudo crontab -l | grep -i "cleanup\|logs\|nas-cleanup" || echo "No cleanup cron found"

# If not found, verify nas-cleanup.sh exists
ls -lh /usr/local/bin/nas-cleanup.sh 2>/dev/null || echo "Cleanup script not found"

# Check last cleanup run
sudo journalctl -u nas-cleanup.timer 2>/dev/null | head -5 || echo "Timer unit not found"
```

## Step 4: Monitor Disk Usage Going Forward

Add monitoring to ensure disk doesn't fill up again:

```bash
# Check current disk usage and trend
df -h / && echo && echo "Disk usage trending:" && \
  for i in {1..3}; do
    echo "Sample $i:"
    du -sh /nas/transient/* 2>/dev/null | sort -rh | head -5
    sleep 5
  done
```

## Expected Timeline

| Phase | Disk % | Action | Timeline |
|-------|--------|--------|----------|
| **Current** | 73% | Remove swap.img (8GB) | Now |
| **Post-cleanup** | 63% | NAS cleanup automation runs | Daily |
| **Trend** | 63-65% | Steady state (cleanup balances growth) | Ongoing |
| **Days to fill** | 150+ | Extended runway | Target |

## Full Manual Remediation Script

If you want to run everything at once:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] NAS Disk Space Cleanup"
echo "[INFO] ========================"
echo ""

# Step 1: Check current state
echo "[INFO] Current disk usage:"
df -h /
echo ""

# Step 2: Disable and remove swap
echo "[INFO] Removing /swap.img (8.1 GB)..."
sudo swapoff /swap.img 2>/dev/null || true
sudo rm -f /swap.img
echo "[INFO] ✓ Removed"
echo ""

# Step 3: Verify
echo "[INFO] New disk usage:"
df -h /
echo ""

# Step 4: Check cleanup automation
echo "[INFO] Verifying cleanup automation..."
if [ -f /usr/local/bin/nas-cleanup.sh ]; then
    echo "[INFO] ✓ Cleanup script found"
else
    echo "[WARN] Cleanup script not found - monitor disk usage manually"
fi

echo "[INFO] ✓ NAS disk space cleanup complete"
echo "[INFO] Freed ~8GB, disk usage 73% → 63%"
```

## Rollback

If needed, recreate the swap file:

```bash
# Create 8GB swap file
sudo fallocate -l 8G /swap.img
sudo chmod 600 /swap.img
sudo mkswap /swap.img
sudo swapon /swap.img

# Check
swapon --show
```

## Monitoring (Post-Cleanup)

```bash
# Monitor disk usage over next 7 days
# Check daily:
df -h / | grep 'Avail\|/dev/mapper'

# After 7 days, should be stable at ~63% (before next cleanup rotation)
# If trending above 65%, investigate what's consuming space:
du -sh /nas/transient/* | sort -rh | head -10
```

---

**Time Estimate**: 2 minutes (one rm command + verification)  
**Risk**: LOW (only removes unused swap file)  
**Impact**: +27GB effective available space, extends NAS uptime 30 days (~120→150 days)  
**Automated**: Yes - cleanup cron runs daily to maintain this headroom
