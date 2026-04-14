# Phase 19: Operational Runbooks & Procedures

## Overview
This document contains 50+ operational procedures for Phase 19 Advanced Operations & Production Excellence. All procedures include prerequisites, step-by-step instructions, success criteria, and rollback procedures.

---

## INFRASTRUCTURE EMERGENCIES

### 1. Node Failure / Node Replacement
**Severity**: P0 | **MTTD**: < 1 min | **MTTR**: < 15 min

#### Prerequisites
- kubectl access with cluster-admin role
- PagerDuty escalation configured
- Backup nodes ready in node pool

#### Procedure
1. **Detect node failure**
   ```bash
   # Cluster auto-detects unhealthy node (CPU/memory/disk check every 30s)
   kubectl get nodes -o wide | grep NotReady
   ```

2. **Immediate containment** (< 1 minute)
   ```bash
   # Mark node as unschedulable (prevents new pods)
   kubectl cordon <node-name>

   # Drain existing workloads (3-minute grace period)
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --grace-period=180
   ```

3. **Replace node**
   ```bash
   # Trigger auto-scaling to provision replacement
   gcloud compute instance-groups managed abandon-instances <instance-group> <instance-id>

   # Auto-scaler provisions new node (~2-3 minutes)
   # Monitor replacement: kubectl watch nodes
   ```

4. **Verify recovery**
   - All pods running: `kubectl get pods -A | grep -c Running`
   - Service available: `curl -s http://api-server/health`
   - Error rate normal: `curl prometheus:9090/api/v1/query?query=rate(http_requests_total[5m])`

5. **Remove old node** (after 30-min grace period)
   ```bash
   kubectl delete node <old-node-name>
   ```

#### Success Criteria
- ✅ No pod loss (stateful sets use PVC)
- ✅ Service downtime < 2 minutes
- ✅ Error rate returns to normal within 5 minutes
- ✅ All workloads rescheduled

#### Rollback
- Not applicable (node replacement is irreversible)

---

### 2. Database Failover (Primary → Replica)
**Severity**: P0 | **MTTD**: < 30 sec | **MTTR**: < 2 min

#### Prerequisites
- PostgreSQL replica running and synchronized (replication lag < 10ms)
- Keepalived configured for automatic VIP failover
- Monitoring alerting on replication lag

#### Procedure
1. **Detect primary failure**
   ```bash
   # Automated detection: Health check fails 3 consecutive times
   # Triggers automatic failover Kubernetes probe
   kubectl get pod postgres-0 -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'
   ```

2. **Promote replica** (automatic via Patroni/etcd)
   ```bash
   # Kubernetes operator handles this automatically
   # Monitor: kubectl logs -f deployment/postgres-operator
   ```

3. **Verify new primary**
   ```bash
   # Check replication role
   kubectl exec postgres-1 -- psql -c "SELECT pg_is_in_recovery();"
   # Should return: f (false = now primary)

   # Verify write access
   kubectl exec postgres-1 -- psql -c "INSERT INTO health_check (timestamp) VALUES (NOW());"
   ```

4. **Reconfigure standby**
   ```bash
   # Old primary becomes new standby
   # Patroni cluster manager handles this automatically
   kubectl port-forward postgres-0 5432:5432 &
   psql -h localhost -c "ALTER SYSTEM SET recovery_target_timeline = 'latest';"
   ```

5. **Resume replication**
   ```bash
   # Verify replica catching up
   watch 'kubectl exec postgres-0 -- psql -c "SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()));"'
   # Should decrease to < 100ms
   ```

#### Success Criteria
- ✅ Failover completes in < 2 minutes
- ✅ Zero data loss (sync replication)
- ✅ Applications reconnect automatically
- ✅ Replication resumes within 60 seconds

#### Rollback
1. Wait for original primary to recover
2. Failover back: `patronictl switchover --master <current-primary> --candidate <original-primary>`

---

### 3. Cache Layer Invalidation (Redis Failure)
**Severity**: P1 | **MTTD**: < 10 sec | **MTTR**: < 30 sec

#### Prerequisites
- Redis cluster (3+ nodes)
- Automatic failover configured
- Cache warming strategy ready

#### Procedure
1. **Detect cache failure**
   ```bash
   # Health check fails 2 consecutive times
   kubectl get pod redis-0 -w
   ```

2. **Trigger automatic failover** (Redis Sentinel)
   ```bash
   # Sentinel automatically promotes replica
   # No manual action needed
   # Verify: redis-cli -p 26379 SENTINEL masters
   ```

3. **Warm cache** (optional, depends on failure)
   ```bash
   # Trigger cache warmer for critical data
   kubectl exec redis-warmer -- /bin/sh -c './warm-critical-cache.sh'

   # Monitor: grep "Cache warm" /var/log/application.log
   ```

4. **Monitor cache hit ratio**
   ```bash
   # Should recover to normal (90%+) within 60 seconds
   curl -s prometheus:9090/api/v1/query?query=redis_hits/(redis_hits+redis_misses)
   ```

#### Success Criteria
- ✅ Failover < 30 seconds
- ✅ Cache hit ratio > 85%
- ✅ Application response time normal
- ✅ No 5xx errors from cache timeouts

#### Rollback
- Not applicable (automatic recovery)

---

### 4. Disk Space Emergency (Node Running Out of Space)
**Severity**: P0 | **MTTD**: < 2 min | **MTTR**: < 10 min

#### Prerequisites
- Disk usage monitoring alerting (80% warning, 90% critical)
- Log rotation configured
- Cleanup scripts available

#### Procedure
1. **Immediate diagnostics**
   ```bash
   # Find what's consuming disk
   kubectl debug node/<node-name> -it --image=ubuntu
   du -sh /* | sort -rh | head -20
   ```

2. **Emergency cleanup**
   ```bash
   # Kill debug pods (can consume significant disk)
   kubectl delete pod -A --field-selector=status.phase=Failed,status.phase=Unknown

   # Clear old logs (be careful!)
   kubectl logs -n <namespace> <pod> --tail=0 > /dev/null

   # Clean old images
   docker image prune -a --force --filter "until=720h"
   ```

3. **Increase storage**
   ```bash
   # Add new disk to node
   gcloud compute disks create disk-<timestamp> --size=50GB
   gcloud compute instances attach-disk <instance> --disk=disk-<timestamp>

   # Mount disk
   sudo mkdir /mnt/data
   sudo mkfs.ext4 /dev/sdb
   sudo mount /dev/sdb /mnt/data
   ```

4. **Verify recovery**
   ```bash
   # Check available space
   df -h
   # Should show critical threshold < 80%

   # Monitor impact on pods
   kubectl get events -A --sort-by='.lastTimestamp' | tail -20
   ```

#### Success Criteria
- ✅ Disk usage < 75%
- ✅ No `DiskPressure` node conditions
- ✅ Pod scheduling resumes
- ✅ No data loss

#### Rollback
- Clean up temporary files added during emergency

---

### 5. Network Partition / Split Brain
**Severity**: P0 | **MTTD**: < 1 min | **MTTR**: < 5 min

#### Prerequisites
- Network monitoring with packet loss detection
- Cluster quorum (3+ etcd nodes)
- Split-brain prevention configured

#### Procedure
1. **Detect network partition**
   ```bash
   # etcd health shows "unhealthy" for isolated nodes
   kubectl -n kube-system exec -it etcd-<node> -- etcdctl endpoint health

   # Look for "failed: 0" entries
   ```

2. **Isolate affected component**
   ```bash
   # Move workloads off isolated nodes
   for node in $(kubectl get nodes | grep NotReady); do
     kubectl cordon $node
   done
   ```

3. **Wait for network recovery or remove bad nodes**
   ```bash
   # Try waiting for auto-recovery (30 seconds)
   sleep 30
   kubectl get nodes

   # If still NotReady, remove from cluster
   kubectl delete node <bad-node> --ignore-daemonsets
   ```

4. **Verify consistency**
   ```bash
   # Check etcd consistency
   kubectl -n kube-system exec etcd-<primary> -- \
     etcdctl endpoint health

   # Verify no data loss
   kubectl get all -A | wc -l  # Should match previous count
   ```

5. **Rejoin healed node**
   ```bash
   # After network recovery, rejoin node
   kubectl uncordon <recovered-node>

   # Monitor join: kubectl logs -f -n kube-system <kubelet-pod>
   ```

#### Success Criteria
- ✅ etcd cluster healthy (all members reporting healthy)
- ✅ API server responding on all nodes
- ✅ No split-brain (only one primary active)
- ✅ Data consistency verified

#### Rollback
- Re-add isolated nodes once network recovered

---

## APPLICATION ISSUES

### 6. Memory Leak Detection & Container Restart
**Severity**: P1 | **MTTD**: < 2 min | **MTTR**: < 1 min

#### Prerequisites
- Memory usage monitoring (alert at 80% of limit)
- Pod resource limits configured
- Automatic restart on OOM enabled

#### Procedure
1. **Detect memory leak**
   ```bash
   # Alert triggers when Usage > Threshold (e.g., 800Mi for 1Gi limit)
   kubectl top pod <pod-name>

   # Check memory over time
   curl -s 'prometheus:9090/api/v1/query_range' \
     --data-urlencode 'query=container_memory_usage_bytes{pod="<pod>"}' \
     --data-urlencode 'start=<1h-ago>' \
     --data-urlencode 'step=60' | jq '.data.result[0].values[-5:]'
   ```

2. **Diagnose memory profile**
   ```bash
   # Get memory profile
   kubectl port-forward <pod> 6060:6060 &
   go tool pprof http://localhost:6060/debug/pprof/heap -http=:8080

   # Identify top memory consumers
   ```

3. **Trigger graceful shutdown**
   ```bash
   # Send SIGTERM to pod (allows cleanup)
   kubectl delete pod <pod-name> --grace-period=30

   # Kubernetes automatically restarts (via ReplicaSet)
   ```

4. **Monitor restart and recovery**
   ```bash
   # Watch pod restart
   kubectl get pod <pod-name> -w

   # Verify new container memory
   kubectl top pod <pod-name>
   # Should show normal usage
   ```

#### Success Criteria
- ✅ Pod restarts successfully
- ✅ Memory drops to normal (< 30% limit)
- ✅ No lost requests (service continues)
- ✅ Error rate returns to baseline

#### Rollback
- Deploy fixed application version

---

### 7. High CPU Usage / Service Degradation
**Severity**: P1 | **MTTD**: < 1 min | **MTTR**: < 5 min

#### Prerequisites
- CPU usage monitoring (alert at 80%)
- Horizontal Pod Autoscaler configured
- Load distribution configured

#### Procedure
1. **Identify CPU consumer**
   ```bash
   # Find pod with high CPU
   kubectl top pods -A | sort -k3 -rn | head -5

   # Check if normal or anomaly
   curl -s 'prometheus:9090/api/v1/query' \
     --data-urlencode 'query=rate(cpu{container="api-server"}[5m])' | jq
   ```

2. **Check for runaway process**
   ```bash
   # Get detailed process list
   kubectl exec <pod> -- top -b -n 1 | head -20

   # Check for infinite loops in logs
   kubectl logs <pod> | tail -100 | grep -E "loop|retry|Exception" | uniq -c
   ```

3. **Scale up service**
   ```bash
   # Manual scale (for immediate relief)
   kubectl scale deployment <service> --replicas=10

   # Or trigger HPA (if configured)
   kubectl patch hpa <service> -p '{"spec":{"minReplicas":5,"maxReplicas":20}}'
   ```

4. **Monitor load distribution**
   ```bash
   # Verify requests distributed evenly
   kubectl top pods -l app=<service> | awk 'NR>1 {print $3}' | sort -n

   # Check response latency
   curl -w 'Total time: %{time_total}s\n' http://<service>/health
   ```

5. **Investigate root cause**
   ```bash
   # Get CPU profile
   kubectl port-forward <pod> 6060:6060 &
   go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30 -http=:8080
   ```

#### Success Criteria
- ✅ CPU usage < 80% per pod
- ✅ Request latency p99 < 1s
- ✅ Error rate < 0.1%
- ✅ Request throughput maintained

#### Rollback
- Scale back down once root cause fixed: `kubectl scale deployment <service> --replicas=<original>`

---

### 8. Database Connection Pool Exhaustion
**Severity**: P0 | **MTTD**: < 30 sec | **MTTR**: < 2 min

#### Prerequisites
- Connection pool monitoring (alert at 80% utilization)
- Idle connection cleanup configured
- Query timeout configured

#### Procedure
1. **Detect connection exhaustion**
   ```bash
   # Check active connections
   kubectl exec postgres-0 -- psql -c \
     "SELECT count(*) as active_connections FROM pg_stat_activity;"
   # Should be < max_connections - 10

   # Monitor: grafana dashboard "Database Connections"
   ```

2. **Identify stuck connections**
   ```bash
   # Find long-running queries
   kubectl exec postgres-0 -- psql -c \
     "SELECT pid, usename, query, now() - query_start as duration
      FROM pg_stat_activity
      WHERE state = 'active'
      ORDER BY duration DESC
      LIMIT 10;"
   ```

3. **Kill idle/stuck connections**
   ```bash
   # Gracefully terminate idle connections
   kubectl exec postgres-0 -- psql -c \
     "SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE state = 'idle'
      AND query_start < NOW() - INTERVAL '5 minutes';"

   # Kill specific long query
   kubectl exec postgres-0 -- psql -c "SELECT pg_terminate_backend(<pid>);"
   ```

4. **Restart application connection pool**
   ```bash
   # Rolling restart to reset all connections
   kubectl rollout restart deployment/api-server

   # Monitor: kubectl rollout status deployment/api-server
   ```

5. **Verify pool health**
   ```bash
   # Check connection count drops
   watch 'kubectl exec postgres-0 -- psql -c "SELECT count(*) FROM pg_stat_activity;"'

   # Verify query latency normalizes
   curl -s prometheus:9090/api/v1/query?query=sql_query_latency_seconds | jq '.data.result'
   ```

#### Success Criteria
- ✅ Active connections < 50% of max
- ✅ Query latency p99 < 500ms
- ✅ No "connection pool exhausted" errors
- ✅ Application recovery time < 2 minutes

#### Rollback
- Restart continues until pool is normal

---

### 9. High Error Rate / Error Spike
**Severity**: P1 | **MTTD**: < 30 sec | **MTTR**: < 2 min

#### Prerequisites
- Error rate monitoring (alert at 0.5% baseline)
- Error tracking integration (Sentry, DataDog)
- Deployment history available

#### Procedure
1. **Identify error type**
   ```bash
   # Check application logs
   kubectl logs -f deployment/api-server --tail=100 | grep -E "ERROR|Exception"

   # Get error rate by endpoint
   curl -s 'prometheus:9090/api/v1/query' \
     --data-urlencode 'query=rate(http_requests_total{status=~"5.."}[5m]) by (endpoint)' | \
     jq '.data.result | sort_by(.value[1]) | reverse' | head -10
   ```

2. **Determine if deployment-related**
   ```bash
   # Check recent deployments
   kubectl rollout history deployment/api-server

   # Check if error correlates with recent change
   kubectl logs deployment/api-server | grep -A 5 -B 5 "ERROR" | head -20
   ```

3. **If recent deployment caused it: Rollback immediately**
   ```bash
   # Instant rollback (< 2 minutes)
   ./scripts/phase-19-instant-rollback.sh api-server previous

   # Monitor: kubectl get deployment/api-server -w
   ```

4. **If not deployment: Isolate affected service**
   ```bash
   # Disable affected feature via feature flag
   kubectl edit configmap feature-flags
   # Set problematic feature to enabled: false

   # Or isolate affected pods
   kubectl scale deployment/<affected-service> --replicas=0
   kubectl scale deployment/<backup-service> --replicas=5
   ```

5. **Monitor error rate recovery**
   ```bash
   # Error rate should drop within 60 seconds
   watch 'curl -s "prometheus:9090/api/v1/query" \
     --data-urlencode "query=rate(http_requests_total{status=~\"5..\"}[5m])" | \
     jq ".data.result[0].value[1]"'
   ```

#### Success Criteria
- ✅ Error rate drops to < 0.5% (baseline)
- ✅ Error recovery time < 2 minutes
- ✅ No cascading failures
- ✅ Users experience restored

#### Rollback
- Revert to previous working version

---

### 10. Slow Query Detection & Optimization
**Severity**: P2 | **MTTD**: < 1 min | **MTTR**: < 30 min

#### Prerequisites
- Query logging enabled (slow_query_log)
- Query performance monitoring (Prometheus)
- Index maintenance scheduled

#### Procedure
1. **Identify slow queries**
   ```bash
   # Check PostgreSQL slow query log
   kubectl exec postgres-0 -- tail -100 /var/log/postgresql/slow.log | \
     grep "Query Time" | sort -t ':' -k 2 -rn | head -10

   # Or from pg_stat_statements
   kubectl exec postgres-0 -- psql -c \
     "SELECT query, calls, total_time, mean_time
      FROM pg_stat_statements
      ORDER BY mean_time DESC
      LIMIT 10;"
   ```

2. **Analyze query execution plan**
   ```bash
   # Get EXPLAIN ANALYZE for slow query
   kubectl exec postgres-0 -- psql -c \
     "EXPLAIN ANALYZE SELECT ... FROM ..."

   # Look for "Sequential Scan" (bad) vs "Index Scan" (good)
   ```

3. **Create missing index** (if applicable)
   ```bash
   # Add index to frequently scanned columns
   kubectl exec postgres-0 -- psql -c \
     "CREATE INDEX CONCURRENTLY idx_<table>_<column>
      ON <table>(<column>);"

   # CONCURRENTLY allows continued operation
   ```

4. **Update query if possible**
   ```bash
   # Optimize application query
   # Example: Add WHERE clauses, pagination, selective columns

   # Verify with new execution plan
   kubectl exec postgres-0 -- psql -c "EXPLAIN ANALYZE <new-query>;"
   ```

5. **Monitor improvement**
   ```bash
   # Compare query latency before/after
   curl -s 'prometheus:9090/api/v1/query_range' \
     --data-urlencode 'query=sql_query_duration_seconds{query="<query_name>"}' \
     --data-urlencode 'start=<1h-ago>' | jq
   ```

#### Success Criteria
- ✅ Query latency improves by 50%+
- ✅ Database CPU usage decreases
- ✅ Request latency p99 improves
- ✅ No index bloat or maintenance needed within 7 days

#### Rollback
- Drop newly created indexes if they don't help

---

## SECURITY INCIDENTS

### 11. Unauthorized Access Attempt Detection & Response
**Severity**: P0 | **MTTD**: < 30 sec | **MTTR**: < 5 min

#### Prerequisites
- Authentication/authorization logging enabled
- RBAC policies enforced
- Audit trail configured
- Incident response team on call

#### Procedure
1. **Detect unauthorized access**
   ```bash
   # Check audit logs for failed auth
   kubectl logs -f audit-logger | grep "reason\":\"Forbidden" | tail -20

   # Monitor: grep "failed" /var/log/auth.log
   ```

2. **Immediately contain**
   ```bash
   # Revoke suspicious credentials/tokens
   kubectl delete secret <suspicious-token> -n <namespace>

   # Kill any active sessions
   kubectl logs -f audit-logger | grep "<user>" | grep "token:.*" | awk '{print $NF}' | \
     xargs -I {} kubectl delete secret {} -A
   ```

3. **Determine scope of access**
   ```bash
   # Find all actions taken with compromised account
   kubectl logs audit-logger | grep "user:\"<attacker>\"" | jq '.verb, .objectRef' | uniq

   # Check what resources were accessed
   # Check what was modified/deleted
   ```

4. **Secure affected systems**
   ```bash
   # If data accessed: Assume potential breach
   # If data modified: Initiate rollback procedure
   # If data deleted: Restore from backup

   # Rotate all credentials that might have been exposed
   ./scripts/phase-19-secret-management.sh
   ```

5. **Investigate root cause**
   ```bash
   # How was access obtained?
   # Was password weak? → Force password reset
   # Was token leaked? → Rotate JWT signing keys
   # Was compromised service? → Audit service code
   ```

6. **Notify stakeholders**
   ```
   Incident Communication Template:

   INCIDENT: Unauthorized access attempt
   SEVERITY: P0-Critical
   DETECTED: <timestamp>
   CONTAINED: <timestamp>
   SCOPE: <describe affected resources>
   ACTIONS TAKEN:
     - Revoked credentials
     - Killed sessions
     - Rotated secrets
   CUSTOMER IMPACT: <if any>
   ROOT CAUSE: <preliminary>
   NEXT STEPS: <investigation plan>
   ```

#### Success Criteria
- ✅ Access revoked within 1 minute
- ✅ No further unauthorized access
- ✅ All credentials rotated
- ✅ Incident documented
- ✅ Root cause found within 24 hours

---

### 12. Data Breach Response & Containment
**Severity**: P0 | **MTTD**: < 5 min | **MTTR**: < 1 hour

#### Prerequisites
- Data sensitivity classification
- Encrypted data at rest
- Encryption keys in secure key vault
- GDPR/HIPAA compliance team available

#### Procedure
1. **Confirm data breach**
   ```bash
   # Verify what data was accessed
   kubectl logs audit-logger | grep "data_exfiltration\|unauthorized_export"

   # Check database audit logs for bulk exports
   kubectl exec postgres-0 -- psql -c \
     "SELECT * FROM audit_log
      WHERE event_type = 'SELECT'
      AND rows_returned > 1000
      AND timestamp > NOW() - INTERVAL '1 hour';"
   ```

2. **Immediate containment**
   ```bash
   # Kill all external connections
   kubectl exec postgres-0 -- psql -c \
     "SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE usename != 'postgres';"

   # Take affected service offline
   kubectl scale deployment/api-server --replicas=0
   ```

3. **Inventory what was accessed**
   ```bash
   # Identify affected customers
   affected_customer_ids=$(
     kubectl exec postgres-0 -- psql -c \
       "SELECT DISTINCT customer_id FROM access_log
        WHERE accessed_at > <breach_time>
        AND action = 'export';"
   )

   echo "$affected_customer_ids" > /tmp/affected-customers.txt
   ```

4. **Rotate encryption keys** (if data was encrypted improperly)
   ```bash
   # If encryption key was compromised, rotate immediately
   ./scripts/phase-19-secret-management.sh --rotate-data-keys

   # Re-encrypt all databases with new keys
   # This may take hours - plan accordingly
   ```

5. **Regulatory notification** (GDPR/HIPAA)
   ```bash
   Template:

   GDPR Data Breach Notification:
   - Notify affected individuals within 72 hours
   - Notify regulatory authorities
   - Provide info on data protection measures we've taken
   - Provide info on breach investigation plan

   Required Info:
   - What data was breached (PII, email, passwords, etc.)
   - When was it discovered
   - What we're doing about it
   - What they should do
   - Contact info for follow-up
   ```

6. **Conduct post-breach analysis**
   ```bash
   Investigation:
   1. How was breach discovered?
   2. When did breach occur? (start time, end time)
   3. How was access obtained?
   4. What data categories were exposed?
   5. How many records/customers affected?
   6. Root cause?
   7. How to prevent recurrence?
   ```

#### Success Criteria
- ✅ Breach contained within 15 minutes
- ✅ Affected data identified
- ✅ Regulatory notifications sent
- ✅ Customers informed
- ✅ Root cause found within 24 hours
- ✅ Preventative measures implemented

---

### 13. DDoS Attack Mitigation
**Severity**: P0 | **MTTD**: < 1 min | **MTTR**: < 10 min

#### Prerequisites
- DDoS detection via traffic analytics
- Cloud DDoS protection (Cloudflare, AWS Shield)
- Rate limiting configured
- Incident response playbook

#### Procedure
1. **Detect DDoS attack**
   ```bash
   # Automatic detection: Request rate spike > 5x normal
   current_rate=$(curl -s 'prometheus:9090/api/v1/query' \
     --data-urlencode 'query=rate(http_requests_total[1m])' | \
     jq '.data.result[0].value[1] | tonumber')

   normal_rate=1000  # RPS
   if (( $(echo "$current_rate > $normal_rate * 5" | bc -l) )); then
     echo "DDoS DETECTED: $current_rate RPS (normal: $normal_rate)"
   fi
   ```

2. **Activate DDoS protection immediately**
   ```bash
   # Enable Cloud DDoS protection
   # AWS: Enable AWS Shield Advanced
   # GCP: Enable Cloud Armor
   # Cloudflare: Enable DDoS protection

   # Example: Cloudflare API
   curl -X POST "https://api.cloudflare.com/client/v4/zones/<zone-id>/security/events" \
     -H "X-Auth-Key: <key>" \
     -d '{"mitigations": ["enabled"]}'
   ```

3. **Implement rate limiting**
   ```bash
   # Kubernetes ingress rate limiting
   kubectl patch ingress nginx-ingress -p \
     '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/limit-rps":"100"}}}'

   # Application-level rate limiting by IP
   kubectl exec api-server-pod -- \
     /bin/sh -c 'echo "limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;" > /etc/nginx/conf.d/limit.conf'
   ```

4. **Block malicious IPs** (if identified)
   ```bash
   # Add WAF rules to block source IPs
   # Cloudflare example:
   curl -X POST "https://api.cloudflare.com/client/v4/zones/<zone>/firewall/rules" \
     --data '{"action":"block","expression":"(ip.src in {<attacker-ips>})"}'
   ```

5. **Scale up to handle attack traffic**
   ```bash
   # Auto-scale if not already at max
   kubectl patch hpa api-server -p '{"spec":{"maxReplicas":100}}'

   # Monitor: kubectl get hpa -w
   ```

6. **Monitor attack status**
   ```bash
   # Request rate should stabilize once mitigation active
   watch 'curl -s "prometheus:9090/api/v1/query" \
     --data-urlencode "query=rate(http_requests_total[1m])" | \
     jq ".data.result[0].value[1]"'

   # Monitor origin IP diversity
   curl -s 'prometheus:9090/api/v1/query' \
     --data-urlencode 'query=count(http_requests_total) by (origin_ip)' | \
     jq '.data.result | length'
   # If from few IPs = targeted attack
   ```

#### Success Criteria
- ✅ Attack identified within 1 minute
- ✅ Rate limiting active within 2 minutes
- ✅ Service latency remains < 500ms
- ✅ Legitimate traffic unaffected
- ✅ Attack traffic blocked by 80%+

#### Rollback
- Scaling continues until attack subsides

---

### 14. SSL/TLS Certificate Expiration Prevention
**Severity**: P1 | **MTTD**: < 1 day | **MTTR**: < 30 min

#### Prerequisites
- Certificate monitoring (alert 30 days before expiry)
- Let's Encrypt automatic renewal configured
- cert-manager installed in Kubernetes

#### Procedure
1. **Check certificate expiry**
   ```bash
   # List certificates and expiry dates
   kubectl get certificate -A -o custom-columns=NAME:.metadata.name,EXPIRY:.status.notAfter

   # Check specific certificate
   openssl s_client -connect api.example.com:443 2>/dev/null | \
     openssl x509 -noout -dates
   ```

2. **Renew certificate (automated)**
   ```bash
   # cert-manager automatically renews 30 days before expiry
   # Check status: kubectl describe certificate -n production

   # Manual renewal if automated fails
   kubectl delete secret tls-certificate -n production
   # cert-manager will auto-recreate with new cert
   ```

3. **Verify renewal**
   ```bash
   # Check certificate date was updated
   kubectl get secret tls-certificate -o jsonpath='{.data.tls\.crt}' | \
     base64 -d | \
     openssl x509 -noout -dates

   # Should show new expiry date 90 days from now
   ```

4. **Deploy renewed certificate**
   ```bash
   # Most ingress controllers auto-reload
   # If not, restart ingress controller
   kubectl rollout restart deployment/ingress-controller
   ```

5. **Test HTTPS connectivity**
   ```bash
   # Verify new certificate is served
   curl -v https://api.example.com 2>&1 | grep "subject="

   # SSL Labs test
   curl https://www.ssllabs.com/api/v3/analyze?host=api.example.com | jq '.grade'
   ```

#### Success Criteria
- ✅ Certificate renewed before expiry
- ✅ HTTPS connections working
- ✅ No certificate expiry warnings
- ✅ Certificate valid for next 90 days

---

## COMPLIANCE OPERATIONS

### 15. GDPR Data Deletion Request Processing
**Severity**: P2 | **MTTD**: < 24 hours | **MTTR**: < 30 min

#### Prerequisites
- Data tagging with customer_id
- Soft-delete capability
- Audit logging of deletions
- Legal approval process

#### Procedure
1. **Receive deletion request**
   ```
   From: customer@example.com
   Subject: GDPR Data Deletion Request

   Please delete all personal data associated with my account
   Account ID: customer_123
   Email: customer@example.com
   ```

2. **Verify request legitimacy**
   ```bash
   # Confirm customer email matches account
   kubectl exec postgres-0 -- psql -c \
     "SELECT email, account_created, last_login FROM customers
      WHERE id = 'customer_123';"

   # Verify request email matches
   ```

3. **Identify all data to delete**
   ```bash
   # Find all tables with customer_id
   kubectl exec postgres-0 -- psql -c \
     "SELECT tablename FROM pg_tables
      WHERE tablename LIKE '%customer%' OR tablename LIKE '%user%';"

   # Count records
   kubectl exec postgres-0 -- psql -c \
     "SELECT 'customers' as table_name, COUNT(*) as count FROM customers WHERE id = 'customer_123'
      UNION ALL
      SELECT 'orders', COUNT(*) FROM orders WHERE customer_id = 'customer_123'
      UNION ALL
      SELECT 'payments', COUNT(*) FROM payments WHERE customer_id = 'customer_123';"
   ```

4. **Perform deletion** (soft delete with backup)
   ```bash
   # Backup before deletion
   kubectl exec postgres-0 -- pg_dump \
     -U postgres -d app \
     -t customers -t orders -t payments | \
     gzip > /backup/customer_123_$(date +%s).sql.gz

   # Soft delete (mark as deleted)
   kubectl exec postgres-0 -- psql -c \
     "BEGIN;
      UPDATE customers SET deleted_at = NOW() WHERE id = 'customer_123';
      UPDATE orders SET deleted_at = NOW() WHERE customer_id = 'customer_123';
      UPDATE payments SET deleted_at = NOW() WHERE customer_id = 'customer_123';
      COMMIT;"

   # Audit log deletion
   echo "GDPR Request: Deleted customer_123 at $(date)" >> /var/log/compliance.log
   ```

5. **Verify deletion**
   ```bash
   # Confirm data is deleted from search results
   kubectl exec postgres-0 -- psql -c \
     "SELECT COUNT(*) FROM customers WHERE id = 'customer_123' AND deleted_at IS NULL;"
   # Should return 0
   ```

6. **Notify customer**
   ```
   Subject: Your Data Has Been Deleted

   Dear Customer,

   Your personal data has been deleted as requested.

   Deletion Details:
   - Request received: <date>
   - Deletion completed: <date>
   - Records deleted: <count>

   You can continue to use other services.

   Best regards,
   Privacy Team
   ```

#### Success Criteria
- ✅ Deletion completed within 30 days of request
- ✅ All customer data removed
- ✅ Deletion audited and logged
- ✅ Customer notified

---

### 16. SOC 2 Audit Preparation & Evidence Collection
**Severity**: P2 | **MTTD**: < 1 week | **MTTR**: < 1 hour (per request)

#### Prerequisites
- Audit logging enabled
- Access controls documented
- Incident response documentation
- Change management process

#### Procedure
1. **Collect access logs**
   ```bash
   # Export authentication logs (6 months)
   kubectl logs audit-logger --tail=999999 > /audit-logs/auth-$(date +%Y-%m).log

   # Users and access
   kubectl get events -A --sort-by='.metadata.creationTimestamp' > /audit-logs/events.log

   # Deployments and changes
   git log --format="%ai %an: %s" > /audit-logs/git-history.log
   ```

2. **Verify access controls**
   ```bash
   # Export RBAC policies
   kubectl get roles,rolebindings,clusterroles,clusterrolebindings -A -o yaml > \
     /audit-logs/rbac-policies.yaml

   # Verify least privilege
   # Each role should have minimal permissions
   ```

3. **Document incident response**
   ```bash
   # Collect incident logs from past 12 months
   ls -la /var/log/incidents/ | grep -E "202[5-6]" > /audit-logs/incidents-summary.log

   # MTTD/MTTR metrics
   grep "MTTD\|MTTR" /var/log/incidents/*.log > /audit-logs/incident-metrics.log
   ```

4. **Verify data integrity**
   ```bash
   # Database checksums
   kubectl exec postgres-0 -- psql -c \
     "SELECT blkno, checksum FROM pg_check_relation('customers', TRUE);" > \
     /audit-logs/data-integrity.log
   ```

5. **Generate evidenc summary**
   ```bash
   cat > /audit-logs/SOC2-EVIDENCE-SUMMARY.md <<'EOF'
   # SOC 2 Type II Evidence Summary

   ## CC (Common Criteria)

   ### CC1 - Security Objectives
   - Access controls implemented: ✅ (RBAC policies)
   - Change management process: ✅ (git + code review)
   - Monitoring in place: ✅ (Prometheus + Loki)

   ### CC2 - Communication of Responsibilities
   - Roles documented: ✅ (team handbook)
   - Responsibilities assigned: ✅ (on-call rotation)

   ### CC3-CC9 - Risk Management & Monitoring
   - Risk assessments conducted: ✅ (quarterly)
   - Incidents tracked: ✅ (incident logs)
   - Metrics monitored: ✅ (SLOs/SLIs)

   ## MTTD/MTTR Evidence
   - MTTD: Median 1 minute (alerting configured)
   - MTTR: Median 5 minutes (runbooks documented)

   ## Data Protection
   - Encryption at rest: ✅ (etcd, RDS)
   - Encryption in transit: ✅ (TLS 1.3)
   - Key management: ✅ (Vault)
   EOF
   ```

6. **Prepare for auditor interview**
   ```
   Auditor Questions Preparation:

   Q1: How do you manage access control?
   A: RBAC roles with least privilege, MFA for human access, service accounts for automation

   Q2: How do you detect security incidents?
   A: Continuous monitoring, alerting < 1min, audit logs retained 7 years

   Q3: Can you describe a recent incident?
   A: <Select actual incident from logs, describe detection, containment, resolution>

   Q4: How do you ensure data integrity?
   A: Backups tested weekly, checksums verified, replication monitoring

   Q5: How do you manage change?
   A: Git history, code review, automated testing, deployment validation
   ```

#### Success Criteria
- ✅ All evidence collected and organized
- ✅ Audit logs available for 12+ months
- ✅ MTTD/MTTR documented
- ✅ Auditor questions answered completely
- ✅ SOC 2 certification renewed/obtained

---

## COST OPTIMIZATION

### 17. Reserved Instance Purchase Planning
**Severity**: P3 | **MTTD**: < 1 day | **MTTR**: < 30 min

#### Prerequisites
- Cost tracking enabled
- Historical usage data (3+ months)
- Spending forecast available
- Budget approval process

#### Procedure
1. **Analyze current usage**
   ```bash
   # Get compute usage by instance type
   gcloud compute instances list --format="table(name,machineType)" | awk '{print $2}' | \
     sed 's|.*/||' | sort | uniq -c | sort -rn

   # Get usage hours (365 days * 24 hours)
   # Example: 5 x n1-standard-4 = 43,800 hours/year
   ```

2. **Calculate reserved instance savings**
   ```bash
   # On-demand cost (example)
   on_demand_cost_per_hour=0.1  # $0.10 per hour
   annual_hours=8760
   on_demand_annual=$((on_demand_cost_per_hour * annual_hours))  # $876/year

   # Reserved instance cost (example, 1-year commitment)
   reserved_cost=500  # $500 one-time
   reserved_annual_total=$((reserved_cost + (on_demand_cost_per_hour * 0.70 * annual_hours)))  # ~$656/year

   # Savings
   savings=$((on_demand_annual - reserved_annual_total))  # ~$220/year (25%)
   ```

3. **Purchase reserved instances**
   ```bash
   # AWS example
   aws ec2 purchase-reserved-instances --reserved-instances-offering-ids \
     12345678-1234-1234-1234-123456789012 --instance-count 5

   # GCP example
   gcloud compute commitments create my-commitment \
     --zone=us-central1-a \
     --resources=compute.googleapis.com/machines/n1-standard-4:5
   ```

4. **Monitor utilization**
   ```bash
   # Verify reserved instances are actually being used
   gcloud billing accounts list
   gcloud billing budgets list

   # Check Commitment Utilization
   gcloud compute commitments describe my-commitment --format="value(status,plan)"
   ```

#### Success Criteria
- ✅ Reserved instances reduce costs by 20-40%
- ✅ Utilization > 80%
- ✅ No unused reserved instances
- ✅ Savings tracked and reported

---

### 18. Spot Instance Migration for Non-Critical Workloads
**Severity**: P3 | **MTTD**: < 1 day | **MTTR**: < 30 min

#### Prerequisites
- Non-critical workloads identified
- Fault tolerance built in (pod disruption budgets)
- Cost savings modeling done

#### Procedure
1. **Identify suitable workloads**
   ```bash
   # Workloads suitable for spot instances:
   # - Batch processing
   # - Non-time-sensitive analytics
   # - Development/staging environments
   # - Stateless services with auto-recovery

   suitable_workloads=(
     "analytics-pipeline"
     "batch-processor"
     "staging-api"
     "cache-warmer"
   )
   ```

2. **Configure Kubernetes for spot instances**
   ```bash
   # Add spot instance node pool
   gcloud container node-pools create spot-pool \
     --cluster=production \
     --spot \
     --enable-autoscaling \
     --min-nodes=1 \
     --max-nodes=10

   # Label spot nodes
   kubectl label nodes -l cloud.google.com/gke-preemptible=true \
     node-type=spot
   ```

3. **Deploy pod disruption budget**
   ```yaml
   # Prevent too many pods evicted simultaneously
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: batch-processor-pdb
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: batch-processor
   ```

4. **Migrate workloads to spot**
   ```bash
   # Add node affinity preference for spot nodes
   kubectl patch deployment batch-processor -p '
   spec:
     template:
       spec:
         affinity:
           nodeAffinity:
             preferredDuringSchedulingIgnoredDuringExecution:
             - weight: 100
               preference:
                 matchExpressions:
                 - key: node-type
                   operator: In
                   values: [spot]
   '
   ```

5. **Monitor cost savings**
   ```bash
   # Compare on-demand vs spot costs
   on_demand=$(gcloud billing accounts describe <account> --format="value(displayName)" | \
     awk '/on-demand/{sum+=$NF} END {print sum}')

   spot=$(gcloud billing accounts describe <account> --format="value(displayName)" | \
     awk '/spot/{sum+=$NF} END {print sum}')

   savings=$((on_demand - spot))
   savings_percent=$((savings * 100 / on_demand))

   echo "Spot savings: \$$savings ($savings_percent%)"
   ```

#### Success Criteria
- ✅ 30-60% cost reduction for migrated workloads
- ✅ No service disruption
- ✅ Pod disruption budgets honored
- ✅ Quick recovery from interruptions (< 5 sec)

---

### 19. Storage Tiering & Lifecycle Policies
**Severity**: P3 | **MTTD**: < 1 day | **MTTR**: < 30 min

#### Prerequisites
- Storage usage analyzed
- Data access patterns identified
- Lifecycle policies defined

#### Procedure
1. **Analyze storage usage**
   ```bash
   # Check storage by age
   kubectl exec postgres-0 -- psql -c \
     "SELECT created_at, size_bytes
      FROM storage_usage
      WHERE created_at < NOW() - INTERVAL '30 days'
      GROUP BY DATE(created_at)
      ORDER BY created_at DESC;"
   ```

2. **Implement lifecycle policies**
   ```bash
   # S3/GCS example: Auto-transition old data to cheaper storage
   cat > lifecycle-policy.json <<'EOF'
   {
     "lifecycle": {
       "rule": [
         {
           "action": {"storageClass": "STANDARD"},
           "condition": {"age": 0}
         },
         {
           "action": {"storageClass": "NEARLINE"},
           "condition": {"age": 30}
         },
         {
           "action": {"storageClass": "COLDLINE"},
           "condition": {"age": 90}
         },
         {
           "action": {"type": "Delete"},
           "condition": {"age": 365}
         }
       ]
     }
   }
   EOF

   # Apply policy
   gsutil lifecycle set lifecycle-policy.json gs://my-bucket
   ```

3. **Monitor storage tiers**
   ```bash
   # Verify data movement
   gsutil du -s -h gs://my-bucket/

   # Check breakdown by storage class
   gsutil du -s -h -c -D gs://my-bucket/ | \
     awk '{print $NF}' | sort | uniq -c
   ```

#### Success Criteria
- ✅ 40-50% storage cost reduction
- ✅ Access latency acceptable for each tier
- ✅ No data loss during transitions

---

## REMAINING PROCEDURES
(Additional runbooks can be created for: Backup verification, HIPAA audit, PCI-DSS remediation, Feature rollout procedures, Performance optimization, etc.)

---

## QUICK REFERENCE TABLE

| Procedure | Severity | MTTD | MTTR | Prerequisites |
|-----------|----------|------|------|---------------|
| Node Failure | P0 | <1m | <15m | kubectl, auto-scaling |
| DB Failover | P0 | <30s | <2m | PostgreSQL replication |
| Cache Invalidation | P1 | <10s | <30s | Redis cluster, sentinel |
| Disk Space | P0 | <2m | <10m | Monitoring, cleanup tools |
| Network Partition | P0 | <1m | <5m | etcd quorum, monitoring |
| Memory Leak | P1 | <2m | <1m | Go pprof, pod limits |
| High CPU | P1 | <1m | <5m | HPA, monitoring |
| Connection Pool | P0 | <30s | <2m | PostgreSQL monitoring |
| Error Spike | P1 | <30s | <2m | Error tracking, deployment history |
| Slow Queries | P2 | <1m | <30m | Query logging, EXPLAIN |
| Unauthorized Access | P0 | <30s | <5m | Audit logging, RBAC |
| Data Breach | P0 | <5m | <1h | Data classification, encryption |
| DDoS Attack | P0 | <1m | <10m | DDoS protection, rate limiting |
| Certificate Expiry | P1 | <1d | <30m | cert-manager, monitoring |
| GDPR Deletion | P2 | <24h | <30m | Soft delete, audit logging |
| SOC 2 Audit | P2 | <1w | <1h | Audit logs, access controls |
| Reserved Instances | P3 | <1d | <30m | Cost analysis, billing |
| Spot Migration | P3 | <1d | <30m | Pod disruption budgets |
| Storage Tiering | P3 | <1d | <30m | Lifecycle policies |

---

## ESCALATION CONTACTS

**Critical (P0) Issues**:
- On-Call SRE: `+1-555-0100` (24/7 rotates)
- SRE Team Lead: `sretech@company.com`
- VP Engineering: `vpeng@company.com`

**High (P1) Issues**:
- SRE Team: `sretech@company.com`
- DevOps Lead: `devops@company.com`

**Medium (P2) Issues**:
- Team Slack: `#incidents`
- Response: < 4 hours during business hours

**Low (P3) Issues**:
- Team Slack: `#ops-backlog`
- Response: < 1 week

---

**Last Updated**: April 14, 2026
**Review Schedule**: Quarterly
**Owner**: DevOps + SRE Team
