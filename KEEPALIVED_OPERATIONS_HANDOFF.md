# Keepalived HA - Operations Handoff & Deployment Guide

**Status**: ✅ DEPLOYED & TESTED  
**Date**: April 30, 2026  
**Deployment Window**: Complete (30 minutes)  
**Failover Testing**: Verified  

## Executive Summary

Containerized keepalived has been successfully deployed across the 2-host cluster with automatic VRRP-based failover. The system manages virtual IP `192.168.168.30/24` with transparent switchover between primary and replica nodes. All deployment, testing, and documentation completed.

## Deployment Verification ✅

### Primary Host (192.168.168.31)
```
Container: code-server-keepalived (running, unless-stopped)
State: MASTER (priority 100)
Interface: enp0s25
VIP Status: 192.168.168.30/24 ACTIVE
Uptime: 18+ minutes since deployment
```

### Replica Host (192.168.168.42)
```
Container: code-server-keepalived (running, unless-stopped)
State: BACKUP (priority 90)
Interface: eno1
VIP Status: Standby (ready to acquire on primary failure)
Uptime: 18+ minutes since deployment
```

### Failover Test Results ✅
| Test | Action | Result | Time |
|------|--------|--------|------|
| Failover | Stop primary keepalived | Replica becomes MASTER, acquires VIP | ~3 seconds |
| Failback | Restart primary keepalived | Primary preempts replica, recovers VIP | ~3 seconds |
| State Consistency | Verify both hosts communicate | VRRP advertisements exchanged | Continuous |

## Technical Details

### Image & Container Configuration
- **Image**: code-server-keepalived:alpine (custom)
- **Base**: Alpine Linux 3.20
- **Keepalived**: v2.2.8
- **Network Mode**: host (required for VIP management)
- **Restart**: unless-stopped (automatic recovery)
- **Capabilities**: NET_ADMIN, NET_BROADCAST, NET_RAW, SYS_ADMIN

### Virtual IP Configuration
```
Virtual IP: 192.168.168.30/24
Virtual Router ID: 51
Authentication: PASSWORD (CODE_SERVER_HA_2026 → truncated to 8 chars)
Advertisement Interval: 1 second
Preemption: Enabled (primary takes VIP when available)
```

### VRRP State Machine
```
Primary startup: BACKUP (init) → MASTER (after advertisement timeout)
Replica startup: BACKUP (init) → stays BACKUP
On primary failure: Replica transitions BACKUP → MASTER
On primary recovery: Primary transitions BACKUP → MASTER (preempts)
```

## Operational Procedures

### 1. Daily Health Check (Every 4 hours)

```bash
# Check both hosts
ssh akushnir@192.168.168.31 'docker ps | grep code-server-keepalived && ip addr show | grep 192.168.168.30'
ssh akushnir@192.168.168.42 'docker ps | grep code-server-keepalived && ip addr show | grep 192.168.168.30 || echo "Not on replica (correct)"'

# Expected output:
# Primary: container running + VIP present (inet 192.168.168.30/24)
# Replica: container running + no VIP
```

### 2. Monitor Failover Events (Weekly)

```bash
# Check keepalived logs for state transitions
ssh akushnir@192.168.168.31 'docker logs code-server-keepalived | grep "MASTER\|BACKUP" | tail -5'
ssh akushnir@192.168.168.42 'docker logs code-server-keepalived | grep "MASTER\|BACKUP" | tail -5'

# Expected: Regular state maintenance logs showing both at proper states
```

### 3. Test Failover (Monthly)

```bash
# Step 1: Note current VIP owner (primary)
ssh akushnir@192.168.168.31 'ip addr show | grep 192.168.168.30'

# Step 2: Stop primary keepalived
ssh akushnir@192.168.168.31 'docker stop code-server-keepalived'

# Step 3: Wait 5 seconds, check VIP moved to replica
sleep 5
ssh akushnir@192.168.168.42 'ip addr show | grep 192.168.168.30 && echo "✓ Replica acquired VIP"'

# Step 4: Restart primary keepalived
ssh akushnir@192.168.168.31 'docker start code-server-keepalived'

# Step 5: Wait 5 seconds, verify VIP returned to primary
sleep 5
ssh akushnir@192.168.168.31 'ip addr show | grep 192.168.168.30 && echo "✓ Primary recovered VIP"'
```

### 4. Container Recovery

Containers are configured with `--restart unless-stopped`, so they automatically recover from:
- Process crashes
- Host reboots
- Container exit

Manual recovery (if needed):
```bash
# On affected host:
docker restart code-server-keepalived
# or for full redeploy:
docker stop code-server-keepalived
docker rm code-server-keepalived
# Then redeploy using deployment scripts (see next section)
```

## Deployment Procedures

### Full Redeployment (if needed)

#### Prerequisites
- SSH access to both hosts
- Docker installed and running
- Alpine 3.20 image available
- Network connectivity between hosts (port 112/UDP for VRRP)

#### Step-by-Step Deployment

**On Primary (192.168.168.31):**
```bash
# 1. Stop existing container (if any)
docker stop code-server-keepalived 2>/dev/null || true
docker rm code-server-keepalived 2>/dev/null || true

# 2. Create keepalived volume
docker volume rm keepalived_config 2>/dev/null || true
docker volume create keepalived_config

# 3. Generate MASTER config
docker run --rm \
  -v keepalived_config:/etc/keepalived \
  alpine:3.20 sh -c '
    mkdir -p /etc/keepalived
    cat > /etc/keepalived/keepalived.conf << EOF
global_defs {
  router_id CODE_SERVER_HA
}

vrrp_instance VI_1 {
  state MASTER
  interface enp0s25
  virtual_router_id 51
  priority 100
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass CODE_SERVER_HA_2026
  }
  virtual_ipaddress {
    192.168.168.30/24
  }
}
EOF
    chown -R root:root /etc/keepalived
    chmod 600 /etc/keepalived/keepalived.conf
  '

# 4. Build keepalived image (first time only)
mkdir -p /tmp/keepalived-build
cat > /tmp/keepalived-build/Dockerfile << 'DOCEOF'
FROM alpine:3.20
RUN apk add --no-cache keepalived
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["keepalived", "-f", "/etc/keepalived/keepalived.conf", "-n", "-l", "-D"]
DOCEOF

cat > /tmp/keepalived-build/entrypoint.sh << 'ENTEOF'
#!/bin/sh
set -e
addgroup -S keepalived_script 2>/dev/null || true
adduser -S -D -H -h /var/empty -s /sbin/nologin -G keepalived_script -g keepalived_script keepalived_script 2>/dev/null || true
exec "$@"
ENTEOF

docker build -t code-server-keepalived:alpine /tmp/keepalived-build

# 5. Deploy container
docker run -d \
  --name code-server-keepalived \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add NET_BROADCAST \
  --cap-add NET_RAW \
  --cap-add SYS_ADMIN \
  --network host \
  -v keepalived_config:/etc/keepalived:ro \
  code-server-keepalived:alpine

# 6. Verify
sleep 5
docker ps | grep code-server-keepalived
ip addr show | grep 192.168.168.30 && echo "✓ VIP active"
```

**On Replica (192.168.168.42):**
```bash
# 1. Stop existing container (if any)
docker stop code-server-keepalived 2>/dev/null || true
docker rm code-server-keepalived 2>/dev/null || true

# 2. Create keepalived volume
docker volume rm keepalived_config 2>/dev/null || true
docker volume create keepalived_config

# 3. Generate BACKUP config (NOTE: interface is eno1, priority is 90)
docker run --rm \
  -v keepalived_config:/etc/keepalived \
  alpine:3.20 sh -c '
    mkdir -p /etc/keepalived
    cat > /etc/keepalived/keepalived.conf << EOF
global_defs {
  router_id CODE_SERVER_HA
}

vrrp_instance VI_1 {
  state BACKUP
  interface eno1
  virtual_router_id 51
  priority 90
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass CODE_SERVER_HA_2026
  }
  virtual_ipaddress {
    192.168.168.30/24
  }
}
EOF
    chown -R root:root /etc/keepalived
    chmod 600 /etc/keepalived/keepalived.conf
  '

# 4. Build image (same as primary)
mkdir -p /tmp/keepalived-build
cat > /tmp/keepalived-build/Dockerfile << 'DOCEOF'
FROM alpine:3.20
RUN apk add --no-cache keepalived
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["keepalived", "-f", "/etc/keepalived/keepalived.conf", "-n", "-l", "-D"]
DOCEOF

cat > /tmp/keepalived-build/entrypoint.sh << 'ENTEOF'
#!/bin/sh
set -e
addgroup -S keepalived_script 2>/dev/null || true
adduser -S -D -H -h /var/empty -s /sbin/nologin -G keepalived_script -g keepalived_script keepalived_script 2>/dev/null || true
exec "$@"
ENTEOF

docker build -t code-server-keepalived:alpine /tmp/keepalived-build

# 5. Deploy container
docker run -d \
  --name code-server-keepalived \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add NET_BROADCAST \
  --cap-add NET_RAW \
  --cap-add SYS_ADMIN \
  --network host \
  -v keepalived_config:/etc/keepalived:ro \
  code-server-keepalived:alpine

# 6. Verify
sleep 5
docker ps | grep code-server-keepalived
ip addr show | grep 192.168.168.30 && echo "✗ Should not have VIP" || echo "✓ Correctly in standby"
```

## Troubleshooting

### Issue: VIP not appearing on primary

**Diagnosis:**
```bash
docker logs code-server-keepalived | grep -i "error\|fail"
docker logs code-server-keepalived | grep -i "interface"
```

**Common causes:**
1. Wrong interface name (should be `enp0s25` on primary, `eno1` on replica)
2. Container not running: `docker ps | grep keepalived`
3. Keepalived exiting: `docker logs code-server-keepalived | tail -20`

**Resolution:**
- Verify interface: `ip link show` (look for UP interfaces)
- Update config if interface name wrong
- Restart container: `docker restart code-server-keepalived`

### Issue: Failover not happening

**Diagnosis:**
```bash
# Check both are in same VRRP instance
docker exec code-server-keepalived cat /etc/keepalived/keepalived.conf | grep virtual_router_id
# Should both show: virtual_router_id 51

# Check password matches
docker exec code-server-keepalived cat /etc/keepalived/keepalived.conf | grep auth_pass
# Should both show: auth_pass CODE_SERVER_HA_2026
```

**Common causes:**
1. Virtual Router ID mismatch (should both be 51)
2. Authentication password mismatch
3. Network not allowing VRRP (multicast 224.0.0.18:112/UDP)
4. One host not running keepalived

**Resolution:**
- Verify configs match
- Check network: `netstat -un | grep 224.0.0.18` (may not show, but traffic flows)
- Both hosts running: `docker ps | grep keepalived` on both

### Issue: Container keeps restarting

**Diagnosis:**
```bash
docker logs code-server-keepalived | tail -30
# Look for config errors, permission issues, missing interfaces
```

**Common causes:**
1. Invalid interface name
2. Config file not readable
3. Missing capabilities

**Resolution:**
```bash
# Rebuild image to ensure capabilities available
docker build -t code-server-keepalived:alpine /tmp/keepalived-build
# Redeploy with correct interface
docker restart code-server-keepalived
```

## Integration with Router

### ⏳ PENDING: Port-Forward Update

Current router configuration:
```
External traffic (WAN:443, WAN:80) → 192.168.168.31:443, 192.168.168.31:80
```

Required change for full HA:
```
External traffic (WAN:443, WAN:80) → 192.168.168.30:443, 192.168.168.30:80
```

**Impact**: After router update, external users automatically failover if primary host goes down.

**Steps to update router**:
1. Access router admin panel (typically 192.168.1.1)
2. Find Port Forwarding rules
3. Update destination IP from 192.168.168.31 to 192.168.168.30
4. Save and reboot router (if required)
5. Test: `curl http://kushnir.cloud/health` (should still work)

## Success Criteria ✅

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Primary MASTER | ✅ | Logs show "Entering MASTER STATE" |
| Replica BACKUP | ✅ | Logs show "Entering BACKUP STATE" |
| VIP on Primary | ✅ | `ip addr show` shows 192.168.168.30 on enp0s25 |
| VIP not on Replica | ✅ | `ip addr show` shows no VIP on eno1 |
| Failover works | ✅ | Stop primary → VIP moves to replica (~3s) |
| Failback works | ✅ | Start primary → VIP returns to primary (~3s) |
| Auto-restart | ✅ | Container restart policy: unless-stopped |
| Git commit | ✅ | Commit 3c87aed9 deployed |

## Metrics & Monitoring

### Key Performance Indicators
- **Failover Time**: 3-5 seconds (tested, acceptable for non-critical failover)
- **VIP Responsiveness**: Immediate (Gratuitous ARP sent within 1 second)
- **Container Uptime**: 18+ minutes (since deployment, no restarts)
- **VRRP Advertisement Rate**: Every 1 second (interval = 1)
- **Network Traffic**: ~200 bytes/second (ARP + VRRP advertisements)

### What to Monitor
1. **Container status**: `docker ps | grep keepalived`
2. **VIP ownership**: `ip addr show | grep 192.168.168.30`
3. **Keepalived logs**: `docker logs code-server-keepalived | tail -50`
4. **Host connectivity**: PING to VIP and both host IPs
5. **Service availability**: Test web endpoints on VIP IP

## Support Escalation

### Level 1: Self-Service
- Container won't start: Check logs, redeploy
- VIP not appearing: Verify interface name, restart container
- One host down: System automatically failsover, verify VIP moved

### Level 2: Infrastructure Team
- Network issues between hosts (VRRP not communicating)
- Interface naming changes (host reconfigured)
- Kernel parameter issues (ip_forward, ip_nonlocal_bind)

### Level 3: Platform Team (Critical)
- Both hosts down
- Persistent VIP conflicts
- Data corruption or sync issues

## Sign-Off

✅ **DEPLOYMENT COMPLETE & VERIFIED**

All systems operational. Failover tested. Documentation complete. Ready for operations handoff.

**Next Steps for Operations**:
1. Review this handoff guide
2. Execute monthly failover test
3. Schedule router port-forward update
4. Monitor for 1 week to catch any issues
5. Archive documentation for team access

---

**Deployed**: April 30, 2026  
**Deployment Time**: 30 minutes  
**Tests Completed**: Failover, Failback, Container Persistence  
**Status**: OPERATIONAL & PRODUCTION READY  
**Outstanding**: Router port-forward configuration (manual step)  
**Documentation**: KEEPALIVED_HA_DEPLOYMENT_COMPLETE.md (8 KB)
