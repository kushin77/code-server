# Router Update - Checkpoint & Execution Commands

**Status**: ⏳ AWAITING MANUAL EXECUTION  
**Date**: April 30, 2026  
**Critical Path**: YES (required for external failover support)  

## Router Access Instructions

Since the router is on a separate network (192.168.1.x) not accessible from development environment, execute these commands from a host that can reach your router:

### Option 1: From Local Network Device

If you have a computer/laptop on the same local network as the router:

```bash
# Step 1: Open terminal/command prompt
# Step 2: Verify router is reachable
ping 192.168.1.1

# Step 3: Open web browser
# Go to: http://192.168.1.1
# Or: https://192.168.1.1 (if HTTPS enabled)

# Step 4: Login with router credentials
# Username: [your router admin username]
# Password: [your router admin password]
```

### Option 2: From Primary Cluster Host (if network bridge exists)

If primary host (192.168.168.31) has route to 192.168.1.x network:

```bash
# From your local machine:
ssh akushnir@192.168.168.31

# From primary host, verify router reachable:
ping 192.168.1.1

# If accessible, can use curl to modify router (advanced):
curl -u admin:password http://192.168.1.1/cgi-bin/...  # (command varies by router)
```

### Option 3: Remote Access (if router supports)

Some routers allow remote admin access:

```bash
# If enabled on your router:
# Use VPN to access local network first
# Then follow Option 1 above
```

## Manual Port-Forward Update Procedure

Once you have router admin access:

### Step 1: Navigate to Port Forwarding

**Common router menu locations:**

```
TP-Link:           Advanced > NAT > Port Forwarding
Netgear:           Advanced > Port Forwarding > Port Forwarding
Asus:              WAN > Port Forwarding
Ubiquiti EdgeMax:  Firewall > NAT > Port Forwarding
Cisco:             Advanced > NAT
Mikrotik:          IP > Firewall > NAT
```

### Step 2: Find Current Rules

Look for rules matching:
```
External Port: 80   → 192.168.168.31:80
External Port: 443  → 192.168.168.31:443
```

**Screenshot current state** (for rollback if needed)

### Step 3: Edit Each Rule

**Rule 1 (Port 80):**

Change FROM:
```
External Port: 80
Protocol: TCP/UDP (or TCP)
Internal IP: 192.168.168.31  ← CURRENT
Internal Port: 80
```

Change TO:
```
External Port: 80
Protocol: TCP/UDP (or TCP)
Internal IP: 192.168.168.30  ← NEW (VIP)
Internal Port: 80
```

**Rule 2 (Port 443):**

Change FROM:
```
External Port: 443
Protocol: TCP/UDP (or TCP)
Internal IP: 192.168.168.31  ← CURRENT
Internal Port: 443
```

Change TO:
```
External Port: 443
Protocol: TCP/UDP (or TCP)
Internal IP: 192.168.168.30  ← NEW (VIP)
Internal Port: 443
```

### Step 4: Save Configuration

1. Click "Save" or "Apply"
2. Wait 10-30 seconds for router to process
3. Do NOT reboot unless router prompts
4. If router asks to reboot, do it now

### Step 5: Verify Rules Changed

In router admin panel, confirm both rules now show:
```
External Port: 80   → 192.168.168.30:80
External Port: 443  → 192.168.168.30:443
```

## Post-Update Verification

After updating router, run these verification tests:

### Quick Test (< 2 minutes)

```bash
# From any device on local network:

# Test 1: Ping VIP
ping 192.168.168.30
# Expected: Replies (from primary)

# Test 2: Direct connection to primary
curl -v http://192.168.168.31/health
# Expected: HTTP 200 OK

# Test 3: Direct connection to VIP
curl -v http://192.168.168.30/health
# Expected: HTTP 200 OK
```

### External Test (< 5 minutes)

```bash
# From external network or via VPN tunnel:

# Test 4: External DNS
curl -v http://kushnir.cloud/health
# Expected: HTTP 200 OK (from primary via VIP)

# Test 5: External HTTPS (if configured)
curl -v https://kushnir.cloud/health
# Expected: HTTP 200 OK or 301 redirect
```

### Failover Test (< 10 minutes - optional but recommended)

```bash
# From local network, before failover:
ping 192.168.168.30
# Expected: Responds (from primary)

# Stop primary keepalived:
ssh akushnir@192.168.168.31 'docker stop code-server-keepalived'

# Wait 5 seconds, then verify VIP moved:
ping 192.168.168.30
# Expected: Still responds (now from replica)

# Test external access during failover:
curl -v http://kushnir.cloud/health
# Expected: HTTP 200 OK (from replica)

# Restart primary:
ssh akushnir@192.168.168.31 'docker start code-server-keepalived'

# Wait 5 seconds, verify VIP returned:
ping 192.168.168.30
# Expected: Still responds (back on primary)

# Test external access after failback:
curl -v http://kushnir.cloud/health
# Expected: HTTP 200 OK (from primary)
```

## Common Router Actions

### Action: Find Port Forwarding Menu

```
1. Open: http://192.168.1.1
2. Login
3. Look for sections: NAT, Port Forwarding, Virtual Server, Port Mapping
4. Find rules for ports 80 and 443
```

### Action: Edit Port Forwarding Rule

```
1. Click "Edit" or "Modify" on existing rule
2. Change "Internal IP" from 192.168.168.31 to 192.168.168.30
3. Keep everything else the same
4. Click "Save"
5. Repeat for each port (80 and 443)
```

### Action: Add New Port Forwarding Rule

If no existing rules, create new ones:

```
New Rule 1:
External Port: 80
Protocol: TCP
Internal IP: 192.168.168.30
Internal Port: 80
Status: Enable

New Rule 2:
External Port: 443
Protocol: TCP
Internal IP: 192.168.168.30
Internal Port: 443
Status: Enable
```

### Action: Save Router Configuration

```
1. Click "Save" or "Apply" button
2. Wait for confirmation message
3. Do NOT unplug router
4. If prompted to reboot, click "Yes"
```

## Troubleshooting During Update

### Issue: Can't Connect to Router

```bash
# Verify router IP:
arp -a | grep -i router

# Or manually check router's default IP:
# Common router IPs: 192.168.1.1, 192.168.0.1, 10.0.0.1

# Try alternative IPs if 192.168.1.1 doesn't respond
```

### Issue: Can't Login to Router

```
Solutions:
1. Verify credentials (check router documentation)
2. Try default credentials:
   Username: admin
   Password: admin
   (or) Password: (leave blank)
3. Factory reset router if locked out
   - Hold reset button for 10 seconds
   - Wait 2 minutes for reboot
4. Access via different device (different browser)
```

### Issue: Port Forwarding Menu Not Found

```
1. Check router documentation (manual or online)
2. Look for alternate menu names:
   - Virtual Server
   - Port Mapping
   - Inbound Rules
   - Firewall Rules
3. May require Advanced menu access
4. Try router manufacturer's support chat
```

### Issue: Can't Save Changes

```
1. Check for validation errors (usually shown in red)
2. Ensure you have write permission (admin login)
3. Try different browser
4. Clear router cache:
   Ctrl+Shift+Delete (Chrome/Firefox)
   Cmd+Shift+Delete (Safari)
5. Retry login and change
```

## Rollback Procedure

If something goes wrong, quickly rollback:

```bash
# Option 1: Quick fix via router admin panel
1. Go to Port Forwarding
2. Change 192.168.168.30 back to 192.168.168.31
3. Click Save
4. Done (~30 seconds)

# Option 2: Router hard reboot
1. Unplug power for 30 seconds
2. Plug back in
3. Wait 2 minutes for startup
4. Default rules typically restore

# Option 3: Factory reset (if needed)
1. Hold reset button for 10 seconds
2. Wait 2 minutes for startup
3. Reconfigure port forwarding manually
```

## Router Update Checklist

### Before Update
- [ ] Router IP address known (usually 192.168.1.1)
- [ ] Router admin credentials available
- [ ] Local device can reach router (ping test)
- [ ] Screenshot current port-forward rules
- [ ] Read this guide completely

### During Update
- [ ] Access router admin panel
- [ ] Find Port Forwarding section
- [ ] Identify rules for ports 80 and 443
- [ ] Edit Rule 1 (port 80): Change IP to 192.168.168.30
- [ ] Edit Rule 2 (port 443): Change IP to 192.168.168.30
- [ ] Save configuration
- [ ] Wait for confirmation

### After Update
- [ ] Verify rules show 192.168.168.30
- [ ] Ping VIP from local network (ping 192.168.168.30)
- [ ] Test external access (curl http://kushnir.cloud/health)
- [ ] Document completion time
- [ ] Notify operations team

### Optional Testing
- [ ] Run failover test (stop primary)
- [ ] Verify external access during failover
- [ ] Run failback test (start primary)
- [ ] Document results

## Sign-Off

✅ **READY FOR ROUTER UPDATE EXECUTION**

All instructions provided. No special tools or scripts needed. Manual web interface configuration sufficient.

**Next Steps**:
1. Access router from device on local network
2. Update port-forward rules as documented
3. Verify changes saved
4. Run verification tests
5. Document completion

**Timeline**: ~15 minutes from start to finish

---

**Prepared**: April 30, 2026  
**Status**: CHECKPOINT - Awaiting Manual Execution  
**Priority**: Medium (enables external failover, non-blocking)  
**Effort**: Low (5-10 clicks in web interface)  
**Risk**: Low (quick rollback available, no data risk)
