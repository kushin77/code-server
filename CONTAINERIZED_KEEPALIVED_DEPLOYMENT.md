# Containerized Keepalived HA Deployment

**Date**: April 29, 2026  
**Status**: Ready for deployment  
**Architecture**: Docker-based VRRP with shared VIP

---

## Overview

Keepalived is now deployed as a Docker container in the stack on both primary and replica hosts. This replaces the previous systemd-based approach with a fully containerized, code-as-infrastructure solution.

### Architecture

```
┌─────────────────────────┬─────────────────────────┐
│   Primary (.31)         │   Replica (.42)         │
├─────────────────────────┼─────────────────────────┤
│ keepalived (MASTER)     │ keepalived (BACKUP)     │
│ Priority: 100           │ Priority: 90            │
│ State: MASTER           │ State: BACKUP           │
├─────────────────────────┼─────────────────────────┤
│ Manages VIP             │ Standby for VIP         │
│ 192.168.168.30/24       │ (takes over on failure) │
└─────────────────────────┴─────────────────────────┘
       VRRP Heartbeat (every 1 second)
     Health Check (every 3 seconds)
```

---

## Deployment Architecture

### Container Definitions

#### 1. **keepalived-init** (Initialization Container)
- **Purpose**: Generate keepalived configuration based on host role
- **Image**: alpine:3.20
- **User**: root (needed to create config files)
- **Restart**: no (exits after setup)
- **Actions**:
  - Creates `/etc/keepalived/` directory
  - Generates keepalived.conf with role-specific values:
    - Primary: state=MASTER, priority=100
    - Replica: state=BACKUP, priority=90
  - Sets proper ownership and permissions

#### 2. **keepalived** (VRRP Service)
- **Purpose**: Manage virtual IP and automatic failover
- **Image**: keepalived:2.2.7
- **User**: root (required for network management)
- **Network**: host (direct access to eth0)
- **Capabilities**: NET_ADMIN, NET_BROADCAST, NET_RAW, SYS_ADMIN
- **Restart**: unless-stopped (critical service)

### Key Features

#### Capabilities & Sysctls
```dockerfile
cap_add:
  - NET_ADMIN          # Manage network interfaces (VIP)
  - NET_BROADCAST      # Send broadcast packets
  - NET_RAW            # Direct socket access
  - SYS_ADMIN          # System administration privileges

sysctls:
  - net.ipv4.ip_forward=1            # Enable IP forwarding
  - net.ipv4.ip_nonlocal_bind=1      # Bind to non-local IP (VIP)
  - net.ipv6.conf.all.forwarding=1   # IPv6 forwarding
```

#### Volumes
| Source | Target | Purpose |
|--------|--------|---------|
| keepalived_config volume | /etc/keepalived | Configuration (R/O) |
| /var/run/docker.sock | /var/run/docker.sock | Monitor containers |
| ./scripts/ha/check-caddy-health.sh | /usr/local/bin/check-caddy-health.sh | Health check script |
| ./scripts/ha/notify-vrrp.sh | /usr/local/bin/notify-vrrp.sh | State change notifications |

#### Environment Variables
- `HOST_ROLE`: "primary" or "replica" (determines state/priority)
- `KEEPALIVED_CMD_LINE_ARGUMENTS`: "-l -D" (log to stdout, debug mode)

---

## VRRP Configuration

### Keepalived Instance (VI_1)

```conf
vrrp_instance VI_1 {
  state MASTER/BACKUP         # Role-specific
  interface eth0              # Network interface
  virtual_router_id 51        # VIP identifier
  priority 100/90             # Role-specific (higher wins)
  advert_int 1                # Heartbeat interval (1 second)
  
  authentication {
    auth_type PASS
    auth_pass CODE_SERVER_HA_2026
  }
  
  virtual_ipaddress {
    192.168.168.30/24         # Shared VIP
  }
  
  track_script {
    check_caddy               # Health check
  }
  
  notify_master /usr/local/bin/notify-vrrp.sh master
  notify_backup /usr/local/bin/notify-vrrp.sh backup
}
```

### Health Check Script

**Location**: `scripts/ha/check-caddy-health.sh`

Verifies:
1. Caddy container is running: `docker ps | grep code-server-caddy`
2. Caddy health endpoint responds: `curl http://127.0.0.1/health`

**Interval**: 3 seconds  
**Failure Threshold**: 3 consecutive failures (9 seconds total)  
**Weight**: -20 (if unhealthy, priority decreased by 20)

### Failover Mechanism

```
PRIMARY (.31) Caddy HEALTHY
  ↓ (3 second checks)
keepalived monitors /health → OK
VIP 192.168.168.30 → PRIMARY (.31)
Router traffic → .31

PRIMARY (.31) Caddy FAILS (example: crash)
  ↓ (after 3 failed checks = 9 seconds)
Health check fails 3 times
keepalived priority drops: 100 - 20 = 80
REPLICA (.90) priority: 90 > 80
VRRP election: REPLICA wins
  ↓
VIP 192.168.168.30 → REPLICA (.42)
Router traffic → .42
  ↓
PRIMARY (.31) Caddy recovers
Health check passes
Priority restored: 100
VRRP election: PRIMARY wins again
VIP returns to PRIMARY (.31)
```

**Failover Time**: 9-12 seconds (3 checks × 3s + VRRP convergence)

---

## Deployment Steps

### Environment Setup

Set the HOST_ROLE environment variable in your .env file:

**Primary (.31)**: `/home/akushnir/code-server-enterprise/.env`
```bash
HOST_ROLE=primary
```

**Replica (.42)**: `/home/akushnir/code-server-enterprise/.env`
```bash
HOST_ROLE=replica
```

### Deploy Containers

#### Primary Host (.31)
```bash
cd ~/code-server-enterprise
docker-compose -f docker-compose.enterprise.yml up -d keepalived-init
docker-compose -f docker-compose.enterprise.yml up -d keepalived
```

#### Replica Host (.42)
```bash
cd ~/code-server-enterprise
docker-compose -f docker-compose.enterprise.yml up -d keepalived-init
docker-compose -f docker-compose.enterprise.yml up -d keepalived
```

### Verify Deployment

#### Check Containers Running
```bash
docker ps | grep keepalived
# Should show both keepalived-init (exited) and keepalived (up)
```

#### Check VRRP Status
```bash
docker logs code-server-keepalived | head -20
# Should show VRRP state transitions and health checks
```

#### Verify VIP
```bash
ip addr show eth0 | grep 192.168.168.30
# On PRIMARY: should see 192.168.168.30/24 dev eth0
# On REPLICA: should see nothing (VIP on primary only)
```

#### Test Health Checks
```bash
docker logs code-server-keepalived | grep "Health"
# Should show periodic health check results
```

---

## Failover Testing

### Test 1: Stop Caddy on Primary

```bash
# On primary (.31)
docker stop code-server-caddy

# Monitor keepalived logs
docker logs -f code-server-keepalived

# Expected: 
# - 3x health check failures (9 seconds)
# - Priority drops to 80
# - REPLICA becomes MASTER
# - VIP moves to replica (.42)

# Verify on replica
ssh akushnir@192.168.168.42 'ip addr show eth0 | grep 192.168.168.30'
# Should now show the VIP

# Restart Caddy on primary
docker start code-server-caddy

# Expected:
# - Health checks pass
# - Priority restored to 100
# - PRIMARY becomes MASTER again
# - VIP returns to primary
```

### Test 2: Simulate Network Partition

```bash
# On replica (.42) only
docker pause code-server-keepalived
# (This simulates network partition without stopping the container)

# Monitor on primary
docker logs -f code-server-keepalived

# Expected: Primary keeps VIP after missing 3 heartbeats

# Unpause to restore
docker unpause code-server-keepalived
```

### Test 3: Traffic Flow During Failover

```bash
# From external host, monitor kushnir.cloud availability
while true; do
  curl -s -w "%{http_code}\n" http://kushnir.cloud/health || echo "DOWN"
  sleep 1
done

# Then trigger failover (stop Caddy on primary)
# Expected: Brief 5-10 second interruption, then traffic resumes
```

---

## Monitoring & Logging

### Container Logs

```bash
# Real-time logs
docker logs -f code-server-keepalived

# Last 50 lines
docker logs --tail 50 code-server-keepalived

# Filter for state changes
docker logs code-server-keepalived | grep -i "state\|becoming\|master\|backup"
```

### VRRP State Changes

Kept in `/var/log/keepalived-state-changes.log` on the host (via notify script):

```bash
tail -f /var/log/keepalived-state-changes.log
```

### Health Check Results

In keepalived logs, search for `check_caddy`:

```bash
docker logs code-server-keepalived | grep check_caddy
```

---

## Troubleshooting

### Keepalived Container Won't Start

```bash
# Check logs
docker logs code-server-keepalived

# Common issues:
# 1. keepalived-init failed
docker logs code-server-keepalived-init

# 2. Configuration file missing/invalid
docker exec code-server-keepalived cat /etc/keepalived/keepalived.conf

# 3. Network interface eth0 doesn't exist
docker exec code-server-keepalived ip addr show
```

### VIP Not Appearing

```bash
# Check if container is in host network mode
docker inspect code-server-keepalived | grep NetworkMode
# Should show "host"

# Verify capabilities
docker inspect code-server-keepalived | grep CapAdd
# Should include NET_ADMIN, NET_RAW

# Check keepalived process
docker exec code-server-keepalived ps aux | grep keepalived
```

### Health Checks Failing

```bash
# Test health check manually
docker exec code-server-keepalived /usr/local/bin/check-caddy-health.sh
echo $?  # 0 = pass, 1 = fail

# If failing, debug:
docker exec code-server-keepalived docker ps | grep caddy
docker exec code-server-keepalived wget -q -O - http://127.0.0.1/health
```

### Replica Not Taking Over Failover

```bash
# Check if replica keepalived is running
ssh akushnir@192.168.168.42 'docker ps | grep keepalived'

# Check replica logs
ssh akushnir@192.168.168.42 'docker logs code-server-keepalived | tail -20'

# Verify replica can reach primary
ssh akushnir@192.168.168.42 'docker exec code-server-keepalived ping -c 3 192.168.168.31'

# Check VRRP authentication (both must match)
ssh akushnir@192.168.168.42 'docker exec code-server-keepalived grep -A3 "authentication" /etc/keepalived/keepalived.conf'
```

---

## DNS & Router Configuration

### Router Configuration

Update port-forward from primary to VIP:

**Before**:
```
External Port 80/443 → 192.168.168.31:80/443 (Primary)
```

**After**:
```
External Port 80/443 → 192.168.168.30:80/443 (VIP)
```

### DNS Updates

kushnir.cloud currently resolves to: 173.77.179.148 (Cloudflare)  
Cloudflare port-forwards to router which forwards to:
- Before: 192.168.168.31 (Primary only)
- After: 192.168.168.30 (VIP, fails over automatically)

**No DNS changes needed** — only router port-forward changes required.

---

## Operations Reference

### Emergency: Force MASTER on Primary

If replica is stuck and you need to force primary to be master:

```bash
# On primary
docker exec code-server-keepalived killall -9 keepalived
docker restart code-server-keepalived

# Keepalived will restart and reclaim MASTER role (priority 100 > 90)
```

### Emergency: Force BACKUP on Primary

If primary Caddy is broken and you need replica to handle traffic:

```bash
# On primary, temporarily reduce priority
docker exec code-server-keepalived sed -i 's/priority 100/priority 50/' /etc/keepalived/keepalived.conf
docker exec code-server-keepalived killall -1 keepalived
# Send SIGHUP to reload config

# Replica will become MASTER (90 > 50)
# Fix primary Caddy, then restore priority
```

### Graceful Failover

```bash
# Drain traffic from primary
docker stop code-server-caddy

# Wait 15 seconds for failover to complete
sleep 15

# Verify VIP moved to replica
ip addr show eth0 | grep 192.168.168.30  # Should be empty on primary

# Perform maintenance on primary
# ...

# Restore primary
docker start code-server-caddy
sleep 5

# VIP automatically returns to primary after health checks pass
```

---

## Summary

| Aspect | Details |
|--------|---------|
| **Container Image** | keepalived:2.2.7 |
| **Deployment** | Primary (MASTER, priority 100), Replica (BACKUP, priority 90) |
| **VIP** | 192.168.168.30/24 |
| **Health Check** | Caddy /health endpoint every 3 seconds |
| **Failover Time** | 9-12 seconds |
| **Network Mode** | host (required for VIP management) |
| **Capabilities** | NET_ADMIN, NET_BROADCAST, NET_RAW, SYS_ADMIN |
| **Init Container** | Role-based config generation (alpine) |
| **Volumes** | keepalived_config + health check scripts |
| **Monitoring** | Docker logs, /var/log/keepalived-state-changes.log |
| **Status** | Ready for production deployment |

---

**Next Steps**:
1. Deploy keepalived-init containers on both hosts
2. Deploy keepalived service containers on both hosts
3. Verify VIP appears on primary
4. Test failover scenarios
5. Update router port-forward to VIP
6. Monitor for 24-48 hours before declaring fully operational
