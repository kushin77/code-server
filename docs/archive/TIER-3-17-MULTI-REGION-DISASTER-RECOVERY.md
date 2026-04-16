# Phase 17: Multi-Region Deployment & Disaster Recovery

**Status:** IN PROGRESS  
**Effort:** 14 hours (split into 17-A and 17-B)  
**Target Completion:** April 21, 2026  
**Dependencies:** Phase 16 (Infrastructure Scaling) ✅ COMPLETED  
**Owner:** Platform & SRE Team  

---

## Phase 17-A: Cross-Region Replication (7 hours)

### Overview

Deploy code and data across multiple regions with automatic failover:
- **Primary Region** (US-East-1): Production
- **Secondary Region** (US-West-2): Warm standby  
- **DR Region** (EU-West-1): Cold backup
- **Replication Lag**: <5 seconds
- **DNS Failover**: Automatic in <2 minutes
- **Data Consistency**: Cross-region transactions

### Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ Users (Global)                                                       │
│ DNS: code-server.dev.yourdomain.com (Cloudflare Global Load Balance) │
└──────────────────────────────────────────────────────────────────────┘
         |
    ┌────┴───────────────────────────────────────────────┐
    |                                                     |
    ↓ (Primary US-East-1)                   ↓ (Secondary US-West-2)
┌──────────────────────┐                ┌──────────────────────┐
│ Region: US-East-1    │ ───Repl ────→ │ Region: US-West-2    │
│                      │  (stream)      │                      │
│ Primary PostgreSQL   │                │ Hot Standby DB       │
│ 192.168.168.31:5432  │                │ 10.0.0.31:5432       │
│                      │                │                      │
│ Primary HAProxy      │                │ Standby HAProxy      │
│ 192.168.168.33:443   │   (via VPN)    │ 10.0.0.33:443        │
│                      │                │                      │
│ App Servers (ASG)    │                │ App Servers (ASG)    │
│ Min: 3, Max: 50      │                │ Min: 2, Max: 20      │
│                      │                │                      │
│ Status: ACTIVE       │◄────heartbeat──│ Status: WARM STANDBY │
└──────────────────────┘                └──────────────────────┘
         |                                     |
         └─────────────────┬───────────────────┘
                           |
                     (Failover Trigger)
                           |
        If East-1 down ────→ DNS flip to West-2
        Traffic: 0 → 100% to US-West-2
        Promotion: 5 second lag
        
Optional:
         |
         ↓ (DR EU-West-1)
    ┌──────────────────────┐
    │ Region: EU-West-1    │
    │                      │
    │ Cold Backup DB       │
    │ (async from East-1)  │
    │                      │
    │ Status: COLD         │
    │ (manual activation)  │
    └──────────────────────┘
```

### Implementation (7 hours)

**Hour 1: Terraform Multi-Region Setup**
```hcl
# Primary Region (us-east-1)
resource "aws_db_subnet_group" "primary" {
  name = "code-server-primary"
  subnet_ids = [aws_subnet.primary_1.id, aws_subnet.primary_2.id]
  provider = aws.us-east-1
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier = "code-server-primary"
  engine = "aurora-postgresql"
  
  # Global database for cross-region replication
  enable_http_endpoint = true
  backup_retention_period = 35
  
  provider = aws.us-east-1
}

# Secondary Region (us-west-2)
resource "aws_rds_global_cluster" "main" {
  global_cluster_identifier = "code-server-global"
  engine = "aurora-postgresql"
  engine_version = "14.6"
}

resource "aws_rds_cluster" "secondary" {
  cluster_identifier = "code-server-secondary"
  
  global_cluster_identifier = aws_rds_global_cluster.main.id
  depends_on = [aws_rds_cluster.primary]
  
  provider = aws.us-west-2
}
```

**Hour 2: Database Replication Configuration**
```bash
#!/bin/bash
# Enable row-level replication for accurate failover

# Primary (us-east-1)
psql -h primary-db.rds.amazonaws.com << 'SQL'
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;

SELECT pg_reload_conf();

-- Create publication for secondary subscription
CREATE PUBLICATION code_server_pub FOR ALL TABLES;
SQL

# Secondary (us-west-2) - subscribe to primary
psql -h secondary-db.rds.amazonaws.com << 'SQL'
CREATE SUBSCRIPTION code_server_sub
CONNECTION 'host=primary-db.us-east-1.rds.amazonaws.com dbname=code_server user=replicator password=XXX'
PUBLICATION code_server_pub;

-- Verify replication
SELECT * FROM pg_stat_replication;
SQL
```

**Hour 3: DNS Failover Setup**
```hcl
# Route53 health check (primary region)
resource "aws_route53_health_check" "primary" {
  fqdn = aws_lb.primary.dns_name
  port = 443
  type = "HTTPS"
  failure_threshold = 3
  measure_latency = true
  request_interval = 10  # Check every 10 seconds
}

# Failover routing policy
resource "aws_route53_record" "code_server" {
  zone_id = aws_route53_zone.main.zone_id
  name = "code-server.dev.yourdomain.com"
  type = "A"
  
  # Primary
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  set_identifier = "primary-us-east-1"
  alias {
    name = aws_lb.primary.dns_name
    zone_id = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
  health_check_id = aws_route53_health_check.primary.id
}

# Secondary
resource "aws_route53_record" "code_server_secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name = "code-server.dev.yourdomain.com"
  type = "A"
  
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  set_identifier = "secondary-us-west-2"
  alias {
    name = aws_lb.secondary.dns_name
    zone_id = aws_lb.secondary.zone_id
  }
}

# CloudFlare Global Load Balancing (optional)
# Sits in front of Route53 for even faster failover
```

**Hour 4: VPN Connectivity Between Regions**
```hcl
# VPN connection between east and west
resource "aws_vpn_connection" "primary_to_secondary" {
  type = "ipsec.1"
  customer_gateway_id = aws_customer_gateway.primary.id
  vpn_gateway_id = aws_vpn_gateway.secondary.id
  
  options {
    static_routes_only = false
    tunnel1_phase1_encryption_algorithms = ["AES256"]
    tunnel1_phase1_integrity_algorithms = ["SHA2-256"]
  }
}

# BGP for dynamic routing
resource "aws_vpn_connection_route" "example" {
  destination_cidr_block = "10.0.0.0/8"  # Secondary VPC
  vpn_connection_id = aws_vpn_connection.primary_to_secondary.id
}
```

**Hour 5: Replication Lag Monitoring**
```yaml
# Prometheus rules
groups:
  - name: replication
    rules:
      - alert: ReplicationLagHigh
        expr: pg_stat_replication_write_lag_bytes > 5242880  # 5MB
        for: 1m
        annotations:
          severity: warning
          summary: "Cross-region replication lag > 5MB"

      - alert: ReplicationLagSecondsHigh
        expr: pg_stat_replication_write_lag_seconds > 10
        for: 2m
        annotations:
          severity: critical
          summary: "Cross-region replication lag > 10 seconds"

      - alert: SecondaryRegionDown
        expr: up{job="secondary-region"} == 0
        for: 30s
        annotations:
          severity: critical
          summary: "Secondary region is unreachable"
```

**Hour 6: Failover Automation**
```bash
#!/bin/bash
# Automatic failover script (runs on secondary region)

REPL_LAG_THRESHOLD=15  # seconds
PRIMARY_DOWN_THRESHOLD=60  # seconds

while true; do
  # Check primary replication lag
  LAG=$(psql -h secondary-db -U moni -c \
    "SELECT EXTRACT(EPOCH FROM (now() - xact_start)) FROM pg_stat_replication;" \
    | grep -oE '[0-9]+')
  
  if [[ $LAG -gt $REPL_LAG_THRESHOLD ]]; then
    echo "WARN: Replication lag $LAG seconds"
  fi
  
  # Check primary health via Route53
  PRIMARY_HEALTH=$(aws route53 get-health-check-status \
    --health-check-id $PRIMARY_HC_ID \
    --query 'HealthCheckObservations[0].StatusReport.Status' \
    --output text)
  
  if [[ "$PRIMARY_HEALTH" == "Failed" ]]; then
    echo "CRITICAL: Primary region unhealthy"
    
    # Trigger failover
    promote_secondary_to_primary
    
    # Disable replication (secondary becomes new primary)
    psql -h secondary-db -U admin << 'SQL'
    ALTER SUBSCRIPTION code_server_sub DISABLE;
    SELECT pg_promote();  -- Promote replica to primary
    SQL
    
    echo "FAILOVER COMPLETE: Secondary is now primary"
    break
  fi
  
  sleep 10
done
```

**Hour 7: Testing Failover**
```bash
#!/bin/bash
# Test script for multi-region failover

# 1. Generate load on primary
wrk -t 4 -c 100 -d 2m https://code-server.dev.yourdomain.com/api/health &

# 2. Verify replication lag
echo "Replication lag:"
psql -h secondary-db -c "SELECT now() - pg_last_xact_replay_timestamp() as lag;" 

# 3. Simulate primary failure
aws ec2 stop-instances --instance-ids i-primary-alb --region us-east-1

# 4. Monitor DNS failover (should happen in <2 min)
watch -n 2 'dig +short code-server.dev.yourdomain.com'

# Expected: DNS resolves to secondary IP after ~90 seconds
# Expected: No traffic loss (connections retry automatically)

# 5. Check traffic now going to secondary
curl -I https://code-server.dev.yourdomain.com
# Should return 200 OK from secondary region

# 6. Restart primary
aws ec2 start-instances --instance-ids i-primary-alb --region us-east-1

# 7. Wait for re-replication
sleep 120
psql -h secondary-db -c "SELECT pg_last_xact_replay_timestamp();"
```

---

## Phase 17-B: Disaster Recovery Runbook (7 hours)

### Purpose

Document procedures for all failure scenarios with RTO/RPO targets:

**Failure Scenarios:**
1. Single server down (app-1 fails)
2. Database down (primary PostgreSQL fails)
3. Region down (entire US-East-1 fails)
4. Multi-region failure (two regions down)
5. Data center network issue
6. Accidental data deletion

### Runbook Structure (7 hours)

**Hour 1-3: Create Runbooks**
```markdown
# Disaster Recovery Runbook

## Scenario 1: Single App Server Down
Target RTO: 10 seconds
Target RPO: 0 (no data loss)

Detection:
  - HAProxy health check fails (10s)
  - Monitoring alert fires
  
Action:
  1. HAProxy automatically removes failed server
  2. ASG detects unhealthy instance
  3. ASG terminates and replaces instance (3 min)
  
Verification:
  - New instance: healthy
  - Traffic: no gaps
  -Latency: normal
  
Expected Impact: <30 seconds of increased latency for existing connections

---

## Scenario 2: Database Primary Down
Target RTO: 30 seconds
Target RPO: <5 seconds (streaming replication)

Detection:
  - Connection timeout to primary
  - Monitoring alert in <10 seconds
  
Action:
  1. Standby automatic failover triggers
  2. pgBouncer detects: promotes standby
  3. DNS (optional): Switch to secondary region if needed
  
Verification:
  - SELECT current_primary(): Returns standby name
  - replication lag: 0 (no more replication)
  - Data: Verified intact
  
Expected Impact: <60 seconds downtime, zero data loss (streaming rep)

---

## Scenario 3: Entire Region Down (US-East-1)
Target RTO: 2 minutes
Target RPO: <5 seconds

Detection:
  - Multiple health checks fail (30s)
  - Route53 detects primary region unhealthy
  
Action:
  1. Route53 fails over to secondary region
  2. DNS propagates globally (30-60s)
  3. Secondary becomes primary (no action needed)
  4. Clients connect to secondary region
  
Verification:
  - Data in secondary: Verified current
  - DNS resolves to secondary IP
  - No connection errors for new clients
  
Expected Impact: Old connections: timeout
             New connections: route to secondary
             Data: Consistent (replication)

---

## Scenario 4: Multi-Region Failure
Target RTO: 4 hours
Target RPO: Last backup (up to 24h old)

Detection:
  - Both primary and secondary down
  - DR region only option
  
Action:
  1. Manual intervention required
  2. Restore from latest backup in DR region
  3. Verify data integrity
  4. Point DNS to DR region
  5. Document root cause
  
Verification:
  - DR region: Data restored and online
  - DNS: Pointing to DR
  - Alerting: Updated to monitor DR
  
Expected Impact: 2-4 hours of downtime
                Data loss: Up to 24 hours (backup frequency)

---

## Scenario 5: Network Between Regions
Target RTO: 10 minutes
Target RPO: <5 seconds

Detection:
  - Replication lag increases rapidly
  - VPN connection down
  
Action:
  1. Try VPN reconnect
  2. If sustained >1 min: Assume full region failure
  3. Perform secondary region full failover
  
Verification:
  - VPN: Up or failed gracefully
  - Replication: Resumed or failed over
  
Expected Impact: Temporary lag spike or brief failover

---

## Scenario 6: Accidental Data Deletion
Target RTO: 30 minutes (manual recovery)
Target RPO: Last backup (24h window)

Detection:
  - Application reports missing data
  - Monitoring: anomaly detected
  
Action:
  1. Pause replication (stop slave)
  2. Restore point-in-time backup
  3. Resume replication
  
Verification:
  - Data: Restored to before deletion
  - Integrity: Checked
  - Replication: Caught up to present
  
Expected Impact: Data rolls back to backup point
```

**Hour 4-5: Create Tools**
```bash
#!/bin/bash
# Automated failover tools

# Tool 1: Health Dashboard
update_health_dashboard() {
  METRICS=$(cat <<SQL
SELECT 
  'Primary' as region,
  (SELECT now() - pg_last_xact_replay_timestamp())::text as repl_lag,
  (SELECT count(*) FROM pg_stat_replication) as active_replicas,
  (SELECT status FROM aws_health_check WHERE name='primary') as health
UNION ALL
SELECT 'Secondary', ..., ..., ...
FROM secondary_db;
SQL
  )
  
  echo "$METRICS" | tee /tmp/dr_dashboard.txt
  # Send to Slack
  curl -X POST -d "{text: \"$METRICS\"}" $SLACK_WEBHOOK
}

# Tool 2: Failover Trigger
trigger_failover() {
  REGION=$1
  
  if [[ "$REGION" == "primary" ]]; then
    # Failover from primary to secondary
    ssh secondary-db "sudo pg_promote"
    aws route53 change-resource-record-sets ... # Update DNS
    
  elif [[ "$REGION" == "secondary" ]]; then
    # Failover from secondary to DR (manual)
    echo "Manual activation required for DR region"
    echo "1. Stop development traffic"
    echo "2. Verify backup integrity"
    echo "3. Run: aws rds restore-db-cluster-from-snapshot ..."
  fi
}

# Tool 3: Data Integrity Check
verify_data_integrity() {
  # Compare checksums between regions
  PRIMARY_CHECKSUM=$(psql -h primary-db -c "SELECT md5(string_agg(*, '')) FROM ..." | tail -1)
  SECONDARY_CHECKSUM=$(psql -h secondary-db -c "SELECT md5(string_agg(*, '')) FROM ..." | tail -1)
  
  if [[ "$PRIMARY_CHECKSUM" != "$SECONDARY_CHECKSUM" ]]; then
    echo "ERROR: Data mismatch between regions!"
    exit 1
  fi
  
  echo "OK: Data consistent across regions"
}
```

**Hour 6-7: Manual Procedures & Training**
```markdown
# Manual Procedure: Full Failover

## Step 1: Assessment (5 minutes)
- [ ] Verify primary region is truly down (not network glitch)
- [ ] Check replication lag on secondary
- [ ] Verify secondary region health
- [ ] Check data integrity: both regions

## Step 2: Communication (5 minutes)
- [ ] Notify stakeholders via Slack #incidents
- [ ] Page on-call team
- [ ] Create incident ticket
- [ ] Initiate incident call (Zoom/Teams)

## Step 3: Failover Execution (10 minutes)
- [ ] Disable replication subscription (stop slave)
- [ ] Promote secondary: SELECT pg_promote()
- [ ] Verify: SELECT pg_is_in_recovery() returns f
- [ ] Update DNS: Point to secondary IP
- [ ] Verify: Clients can connect

## Step 4 Verification (10 minutes)
- [ ] Test application functionality
- [ ] Verify data integrity
- [ ] Check metrics (latency, errors)
- [ ] Confirm all replicas attached

## Step 5: Recovery (varies)
- [ ] Investigate root cause of failure
- [ ] Fix primary region issue
- [ ] Rebuild primary as replica
- [ ] Switch back when ready (manual decision)

## Step 6: Post-Incident (30 minutes)
- [ ] Document timeline
- [ ] Identify improvements
- [ ] Update runbooks
- [ ] Schedule blameless postmortem
```

---

## Success Criteria

✅ **All Met** (After implementation):

1. **Cross-Region Replication**
   - [ ] Secondary region receives updates <5 seconds
   - [ ] No data loss during replication
   - [ ] Replication resumable after interruption

2. **DNS Failover**
   - [ ] Health checks detect failure <30 seconds
   - [ ] DNS updates <2 minutes
   - [ ] Clients route to secondary automatically

3. **Runbooks**
   - [ ] All 6 scenarios documented with procedures
   - [ ] RTO/RPO targets defined for each
   - [ ] Tools and scripts automated where possible
   - [ ] Team trained and certified

4. **Testing**
   - [ ] Monthly failover drill conducted
   - [ ] Data integrity verified post-failover
   - [ ] RTO/RPO targets met in test
   - [ ] Documentation updated based on learnings

---

## Timeline

**Week 1 (Apr 14-17):**
- Phase 16: Database HA + Load Balancing ✅

**Week 2 (Apr 18-21):**
- [ ] Phase 17-A: Multi-region replication (deploy)
- [ ] Phase 17-B: DR runbook (document + test)

**Week 3 (Apr 22-25):**
- Phase 18: Security hardening

**Week 4 (Apr 26-May 1):**
- Integration testing
- Monthly failover drill
- Customer UAT

---

## Related Documents

- TIER-3-MAJOR-PROJECTS-EXECUTION.md (Roadmap)
- TIER-3-16A-DATABASE-HA-IMPLEMENTATION.md (Prerequisite)
- TIER-3-16B-LOAD-BALANCING-IMPLEMENTATION.md (Prerequisite)
