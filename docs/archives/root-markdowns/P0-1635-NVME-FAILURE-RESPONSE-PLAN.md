# P0 #1635 - NVMe Failure Response Plan

**Status:** RESPONDING  
**Date:** April 23, 2026  
**Severity:** P0 CRITICAL  
**Impact:** Hardware failure on Replica 2 NVMe drive

---

## Current Situation

**Replica 2 (192.168.168.42) Status:**
- ✅ Currently operational (20/20 services running)
- ⚠️ SMART health check indicates NVMe reliability degraded (0x04)
- ⚠️ Self-test failed with bad segments detected
- 🔴 **RISK:** Drive may fail completely, causing data loss and cluster unavailability

**Replica 1 (192.168.168.31) Status:**
- ✅ Fully operational (19-22/22 services running)
- ✅ Can handle full traffic if Replica 2 isolated
- ✅ Session state in Redis (survives node failures)
- ✅ PostgreSQL replication confirmed working

---

## Immediate Actions Required (Next 1-4 Hours)

### Phase 1: Assess Risk (15 minutes)
```bash
# On Replica 2: Get detailed SMART status
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'sudo smartctl -a /dev/nvme0n1 | grep -E "(FAILED|Reliability|Temperature|Errors)" || echo "smartctl not available"'

# Check if data is being written (risk of corruption)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'iostat -x 1 3 | tail -5'
```

### Phase 2: Failover to Replica 1 (30 minutes)
**Option A - Active Failover (Recommended):**
1. Update load balancer DNS/HAProxy to point only to Replica 1 (192.168.168.31)
2. Verify traffic only going to Replica 1: `curl -I https://ide.kushnir.cloud`
3. Monitor Replica 1 error logs: `docker-compose logs --tail 100 caddy | grep -i error`
4. Keep Replica 2 offline for 24h to prevent further stress on failing drive

**Option B - Planned Shutdown (Conservative):**
1. Gracefully stop services on Replica 2: `ssh ... docker-compose down`
2. Verify no data loss in Replica 1 PostgreSQL
3. Wait for replacement hardware

### Phase 3: Data Backup (30 minutes)
```bash
# Backup critical data from Replica 2 before failure
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose exec -T postgres pg_dump -U codeserver codeserver > /tmp/backup-$(date +%s).sql'

# Copy to safe storage (NAS)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cp /tmp/backup-*.sql /mnt/nas-export/backups/ 2>/dev/null || echo "NAS not accessible"'
```

### Phase 4: Order Replacement Hardware
- **Part:** WD_BLACK SN770 2TB (same as current failure)
- **Supplier:** [CDW, NewEgg, Amazon - pick fastest shipping]
- **Timeline:** 24-48h delivery or same-day local pickup
- **Cost:** ~$150-200 USD

---

## Monitoring During Crisis

**Replica 1 Health Checks (run every 5 min):**
```bash
# Service health
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'docker-compose ps | grep -E "(postgres|redis|caddy|code-server)" | grep -v "Up"'

# PostgreSQL replication lag
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'docker-compose exec -T postgres psql -U codeserver -c "SELECT NOW() - pg_last_wal_receive_lsn()::pg_lsn::text::interval::timestamp AS lag"'

# Error logs
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'docker-compose logs --tail 20 | grep -iE "(error|FATAL|exception|panic)"'
```

**Replica 2 Status (before shutdown):**
```bash
# SMART status change
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'sudo smartctl -A /dev/nvme0n1 | grep -E "Errors|Critical"'

# Disk I/O stress
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'df -h / && iostat -x 5 1 | grep nvme'
```

---

## Post-Failure Recovery (When Hardware Arrives)

### Day 1: Hardware Installation
1. Physical drive replacement (requires console access)
2. BIOS verification of new drive detection
3. OS disk partition recreation
4. NAS mount configuration

### Day 2: Service Restoration
1. Docker-compose pull latest images
2. Run PostgreSQL schema migrations: `db/migrations/*.sql`
3. Restore application data from Replica 1 replication
4. Health check verification

### Day 3: Failover Validation
1. Sync both replicas
2. Test failover: isolate Replica 1, verify Replica 2 serves traffic
3. Restore normal load balancer config
4. Monitor for 24h

---

## Decision Tree

```
NVMe Health Check = FAILED?
├─ YES
│  ├─ Is Replica 1 healthy?
│  │  ├─ YES → Failover to R1, isolate R2, order replacement
│  │  └─ NO → CRITICAL: Incident escalation needed
│  └─ Schedule maintenance window
└─ NO → False alarm, continue monitoring
```

---

## Contact/Escalation

- **On-call:** Check GitHub issue #1635 for assignment
- **Hardware Vendor:** [Contact info]
- **Data Backup Verification:** Confirm Replica 1 has 24h of data retention
- **Customer Notification:** If downtime expected >1h, notify stakeholders

---

## Success Criteria

✅ Replica 2 isolated (no risk of cascading failure)  
✅ Replica 1 serving 100% of traffic with zero errors  
✅ PostgreSQL replication lag < 1 second  
✅ Session state preserved (Redis operational)  
✅ Replacement hardware ordered (2-day lead time)  
✅ Recovery plan documented and tested  

---

**Status:** Ready for failover decision  
**Owner:** On-call ops  
**Next Review:** When Replica 2 NVMe failure worsens or replacement arrives
