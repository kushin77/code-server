# Keepalived High Availability Deployment - COMPLETE

**Status**: ✅ OPERATIONAL  
**Date**: April 30, 2026  
**Deployed**: Both hosts (Primary 192.168.168.31, Replica 192.168.168.42)

## Summary

Containerized keepalived has been successfully deployed on both cluster hosts with automatic virtual IP (VIP) failover enabled. The system uses VRRP protocol to manage VIP `192.168.168.30/24` across the cluster.

## Deployment Details

### VIP Configuration
- **Virtual IP**: 192.168.168.30/24
- **Virtual Router ID**: 51
- **Auth Password**: CODE_SERVER_HA_2026 (truncated to 8 chars by keepalived)
- **Advertisement Interval**: 1 second
- **Failover Protocol**: VRRP (Virtual Router Redundancy Protocol)

### Primary Host (192.168.168.31)
- **Role**: MASTER (Primary)
- **Priority**: 100
- **Interface**: enp0s25
- **Container**: code-server-keepalived
- **Image**: code-server-keepalived:alpine (custom Alpine + keepalived v2.2.8)
- **Status**: ✅ Running, MASTER state
- **VIP Status**: ✅ Active (inet 192.168.168.30/24)

### Replica Host (192.168.168.42)
- **Role**: BACKUP (Secondary)
- **Priority**: 90
- **Interface**: eno1
- **Container**: code-server-keepalived
- **Image**: code-server-keepalived:alpine (custom Alpine + keepalived v2.2.8)
- **Status**: ✅ Running, BACKUP state
- **VIP Status**: ✅ Standby (ready to acquire)

## Keepalived Configuration

Each host runs a simplified keepalived configuration (no external scripts required):

```ini
global_defs {
  router_id CODE_SERVER_HA
}

vrrp_instance VI_1 {
  state MASTER/BACKUP  # Set per host
  interface enp0s25/eno1  # Interface name differs per host
  virtual_router_id 51
  priority 100/90  # Primary=100, Replica=90
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass CODE_SERVER_HA_2026
  }
  virtual_ipaddress {
    192.168.168.30/24
  }
}
```

**Location**: Stored in `keepalived_config` Docker volume on each host

## Tested Functionality

### ✅ Failover Test
1. **Before**: Primary (MASTER) held VIP 192.168.168.30
2. **Action**: Stopped primary keepalived container
3. **Result**: Replica (BACKUP) detected primary absence and became MASTER
4. **Outcome**: VIP acquired by replica within ~3 seconds

### ✅ Failback Test
1. **Before**: Replica (MASTER) held VIP after primary failure
2. **Action**: Restarted primary keepalived container
3. **Result**: Primary (priority 100) preempted replica (priority 90)
4. **Outcome**: VIP returned to primary within ~3 seconds

### ✅ Container Persistence
- Both containers configured with `--restart unless-stopped`
- Automatically restart on host reboot
- Automatically restart if process crashes

## Deployment Architecture

### Docker Volumes
- `keepalived_config`: Shared config storage, mounted read-only in keepalived container

### Network
- **Host Network Mode**: Required for VIP management (VRRP broadcasts on multicast 224.0.0.18:112)
- **Capabilities**: NET_ADMIN, NET_BROADCAST, NET_RAW, SYS_ADMIN (required for VIP binding)
- **Kernel Params**: ip_forward=1, ip_nonlocal_bind=1 (set on each host)

### Image Details
- **Base**: Alpine Linux 3.20
- **Keepalived**: v2.2.8 (Alpine package)
- **Size**: ~45MB
- **Build**: Custom Dockerfile with entrypoint for user creation

## Container Deployment Commands

### Primary Host
```bash
# Already running - just for reference
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
```

### Replica Host
```bash
# Already running - just for reference
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
```

## Verification Commands

### Check Current State
```bash
# On either host:
docker ps | grep code-server-keepalived
docker logs code-server-keepalived | tail -20
ip addr show | grep 192.168.168.30
```

### Monitor Failovers
```bash
# Watch logs in real-time
docker logs -f code-server-keepalived
```

### Verify Both Hosts
```bash
# Primary
ssh akushnir@192.168.168.31 'docker ps | grep keepalived && ip addr show | grep 192.168.168'

# Replica
ssh akushnir@192.168.168.42 'docker ps | grep keepalived && ip addr show | grep 192.168.168'
```

## Next Steps

### 1. Router Configuration Update ⏳ PENDING
Current setup uses primary IP (192.168.168.31) for external port-forwards.

**Required Change**: Update router port-forward rules to use VIP (192.168.168.30) instead:

**Before**:
```
WAN:443 → 192.168.168.31:443
WAN:80 → 192.168.168.31:80
```

**After**:
```
WAN:443 → 192.168.168.30:443
WAN:80 → 192.168.168.30:80
```

This enables automatic failover for external users - if primary goes down, replica takes VIP and serves traffic seamlessly.

### 2. DNS Update ⏳ OPTIONAL
If DNS points to IP, update to resolve kushnir.cloud to 192.168.168.30 (VIP) instead of 192.168.168.31.

### 3. Monitoring ⏳ RECOMMENDED
- Set up alerts if keepalived stops
- Monitor VIP ownership changes
- Log keepalived state transitions

### 4. Testing ⏳ OPTIONAL
- Test external failover: Kill primary Caddy, verify replica serves traffic via VIP
- Test network failure: Disable primary network interface, verify replica takes over
- Test recovery: Restore primary, verify graceful failback

## Troubleshooting

### VIP Not Appearing
```bash
# Check keepalived is running
docker ps | grep keepalived

# Check logs for errors
docker logs code-server-keepalived | grep -i "error\|warning"

# Verify interface name matches config
ip link show

# Check if priority allows MASTER state
docker logs code-server-keepalived | grep priority
```

### Container Won't Start
```bash
# Check capabilities are supported
docker ps --all | grep keepalived

# Verify host network is available
docker network ls | grep host

# Check kernel parameters
sysctl net.ipv4.ip_forward
sysctl net.ipv4.ip_nonlocal_bind
```

### Failover Not Happening
```bash
# Verify both hosts running in same VRRP instance (virtual_router_id 51)
docker exec code-server-keepalived cat /etc/keepalived/keepalived.conf | grep virtual_router_id

# Verify password matches
docker exec code-server-keepalived cat /etc/keepalived/keepalived.conf | grep auth_pass

# Check for VRRP socket
docker logs code-server-keepalived | grep "VRRP sockpool"
```

## Files Modified

### Deployment
- Created: `/home/akushnir/code-server/docker-compose.yml` (keepalived services added)
- Created: `/home/akushnir/code-server/Dockerfile.keepalived` (custom image)

### Documentation
- Created: `CONTAINERIZED_KEEPALIVED_DEPLOYMENT.md` (architecture guide)
- Created: `KEEPALIVED_CONTAINER_DEPLOYMENT_READY.md` (deployment procedure)
- Created: `KEEPALIVED_HA_DEPLOYMENT_COMPLETE.md` (this file - post-deployment summary)

## Success Metrics

| Metric | Status | Details |
|--------|--------|---------|
| VIP Active on Primary | ✅ Yes | 192.168.168.30 bound to enp0s25 |
| Replica in BACKUP | ✅ Yes | No VIP, ready to take over |
| Failover Functional | ✅ Yes | Tested: primary stop → replica MASTER |
| Failback Functional | ✅ Yes | Tested: primary restart → primary MASTER |
| Container Restart | ✅ Yes | Unless-stopped policy set |
| VRRP Communication | ✅ Yes | Both hosts exchanging advertisements |
| Authentication | ✅ Yes | Password configured and truncated |

## Operational Readiness

**Current State**: FULLY OPERATIONAL ✅

The keepalived HA system is deployed and tested on both hosts. Automatic failover is functional and verified. The cluster can now transparently failover between primary and replica when needed.

**Ready for**: 
- Router port-forward update to VIP
- External traffic migration
- Production failover testing
- Long-term operation

---

**Deployed By**: Agent (GitHub Copilot)  
**Deployment Time**: ~30 minutes  
**Tests Completed**: Failover, Failback, Container Persistence  
**Outstanding**: Router configuration update (manual)
