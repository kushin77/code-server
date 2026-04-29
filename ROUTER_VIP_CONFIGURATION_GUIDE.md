# Router Configuration - VIP Port-Forward Update

**Status**: ⏳ PENDING MANUAL EXECUTION  
**Date**: April 30, 2026  
**Purpose**: Enable external failover via VIP  

## Overview

Currently, external traffic routes through primary host IP (192.168.168.31). This guide updates the router to route through VIP (192.168.168.30) for automatic failover when primary is unavailable.

## Current Configuration

```
Router Port-Forward Rules (Before):
├── WAN Port 80 → 192.168.168.31:80 (primary only)
├── WAN Port 443 → 192.168.168.31:443 (primary only)
└── Impact: External users only reach primary; no automatic failover
```

## Target Configuration

```
Router Port-Forward Rules (After):
├── WAN Port 80 → 192.168.168.30:80 (VIP - automatic failover)
├── WAN Port 443 → 192.168.168.30:443 (VIP - automatic failover)
└── Impact: External users reach VIP; automatic failover to replica if primary down
```

## Step-by-Step Router Update

### Prerequisites
- Router admin credentials
- SSH access to cluster hosts (for testing)
- ~15 minutes availability

### Step 1: Access Router Admin Panel

**For most routers:**
```
1. Open browser: http://192.168.1.1 (or your router IP)
2. Login with admin credentials
3. Navigate to: Advanced > Port Forwarding (or similar menu)
```

**Router menu locations by brand:**
- TP-Link: Forwarding > Port Forwarding
- Netgear: Port Forwarding/Port Triggering
- Asus: WAN > Port Forwarding
- Ubiquiti: Network > Port Forwarding
- Cisco: Services > Port Forwarding

### Step 2: Locate Existing Rules

Find existing rules for ports 80 and 443:
- **Rule 1**: External Port 80 → Internal 192.168.168.31:80
- **Rule 2**: External Port 443 → Internal 192.168.168.31:443

**Screenshot the current rules** (for rollback if needed)

### Step 3: Update Port-Forward Rules

**For each rule (80 and 443):**

Change FROM:
```
External Port: 80 or 443
Protocol: TCP
Internal IP: 192.168.168.31
Internal Port: 80 or 443
```

Change TO:
```
External Port: 80 or 443
Protocol: TCP
Internal IP: 192.168.168.30  ← CHANGED
Internal Port: 80 or 443
```

**Update both rules** (port 80 AND port 443)

### Step 4: Save Configuration

1. Click "Save" or "Apply" on router
2. Wait for router to apply changes (usually 10-30 seconds)
3. Do NOT reboot unless router prompts you
4. If router requires reboot, do it now

### Step 5: Verification

#### Test 1: Verify Rules Changed

```bash
# Check if rules are saved
# (Most routers show in admin panel, status page, or via SSH)
```

#### Test 2: Verify Primary Still Reachable

```bash
# From local network:
ping 192.168.168.31
ping 192.168.168.30 (VIP)

# Should both respond
```

#### Test 3: Verify External Port 80

```bash
# From external network or via tunnel:
curl -v http://kushnir.cloud/health

# Expected:
# - HTTP 200 OK response
# - Content: "OK" or similar health status
# - No timeouts or connection refused
```

#### Test 4: Verify External Port 443 (if HTTPS)

```bash
# From external network:
curl -v https://kushnir.cloud/health

# Expected:
# - HTTP 200 OK (or 301 redirect to HTTPS)
# - Valid SSL certificate
# - Response from server
```

#### Test 5: Verify VIP Ownership

On local network, verify VIP is on primary:
```bash
ssh akushnir@192.168.168.31 'ip addr show | grep 192.168.168.30'

# Should output: inet 192.168.168.30/24 scope global secondary enp0s25
```

## Failover Verification After Update

### Test 1: Simulate Primary Failure

```bash
# On primary host:
ssh akushnir@192.168.168.31 'docker stop code-server-keepalived'

# Wait 5 seconds for failover

# Verify VIP moved to replica:
ssh akushnir@192.168.168.42 'ip addr show | grep 192.168.168.30'

# Should output: inet 192.168.168.30/24 scope global secondary eno1

# Test external access still works:
curl -v http://kushnir.cloud/health
# Should still respond (now from replica)
```

### Test 2: Verify Automatic Failback

```bash
# Restart primary keepalived:
ssh akushnir@192.168.168.31 'docker start code-server-keepalived'

# Wait 5 seconds for failback

# Verify VIP returned to primary:
ssh akushnir@192.168.168.31 'ip addr show | grep 192.168.168.30'

# Should output: inet 192.168.168.30/24 scope global secondary enp0s25

# Test external access still works:
curl -v http://kushnir.cloud/health
# Should respond from primary again
```

## Rollback Procedure (If Issues Occur)

If external access breaks after router update:

### Quick Rollback (< 2 minutes)

```bash
# In router admin panel:
1. Go to Port Forwarding
2. Change 192.168.168.30 back to 192.168.168.31
3. Save
4. Test: curl http://kushnir.cloud/health
```

### Extended Rollback (If router unresponsive)

```bash
# Option 1: Hard reset router
1. Power cycle: Turn off router for 30 seconds
2. Power on: Wait for LED stabilization
3. Re-enter settings: Default rules will restore

# Option 2: SSH to router (if available)
ssh admin@192.168.1.1 'restore-defaults'  # command varies by router

# Option 3: Factory reset
1. Locate reset button (usually recessed)
2. Press for 10 seconds while powered on
3. Wait 2 minutes for reboot
4. Re-enter port-forward rules manually
```

## Advanced: Verify DNS Points to Correct IP

```bash
# Check DNS resolution:
nslookup kushnir.cloud
# or
dig kushnir.cloud

# Should resolve to:
# - 192.168.168.30 (VIP - best choice for HA)
# - or external IP that router forwards from
```

**Note**: If DNS points to primary IP (192.168.168.31), update DNS to VIP (192.168.168.30) for best failover support. (Separate DNS update may be needed - consult your DNS provider)

## Success Criteria ✅

| Criterion | How to Verify | Expected Result |
|-----------|---------------|-----------------|
| Router rules saved | Check admin panel | Rules show 192.168.168.30 |
| VIP accessible | `ping 192.168.168.30` | Responds (from primary) |
| External port 80 works | `curl http://kushnir.cloud/health` | HTTP 200 OK |
| External port 443 works | `curl https://kushnir.cloud/health` | HTTP 200 OK |
| Failover works | Stop primary, test external | Still responds (from replica) |
| Failback works | Start primary, test external | Responds with lower latency |

## Testing Timeline

```
T+0:00  Update router rules
T+0:05  Verify rules saved, test primary/VIP accessible
T+0:10  Test external port 80 access
T+0:15  Test external port 443 access
T+0:20  Verify VIP on primary (ip addr show)
T+0:25  PASSED - router configuration complete

Optional (for full HA verification):
T+0:30  Failover test: Stop primary keepalived
T+0:35  Verify VIP moved to replica
T+0:40  Verify external access still works
T+0:45  Failback test: Start primary keepalived
T+0:50  Verify VIP returned to primary
T+0:55  PASSED - HA failover verified end-to-end
```

## Common Issues & Solutions

### Issue: External access fails after update

**Diagnosis:**
```bash
# Test direct VIP:
curl -v http://192.168.168.30/health

# Test via router rules (external):
curl -v http://kushnir.cloud/health
```

**Solutions:**
1. Verify both rules changed (ports 80 AND 443)
2. Check VIP is active: `ssh akushnir@192.168.168.31 'ip addr show | grep 192.168.168.30'`
3. Verify Caddy running: `ssh akushnir@192.168.168.31 'docker ps | grep caddy'`
4. Rollback if needed: Change 192.168.168.30 back to 192.168.168.31

### Issue: Port 80 works but port 443 fails

**Diagnosis:**
```bash
curl -v http://kushnir.cloud/health    # Port 80 test
curl -v https://kushnir.cloud/health   # Port 443 test
```

**Solution:**
- Verify SSL certificate is valid: `openssl s_client -connect kushnir.cloud:443`
- Check port 443 rule was updated to VIP
- Verify Caddy is listening on both ports

### Issue: Failover doesn't work after router update

**Diagnosis:**
```bash
# Test failover manually:
ssh akushnir@192.168.168.31 'docker stop code-server-keepalived'
sleep 5
ssh akushnir@192.168.168.42 'ip addr show | grep 192.168.168.30'
# Should show VIP on replica

# Test external access during failover:
curl -v http://kushnir.cloud/health
```

**Solution:**
- Verify keepalived containers running on both hosts
- Check VIP actually moved to replica
- Verify network connectivity to replica
- Test direct replica access: `curl http://192.168.168.42/health`

## Support & Escalation

### Self-Service
- Router rules not saving: Try again, some routers delay
- External access timing out: Check both port 80 AND 443 rules
- DNS not resolving: Flush DNS cache on client

### Infrastructure Team
- Router admin credentials not working: Contact IT
- Router doesn't support port forwarding: Upgrade router or use alternative
- Network blocking port 80/443: Firewall policy may need update

### Platform Team (Critical)
- Both primary and replica unreachable from external: Check if router is online
- VIP not moving during failover: keepalived troubleshooting needed
- Cascading failures during router update: Rollback and investigate

## Documentation References

- **Primary Deployment**: KEEPALIVED_HA_DEPLOYMENT_COMPLETE.md
- **Operations Guide**: KEEPALIVED_OPERATIONS_HANDOFF.md
- **Architecture**: KEEPALIVED_CONTAINER_DEPLOYMENT_READY.md
- **Troubleshooting**: See KEEPALIVED_OPERATIONS_HANDOFF.md section "Troubleshooting"

## Sign-Off

✅ **ROUTER UPDATE READY FOR EXECUTION**

All steps documented. All testing procedures included. Ready for operations team to execute.

**Current Status**:
- ✅ Keepalived deployed on both hosts
- ✅ VIP 192.168.168.30 managed by VRRP
- ✅ Failover tested internally
- ⏳ Router port-forward update (next step - this guide)
- ⏳ External failover verification (after router update)

**Next Steps**:
1. Follow Step 1-5 above to update router
2. Execute verification tests
3. Document failover test results
4. Notify operations team of completion

---

**Created**: April 30, 2026  
**Status**: READY FOR IMPLEMENTATION  
**Time to Execute**: ~15 minutes  
**Risk Level**: 🟡 MEDIUM (15-30 second service interruption possible during failover test)  
**Rollback Time**: < 2 minutes (if needed)
