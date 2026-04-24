# P0 #1386 - NAS Data Protection Plan

## Executive Summary
Implements comprehensive data protection strategy for production infrastructure using 99G NAS export at 192.168.168.55 with 27G available capacity (73% utilized).

## Current State Analysis

### NAS Inventory
- **Host**: 192.168.168.55 (/export)
- **Total**: 99G
- **Used**: 68G
- **Available**: 27G (capacity for ~10 additional production databases)
- **Utilization**: 73%

### Data Placement
✅ **Protected (NAS-backed)**:
- PostgreSQL backups: `/mnt/nas-56/backups` (PITR-ready, NFS mounted)
- Logs: `/var/log` (NFS mounted from `/export/logs`)
- Code Server workspace: `/mnt/nas-56/code-server`
- Grafana dashboards: `/mnt/nas-56/api`

❌ **At Risk (Local Docker volumes)**:
- postgres-data: Local volume (running container)
- redis-data: Local volume (in-memory with backup capability)
- redis-sentinel-*-data: Local volume (state only)
- prometheus-data: Local volume (metrics - 15 day retention)

## Protection Strategy

### Phase 1: Automated Backups (IMMEDIATE - P0)
1. **PostgreSQL PITR**:
   - `postgres-backup` volume already NAS-mounted
   - Configure WAL archiving to NAS
   - Test point-in-time recovery weekly
   
2. **Redis Persistence**:
   - RDB snapshots via `appendonly yes` config
   - Backup to NAS: `/export/redis-snapshots/`
   - Automate daily snapshot export

3. **Application Data**:
   - code-server-workspace: Already NAS-mounted
   - Scheduled daily tarballs to `/export/backups/`

### Phase 2: Storage Consolidation (OPTIONAL - P2)
1. **Move prometheus-data to NAS**:
   - Add NFS driver option to prometheus-data volume
   - Requires metric volume format support check
   
2. **Redis Sentinel State**:
   - Sentinel state is ephemeral (recreates from master)
   - No backup needed (low priority)

### Phase 3: Capacity Planning (P2)
- Current: 27G available
- Reserved: 10G for safety margin
- Working capacity: 17G
- Quarterly review of growth rate

## Implementation Checklist

### Backup Automation
- [ ] Create backup scripts: `scripts/backup/postgres-backup-daily.sh`
- [ ] Create backup scripts: `scripts/backup/redis-snapshot-backup.sh`
- [ ] Configure systemd timers on .31 for daily execution
- [ ] Create backup verification tests
- [ ] Document recovery procedures

### Monitoring
- [ ] Add NAS capacity alerts to Prometheus
- [ ] Alert when capacity >80% (23G remaining)
- [ ] Alert when backups fail or miss SLA
- [ ] Dashboard for backup health

### Testing
- [ ] Monthly PostgreSQL PITR recovery test
- [ ] Monthly Redis snapshot recovery test
- [ ] Failover scenario with backup recovery

## Risk Mitigation

### Failure Modes
| Scenario | Impact | Mitigation |
|----------|--------|-----------|
| NAS host down | All backups inaccessible | Configure .42 as backup NAS client |
| NAS disk full | Backups fail | Implement capacity alerts at 80% |
| Network failure | NAS mount hangs | timeout configs on NFS mounts |
| Backup corruption | Restore fails | Weekly verification tests |

## Success Criteria
- ✅ PostgreSQL: WAL archiving to NAS, PITR tested
- ✅ Redis: Daily snapshots to NAS, verified recoverable
- ✅ Application: Workspace backups on NAS, tested
- ✅ Monitoring: Alerts for capacity/backup failures
- ✅ Documentation: Procedures for all recovery scenarios

## Related Issues
- P0 #1377: Redis security (completed)
- P0 #1360: Sentinel HA (completed)
- P1 #1392: Firewall hardening (pending)

---
**Status**: Ready for implementation  
**Priority**: P0 (data protection critical for production)  
**Owner**: Infrastructure team
