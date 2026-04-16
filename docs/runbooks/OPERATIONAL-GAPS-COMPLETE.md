# Operational Gap Runbooks

## 1. Container Restart Loop

**Alert**: `ContainerRestartLoopDetected`  
**Severity**: WARNING (P2)  
**MTTD**: 5 minutes (automatic detection)  
**MTTR**: 10-30 minutes (depending on cause)

### Diagnosis

```bash
# Check container restart history
docker inspect <container_name> | grep -A 5 RestartCount

# Check recent logs
docker logs <container_name> --tail 100 | grep -i error

# Check resource usage
docker stats <container_name>

# Check docker events (real-time)
docker events --filter container=<container_name> --filter type=container
```

### Common Causes

1. **Application Crash**: Unhandled exception, segfault, assertion failure
   - Action: Check logs for exceptions, fix code, redeploy

2. **Resource Limits**: Memory/CPU limit exceeded
   - Check: `docker inspect` limits
   - Fix: Increase limits or optimize application

3. **Missing Dependencies**: Database not ready, services not accessible
   - Check: Network connectivity, service health
   - Fix: Ensure dependencies start first, add health checks, increase startup timeout

4. **Configuration Error**: Invalid config file, missing credentials
   - Check: Environment variables, config files
   - Fix: Validate config, add validation to entrypoint

5. **Health Check Failure**: Health check returns non-zero
   - Check: `docker inspect` healthcheck config
   - Fix: Adjust health check timeout/interval, or fix actual health issue

### Remediation Steps

#### Immediate (Stop the Loop)

```bash
# Stop container temporarily
docker stop <container_name>

# Check logs while stopped
docker logs <container_name> --since 5m

# Increase restart delay
docker update --restart-policy unless-stopped <container_name>

# Scale down to 0 replicas (Kubernetes)
kubectl scale deployment <deployment> --replicas 0
```

#### Investigation

```bash
# Run with debug logging
docker run -e DEBUG=1 <image_id>

# Run without entrypoint for inspection
docker run -it --entrypoint /bin/bash <image_id>

# Check disk space (full disk can cause crashes)
df -h

# Check system logs
journalctl -u docker -n 50
```

#### Fix

```bash
# For code bugs:
1. Fix code in repository
2. Build new image: docker build -t <image>:<tag> .
3. Push: docker push <image>:<tag>
4. Redeploy: docker-compose up -d <service>

# For config issues:
1. Update .env or config files
2. Validate config: docker run <image> --validate-config
3. Restart: docker restart <container_name>

# For resource limits:
1. Edit docker-compose.yml or Kubernetes manifest
2. Increase limits, redeploy
3. Add HPA (horizontal pod autoscaler) if needed
```

#### Verification

```bash
# Monitor restart count
watch -n 5 'docker inspect <container> | grep RestartCount'

# Should stabilize (no new restarts for 10+ minutes)
# Or: restartCount doesn't increase

# Check logs for clean startup
docker logs <container> --tail 20
# Should end with: "Server started successfully" or similar
```

### Alert Response SLA

- **Page On-Call**: Yes (if production)
- **Response Time**: 15 minutes
- **Resolution**: 1 hour
- **Escalation**: After 30 min without resolution, escalate to on-call engineer

### Prevention

1. **Add health checks** to all services
2. **Increase startup timeout** for slow services
3. **Add resource requests/limits** to prevent OOM kills
4. **Test config changes** before deploying
5. **Add structured logging** to catch errors earlier
6. **Monitor application-level errors** (separate alert for app exceptions)

---

## 2. Disk I/O Saturation

**Alert**: `DiskIOSaturation` / `DiskIOSaturationCritical`  
**Severity**: WARNING (P2) → CRITICAL (P1)  
**MTTD**: 5 minutes  
**MTTR**: 30-60 minutes

### Diagnosis

```bash
# Real-time I/O usage
iostat -x 1 10

# Per-process I/O
iotop -o -b -n 3

# Disk bandwidth
dstat -d

# Check for slow queries (database)
sudo tail -f /var/log/postgresql/postgresql.log | grep duration

# Check Prometheus metrics
curl http://localhost:9090/api/v1/query?query=node_disk_io_time_seconds_total
```

### Common Causes

1. **Slow Database Queries**: Full table scans, missing indexes
   - Check: EXPLAIN ANALYZE on slow queries
   - Fix: Add indexes, optimize query, increase work_mem

2. **Large Data Transfers**: Backup, replication, logs
   - Check: docker logs, pg_wal directory size
   - Fix: Move to off-peak, compress, use throttling

3. **Memory-Pressure Swap**: System swapping to disk (OOM)
   - Check: `free -h | grep Swap`
   - Fix: Increase RAM, reduce memory usage, kill memory hogs

4. **Unoptimized Application Code**: Inefficient data access patterns
   - Check: Application profiling, database metrics
   - Fix: Code optimization, caching, batching

5. **Disk Controller/Hardware Issue**: Bad sectors, controller lag
   - Check: SMART data, kernel logs for I/O errors
   - Fix: Replace disk, upgrade controller

### Remediation Steps

#### Immediate

```bash
# Stop heavy I/O processes (temporarily)
# WARNING: Only if you understand the impact!
docker pause <heavy_container>

# Monitor improvement
watch -n 2 'iostat -x 1 1 | grep sda'

# Identify heavy process
iotop -o -b -n 1 | head -10
```

#### Investigation

```bash
# Database slow queries (PostgreSQL)
psql -U postgres -d postgres
SELECT query, calls, mean_time FROM pg_stat_statements 
WHERE mean_time > 1000 ORDER BY mean_time DESC LIMIT 10;

# Check index usage
SELECT schemaname, tablename, indexname FROM pg_stat_user_indexes 
WHERE idx_scan = 0;  -- Unused indexes

# Check WAL archiving delay
ps aux | grep archive
ls -lh /var/lib/postgresql/*/main/pg_wal/ | head -20
```

#### Fix

```bash
# For slow queries:
1. Add missing indexes: CREATE INDEX idx_name ON table(column);
2. Analyze table: ANALYZE table_name;
3. Update statistics: VACUUM ANALYZE;

# For memory pressure/swap:
1. Identify OOM candidates: docker stats --no-stream | sort -k 4 -hr
2. Increase memory limits
3. Kill or restart memory leaker

# For large data transfers:
1. Throttle backup: pg_dump | pv -L 10M | gzip > backup.gz
2. Configure replication delay: max_wal_senders, max_replication_slots
3. Move logs off critical disk
```

#### Verification

```bash
# Monitor I/O over 10+ minutes
iostat -x 300 1 sda | tail -1

# Should show <80% utilization
# Or: Read/write latency <5ms

# Check alert clears
curl http://localhost:9090/api/v1/query?query=DiskIOSaturation
# Should return: value: [] (empty, no alert firing)
```

### Prevention

1. Add Prometheus recording rules for query latency percentiles
2. Monitor index usage and add missing indexes proactively
3. Configure Postgres `autovacuum` aggressively for large tables
4. Implement query result caching (Redis)
5. Use connection pooling to limit concurrent queries
6. Regular backup testing to find slow queries

---

## 3. Memory Pressure / OOM Risk

**Alert**: `MemoryPressureHigh` / `MemoryPressureCritical`  
**Severity**: WARNING (P2) → CRITICAL (P1)  
**MTTD**: 5 minutes  
**MTTR**: 10-20 minutes

### Diagnosis

```bash
# Real-time memory usage
free -h

# Per-process memory
ps aux --sort=-%mem | head -10

# Memory statistics
cat /proc/meminfo

# Docker container memory
docker stats --no-stream | sort -k 4 -hr

# Kubernetes pod memory
kubectl top pods --all-namespaces | sort -k 3 -hr
```

### Common Causes

1. **Memory Leak**: Application holding memory, not releasing
   - Check: docker logs for leak patterns
   - Fix: Upgrade package, patch code, add memory limits (will restart)

2. **Cache Growing**: Unbound cache, no eviction
   - Check: application config, cache settings
   - Fix: Add cache size limits, TTLs, or LRU eviction

3. **Connection Accumulation**: Too many open connections
   - Check: pg_stat_activity, netstat
   - Fix: Increase connection timeout, kill idle connections

4. **Inefficient Queries**: Loading large datasets into memory
   - Check: EXPLAIN, slow query log
   - Fix: Pagination, streaming, filtering

5. **Resource Limit Too Low**: Container limit < actual need
   - Check: docker inspect memory limit
   - Fix: Increase limit, or optimize app

### Remediation Steps

#### Immediate (MemoryPressureHigh - P2)

```bash
# Monitor without action (warning level)
watch -n 5 'free -h'

# Identify memory hogs
docker stats --no-stream | sort -k 4 -hr

# Kill non-essential containers
docker stop <non-critical-service>

# Trigger garbage collection (if supported)
# Java: curl localhost:9999/admin/gc
# Node: --expose-gc and trigger externally
```

#### Critical (MemoryPressureCritical - P1)

```bash
# IMMEDIATE ACTION REQUIRED

# Kill the largest memory consumer (if not critical)
docker kill <memory_hog>

# Or: Restart the service (triggers GC + memory reallocation)
docker restart <service>

# Scale down if in Kubernetes
kubectl scale deployment <deployment> --replicas 1

# Emergency failover to replica (if HA setup)
# Manually trigger failover procedure
```

#### Investigation

```bash
# Find leak signature (Java)
jmap -histo:live <pid> | head -20

# Find leak signature (Python)
objgraph.show_growth()

# Check for zombie processes (not releasing memory)
ps aux | grep -v awk | grep '<defunct>'

# Check memory fragmentation
cat /proc/meminfo | grep -E 'Slab|Cache'
```

#### Fix

```bash
# Update application (fix memory leak)
docker build -t app:v2 .
docker-compose up -d --force-recreate

# Configure memory limits properly
docker update --memory 2g <container_name>

# Add memory monitoring/alerting
# Prometheus: container_memory_usage_bytes, memory leak detector

# Implement graceful shutdown
# Allow in-flight requests to complete before OOMkill
```

#### Verification

```bash
# Monitor continuously over 1 hour
watch -n 60 'free -h'

# Should stabilize (not constantly increasing)
# Available memory > 15% (warning threshold)

# Check container restart count (should not increase)
docker inspect <container> | grep RestartCount
```

### Prevention

1. Set appropriate memory limits for all containers
2. Implement memory usage baselines and alerting
3. Use memory profilers during load testing
4. Enable kernel memory accounting (CONFIG_MEMCG)
5. Configure swap appropriately (or disable)
6. Regular restarts of services with leaks (temporary until fixed)
7. Use `cgroups` memory limits to prevent system-wide OOM

---

## 4. Network Saturation

**Alert**: `NetworkSaturation` / `NetworkSaturationCritical`  
**Severity**: WARNING (P2) → CRITICAL (P1)  
**MTTD**: 5 minutes  
**MTTR**: 30-60 minutes

### Diagnosis

```bash
# Real-time bandwidth
bwm-ng -o csv 1

# Per-interface stats
ifstat -i eth0 -z

# Per-process network
nethogs

# Active connections
netstat -tlnp | grep ESTABLISHED | wc -l

# Prometheus metrics
curl 'http://localhost:9090/api/v1/query?query=rate(node_network_transmit_bytes_total[5m])'
```

### Common Causes

1. **DDoS Attack**: High packet rate from random sources
   - Check: `ddos-detect.sh` or rate-limit metrics
   - Fix: Activate DDoS mitigation (Cloudflare, WAF rules)

2. **Large Data Transfer**: Backup, export, replication
   - Check: `nethogs` shows backup process
   - Fix: Schedule for off-peak, throttle, compress

3. **Inefficient Queries**: Returning huge datasets
   - Check: slow query log, network packet sizes
   - Fix: Pagination, filtering, select only needed columns

4. **Bandwidth Limit Reached**: Actual capacity ceiling
   - Check: NIC specs, ISP plan
   - Fix: Upgrade link, add redundancy, implement QoS

5. **Network Loop**: Spanning tree issues, port flapping
   - Check: switch logs, show flapping ports
   - Fix: Disable bridging loop, check cable connections

### Remediation Steps

#### Immediate

```bash
# Check if DDoS
curl -s http://localhost:8080/metrics | grep -i 'request.*rate'

# If suspected DDoS:
# 1. Enable WAF rules (if using Cloudflare/AWS WAF)
# 2. Fail over to DDoS mitigation service
# 3. Block suspicious IPs at firewall

# Identify data transfer source
nethogs -p | head -20

# Rate limit if needed
tc qdisc add dev eth0 root tbf rate 100mbit burst 32kbit latency 400ms
```

#### Investigation

```bash
# Check for DDoS patterns
tcpdump -i eth0 -c 1000 | sort | uniq -c | sort -rn | head -20

# Analyze packet destinations
netstat -tnp | awk '{print $5}' | sort | uniq -c | sort -rn | head -10

# Check for SYN flood
netstat -tn | grep SYN_RECV | wc -l

# Monitor TCP states
watch -n 1 'netstat -tn | awk "/tcp/ {print $6}" | sort | uniq -c'
```

#### Fix

```bash
# For DDoS:
# Activate DDoS protection:
# - Cloudflare: Enable "Under Attack" mode
# - AWS WAF: Increase rate limiting
# - iptables: Block attacker IPs

# For large transfers:
# 1. Throttle to off-peak hours
# 2. Compress data before transfer
# 3. Use incremental transfers instead of full

# For capacity issues:
# 1. Upgrade network link (from ISP)
# 2. Add bonded/teamed interfaces for redundancy
# 3. Implement load balancing (split traffic)

# For network loops:
# Check switch spanning tree
# Disable bad port or loop prevention
```

#### Verification

```bash
# Monitor bandwidth for 1 hour
bwm-ng -o csv 300 5

# Should drop back to normal (after fix)
# Peak < 80% of capacity

# Check DDoS cleared (if was attack)
curl http://localhost:9090/api/v1/query?query=NetworkSaturation
# Should return empty (no alert)
```

### Prevention

1. Enable Cloudflare DDoS protection
2. Implement rate limiting at application level
3. Use CDN for large static content
4. Monitor bandwidth baseline and set thresholds
5. Configure QoS for critical traffic
6. Implement circuit breakers for external calls
7. Monitor top talkers weekly

---

## 5. PostgreSQL Connection Pool Exhaustion

**Alert**: `PostgreSQLConnectionPoolNearExhaustion` / `PostgreSQLConnectionPoolExhausted`  
**Severity**: WARNING (P2) → CRITICAL (P1)  
**MTTD**: 5 minutes  
**MTTR**: 5-15 minutes

### Diagnosis

```bash
# Current connections
psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Max connections
psql -U postgres -c "SHOW max_connections;"

# Connections by state
psql -U postgres -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"

# Idle connections
psql -U postgres -c "SELECT pid, usename, state, query_start FROM pg_stat_activity WHERE state = 'idle';"

# Prometheus query
curl 'http://localhost:9090/api/v1/query?query=pg_stat_activity_count'
```

### Common Causes

1. **Connection Leak**: Application not closing connections
   - Check: Long-running idle connections
   - Fix: Add connection timeouts, fix app code

2. **Connection Pool Size Too Small**: Need > current max_connections
   - Check: app config connection pool size
   - Fix: Increase pool size, increase max_connections

3. **Slow Queries**: Long-running queries hold connections
   - Check: pg_stat_statements, query duration
   - Fix: Optimize queries, add indexes

4. **Too Many Clients**: More applications connecting than expected
   - Check: which apps are connecting
   - Fix: Reduce client count, use connection pooler (PgBouncer)

5. **Connections Not Released on Error**: Error handling doesn't close connections
   - Check: application error logs
   - Fix: Ensure try/finally or using statements

### Remediation Steps

#### Immediate (P2)

```bash
# Kill idle connections (safe)
psql -U postgres << EOF
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE state = 'idle' 
AND state_change < now() - interval '10 minutes';
EOF

# Check remaining
psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"
```

#### Critical (P1)

```bash
# Kill all non-critical connections
psql -U postgres << EOF
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE usename != 'postgres' 
AND pid <> pg_backend_pid();
EOF

# Or: Disable new connections temporarily
ALTER DATABASE production CONNECTION LIMIT 10;

# Restart application service (will reestablish)
docker restart <app_service>
```

#### Investigation

```bash
# Find connection leaker (which app/user)
psql -U postgres -c "SELECT datname, usename, count(*) FROM pg_stat_activity GROUP BY datname, usename;"

# Long-running queries holding connections
psql -U postgres -c "SELECT pid, usename, query_start, query FROM pg_stat_activity WHERE query_start < now() - interval '5 minutes';"

# Per-application conn usage
docker ps | awk '{print $NF}' | xargs -I {} docker logs {} --tail 20 | grep -i connect
```

#### Fix

```bash
# Increase PostgreSQL max_connections (requires restart)
# Edit postgresql.conf:
max_connections = 300

# Restart PostgreSQL
docker restart postgres

# Deploy connection pooler (PgBouncer)
# Sits between app and database, multiplexes connections

# Fix application connection leaks
# Ensure all connections are closed in finally blocks:
try:
    conn = psycopg2.connect(...)
    # use conn
finally:
    conn.close()  # CRITICAL

# Or use context manager:
with psycopg2.connect(...) as conn:
    # use conn
    # automatically closed
```

#### Verification

```bash
# Monitor connection count
watch -n 5 'psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"'

# Should drop back below 50% of max
# No more "too many connections" errors in app logs

# Check alert clears
curl http://localhost:9090/api/v1/query?query=PostgreSQLConnectionPoolExhausted
# Should return empty
```

### Prevention

1. Implement connection pooling (PgBouncer, pgpool)
2. Set connection timeout in application (idle connections auto-close)
3. Monitor connection usage trends (add to dashboard)
4. Load test to find connection pool size needed
5. Add alerts for connection pool > 50%
6. Use pg_stat_statements to find slow queries regularly
7. Code review to catch connection leaks

---

## 6. TLS/SSL Certificate Expiry

**Alert**: `CertificateExpiryWarning` / `CertificateExpiryCritical` / `CertificateExpired`  
**Severity**: WARNING (P2) → CRITICAL (P1)  
**MTTD**: Automatic (daily check)  
**MTTR**: 5-30 minutes

### Diagnosis

```bash
# Check certificate expiry (OpenSSL)
openssl s_client -connect code-server.example.com:443 -showcerts < /dev/null | \
  openssl x509 -text | grep -A 1 "Not After"

# Check all certificates
openssl x509 -in /etc/letsencrypt/live/*/cert.pem -text -noout | grep -A 1 "Not After"

# Check cert in Kubernetes secret
kubectl get secret tls-cert -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -text | grep -A 1 "Not After"

# Prometheus metric
curl 'http://localhost:9090/api/v1/query?query=certmanager_certificate_expiration_timestamp_seconds'
```

### Common Causes

1. **Renewal Failed**: Let's Encrypt renewal process failed
   - Check: cert-manager logs, Certbot logs
   - Fix: Manual renewal, check DNS, check file permissions

2. **Old Certificate**: Not using cert-manager, manual renewal needed
   - Check: certificate issue date
   - Fix: Implement cert-manager for automatic renewal

3. **Cert Manager Down**: cert-manager pod not running
   - Check: kubectl get pods -n cert-manager
   - Fix: Restart cert-manager

4. **Wrong Domain**: Certificate for different domain
   - Check: Certificate CN and SANs
   - Fix: Order new certificate, update ingress

5. **Clock Skew**: System time is wrong, looks expired
   - Check: `date`, `timedatectl status`
   - Fix: Sync system time (ntpd/systemd-timesyncd)

### Remediation Steps

#### Immediate (P2 - Expiring in 30+ days)

```bash
# Verify cert details
openssl s_client -connect code-server.example.com:443 < /dev/null | \
  openssl x509 -text

# Check renewal status
cert-manager logs: kubectl logs -n cert-manager cert-manager-* -f

# Manual renewal (Certbot)
certbot renew --cert-name code-server --force-renewal
```

#### Critical (P1 - Expiring in <7 days)

```bash
# IMMEDIATE RENEWAL REQUIRED

# Check cert-manager
kubectl describe certificate code-server -n default

# Force cert-manager renewal
kubectl annotate certificate code-server \
  certmanager.k8s.io/issue-temporary-certificate=true \
  --overwrite -n default

# Or manual renewal (fastest)
certbot certonly --standalone -d code-server.example.com --force-renewal
sudo systemctl reload nginx  # or caddy/apache

# Verify new cert is loaded
openssl s_client -connect code-server.example.com:443 < /dev/null | \
  openssl x509 -text | grep "Not After"
```

#### Investigation (If renewal failed)

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail 100

# Check issuer status
kubectl describe issuer letsencrypt-prod -n default

# Check DNS challenge
kubectl describe challenge <challenge-name> -n default

# Check Certbot logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Test DNS
dig code-server.example.com @8.8.8.8

# Test ACME challenge
curl http://code-server.example.com/.well-known/acme-challenge/
```

#### Fix

```bash
# Fix DNS (if ACME DNS01 challenge failed)
1. Verify DNS records: dig code-server.example.com
2. Wait for DNS propagation: 10-30 minutes
3. Retry renewal

# Fix file permissions (if renewal failed)
sudo chown -R certbot:certbot /etc/letsencrypt/
sudo chmod -R 755 /etc/letsencrypt/

# Fix clock skew
sudo timedatectl set-ntp true
sudo ntpq -p  # verify

# Rollback to manual cert if cert-manager is broken
certbot certonly --standalone ...
Deploy cert in Kubernetes secret manually

# Implement automatic renewal
# - Ensure cert-manager is running
# - Ensure letsencrypt ClusterIssuer configured
# - Set renewBefore: 30 days in Certificate resource
```

#### Verification

```bash
# Check new certificate is active
openssl s_client -connect code-server.example.com:443 < /dev/null | \
  openssl x509 -text | grep -E "Not After|Subject:"

# Monitor renewals in logs
tail -f /var/log/letsencrypt/letsencrypt.log

# Check alert clears
curl http://localhost:9090/api/v1/query?query=CertificateExpiryCritical
# Should return empty

# Confirm in browser (no warnings)
curl -v https://code-server.example.com/ 2>&1 | grep -i certificate
```

### Prevention

1. **Implement cert-manager** (automatic renewal)
2. **Set renewBefore: 30 days** in Certificate resource
3. **Monitor certificate expiry** with Prometheus alerts (this runbook)
4. **Test renewal procedure** monthly (practice RTO/RPO)
5. **Calendar reminder** 60 days before expiry (backup)
6. **Staging environment test** before production renewal
7. **DNS validation** (DNS01) instead of HTTP validation (HTTP01) for reliability

### Production Readiness Checklist

- [x] Alerts configured (warning at 30d, critical at 7d, fired at 0d)
- [x] Runbooks documented (this document)
- [x] Automated renewal (cert-manager)
- [x] Manual renewal procedure tested
- [x] On-call can execute renewal in <5 minutes
- [x] Communication plan (notify users if emergency renewal needed)
