# Enterprise Observability Suite - SSOT
# P2 #429: Complete runbooks, dashboards, SLO monitoring
#
# PURPOSE: Operational runbooks for incident response
# All critical failure scenarios with resolution procedures
# SLO targets, dashboards, and escalation procedures

---
# ═════════════════════════════════════════════════════════════════════════════
# DATABASE PRIMARY DOWN - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: DatabasePrimaryDown
# Severity: P0 - CRITICAL
# Impact: Users cannot authenticate or persist data
# RTO: < 5 minutes
# On-Call: Database Team

DATABASE_PRIMARY_DOWN:
  summary: "PostgreSQL primary database is unreachable"
  
  detection:
    alert: DatabasePrimaryDown
    condition: "up{job=\"postgres\"} == 0 for 30s"
    dashboard: "https://grafana.kushnir.cloud/d/postgres-health"
  
  immediate_response:
    1. Acknowledge alert (PagerDuty)
    2. Check Patroni cluster status:
       $ patronictl list
       Expected: Primary unhealthy, Replica ready for promotion
    3. Verify network connectivity:
       $ ssh primary-host docker logs postgres
       Look for: Connection errors, disk space issues, OOM
    4. Check disk space on primary:
       $ ssh primary-host df -h | grep data
       If <10%: EMERGENCY - clear space immediately
  
  resolution_automatic:
    # Patroni auto-failover (< 60s)
    1. Patroni detects primary down (30s health check)
    2. etcd leader election: new primary elected
    3. Replica promoted to primary
    4. redis-sentinel triggers Redis failover
    5. Keepalived VIP reassigned to new primary
    
  resolution_manual:
    1. Force failover if auto-failover fails:
       $ patronictl failover --force
    2. Restart PostgreSQL container:
       $ docker-compose restart postgres
    3. Check recovery status:
       $ docker-compose logs postgres | tail -50
    4. Verify data integrity:
       $ docker-compose exec postgres psql -c "SELECT datname FROM pg_database"
    5. Monitor replication lag:
       $ docker-compose exec postgres psql -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag"
  
  post_resolution:
    1. Investigate root cause (disk? memory? network?)
    2. Fix underlying issue
    3. Restart failed primary:
       $ docker-compose up -d postgres
       # Will rejoin cluster as replica
    4. After 5 min of stability, consider failback
    5. Document incident in runbook
  
  escalation:
    3 min: No failover→ escalate to Infrastructure Lead
    5 min: Still down→ escalate to VP Engineering
    10 min: No restore→ activate disaster recovery

# ═════════════════════════════════════════════════════════════════════════════
# REPLICATION LAG CRITICAL - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: DatabaseReplicationLag
# Severity: P0
# Impact: Failover unsafe (data loss risk > 60 seconds)
# RTO: < 2 minutes (reduce lag)
# On-Call: Database Team

DATABASE_REPLICATION_LAG:
  summary: "PostgreSQL replication lag exceeds 60 seconds"
  
  detection:
    alert: DatabaseReplicationLag
    condition: "pg_replication_lag_seconds > 60 for 1m"
    dashboard: "https://grafana.kushnir.cloud/d/postgres-replication"
  
  immediate_response:
    1. Check replication status:
       $ docker-compose exec postgres psql -x -c "SELECT * FROM pg_stat_replication"
       Look for: reply_time lag, write/flush/replay LSN
    2. Identify slow query on primary:
       $ docker-compose exec postgres psql -c "SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5"
    3. Kill long-running query:
       $ docker-compose exec postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state != 'idle'"
    4. Check write rate:
       $ docker-compose exec postgres psql -c "SELECT writea || ' bytes/sec' FROM pg_stat_statements"
  
  resolution:
    1. Reduce write rate (scale down write-heavy apps)
    2. Optimize slow queries:
       - ANALYZE table
       - Rebuild indexes
       - Partition large tables
    3. Increase wal_sender_timeout:
       ALTER SYSTEM SET wal_sender_timeout = '10s'
    4. Monitor lag recovery:
       $ watch 'docker-compose exec postgres psql -c "SELECT now() - pg_last_xact_replay_timestamp()"'
    5. When lag < 10s: Resume normal operations
  
  prevention:
    - Monitor query performance continuously
    - Implement write rate limiting
    - Schedule maintenance during low-traffic windows
    - Use connection pooling (pgbouncer)

# ═════════════════════════════════════════════════════════════════════════════
# REDIS PRIMARY DOWN - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: RedisPrimaryDown
# Severity: P0
# Impact: Session loss, authentication cache miss
# RTO: < 1 minute

REDIS_PRIMARY_DOWN:
  summary: "Redis primary cache is unreachable"
  
  immediate_response:
    1. Check Redis status:
       $ docker-compose ps | grep redis
    2. Check Redis Sentinel status:
       $ redis-cli -p 26379 sentinel masters
       Expected: master_link_down: 0 (healthy)
    3. Sentinel auto-failover (< 30s):
       - Detects primary down
       - Promotes replica to primary
       - Updates sentinel configuration
    4. Monitor failover:
       $ watch 'redis-cli -p 26379 sentinel info'
  
  resolution_if_sentinel_fails:
    1. Manual promotion:
       $ docker-compose restart redis-replica
       $ redis-cli -p 6380 slaveof NO ONE  # Promote to master
       $ redis-cli -p 6380 config set masterauth $(cat .env | grep REDIS_PASSWORD)
    2. Point applications to new master (port 6380)
    3. Restart failed primary:
       $ docker-compose restart redis-primary
       # Will automatically join as replica
  
  post_recovery:
    1. Verify data consistency:
       $ redis-cli info replication  # Check master/slave status
    2. Monitor for 5 minutes
    3. Plan primary restart (during maintenance window)

# ═════════════════════════════════════════════════════════════════════════════
# OAUTH2-PROXY DOWN - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: OAuth2ProxyDown
# Severity: P0
# Impact: Users cannot authenticate - complete service unavailable
# RTO: < 2 minutes

OAUTH2_PROXY_DOWN:
  summary: "OAuth2 authentication gateway unreachable"
  
  immediate_response:
    1. Check oauth2-proxy health:
       $ curl http://localhost:4180/ping
       Expected: 200 OK
    2. Check logs:
       $ docker-compose logs oauth2-proxy --tail=100
    3. Restart oauth2-proxy:
       $ docker-compose restart oauth2-proxy
    4. Verify:
       $ curl -I https://code-server.kushnir.cloud/oauth2/start?rd=/
       Expected: 302 redirect to Google
  
  if_restart_fails:
    1. Check environment variables:
       $ docker-compose config | grep oauth2
       Verify: OAUTH2_PROXY_PROVIDER, CLIENT_ID, CLIENT_SECRET set
    2. Verify credentials in Vault:
       $ vault kv get secret/oauth2-proxy
    3. Rebuild container:
       $ docker-compose build --no-cache oauth2-proxy
       $ docker-compose up -d oauth2-proxy

# ═════════════════════════════════════════════════════════════════════════════
# CADDY DOWN - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: CaddyDown
# Severity: P0
# Impact: All HTTPS traffic blocked
# RTO: < 2 minutes

CADDY_DOWN:
  summary: "Caddy reverse proxy/TLS terminator is down"
  
  immediate_response:
    1. Check Caddy status:
       $ docker-compose ps caddy
    2. Check TLS handshake:
       $ openssl s_client -connect code-server.kushnir.cloud:443 -servername code-server.kushnir.cloud
    3. Restart Caddy:
       $ docker-compose restart caddy
    4. Verify TLS recovery:
       $ curl -Iv https://code-server.kushnir.cloud/healthz
  
  certificate_issues:
    1. Check certificate expiry:
       $ docker-compose exec caddy caddy list-certs
    2. If expired, force renewal:
       $ docker-compose exec caddy caddy reload  # Reload config
       # Caddy auto-renews via ACME
    3. Monitor renewal:
       $ docker-compose logs caddy | grep renewal

# ═════════════════════════════════════════════════════════════════════════════
# HIGH ERROR RATE - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: HighErrorRate
# Severity: P1
# Impact: ~{{ $value }}% of requests failing
# RTO: < 30 minutes

HIGH_ERROR_RATE:
  summary: "Application error rate exceeded threshold"
  
  diagnosis:
    1. Check error distribution:
       SELECT status, count(*) FROM access_logs WHERE timestamp > now()-5min GROUP BY status
    2. Check for specific error (HTTP status):
       - 500: Server error (app crash)
       - 503: Service unavailable (overload)
       - 502: Bad gateway (upstream timeout)
    3. Check application logs:
       $ docker-compose logs code-server --tail=500 | grep ERROR
    4. Check resource usage:
       $ docker stats code-server --no-stream
  
  resolution_5xx_errors:
    1. Check memory/CPU limits:
       $ docker inspect code-server | jq .[0].HostConfig.Memory
    2. If OOM: Increase memory limit
    3. If CPU throttled: Increase CPU limit
    4. Restart service:
       $ docker-compose restart code-server
    5. Monitor error rate (should drop to <0.1%)
  
  resolution_503_overload:
    1. Scale horizontally (add replicas)
    2. Implement rate limiting:
       $ curl -X PATCH http://kong:8001/services/code-server/rate-limiting
    3. Redirect traffic to replica
  
  resolution_502_gateway:
    1. Check upstream connectivity:
       $ curl http://code-server:8080/healthz
    2. Check network:
       $ docker exec caddy ping code-server
    3. Restart upstream service:
       $ docker-compose restart code-server

# ═════════════════════════════════════════════════════════════════════════════
# PROMETHEUS DOWN - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: PrometheusDown
# Severity: P1
# Impact: Metrics not collected - dashboards stale
# RTO: < 5 minutes

PROMETHEUS_DOWN:
  summary: "Prometheus monitoring system unreachable"
  
  impact: |
    - Dashboards show old data
    - New metrics not collected
    - Alerts based on missing metrics won't fire
    - Operational blind spot
  
  response:
    1. Check Prometheus status:
       $ curl http://prometheus:9090/-/healthy
    2. Check disk space (Prometheus uses disk for TSDB):
       $ df -h | grep prometheus
       If <10% free: cleanup old metrics
    3. Restart Prometheus:
       $ docker-compose restart prometheus
    4. Wait for startup (1-2 min):
       $ docker-compose logs prometheus | tail
    5. Verify:
       $ curl http://prometheus:9090/api/v1/query?query=up
  
  if_startup_fails:
    1. Check config:
       $ docker-compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
    2. Check TSDB corruption:
       $ docker-compose run prometheus promtool tsdb list /prometheus
    3. If corrupted, rebuild:
       $ docker-compose down prometheus
       $ rm -rf data/prometheus
       $ docker-compose up -d prometheus
       # Rebuilds TSDB from scratch

# ═════════════════════════════════════════════════════════════════════════════
# DISK SPACE LOW - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: DiskSpaceLow
# Severity: P2
# Impact: Services may fail when disk fills
# RTO: < 1 hour (cleanup/expansion)

DISK_SPACE_LOW:
  summary: "Disk space running low (< 10%)"
  
  response:
    1. Check disk usage:
       $ df -h
       $ du -sh /* | sort -h
    2. Identify largest directories:
       /var/lib/postgresql - database data
       /var/lib/code-server - user data
       /var/log - logs
    3. Cleanup options:
       - Clear old logs: $ journalctl --vacuum=100M
       - Clear old Prometheus data: $ rm -rf prometheus/wal/*
       - Clear Docker artifacts: $ docker system prune -a --volumes
    4. If cleanup insufficient:
       - Expand storage device
       - Move data to larger volume
    5. Monitor recovery:
       $ watch df -h

# ═════════════════════════════════════════════════════════════════════════════
# SLA/SLO VIOLATION - RUNBOOK
# ═════════════════════════════════════════════════════════════════════════════
# Alert: AvailabilitySLOViolation or LatencySLOViolation
# Severity: P1
# Impact: Customer SLA credit owed

SLA_VIOLATION:
  summary: "Service availability or latency below SLO target"
  
  slo_targets:
    availability: "99.99% uptime (< 50 min/month downtime)"
    latency_p99: "< 100ms (target: 100ms, alert if > 150ms)"
    error_rate: "< 0.1% errors"
  
  response:
    1. Calculate SLO violation:
       $ SELECT 1 - (success_requests / total_requests) as error_rate FROM metrics
       If error_rate > 0.001 (0.1%): SLO violated
    2. Identify root cause:
       - Database slow? (check replication lag)
       - Network congested? (check packet loss)
       - Application overloaded? (check memory/CPU)
    3. Implement quick fix:
       - Scale up replicas
       - Kill slow queries
       - Clear cache
    4. Implement lasting fix:
       - Optimize queries
       - Add caching
       - Implement rate limiting
    5. Document in incident report

# ═════════════════════════════════════════════════════════════════════════════
# ESCALATION PROCEDURES
# ═════════════════════════════════════════════════════════════════════════════

escalation_procedures:
  tier1_response:
    participants: "On-call engineer"
    time_limit: "15 minutes"
    actions: |
      - Acknowledge alert
      - Diagnose issue
      - Execute runbook
  
  tier2_escalation:
    trigger: "Tier 1 cannot resolve in 15 minutes"
    participants: "Team lead + on-call"
    time_limit: "30 minutes"
    actions: |
      - Involve team lead
      - Review incident impact
      - Consider failover/emergency measures
  
  tier3_escalation:
    trigger: "Tier 2 cannot resolve in 30 minutes"
    participants: "VP Engineering + CTO"
    time_limit: "5 minutes"
    actions: |
      - Declare incident
      - Brief stakeholders
      - Activate disaster recovery if needed

# ═════════════════════════════════════════════════════════════════════════════
# NOTES
# ═════════════════════════════════════════════════════════════════════════════
#
# All runbooks are:
# ✓ Linked from alert annotations (runbook URL)
# ✓ Accessible to on-call engineers (GitHub wiki)
# ✓ Version controlled (git history)
# ✓ Tested in chaos experiments
# ✓ Updated after each incident
#
# Incident Response SLA:
# - P0 (Critical): 15 min response, 1 hour resolution
# - P1 (High): 1 hour response, 4 hour resolution
# - P2 (Medium): 4 hour response, 24 hour resolution
#
# Post-Incident:
# 1. Conduct blameless postmortem
# 2. Update runbook with lessons learned
# 3. Add test case to prevent recurrence
# 4. Schedule follow-up action items
#
# Last Updated: 2026-04-15
# Version: 1.0 (Enterprise Observability SSOT)
