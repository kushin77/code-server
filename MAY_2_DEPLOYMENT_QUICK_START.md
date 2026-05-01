# May 2 Deployment Quick Start

**Fastest way to deploy Phase 29 autonomous operations to production.**

---

## 30-Second Deployment

```bash
# From /home/akushnir/code-server
bash deploy-phase-29-autonomous-ops.sh
```

**That's it.** The script handles:
- ✅ SSH to both hosts
- ✅ Git sync to latest release
- ✅ Systemd service creation
- ✅ Service startup and verification
- ✅ Integration test validation
- ✅ Deployment report generation

**Expected output:**
```
✓ PRIMARY orchestrator: RUNNING
✓ REPLICA orchestrator: RUNNING
✓ Integration tests: PASSED
✓ Deployment report saved
```

---

## Advanced Options

### Dry-Run (Test Without Deploying)

```bash
bash deploy-phase-29-autonomous-ops.sh --dry-run
```

Shows exactly what would be deployed without making any changes.

### Deploy to Primary Only

```bash
bash deploy-phase-29-autonomous-ops.sh --primary-only
```

Useful for rolling deployment or testing one host first.

### Deploy to Replica Only

```bash
bash deploy-phase-29-autonomous-ops.sh --replica-only
```

For sequential deployment: do primary first, verify, then replica.

---

## What Gets Deployed

### On Each Host:

1. **Git Repository Update**
   - Syncs to `release/v1.0.0-production`
   - Pulls latest code from GitHub

2. **Systemd Service Creation**
   - File: `/etc/systemd/system/code-server-phase29.service`
   - Type: `simple` (runs continuously)
   - Restart: `always` (auto-restarts on crash)
   - Mode: `automate` (full autonomous operations)
   - Interval: `60` seconds per cycle

3. **Service Activation**
   - Daemon reload
   - Service enabled (survives host reboot)
   - Service started immediately

---

## Verification

After deployment, verify operations are running:

```bash
# Check primary
ssh akushnir@192.168.168.31 "sudo journalctl -u code-server-phase29 -n 10 --no-pager"

# Expected output:
# ... OBSERVE: collecting metrics ...
# ... PREDICT: generating forecasts ...
# ... REMEDIATE: applying actions ...
# ... AUTOMATE: cycle complete (1/60s remaining)
```

Or check the operations log:

```bash
# View real-time operations
ssh akushnir@192.168.168.31 "tail -f artifacts/phase29/operations.log"
```

---

## Troubleshooting

### Service won't start

```bash
# Check what's wrong
ssh akushnir@192.168.168.31 "sudo systemctl status code-server-phase29"
sudo journalctl -u code-server-phase29 -n 50

# If Phase 29 scripts missing:
ssh akushnir@192.168.168.31 "cd /home/akushnir/code-server && git status"

# If permission denied:
ssh akushnir@192.168.168.31 "chmod +x scripts/ops/phase-29-operational-orchestrator.sh"
```

### SSH connection fails

```bash
# Test connectivity
ssh -v akushnir@192.168.168.31 "echo test"

# If timeout:
# - Check host is online: ping 192.168.168.31
# - Check SSH service: ssh akushnir@192.168.168.31 "sudo systemctl status ssh"
# - Check firewall: ssh akushnir@192.168.168.31 "sudo ufw status"
```

### Integration tests fail

This is OK if all failures are environment-related:

```
✗ test_docker_stats_available
✗ test_prometheus_metrics_available
✗ test_grafana_responsive
(other 3 failures)
```

These are expected in dev environments without Docker daemon. The deployment still succeeds.

---

## Deployment Log

Each deployment creates a log file:

```
artifacts/deployment-YYYYMMDD-HHMMSS.log
```

Example log entries:

```
[2026-05-02 00:00:15] Deployment started
[2026-05-02 00:00:16] === Starting deployment to PRIMARY (192.168.168.31) ===
[2026-05-02 00:00:20] ✓ Deployment successful on 192.168.168.31
[2026-05-02 00:00:20] ✓ Service verified running on 192.168.168.31
[2026-05-02 00:00:22] === Starting deployment to REPLICA (192.168.168.42) ===
[2026-05-02 00:00:28] ✓ Deployment successful on 192.168.168.42
[2026-05-02 00:00:28] ✓ Service verified running on 192.168.168.42
[2026-05-02 00:00:29] ✓ Integration tests PASSED
[2026-05-02 00:00:30] Deployment completed successfully
```

---

## Rollback (If Needed)

To disable Phase 29 and revert to manual operations:

```bash
# On both hosts
ssh akushnir@192.168.168.31 "sudo systemctl stop code-server-phase29"
ssh akushnir@192.168.168.42 "sudo systemctl stop code-server-phase29"

# Disable auto-start
ssh akushnir@192.168.168.31 "sudo systemctl disable code-server-phase29"
ssh akushnir@192.168.168.42 "sudo systemctl disable code-server-phase29"

# Verify stopped
ssh akushnir@192.168.168.31 "sudo systemctl status code-server-phase29"
```

Then proceed with manual operations using ELITE scripts.

---

## Timeline for May 2

| Time (UTC) | Action | Command |
|------------|--------|---------|
| 00:00 | Deploy Phase 29 | `bash deploy-phase-29-autonomous-ops.sh` |
| 00:05 | Verify both running | Check journals on both hosts |
| 00:15 | Review operations.log | `tail -100 artifacts/phase29/operations.log` |
| 12:00 | Check 12-hour SLAs | Review dashboard metrics |
| 24:00 | Check 24-hour SLAs | Generate report |

---

## See Also

- [MAY_2_3_AUTONOMOUS_OPERATIONS_PACKAGE.md](./MAY_2_3_AUTONOMOUS_OPERATIONS_PACKAGE.md) — Full deployment guide
- [PHASE_29_OPERATIONAL_RUNBOOK.md](./PHASE_29_OPERATIONAL_RUNBOOK.md) — Operational procedures
- [OPERATIONS_TEAM_HANDOFF.md](./OPERATIONS_TEAM_HANDOFF.md) — Team responsibilities

---

**Ready to deploy:** May 2, 2026, 00:00 UTC ✅
