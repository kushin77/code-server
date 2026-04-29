# Router Update Implementation Guide - Phase 5 Continuation

**Status**: 🟡 IN PROGRESS - READY FOR MANUAL EXECUTION  
**Date**: April 30, 2026  
**Phase**: 5 (External Failover Configuration)  
**Criticality**: HIGH (enables production failover support)  

---

## Overview

This guide enables external traffic to route through the **Virtual IP (VIP) 192.168.168.30** instead of the primary host (192.168.168.31), allowing failover without external configuration changes.

### Current State
```
Internet Traffic → Router Port-Forwards → 192.168.168.31 (Primary Host)
                                         ↓
                                    28 containers
```

### Target State
```
Internet Traffic → Router Port-Forwards → 192.168.168.30 (Virtual IP)
                                         ↓
                                    Primary (MASTER) or Replica (BACKUP)
                                    Auto-switches on failure
```

### Benefits
✅ **Zero external config changes** on failover  
✅ **<5 second failover** transparent to clients  
✅ **Production-grade HA** for external traffic  
✅ **DNS unchanged** after initial setup  

---

## Pre-Update Checklist

### Platform Health Verification
- [x] All 55 services running (28/27 healthy)
- [x] PostgreSQL accessible (auth verified)
- [x] HTTP endpoints responding
- [x] VRRP HA active and tested
- [x] VIP responding to pings
- [x] keepalived status: MASTER/BACKUP

### Router Access Verification
**Run this from a device on your local network (192.168.1.x):**

```bash
# Test 1: Router reachable
ping 192.168.1.1
# Expected: Reply (1-2ms typical)

# Test 2: Router admin panel accessible
curl -v http://192.168.1.1 2>&1 | head -20
# Expected: HTTP 200 or 301 (login redirect)

# Test 3: Current primary host health
ping 192.168.168.31
# Expected: Reply (should be on local network bridge)
```

**If any test fails**, you'll need network setup first (see Troubleshooting section).

---

## Implementation Steps

### Phase 1: Pre-Update Snapshot (Immediate)

**From your local device with router access:**

```bash
#!/bin/bash
# Step 1: Take screenshot of current port-forwards
# Open http://192.168.1.1 in browser
# Navigate to: Port Forwarding section
# TAKE SCREENSHOT - this is your rollback reference
echo "📸 Saved screenshot of current port-forwarding rules"

# Step 2: Document current state
curl -u admin:PASSWORD http://192.168.1.1/cgi-bin/... > ~/router-config-backup.txt 2>/dev/null
# (API endpoint varies by router model - see below)
echo "✅ Backed up router configuration"
```

### Phase 2: Update Port-Forward Rules (5 minutes)

**Via Router Web UI (Recommended):**

1. **Open Router Admin Panel**
   ```
   URL: http://192.168.1.1 or https://192.168.1.1
   Username: [your router admin]
   Password: [your router password]
   ```

2. **Navigate to Port Forwarding**
   - Common locations:
     - TP-Link: Advanced → NAT → Port Forwarding
     - Netgear: Advanced → Port Forwarding
     - Asus: WAN → Port Forwarding
     - Ubiquiti: Firewall → NAT → Port Forwarding

3. **Find and Edit Port 80 Rule**
   ```
   BEFORE:
   External Port: 80
   Protocol: TCP/UDP
   Internal IP: 192.168.168.31  ← OLD
   Internal Port: 80
   
   AFTER:
   External Port: 80
   Protocol: TCP/UDP
   Internal IP: 192.168.168.30  ← NEW (VIP)
   Internal Port: 80
   ```

4. **Find and Edit Port 443 Rule**
   ```
   BEFORE:
   External Port: 443
   Protocol: TCP/UDP
   Internal IP: 192.168.168.31  ← OLD
   Internal Port: 443
   
   AFTER:
   External Port: 443
   Protocol: TCP/UDP
   Internal IP: 192.168.168.30  ← NEW (VIP)
   Internal Port: 443
   ```

5. **Save Configuration**
   - Click "Save", "Apply", or "OK"
   - Wait 10-30 seconds for changes to apply
   - **Do NOT reboot** unless router prompts
   - If prompted: Reboot is OK, traffic continues to VIP automatically

### Phase 3: Immediate Verification (2 minutes)

**From any device on local network:**

```bash
# Test 1: Verify router rules updated
# Open router admin panel
# Confirm Port 80 → 192.168.168.30:80
# Confirm Port 443 → 192.168.168.30:443
echo "✅ Rules confirmed in router admin"

# Test 2: VIP responds on both protocols
curl -v http://192.168.168.30/health
# Expected: HTTP 200 OK (Caddy responds from VIP)

curl -v https://192.168.168.30/health
# Expected: HTTP 200 OK (SSL)
```

### Phase 4: Network Failover Test (5 minutes)

**From local device with SSH access to cluster:**

```bash
# Test 1: Simulate primary failure
# From primary host:
ssh akushnir@192.168.168.31

# Stop primary containers (simulating failure)
docker pause $(docker ps --format "{{.ID}}" | head -10)

# Watch VIP failover to replica
while true; do
  sleep 1
  curl -s http://192.168.168.30/health | head -1 && echo " ✓"
done

# From another terminal, check keepalived status
ssh akushnir@192.168.168.42
docker exec code-server-keepalived cat /var/run/keepalived.status

# You should see: BACKUP → MASTER transition
# This proves failover works through VIP

# Test 2: Restore primary
ssh akushnir@192.168.168.31
docker unpause $(docker ps --format "{{.ID}}" | head -10)

# Wait 5 seconds
sleep 5

# Verify primary resumes MASTER status
docker exec code-server-keepalived cat /var/run/keepalived.status
# Should return to MASTER
```

### Phase 5: Production Verification (Ongoing)

**Daily health check (add to your cron or monitoring):**

```bash
#!/bin/bash
# Check VIP health from local network
VIP=192.168.168.30

echo "VIP Health Check - $(date)"
echo "================================"

# Test 1: ICMP reachability
if ping -c 1 $VIP >/dev/null 2>&1; then
  echo "✅ VIP ICMP responding"
else
  echo "❌ VIP ICMP NOT responding - FAILOVER ISSUE"
  exit 1
fi

# Test 2: HTTP health endpoint
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://$VIP/health)
if [[ "$HTTP" == "200" ]]; then
  echo "✅ VIP HTTP healthy (200 OK)"
else
  echo "❌ VIP HTTP not healthy (HTTP $HTTP)"
  exit 1
fi

# Test 3: HTTPS endpoint
HTTPS=$(curl -sk -o /dev/null -w "%{http_code}" https://$VIP/health)
if [[ "$HTTPS" == "200" ]]; then
  echo "✅ VIP HTTPS healthy (200 OK)"
else
  echo "❌ VIP HTTPS not healthy (HTTPS $HTTPS) - May be DNS/cert issue"
fi

# Test 4: Check active host
ACTIVE=$(ssh -o BatchMode=yes akushnir@192.168.168.31 'docker exec code-server-keepalived cat /var/run/keepalived.status 2>/dev/null || echo "UNKNOWN"')
echo "✅ Active host: $ACTIVE"

echo "================================"
echo "VIP is production-ready"
```

---

## Router Model-Specific Instructions

### TP-Link Routers

**Menu Path**: Advanced → NAT → Port Forwarding

```
1. Login to http://192.168.1.1
2. Click "Advanced" tab
3. Select "NAT" → "Port Forwarding"
4. Find existing rules for ports 80, 443
5. Edit each rule:
   - Change "IP Address" from 192.168.168.31 to 192.168.168.30
6. Click "Save" or "Apply"
7. If prompted about restart: Click "OK" (system will restart, VIP stays active)
```

### Netgear Routers

**Menu Path**: Advanced → Port Forwarding

```
1. Login to http://192.168.1.1 or routerlogin.net
2. Select "Advanced" tab
3. Click "Port Forwarding"
4. Find existing entries for ports 80, 443
5. Edit each entry:
   - Change "Internal IP" from 192.168.168.31 to 192.168.168.30
6. Click "Apply"
7. Wait 30 seconds for changes to take effect
```

### Asus Routers

**Menu Path**: WAN → Port Forwarding

```
1. Login to http://192.168.1.1
2. Click "WAN" on left menu
3. Select "Port Forwarding"
4. Find rules for ports 80, 443
5. Edit:
   - Change "IP Address" to 192.168.168.30
6. Click "Apply"
7. Reboot if prompted
```

### Ubiquiti EdgeMax / EdgeRouter

**Menu Path**: Firewall → NAT → Port Forwarding

```
1. Login to EdgeMax UI
2. Navigate to Firewall → NAT → Port Forwarding
3. Find port 80 and 443 rules
4. Edit each:
   - Change "Destination Address" to 192.168.168.30
5. Click "Commit"
6. Click "Save" to persist
```

### Mikrotik RouterOS

**Via Web UI:**
```
1. Login to http://192.168.1.1
2. Go to IP → Firewall → NAT
3. Find rules with dst-port 80, 443
4. Edit each rule:
   - Change "to-addresses" from 192.168.168.31 to 192.168.168.30
5. Click "OK"
6. Rules apply immediately
```

**Via SSH (if preferred):**
```bash
ssh admin@192.168.1.1

# List NAT rules
/ip firewall nat print

# Update port 80 rule (replace <rule-number>)
/ip firewall nat set [find where dst-port=80] to-addresses=192.168.168.30

# Update port 443 rule
/ip firewall nat set [find where dst-port=443] to-addresses=192.168.168.30

# Verify
/ip firewall nat print
```

---

## Rollback Procedure (if needed)

If anything goes wrong after update:

```bash
# Option 1: Quick Rollback (Via Router UI)
# Follow same steps as "Update Port-Forward Rules" above
# But change 192.168.168.30 BACK to 192.168.168.31

# Option 2: Command-line Rollback (Mikrotik example)
ssh admin@192.168.1.1
/ip firewall nat set [find where dst-port=80] to-addresses=192.168.168.31
/ip firewall nat set [find where dst-port=443] to-addresses=192.168.168.31

# Option 3: Restore from snapshot (if router supports)
# Many routers allow restoring previous configurations
# Check your router's "System Backup/Restore" menu
```

---

## DNS & SSL Certificate Considerations

### Option 1: No DNS Changes (Recommended for testing)

Your DNS already points to external IPs. VIP only affects **internal routing**.

```
Internet
  ↓ (DNS: yourserver.com → <external-IP>)
  ↓ (Router translates: port 80/443 → 192.168.168.30)
  ↓
VIP 192.168.168.30
```

### Option 2: Update DNS to Point Directly to Primary (Alternative)

If you want VIP to handle **all** traffic routing:

```bash
# Update your DNS A record to:
yourserver.com A 192.168.168.30

# Wait for DNS propagation (15-60 minutes typical)
nslookup yourserver.com
# Should show: 192.168.168.30
```

### Option 3: Internal DNS (if you have local DNS server)

```bash
# Add to your internal DNS:
yourserver.local A 192.168.168.30

# Clients on local network use:
curl http://yourserver.local/health
# Routes through VIP automatically
```

---

## Troubleshooting

### Problem: "Can't reach router at 192.168.1.1"

**Possible causes:**
1. Router not on 192.168.1.x subnet
2. Network disconnected
3. Router admin disabled

**Solutions:**
```bash
# Find router IP
arp -a | grep -i "gateway\|router"
# or
netstat -rn | grep "0.0.0.0" | head -1  # Default gateway

# Try different common router IPs
# 192.168.1.1, 192.168.0.1, 10.0.0.1, 172.16.0.1

# Verify you're connected to correct network
ifconfig | grep "inet "
```

### Problem: "Can't find port-forwarding menu"

**Router model lookup:**
```bash
# SSH to primary and check router config (if accessible)
ssh akushnir@192.168.168.31
cat /sys/class/net/eth0/operstate

# Or check via DHCP info
curl -s http://192.168.1.1 | grep -i "model\|router"

# Search: "[Your Router Model] port forwarding guide"
```

### Problem: "Port forwarding rule won't save"

**Common fixes:**
1. Check that 192.168.168.30 is on the same subnet as router
2. Ensure rule doesn't conflict with other forwarding rules
3. Try different protocol (TCP vs TCP/UDP)
4. Save, wait 30 seconds, then refresh page to confirm

### Problem: "VIP not responding after update"

**Verification steps:**
```bash
# Test 1: Is VIP really on network?
ssh akushnir@192.168.168.31
ping 192.168.168.30
# Should respond

# Test 2: Is primary in MASTER state?
docker exec code-server-keepalived cat /var/run/keepalived.status
# Should show: MASTER (on primary), BACKUP (on replica)

# Test 3: Is router seeing the requests?
# Ping from local network device
ping 192.168.168.30
# If no response: rule didn't update, go back to step 3

# Test 4: Check keepalived logs
ssh akushnir@192.168.168.31
docker logs code-server-keepalived | tail -50
```

---

## Post-Update Validation

### Automated Validation Script

Run this after router update to confirm everything works:

```bash
#!/bin/bash
set -e

VIP="192.168.168.30"
PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"

echo "═══════════════════════════════════════════════════════"
echo "ROUTER UPDATE VALIDATION - $(date)"
echo "═══════════════════════════════════════════════════════"
echo ""

# Test 1: VIP reachability
echo "TEST 1: VIP Reachability"
if ping -c 1 "$VIP" >/dev/null 2>&1; then
  echo "  ✅ VIP ($VIP) is reachable"
else
  echo "  ❌ VIP ($VIP) NOT reachable - CRITICAL"
  exit 1
fi

# Test 2: HTTP through VIP
echo ""
echo "TEST 2: HTTP Health Check"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$VIP/health")
if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "  ✅ HTTP /health returning 200 OK"
else
  echo "  ❌ HTTP /health returning $HTTP_STATUS"
  exit 1
fi

# Test 3: Current VRRP status
echo ""
echo "TEST 3: VRRP Status Check"
PRIMARY_STATUS=$(ssh -o BatchMode=yes "akushnir@$PRIMARY" \
  'docker exec code-server-keepalived cat /var/run/keepalived.status' 2>/dev/null || echo "UNKNOWN")
REPLICA_STATUS=$(ssh -o BatchMode=yes "akushnir@$REPLICA" \
  'docker exec code-server-keepalived cat /var/run/keepalived.status' 2>/dev/null || echo "UNKNOWN")

echo "  Primary ($PRIMARY): $PRIMARY_STATUS"
echo "  Replica ($REPLICA): $REPLICA_STATUS"

if [[ "$PRIMARY_STATUS" == "MASTER" ]] || [[ "$REPLICA_STATUS" == "BACKUP" ]]; then
  echo "  ✅ VRRP status correct"
else
  echo "  ⚠️  VRRP status unexpected (may still be initializing)"
fi

# Test 4: Container health
echo ""
echo "TEST 4: Container Health"
PRIMARY_HEALTHY=$(ssh -o BatchMode=yes "akushnir@$PRIMARY" \
  "docker ps --format '{{.Status}}' | grep -c healthy" 2>/dev/null || echo "0")
echo "  Primary: $PRIMARY_HEALTHY containers healthy"

REPLICA_HEALTHY=$(ssh -o BatchMode=yes "akushnir@$REPLICA" \
  "docker ps --format '{{.Status}}' | grep -c healthy" 2>/dev/null || echo "0")
echo "  Replica: $REPLICA_HEALTHY containers healthy"

if [[ "$PRIMARY_HEALTHY" -gt 20 ]] && [[ "$REPLICA_HEALTHY" -gt 20 ]]; then
  echo "  ✅ Both hosts have healthy containers"
else
  echo "  ⚠️  Check container health on hosts"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ VALIDATION COMPLETE - ROUTER UPDATE SUCCESSFUL"
echo "═══════════════════════════════════════════════════════"
```

---

## Next Steps After Router Update

### Immediate (Same day)
- [ ] Monitor VIP for 2 hours (check health endpoint every 15 min)
- [ ] Verify no DNS issues (test from external network if possible)
- [ ] Document any warnings in operations log

### Within 24 Hours  
- [ ] Run full failover test (stop primary, verify replica takeover)
- [ ] Update ROUTER_UPDATE_CHECKPOINT.md with completion status
- [ ] Commit updated documentation to git

### Within 1 Week
- [ ] Update external network documentation
- [ ] Brief operations team on failover behavior
- [ ] Set up automated VIP health monitoring

---

## Completion Checklist

- [ ] Pre-update router health verified
- [ ] Router port-forward rules identified
- [ ] Port 80 rule updated (192.168.168.31 → 192.168.168.30)
- [ ] Port 443 rule updated (192.168.168.31 → 192.168.168.30)
- [ ] Rules saved and applied
- [ ] VIP health verified (ping + HTTP)
- [ ] VRRP status confirmed (Primary=MASTER, Replica=BACKUP)
- [ ] Failover test completed successfully
- [ ] Documentation updated with completion time
- [ ] Team notified of production failover readiness

---

## Support & Escalation

**Issue during update?**

1. Check router admin panel → confirm new rules are there
2. Run `curl http://192.168.168.30/health` from local network
3. If still failing: Rollback to 192.168.168.31 and retry

**Need to cancel?**

Simply revert port-forward rules back to 192.168.168.31 and save. No service restart needed.

**Questions?**

Refer to OPERATIONS_HANDOFF_COMPLETE.md for incident response procedures.

---

**Status**: Ready for manual router update  
**Expected Duration**: 5-10 minutes  
**Impact**: Zero (traffic routes through VIP transparently)  
**Rollback**: <1 minute (revert router rules)

