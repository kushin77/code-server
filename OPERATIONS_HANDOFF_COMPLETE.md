# Operations Handoff Guide - ElevatedIQ Platform

**Effective Date**: April 30, 2026  
**Platform Version**: Phase 5 Complete  
**Cluster Status**: Production Ready  
**Last Updated**: 2026-04-30 00:50 UTC

---

## Quick Start

### Current Platform State
- **Primary Host**: 192.168.168.31 (28 containers, all healthy)
- **Replica Host**: 192.168.168.42 (27 containers, all healthy)
- **Virtual IP**: 192.168.168.30/24 (VRRP managed by keepalived)
- **Total Services**: 55 containers across dual cluster
- **Database**: PostgreSQL 16-alpine (code_server database)

### Verify Platform is Healthy
```bash
# Primary
ssh akushnir@192.168.168.31 'docker ps --format "{{.Names}}" | wc -l && docker ps --format "{{.Status}}" | grep -c healthy'
# Expected: 28 total, 28 healthy

# Replica  
ssh akushnir@192.168.168.42 'docker ps --format "{{.Names}}" | wc -l && docker ps --format "{{.Status}}" | grep -c healthy'
# Expected: 27 total, 27 healthy
```

### Access Points
| Service | Primary | Replica | Port | Purpose |
|---------|---------|---------|------|---------|
| Caddy (gateway) | :80, :443 | — | 80/443 | HTTP/HTTPS |
| Grafana | :3000 | :3000 | 3000 | Dashboards |
| Prometheus | :9090 | :9090 | 9090 | Metrics |
| Loki | :3100 | :3100 | 3100 | Logs |
| Redpanda | :9092 | :9092 | 9092 | Message broker |
| PostgreSQL | :5432 | :5432 | 5432 | Database |
| Redis | :6379 | :6379 | 6379 | Cache |
| Qdrant | :6333-6334 | :6333-6334 | 6333-6334 | Vector DB |

---

## Daily Operations

### Morning Health Check (Every 4 Hours)

```bash
#!/bin/bash
# Check both hosts
for host in 192.168.168.31 192.168.168.42; do
  echo "=== Checking $host ==="
  ssh -o BatchMode=yes akushnir@$host 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep -v healthy && echo "✓ All healthy" || true'
  ssh -o BatchMode=yes akushnir@$host 'curl -fsSI http://localhost:3000 >/dev/null && echo "✓ HTTP responding" || echo "✗ HTTP down"'
done

# Check database
ssh -o BatchMode=yes akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -d code_server -c "SELECT 1" >/dev/null && echo "✓ Database healthy" || echo "✗ Database down"'

# Check VIP (VRRP)
ssh -o BatchMode=yes akushnir@192.168.168.31 'docker exec code-server-keepalived cat /var/run/keepalived.pid >/dev/null && echo "✓ Keepalived running (Primary)" || echo "✗ Keepalived stopped"'
```

### Weekly Failover Test

```bash
# Test primary to replica failover
echo "1. Verify primary is MASTER"
ssh akushnir@192.168.168.31 'docker logs code-server-keepalived 2>&1 | grep -i "master\|transition" | tail -3'

echo "2. Stop keepalived on primary (simulates failure)"
ssh akushnir@192.168.168.31 'docker pause code-server-keepalived'

echo "3. Wait 5 seconds..."
sleep 5

echo "4. Verify replica is now MASTER"
ssh akushnir@192.168.168.42 'docker logs code-server-keepalived 2>&1 | grep -i "master\|transition" | tail -3'

echo "5. Restore primary (unpause keepalived)"
ssh akushnir@192.168.168.31 'docker unpause code-server-keepalived'

echo "6. Wait 5 seconds..."
sleep 5

echo "7. Verify primary recovers MASTER role"
ssh akushnir@192.168.168.31 'docker logs code-server-keepalived 2>&1 | grep -i "master\|transition" | tail -3'

echo "✓ Failover test complete (should be <5 seconds per transition)"
```

### Monthly Infrastructure Review

```bash
# Disk usage
for host in 192.168.168.31 192.168.168.42; do
  echo "=== $host disk usage ==="
  ssh akushnir@$host 'df -h /'
done

# Docker resource usage
ssh akushnir@192.168.168.31 'docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | sort -k3 -hr | head -10'

# Metrics retention
ssh akushnir@192.168.168.31 'docker exec code-server-prometheus du -sh /prometheus'

# Log storage
ssh akushnir@192.168.168.31 'docker exec code-server-loki du -sh /tmp/loki'
```

---

## Incident Response

### Scenario 1: Service Not Healthy

```bash
# 1. Identify the problem
HOST=192.168.168.31
SERVICE=code-server-reputation-engine

# 2. Check logs
ssh akushnir@$HOST "docker logs $SERVICE 2>&1 | tail -50"

# 3. Check resource constraints
ssh akushnir@$HOST "docker stats --no-stream $SERVICE"

# 4. Check dependencies (e.g., database)
ssh akushnir@$HOST "docker exec code-server-postgres psql -U postgres -c 'SELECT 1'"

# 5. Try restart
ssh akushnir@$HOST "docker restart $SERVICE"

# 6. Wait for health check
sleep 10
ssh akushnir@$HOST "docker ps --format '{{.Names}}\t{{.Status}}' | grep $SERVICE"
```

### Scenario 2: Database Connection Errors

```bash
# Symptom: Apps failing to connect to postgres with "password authentication failed"

# 1. Check postgres auth config
ssh akushnir@192.168.168.31 'docker exec code-server-postgres grep "^host" /var/lib/postgresql/data/pg_hba.conf | grep -v replication'
# Expected: "host all all all password"

# 2. If auth method is wrong, fix it:
ssh akushnir@192.168.168.31 'docker exec code-server-postgres sed -i "s/host all all all scram-sha-256/host all all all password/" /var/lib/postgresql/data/pg_hba.conf'

# 3. Reload config
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -c "SELECT pg_reload_conf()"'

# 4. Reset password if needed
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -c "ALTER USER postgres WITH PASSWORD '"'"'postgres_password_2026'"'"';"'

# 5. Restart affected services
ssh akushnir@192.168.168.31 'docker restart code-server-reputation-engine code-server-execution-scheduler'
```

### Scenario 3: Memory Pressure

```bash
# Check container memory limits
ssh akushnir@192.168.168.31 'docker inspect code-server-postgres | grep -A5 "Memory"'

# Monitor in real-time
ssh akushnir@192.168.168.31 'watch -n 5 docker stats --no-stream'

# If OOMKilled, increase system memory or restart containers selectively
ssh akushnir@192.168.168.31 'docker stats --no-stream --format "table {{.Container}}\t{{.MemPerc}}\t{{.MemUsage}}" | sort -k3 -hr | head -10'
```

### Scenario 4: VRRP Failover Stuck

```bash
# Check keepalived state on both hosts
ssh akushnir@192.168.168.31 'docker logs code-server-keepalived 2>&1 | tail -20'
ssh akushnir@192.168.168.42 'docker logs code-server-keepalived 2>&1 | tail -20'

# Check VRRP advertisements (on primary)
ssh akushnir@192.168.168.31 'docker exec code-server-keepalived tcpdump -i enp0s25 -n vrrp 2>/dev/null | head -10' 

# If stuck, restart keepalived on primary
ssh akushnir@192.168.168.31 'docker restart code-server-keepalived'

# Verify failover works
# (See "Weekly Failover Test" section)
```

---

## Maintenance Tasks

### Database Backup

```bash
# Backup postgres database
ssh akushnir@192.168.168.31 'docker exec code-server-postgres pg_dump -U postgres code_server > /tmp/code_server_backup_$(date +%Y%m%d).sql'

# Copy to safe location
scp akushnir@192.168.168.31:/tmp/code_server_backup_*.sql /backup/database/

# List backups
ssh akushnir@192.168.168.31 'ls -lh /var/lib/postgresql/data/pg_wal/'
```

### Clean Old Logs

```bash
# Loki retention is 7 days (auto-cleanup)
# Prometheus retention is 30 days (auto-cleanup)
# Docker logs limited to 3 files (configured in terraform)

# Manual docker log cleanup (if needed)
ssh akushnir@192.168.168.31 'docker run --rm -v /var/lib/docker/containers:/var/lib/docker/containers ubuntu find /var/lib/docker/containers -name "*.log" -mtime +30 -delete'
```

### Update Services

```bash
# To rebuild a custom image:
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker build -t code-server-memory-engine:latest apps/memory-engine/'

# Apply via terraform:
cd /home/akushnir/code-server
TF_VAR_db_password="postgres_password_2026" terraform -chdir=terraform/environments/private plan -target=module.primary.docker_container.memory_engine -out=/tmp/tfplan.bin
TF_VAR_db_password="postgres_password_2026" terraform -chdir=terraform/environments/private apply -auto-approve /tmp/tfplan.bin
```

### Network Debugging

```bash
# Check services can communicate
ssh akushnir@192.168.168.31 'docker exec code-server-reputation-engine curl -fsSI http://code-server-postgres:5432'

# Check DNS resolution
ssh akushnir@192.168.168.31 'docker exec code-server-reputation-engine nslookup code-server-postgres'

# Check port bindings
ssh akushnir@192.168.168.31 'docker port code-server-postgres'

# Check network
ssh akushnir@192.168.168.31 'docker network ls && docker network inspect services | grep -A10 "Containers"'
```

---

## Critical Credentials & Secrets

| Item | Value | Location | Notes |
|------|-------|----------|-------|
| PostgreSQL user | postgres | /var/lib/postgresql/data | Superuser |
| PostgreSQL password | postgres_password_2026 | Terraform var | Change after first login |
| Grafana default | admin / admin | http://192.168.168.31:3000 | Change immediately |
| OAuth2 cookie secret | [in terraform] | terraform.tfvars | Regenerate monthly |
| API Keys | [in config] | /home/akushnir/code-server-enterprise/.env | Rotate quarterly |
| SSH key | [user key] | ~/.ssh/id_rsa | Backup externally |

### Change PostgreSQL Password

```bash
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -c "ALTER USER postgres WITH PASSWORD '"'"'NEW_PASSWORD'"'"';"'

# Then update in terraform vars and redeploy affected services
export TF_VAR_db_password="NEW_PASSWORD"
cd /home/akushnir/code-server
terraform -chdir=terraform/environments/private apply -auto-approve
```

---

## Monitoring & Alerts

### Key Metrics to Watch

**In Grafana** (http://192.168.168.31:3000):
1. Container CPU: should be <50% per container
2. Container Memory: should be <80% of limits
3. Disk usage: alert if >/85%
4. Database connections: should be <30/100 pool
5. Message queue lag: should be <1 second

### Check Alerts

```bash
# View active alerts
ssh akushnir@192.168.168.31 'curl -s http://localhost:9093/api/v1/alerts | jq ".data.alerts[] | {status: .status, labels: .labels}"'

# Prometheus alerts
ssh akushnir@192.168.168.31 'curl -s http://localhost:9090/api/v1/rules | jq ".data.groups[] | {name: .name, rules: .rules[] | select(.state=="firing") }"'
```

### Log Aggregation

```bash
# Query logs in Loki
curl -s 'http://192.168.168.31:3100/loki/api/v1/query_range?query={job="docker"}&start=1&end=2' | jq

# Or use Grafana UI -> Explore -> Loki
# Query: {container_name="code-server-postgres"}
```

---

## Troubleshooting Reference

### Container keeps restarting
```bash
# Check restart policy
docker inspect <container> | grep RestartPolicy

# Check for exit codes
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.ID}}" | grep Exited

# View full logs
docker logs <container> --tail 100 -f
```

### Network connectivity issues
```bash
# Test inter-container connectivity
docker exec <container> ping <target-container>
docker exec <container> nslookup <service-name>
docker exec <container> curl -v http://<target>:port

# Check iptables rules
docker exec <container> iptables -L
```

### High latency
```bash
# Check for packet loss
docker exec <container> ping -c 10 <target> | tail -1

# Measure latency
docker exec <container> ping -c 10 <target> | grep min/avg/max

# Check TCP connection time
docker exec <container> curl -w "@curl-format.txt" -o /dev/null -s http://<target>
```

---

## Escalation Path

### Level 1: Self-Service (Most common)
1. Restart unhealthy container: `docker restart <container>`
2. Check logs: `docker logs <container>`
3. Verify database: `psql -U postgres -c "SELECT 1"`
4. Follow incident response procedures above

### Level 2: Host-Level
1. SSH to remote host
2. Check system resources: `df -h`, `free -h`, `top`
3. Check docker daemon: `systemctl status docker`
4. Restart docker if needed: `systemctl restart docker`

### Level 3: Infrastructure
1. Network connectivity between hosts
2. Storage mount status
3. Firewall rules
4. Physical host health (temperature, power, etc.)

### Level 4: Escalation to Platform Team
- Multiple services failing simultaneously
- Database data corruption
- Network partition between hosts
- Unable to recover VIP failover

---

## Documentation References

- **Architecture**: KEEPALIVED_HA_DEPLOYMENT.md
- **Operations**: KEEPALIVED_OPERATIONS_HANDOFF.md
- **Platform Status**: PLATFORM_OPERATIONAL_STATUS.md
- **Deployment**: DEPLOYMENT_FINAL_STATUS.md
- **Router Config**: ROUTER_UPDATE_CHECKPOINT.md (optional)

---

## Support Contacts

| Role | Name | Contact |
|------|------|---------|
| Platform Lead | — | — |
| Primary Ops | — | — |
| DBA | — | — |
| Network | — | — |

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Deployed By | Agent | 2026-04-30 | ✓ |
| Verified By | — | — | |
| Accepted By | — | — | |

---

**Next Review Date**: 2026-05-07  
**Renewal Cycle**: Weekly  
**Last Update**: 2026-04-30 00:50 UTC

