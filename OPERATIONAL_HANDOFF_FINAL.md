# HA Operational Handoff - April 30, 2026

**Prepared for**: Manual deployment and operations  
**Current Date**: April 30, 2026  
**Platform**: kushnir.cloud (ElevatedIQ Code Server Enterprise)  
**Status**: 🟢 Primary Operational | 🟡 Replica Partial | 🟡 HA Pending

---

## Executive Summary

The platform is **production-ready on the primary host** with Caddy reverse proxy and 53+ containers operational. HA infrastructure (keepalived + VIP) is staged and ready for manual deployment. Replica host is operational but blocked from accepting external traffic due to port 80 conflict with Kubernetes ingress controller.

### Current Metrics
- **Primary Containers**: 53 running (all core services healthy)
- **Replica Containers**: 9 running (partial deployment, no external gateway)
- **Caddy Status**: ✅ Primary (port 80/443) | ❌ Replica (blocked)
- **Keepalived Status**: 📋 Configs staged | ⏳ Requires manual sudo to install
- **VIP Status**: 📋 Ready for deployment | ⏳ Not yet active
- **DNS**: kushnir.cloud → 173.77.179.148 (Cloudflare) → Router port-forward → Primary (.31)

---

## Operational Status

### Primary Host (192.168.168.31) - ✅ FULLY OPERATIONAL

#### Caddy Gateway
- **Status**: Running (34+ minutes uptime)
- **Ports**: 80→80, 443→443 (both TCP and UDP)
- **Health**: http://127.0.0.1/health → HTTP 200 "OK"
- **Config**: /tmp/Caddyfile (deployed, uses ${APEX_DOMAIN}=kushnir.cloud)

#### Core Services (All Healthy)
| Service | Port | Status | Type |
|---------|------|--------|------|
| PostgreSQL | 5432 | ✅ Healthy | Database |
| Redis | 6379 | ✅ Healthy | Cache |
| GitLab | 80/443 | ✅ Healthy | Repository |
| Vault | 8200 | ✅ Healthy | Secrets |
| MinIO | 9001 | ✅ Healthy | Storage |
| Code Server IDE | 8080 | ✅ Healthy | Dev Environment |
| OAuth2-Proxy | 4180 | ✅ Healthy | Auth Gateway |
| Agents (Runtime, Code Reviewer, etc.) | 8080-8100 | ✅ Healthy | AI Services |

#### Total Container Count: **53 running**

#### Keepalived HA (Staged, Ready for Deployment)
- **Config File**: `/tmp/keepalived.conf` (734 bytes)
- **Health Check**: `/tmp/check-caddy-health.sh` (262 bytes, executable)
- **VIP Configuration**: 192.168.168.30/24 (currently unused)
- **VRRP Instance**: VI_1 (state=MASTER, priority=100)
- **Health Check Interval**: 3 seconds
- **Failover Threshold**: 3 failed checks = 9 seconds total
- **Health Check Command**: `curl http://127.0.0.1/health`

### Replica Host (192.168.168.42) - ⚠️ PARTIAL / BLOCKED

#### Deployment Status
- **Containers**: 9 running (hermes*, some code-server services stopped)
- **Issue**: Caddy cannot bind to port 80/443
- **Root Cause**: `nginx-ingress-controller` (Kubernetes, PID 17349, user "message+") holds port 80/443
- **Evidence**: ~40 listening sockets on port 80 (netstat shows orphaned connections)

#### Docker-Compose Status
- **Config**: /tmp/docker-compose.enterprise.yml synced
- **Caddyfile**: /tmp/Caddyfile deployed
- **Env Vars**: Set in .env.production (OAUTH2_COOKIE_SECRET, DB_PASSWORD, etc.)
- **Keepalived**: Configs staged in /tmp/ (same as primary)

#### Port 80 Blocker Analysis
```
Process: /nginx-ingress-controller
  --publish-service=ingress-nginx/ingress-nginx-controller
  --ingress-class=nginx
  --configmap=ingress-nginx/ingress-nginx-controller

User: message+ (non-root)
PID: ~17349
Port: 0.0.0.0:80 (held by Kubernetes ingress system)
Status: NOT systemctl-managed, NOT Docker, NOT nginx service
```

---

## Manual Deployment Procedures

### 1. Deploy Keepalived on Primary (MANUAL - REQUIRES SUDO)

**Prerequisites**: SSH access to primary with sudo capability

**Steps**:
```bash
# SSH into primary
ssh akushnir@192.168.168.31

# Install keepalived
sudo apt-get update
sudo apt-get install -y keepalived

# Deploy configuration
sudo cp /tmp/keepalived.conf /etc/keepalived/keepalived.conf
sudo cp /tmp/check-caddy-health.sh /usr/local/bin/check-caddy-health.sh
sudo chmod +x /usr/local/bin/check-caddy-health.sh

# Enable and start
sudo systemctl enable keepalived
sudo systemctl restart keepalived

# Verify VIP activation
ip addr show eth0 | grep 192.168.168.30
# Should output: inet 192.168.168.30/24 scope global secondary eth0

# Check keepalived status
sudo systemctl status keepalived
sudo tail -f /var/log/syslog | grep -i keepalived
```

**Expected Output After VIP Activation**:
```
inet 192.168.168.30/24 scope global secondary eth0
```

**Verification Commands**:
```bash
# Check VIP is active on primary
ssh akushnir@192.168.168.31 'ip addr show eth0 | grep 192.168.168.30'

# Check keepalived is running
ssh akushnir@192.168.168.31 'sudo systemctl is-active keepalived'

# Monitor health checks
ssh akushnir@192.168.168.31 'sudo tail -20 /var/log/syslog | grep -i keepalived'
```

### 2. Resolve Replica Port 80 Blocker (CHOOSE ONE OPTION)

#### Option A: Kill nginx-ingress-controller (Recommended)
```bash
ssh akushnir@192.168.168.42

# Identify ingress controller process
ps aux | grep nginx-ingress-controller

# Kill it (requires sudo)
sudo pkill -9 -f "nginx-ingress-controller"

# Verify port is free
netstat -tlnp 2>/dev/null | grep ":80 " | wc -l
# Should return: 0

# Then restart docker-compose
cd ~/code-server-enterprise
docker-compose -f docker-compose.enterprise.yml up -d
```

**Risk**: May break Kubernetes/ingress traffic if still in use

**Benefit**: Full HA capability, both hosts can serve traffic

#### Option B: Run Caddy on Alternate Port
```bash
# On replica, run Caddy on port 8080 instead of 80
ssh akushnir@192.168.168.42 '
docker rm -f code-server-caddy 2>/dev/null
docker run -d \
  --name code-server-caddy \
  --network services \
  --restart unless-stopped \
  -p 8080:80 \
  -p 8443:443 \
  -p 8443:443/udp \
  -v /tmp/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v caddy-data:/data \
  -e APEX_DOMAIN=kushnir.cloud \
  caddy:2.7.4 caddy run --config /etc/caddy/Caddyfile
'
```

**Benefit**: Doesn't affect ingress controller

**Limitation**: External traffic cannot reach replica (health check will fail, VIP won't failover to replica)

#### Option C: Configure Passwordless Sudo for akushnir User
```bash
# On replica (requires root or current sudo access)
sudo visudo

# Add this line:
# akushnir ALL=(ALL) NOPASSWD: /usr/bin/pkill

# Then use Option A
```

### 3. Deploy Keepalived on Replica (AFTER PRIMARY IS DONE)

**Same steps as primary** (section 1):
```bash
ssh akushnir@192.168.168.42

sudo apt-get update
sudo apt-get install -y keepalived

# Note: Replica will have BACKUP priority (90) automatically in /tmp/keepalived.conf
sudo cp /tmp/keepalived.conf /etc/keepalived/keepalived.conf
sudo cp /tmp/check-caddy-health.sh /usr/local/bin/check-caddy-health.sh
sudo chmod +x /usr/local/bin/check-caddy-health.sh

sudo systemctl enable keepalived
sudo systemctl restart keepalived

# Verify replica DOES NOT have VIP (it should be on primary)
ip addr show eth0 | grep 192.168.168.30
# Should return nothing (VIP is on primary/MASTER)
```

### 4. Update Router/DNS to Use VIP (AFTER BOTH KEEPALIVED INSTANCES RUNNING)

**Prerequisites**: Access to router admin panel

**Steps**:
1. **Router Port-Forward**: Change target IP from 192.168.168.31 → 192.168.168.30
   - Old: 0.0.0.0:80 → 192.168.168.31:80
   - New: 0.0.0.0:80 → 192.168.168.30:80
   - Same for 443

2. **DNS Configuration**: 
   - Update DNS A record for kushnir.cloud to point to 192.168.168.30
   - Or keep at 173.77.179.148 (Cloudflare) with port-forward at router

3. **Verification** (after DNS propagation):
   ```bash
   # Should resolve to VIP
   dig kushnir.cloud
   
   # Should be reachable
   curl -I https://kushnir.cloud
   
   # On primary, should see VIP
   ssh akushnir@192.168.168.31 'ip addr show eth0 | grep 192.168.168.30'
   ```

### 5. Test Automatic Failover (AFTER FULL HA DEPLOYMENT)

#### Test 1: Verify VIP Ownership
```bash
# Should be on primary (MASTER)
ssh akushnir@192.168.168.31 'ip addr show eth0 | grep 192.168.168.30'

# Should NOT be on replica
ssh akushnir@192.168.168.42 'ip addr show eth0 | grep 192.168.168.30 || echo "OK - not on replica"'
```

#### Test 2: Simulate Primary Failure
```bash
# Stop Caddy on primary
ssh akushnir@192.168.168.31 'docker stop code-server-caddy'

# Wait 9 seconds for health check to fail 3 times
sleep 9

# Verify VIP has moved to replica
ssh akushnir@192.168.168.42 'ip addr show eth0 | grep 192.168.168.30'
# Should now show: inet 192.168.168.30/24 scope global secondary eth0

# Verify traffic is being served from replica
curl -I https://kushnir.cloud/health
# Should respond with HTTP 200 from replica's Caddy

# Restart Caddy on primary
ssh akushnir@192.168.168.31 'docker start code-server-caddy'

# Wait ~6 seconds for health check to pass twice
sleep 6

# Verify VIP has moved back to primary (failback)
ssh akushnir@192.168.168.31 'ip addr show eth0 | grep 192.168.168.30'
```

#### Test 3: Monitor Keepalived Activity
```bash
# On primary, watch keepalived logs
ssh akushnir@192.168.168.31 'sudo tail -f /var/log/syslog | grep -i keepalived'

# Stop Caddy to trigger failover
ssh akushnir@192.168.168.31 'docker stop code-server-caddy'

# Look for log entries like:
# "VRRP_Instance(VI_1) Entering FAULT state"
# "VRRP_Instance(VI_1) Leaving MASTER state"
# On replica:
# "VRRP_Instance(VI_1) Becoming MASTER"
```

---

## Configuration Reference

### Keepalived Configuration Details

#### Primary Config (in /tmp/keepalived.conf)
```yaml
global_defs {
  router_id PRIMARY_CODE_SERVER
  script_user root
  enable_script_security
}

vrrp_script check_caddy {
  script "/usr/local/bin/check-caddy-health.sh"
  interval 3        # Check every 3 seconds
  weight -20        # Reduce priority by 20 if fails
  fall 3            # Mark down after 3 failures
  rise 2            # Mark up after 2 successes
}

vrrp_instance VI_1 {
  state MASTER
  interface eth0
  virtual_router_id 51
  priority 100          # Primary = 100
  advert_int 1
  authentication { 
    auth_type PASS
    auth_pass CODE_SERVER_HA_2026
  }
  virtual_ipaddress { 
    192.168.168.30/24 
  }
  track_script { check_caddy }
}
```

#### Replica Config (auto-generated, in /tmp/keepalived.conf)
```yaml
vrrp_instance VI_1 {
  state BACKUP
  ...
  priority 90           # Replica = 90
  ...
}
```

#### Health Check Script
```bash
#!/bin/bash
# /usr/local/bin/check-caddy-health.sh
set -e
if ! docker ps | grep -q code-server-caddy; then
  exit 1  # Container not running
fi
if ! wget -q --timeout=2 -O - http://127.0.0.1/health 2>/dev/null | grep -q OK; then
  exit 1  # Health check failed
fi
exit 0    # Success
```

---

## Troubleshooting

### Issue: VIP Not Activating on Primary
```bash
# Verify keepalived is running
sudo systemctl status keepalived

# Check for errors
sudo journalctl -u keepalived -n 50

# Verify health check script works
/usr/local/bin/check-caddy-health.sh && echo "OK" || echo "FAILED"

# Check Caddy is running
docker ps | grep code-server-caddy

# Test health endpoint
curl -s http://127.0.0.1/health
```

### Issue: VIP Not Failing Over When Primary Dies
```bash
# Check keepalived on primary
sudo systemctl is-active keepalived

# Check if replica keepalived is running
ssh akushnir@192.168.168.42 'sudo systemctl is-active keepalived'

# Check VRRP advertisements are reaching replica
ssh akushnir@192.168.168.42 'sudo tcpdump -i eth0 proto 112 -n | head -5'

# Verify both have same authentication password
grep auth_pass /tmp/keepalived.conf
```

### Issue: Replica Port 80 Still Blocked After Killing Ingress Controller
```bash
# Verify kill worked
ps aux | grep -i "nginx-ingress" | grep -v grep || echo "Killed successfully"

# Check if nginx processes remain
ps aux | grep nginx | grep -v grep

# Cleanup orphaned listeners
sudo fuser -k 80/tcp
sudo fuser -k 443/tcp

# Try Caddy again
docker run -d --name code-server-caddy -p 80:80 caddy:2.7.4
```

---

## Post-Deployment Checklist

- [ ] **Primary Keepalived**: Installed and running
  - [ ] Config deployed to `/etc/keepalived/keepalived.conf`
  - [ ] Health check script at `/usr/local/bin/check-caddy-health.sh`
  - [ ] Systemctl status shows "active (running)"
  - [ ] VIP appears on eth0: `ip addr show eth0 | grep 192.168.168.30`

- [ ] **Replica Caddy**: Running on port 80/443 OR documented as blocked
  - [ ] Either port 80 blocker resolved OR alternate port documented
  - [ ] docker-compose.enterprise.yml deployed
  - [ ] All required containers running (`docker ps` shows 40+ containers)

- [ ] **Replica Keepalived**: Installed and running (BACKUP state)
  - [ ] Config deployed
  - [ ] Systemctl status shows "active (running)"
  - [ ] Replica does NOT have VIP (should be on primary)

- [ ] **Router/DNS Updated**: Point to VIP (192.168.168.30)
  - [ ] Port-forward target changed to .30
  - [ ] DNS A record verified (or Cloudflare routing confirmed)

- [ ] **Failover Testing Passed**:
  - [ ] Test 1: VIP on primary before failover
  - [ ] Test 2: VIP moves to replica after stopping primary Caddy
  - [ ] Test 3: VIP moves back to primary after restart (failback)

- [ ] **Documentation Updated**:
  - [ ] Final deployment log created
  - [ ] Operational procedures documented
  - [ ] Emergency procedures in runbook

---

## Emergency Procedures

### Force VIP to Primary (Immediate)
```bash
ssh akushnir@192.168.168.31

# Temporarily increase priority
sudo sed -i 's/priority 100/priority 255/' /etc/keepalived/keepalived.conf
sudo systemctl reload keepalived

# Wait for VIP to stabilize
sleep 5
ip addr show eth0 | grep 192.168.168.30

# After stabilization, restore original priority
sudo sed -i 's/priority 255/priority 100/' /etc/keepalived/keepalived.conf
sudo systemctl reload keepalived
```

### Force VIP to Replica (Last Resort)
```bash
ssh akushnir@192.168.168.42

# Temporarily increase replica priority
sudo sed -i 's/priority 90/priority 255/' /etc/keepalived/keepalived.conf
sudo systemctl reload keepalived

# Wait for VIP stabilization
sleep 5
ip addr show eth0 | grep 192.168.168.30

# Restore original priority after recovery
sudo sed -i 's/priority 255/priority 90/' /etc/keepalived/keepalived.conf
sudo systemctl reload keepalived
```

### Disable HA (Fallback to Primary Only)
```bash
# On both hosts, stop keepalived
sudo systemctl stop keepalived
sudo systemctl disable keepalived

# Update router/DNS to point back to primary (.31)
# Verify kushnir.cloud is accessible
curl -I https://kushnir.cloud

# Re-enable when ready to restore HA
sudo systemctl enable keepalived
sudo systemctl start keepalived
```

---

## Summary of Required Manual Actions

| Action | Host | Requires Sudo | Estimated Time |
|--------|------|:-------------:|:---------------:|
| Install keepalived | Primary | ✅ | 2 min |
| Deploy keepalived config | Primary | ✅ | 1 min |
| Enable & restart keepalived | Primary | ✅ | 1 min |
| Verify VIP activation | Primary | ❌ | 1 min |
| Resolve port 80 blocker | Replica | ✅ | 5 min |
| Deploy Caddy to replica | Replica | ❌ | 2 min |
| Deploy keepalived on replica | Replica | ✅ | 5 min |
| Update router/DNS settings | Router/DNS | ✅ | 5 min |
| Test failover scenarios | Primary+Replica | ❌ | 10 min |

**Total Estimated Manual Effort**: ~32 minutes with sudo access

---

## References

- [HA_DEPLOYMENT_STATUS.md](HA_DEPLOYMENT_STATUS.md) - Current deployment status
- [CADDY_REPLICA_DEPLOYMENT_ISSUE.md](CADDY_REPLICA_DEPLOYMENT_ISSUE.md) - Replica blocker analysis
- [KEEPALIVED_HA_DEPLOYMENT.md](KEEPALIVED_HA_DEPLOYMENT.md) - Original HA guide
- [config/caddy/Caddyfile](config/caddy/Caddyfile) - Reverse proxy configuration
- [docs/operations/GSM_SECRETS_RUNBOOK.md](docs/operations/GSM_SECRETS_RUNBOOK.md) - Secrets management

---

**Document Status**: Final operational handoff  
**Last Updated**: April 30, 2026  
**Prepared By**: Automated deployment system  
**Action Required**: Manual sudo-based deployment of keepalived on both hosts + replica port blocker resolution
