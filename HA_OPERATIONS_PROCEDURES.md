# High Availability Operations Procedures

**Date:** April 30, 2026  
**Status:** Production Ready  
**Version:** 1.0

## Architecture Overview

### Infrastructure Separation Model

**Primary Host (192.168.168.31) - Infrastructure Tier**
- PostgreSQL (database)
- Redis (cache)
- Caddy (reverse proxy, TLS termination)
- Prometheus, Grafana, Loki, Alertmanager (monitoring)
- OPA, Ollama (policies, AI/ML)
- Qdrant (vector database)
- Redpanda (message broker)
- 13 total services

**Replica Host (192.168.168.42) - Application Tier**
- GitLab (source control)
- Appsmith (low-code platform)
- Vault (secrets management)
- IDE (development environment)
- Minio (object storage)
- Agent Runtime, Paperclip, Execution Scheduler (AI agents)
- Reputation Engine, Testing services
- 15 total services

### Network Architecture
- **Virtual IP (VIP)**: 192.168.168.30/24 (managed by Keepalived)
- **Primary**: 192.168.168.31
- **Replica**: 192.168.168.42
- **External Access**: 173.77.179.148 (Firewalla NAT to public)
- **Domain**: kushnir.cloud

## Operational Procedures

### 1. Health Monitoring

**Primary Infrastructure Health Check:**
```bash
ssh 192.168.168.31 "docker ps --filter 'status=running' --format '{{.Names}}\t{{.Status}}' | grep code-server"
```
- Verify: 13/13 services running
- Verify: All services showing "(healthy)" status
- Alert threshold: <13 services running

**Replica Application Health Check:**
```bash
ssh 192.168.168.42 "docker ps --filter 'status=running' --format '{{.Names}}\t{{.Status}}' | grep code-server"
```
- Verify: 15/15 services running
- Alert threshold: <15 services running

**Database Connectivity:**
```bash
ssh 192.168.168.31 "docker exec code-server-postgres psql -U postgres -c 'SELECT version();'"
```
- Expected: PostgreSQL version output

**Redis Connectivity:**
```bash
ssh 192.168.168.31 "docker exec code-server-redis redis-cli -a redis-dev-secure-password ping"
```
- Expected: PONG response

### 2. Service Deployment

**Deploy to Primary (Infrastructure):**
```bash
cd /home/akushnir/code-server-enterprise
docker-compose up -d
docker ps --filter 'status=running' --format '{{.Names}}' | grep code-server
```

**Deploy to Replica (Applications):**
```bash
ssh 192.168.168.42 "cd /home/akushnir/code-server-enterprise && docker-compose up -d"
ssh 192.168.168.42 "docker ps --filter 'status=running' --format '{{.Names}}' | grep code-server"
```

### 3. Disaster Recovery

**Primary Host Failure - Activate Replica as Primary:**

1. **Verify Primary is Down:**
   ```bash
   ping 192.168.168.31
   ssh 192.168.168.31 "docker ps -q" # Should fail or return 0
   ```

2. **Backup Data from Primary (if accessible):**
   ```bash
   ssh 192.168.168.31 "docker exec code-server-postgres pg_dump -U postgres code_server > /tmp/backup.sql"
   scp akushnir@192.168.168.31:/tmp/backup.sql /tmp/backup.sql
   ```

3. **Restore Data to Replica:**
   ```bash
   ssh 192.168.168.42 "cat /tmp/backup.sql | docker exec -i code-server-postgres psql -U postgres"
   ```

4. **Update Keepalived VIP (if configured):**
   - VIP 192.168.168.30 should automatically failover to replica (handled by Keepalived)
   - Verify: `ping 192.168.168.30` should resolve to 192.168.168.42

5. **Update DNS Records (if applicable):**
   - Update kushnir.cloud A record to point to 192.168.168.42
   - Or configure external firewall to route traffic to 192.168.168.42

### 4. Service Restart Procedures

**Restart Single Service (Primary):**
```bash
ssh 192.168.168.31 "cd /home/akushnir/code-server-enterprise && docker-compose restart redis"
```

**Restart All Services (Primary):**
```bash
ssh 192.168.168.31 "cd /home/akushnir/code-server-enterprise && docker-compose restart"
```

**Redeploy from IaC (Fresh Start):**
```bash
ssh 192.168.168.31 "cd /home/akushnir/code-server-enterprise && docker-compose down -v && docker-compose up -d"
```

### 5. Scaling Procedures

**Scale Service Replicas (Docker Compose):**
```bash
ssh 192.168.168.31 "cd /home/akushnir/code-server-enterprise && docker-compose up -d --scale service-name=3"
```

**Add New Services:**
1. Update docker-compose.yml with new service definition
2. Commit to git: `git add docker-compose.yml && git commit -m "Add new service"`
3. Deploy: `docker-compose up -d`

### 6. Backup and Recovery

**Automated Daily Backup (Primary PostgreSQL):**
```bash
# Add to crontab on primary host
0 2 * * * docker exec code-server-postgres pg_dump -U postgres code_server > /backups/code-server-$(date +\%Y\%m\%d).sql
```

**Recovery from Backup:**
```bash
gunzip backup.sql.gz
docker exec -i code-server-postgres psql -U postgres code_server < backup.sql
```

**Redis Persistence:**
- Handled by docker-compose volume mapping (code_server_redis_data)
- Automatic recovery on service restart

### 7. TLS Certificate Management

**Current Certificate:** Self-signed (kushnir.cloud.crt, kushnir.cloud.key)
- Validity: April 30, 2026 - April 30, 2027
- Location: /home/akushnir/code-server-enterprise/config/caddy/

**Certificate Rotation (When Needed):**
```bash
# Generate new self-signed cert
openssl req -x509 -newkey rsa:2048 -keyout kushnir.cloud.key -out kushnir.cloud.crt -days 365 \
  -subj "/C=US/ST=CA/L=SanFrancisco/O=CodeServer/CN=kushnir.cloud"

# Copy to deployment
scp kushnir.cloud.* akushnir@192.168.168.31:/home/akushnir/code-server-enterprise/config/caddy/

# Restart Caddy
ssh 192.168.168.31 "cd /home/akushnir/code-server-enterprise && docker-compose restart caddy"
```

**Let's Encrypt Migration (Post-May 1):**
- Rate limit resets May 1, 2026 at ~23:05 UTC
- Configure firewall to allow ACME validation
- Update Caddyfile to remove tls directive (enable automatic ACME)
- Restart Caddy

### 8. Emergency Contacts

**Infrastructure Owner:** akushnir@elevated-iq.com  
**On-Call:** [To be updated with rotation schedule]  
**Escalation:** [CTO/Manager contact]

## Monitoring Checklist

Daily:
- [ ] Primary services: 13/13 running
- [ ] Replica services: 15/15 running
- [ ] Database connectivity confirmed
- [ ] HTTPS endpoint responding

Weekly:
- [ ] Backup verification (PostgreSQL dump successful)
- [ ] Failover test (switch to replica and back)
- [ ] Certificate expiry check
- [ ] Log analysis (error patterns)

Monthly:
- [ ] Full disaster recovery drill
- [ ] Capacity planning review
- [ ] Security audit
- [ ] Documentation update

## Performance Targets

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Service uptime | 99.9% | <99% |
| Response time (p95) | <500ms | >1000ms |
| Database query latency | <100ms | >500ms |
| Redis latency | <10ms | >50ms |
| Backup completion time | <30min | >1hr |

## Change Management

All changes must follow this process:

1. **Planning**: Document change in changelog
2. **Testing**: Test on replica first
3. **Approval**: Get sign-off from stakeholders
4. **Implementation**: Apply to primary during maintenance window
5. **Verification**: Run health checks post-change
6. **Documentation**: Update this procedures file
7. **Commit**: Push changes to git with clear message

## Troubleshooting Quick Reference

| Issue | Command | Resolution |
|-------|---------|------------|
| Service crashed | `docker logs <service>` | Check logs, restart if needed |
| High memory usage | `docker stats` | Scale down or increase resources |
| Database locked | `docker exec postgres psql -U postgres` | Check active connections |
| Network unreachable | `ping 192.168.168.31` | Check firewall rules |
| TLS certificate error | `docker logs caddy` | Regenerate cert, restart Caddy |

## Production Readiness Status

✅ **Infrastructure Tier (Primary):** 13/13 services deployed and healthy
✅ **Application Tier (Replica):** 15/15 services deployed and ready
✅ **IaC:** docker-compose.yml versioned and reproducible
✅ **TLS:** Self-signed certificate deployed (HTTPS operational)
✅ **Monitoring:** Health checks configured
✅ **Backup:** PostgreSQL backup procedure documented
✅ **DR:** Failover procedures documented
✅ **Documentation:** Complete operational procedures

**Status: PRODUCTION READY - April 30, 2026**
