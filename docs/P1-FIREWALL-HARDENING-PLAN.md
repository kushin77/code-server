# P1 #1392 - Firewall Hardening Plan

## Executive Summary
Implements UFW firewall rules on 192.168.168.31 (primary) and 192.168.168.42 (replica) to restrict network access to production services by default and explicitly allow only necessary traffic.

## Current State
- **Firewall Status**: UFW installed, currently inactive (status: inactive)
- **Primary Host**: 192.168.168.31 (akushnir user, requires sudo for UFW)
- **Replica Host**: 192.168.168.42 (for HA failover)
- **Risk**: All Docker ports exposed to internal network without filtering

## Security Requirements

### Allowed Inbound Traffic
| Port | Service | Source | Protocol | Priority |
|------|---------|--------|----------|----------|
| 22 | SSH | 192.168.0.0/16 | TCP | HIGH |
| 80 | HTTP | 0.0.0.0/0 | TCP | HIGH (redirect to 443) |
| 443 | HTTPS | 0.0.0.0/0 | TCP | CRITICAL |
| 26379 | Redis Sentinel | 192.168.168.42 | TCP | HIGH |
| 9093 | AlertManager | 192.168.168.0/24 | TCP | MEDIUM |
| 9090 | Prometheus | 192.168.168.0/24 | TCP | MEDIUM |
| 3000 | Grafana | 192.168.168.0/24 | TCP | MEDIUM |

### Blocked Inbound Traffic (DEFAULT: DROP)
- Redis (6379): Block except from localhost and .42
- PostgreSQL (5432): Block except from localhost and pgbouncer container
- Docker API (2375, 2376): Block all (socket-only)
- Docker daemon ports: Drop all
- All other ports: DROP by default

### Outbound Traffic
- Allow all (required for NAS mounts, DNS, updates)
- Can be restricted later if needed

## Implementation Plan

### Phase 1: Base UFW Configuration (IMMEDIATE)
```bash
# 1. Enable UFW with default DROP inbound
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed

# 2. Allow critical SSH (prevent lockout)
sudo ufw allow 22/tcp comment "SSH access"

# 3. Allow HTTPS (public-facing)
sudo ufw allow 443/tcp comment "HTTPS web access"
sudo ufw allow 80/tcp comment "HTTP redirect"

# 4. Enable UFW
sudo ufw enable
```

### Phase 2: Internal Service Access (POST-ENABLE)
```bash
# Prometheus (metrics internal)
sudo ufw allow from 192.168.168.0/24 to any port 9090 comment "Prometheus metrics"

# AlertManager (alerts internal)
sudo ufw allow from 192.168.168.0/24 to any port 9093 comment "AlertManager API"

# Grafana (dashboards internal)
sudo ufw allow from 192.168.168.0/24 to any port 3000 comment "Grafana dashboards"

# Redis Sentinel (HA failover from replica)
sudo ufw allow from 192.168.168.42 to any port 26379 comment "Sentinel from replica"

# NAS access (required for NFS mounts)
sudo ufw allow to 192.168.168.55 port 2049 comment "NFS from NAS"
```

### Phase 3: Replica Configuration (AFTER PRIMARY STABLE)
```bash
# 1. SSH
sudo ufw allow 22/tcp comment "SSH access"

# 2. HTTPS
sudo ufw allow 443/tcp comment "HTTPS web access"

# 3. Redis Sentinel can reach primary
sudo ufw allow to 192.168.168.31 port 26379 comment "Sentinel to primary"

# 4. Enable
sudo ufw enable
```

## Security Verification Checklist

### Before Going Live
- [ ] SSH access confirmed (test from bastion)
- [ ] HTTPS accessible from external
- [ ] Redis not accessible from outside 192.168.168.0/24
- [ ] PostgreSQL not accessible from outside localhost
- [ ] Internal monitoring still works (Prometheus → targets)
- [ ] Alerting still functional (AlertManager → webhooks)
- [ ] NAS mounts still healthy (NFS traffic allowed)
- [ ] Failover path tested (.42 → .31 Sentinel)

### Monitoring
- [ ] Add UFW rule violation alerts
- [ ] Monitor SSH connection attempts
- [ ] Alert on new inbound SYN packets to restricted ports
- [ ] Dashboard for firewall traffic patterns

## Rollback Plan
If firewall breaks production:
1. SSH into .42 (if .31 is unreachable)
2. From .42, remotely disable UFW on .31: `ssh akushnir@192.168.168.31 sudo ufw disable`
3. Or: `docker exec some-container /bin/sh` and restart services
4. Review log: `sudo tail -f /var/log/ufw.log`

## Related Issues
- P0 #1377: Redis network security (complementary)
- P0 #1358: Caddy health (firewall won't affect)
- P0 #1360: Sentinel HA (firewall supports .42 access)

## Success Criteria
- ✅ UFW enabled on both .31 and .42
- ✅ SSH accessible (verify: ssh akushnir@192.168.168.31)
- ✅ HTTPS accessible (verify: curl -I https://ide.kushnir.cloud)
- ✅ Internal services working (Prometheus scraping, Alerting)
- ✅ Failover still functional (Sentinel → replica promotion)
- ✅ All rules logged and monitored

---
**Status**: Ready for manual implementation  
**Priority**: P1 (network hardening, supports P0 security)  
**Execution**: Requires root access (sudo) on both hosts
