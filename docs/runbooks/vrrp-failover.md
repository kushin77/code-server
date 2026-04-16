# Runbook: VRRP Failover

**Severity**: P1 | **Component**: Keepalived/VRRP | **VIP**: 192.168.168.30

---

## Overview

Production uses VRRP (Keepalived) to float a Virtual IP (`192.168.168.30`) between physical hosts. All external traffic hits the VIP; the primary host holds it under normal operation. Failover is automatic and completes in <2 seconds.

```
Normal:
  192.168.168.30 (VIP) → 192.168.168.31 (primary, MASTER)
  192.168.168.42 (replica, BACKUP — watching)

Failover:
  192.168.168.30 (VIP) → 192.168.168.42 (replica, promoted to MASTER)
```

---

## Alert: VIPNotReachable

**Trigger**: `probe_success{instance="192.168.168.30"} == 0` for 30s

### Immediate Actions (< 2 min)

```bash
# 1. Verify VIP is down
ping -c 4 192.168.168.30

# 2. Check primary
ssh akushnir@192.168.168.31 "sudo systemctl status keepalived; ip addr show eth0 | grep 168.30"

# 3. Check replica
ssh akushnir@192.168.168.42 "sudo systemctl status keepalived; ip addr show eth0 | grep 168.30"
```

### Diagnosis

| Symptom | Likely Cause | Action |
|---------|-------------|--------|
| VIP not on any host, both keepaliveds running | VRRP auth mismatch | Check `auth_pass` matches on both |
| VIP not on any host, one keepalived failed | Crash / OOM | `sudo systemctl restart keepalived` |
| VIP on replica, primary up | Primary health check failing | Check `docker ps` on primary |
| Both keepaliveds running, VIP on primary | False alarm | Re-check blackbox exporter config |

### Recovery Procedure

```bash
# Force VIP back to primary (if primary is healthy):
ssh akushnir@192.168.168.31 "sudo systemctl restart keepalived"
# Wait 5s — primary will re-acquire MASTER if health checks pass

# Verify VIP moved:
ping -c 3 192.168.168.30
ssh akushnir@192.168.168.31 "ip addr show eth0 | grep 168.30"
```

---

## Alert: VRRPStateChange

**Trigger**: VRRP state changed (MASTER → BACKUP or vice versa)

This is informational — a state change may be expected during maintenance or may indicate instability.

```bash
# Check VRRP logs on both hosts
ssh akushnir@192.168.168.31 "sudo journalctl -u keepalived --since '10 minutes ago'"
ssh akushnir@192.168.168.42 "sudo journalctl -u keepalived --since '10 minutes ago'"

# Check which node currently holds VIP
ssh akushnir@192.168.168.31 "ip addr show eth0 | grep '168.30'"
ssh akushnir@192.168.168.42 "ip addr show eth0 | grep '168.30'"
```

---

## Planned Maintenance Failover

When taking the primary offline for maintenance:

```bash
# Step 1: Gracefully transfer VIP to replica
ssh akushnir@192.168.168.31 "sudo systemctl stop keepalived"
# Replica takes over in <2s via VRRP priority

# Step 2: Verify replica holds VIP
ping -c 3 192.168.168.30  # should respond
ssh akushnir@192.168.168.42 "ip addr show eth0 | grep '168.30'"

# Step 3: Perform maintenance on primary

# Step 4: Restore primary (joins as BACKUP due to nopreempt)
ssh akushnir@192.168.168.31 "sudo systemctl start keepalived"
# Primary rejoins as BACKUP (does NOT auto-reclaim MASTER)
# This is intentional — prevents flapping
```

---

## Failover Test (Quarterly)

```bash
# Run from dev machine (not from a production host)
echo "=== VRRP Failover Test ===" 
ping -c 2 192.168.168.30 && echo "VIP responding before test"

# Stop keepalived on primary
ssh akushnir@192.168.168.31 "sudo systemctl stop keepalived"

# Time how long VIP takes to move
time ping -c 5 192.168.168.30  # expect <2s gap

# Verify VIP moved to replica
ssh akushnir@192.168.168.42 "ip addr show eth0 | grep '168.30'"

# Restore primary
ssh akushnir@192.168.168.31 "sudo systemctl start keepalived"

echo "=== Test Complete ==="
```

Expected result: VIP gap < 2 seconds, no persistent disruption.

---

## Configuration

| Parameter | Primary | Replica |
|-----------|---------|---------|
| State | MASTER | BACKUP |
| Priority | 110 | 100 |
| `virtual_router_id` | 51 | 51 |
| `advert_int` | 1s | 1s |
| `nopreempt` | ✅ yes | ❌ no |
| VIP | 192.168.168.30/24 | 192.168.168.30/24 |

Config files:
- `config/keepalived/keepalived-primary.conf`
- `config/keepalived/keepalived-replica.conf`
- `config/keepalived/notify.sh`

Deploy: `VRRP_AUTH_PASS=<secret> scripts/deploy-keepalived.sh`

---

## Related

- Issue #365 — VRRP implementation
- `environments/production/hosts.yml` — canonical host/VIP inventory
- `alert-rules.yml` — `VIPNotReachable`, `VRRPStateChange` alerts
- `grafana-observability-spine-dashboard.json` — monitoring dashboard
