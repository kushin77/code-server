# Cluster Deployment & Migration Guide

## Quick Start - New Cluster with Standard Naming

### One-Time Setup (Assumes clean deployment)

```bash
cd /home/akushnir/code-server

# 1. Sync updated files to Replica 1
scp docker-compose-cluster.yml akushnir@192.168.168.31:~/code-server-enterprise/docker-compose.yml
scp .env.cluster akushnir@192.168.168.31:~/code-server-enterprise/.env

# 2. Sync updated files to Replica 2  
scp docker-compose-cluster.yml akushnir@192.168.168.42:~/code-server-enterprise/docker-compose.yml
scp .env.cluster akushnir@192.168.168.42:~/code-server-enterprise/.env

# 3. Deploy on Replica 1
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose up -d'

# 4. Deploy on Replica 2
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose up -d'

# 5. Verify deployment
ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}\t{{.Status}}" | sort'
```

---

## Migration from Old Naming to Standard Naming

### For Existing Deployments

**Prerequisites:**
- Backup all critical data
- Document current container names
- Plan maintenance window

**Migration Steps:**

#### Step 1: Stop All Containers (Both Replicas)

```bash
# Replica 1
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose down'

# Replica 2
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose down'

# Verify all stopped
ssh akushnir@192.168.168.31 'docker ps | wc -l'  # Should be 0
ssh akushnir@192.168.168.42 'docker ps | wc -l'  # Should be 0
```

#### Step 2: Backup Volumes (Optional but Recommended)

```bash
# Backup PostgreSQL data
ssh akushnir@192.168.168.31 'docker run --rm -v code-server-enterprise_postgres_data:/src \
  -v /backup:/dest alpine tar czf /dest/postgres_backup.tar.gz -C /src .'

# Backup Redis data
ssh akushnir@192.168.168.31 'docker run --rm -v code-server-enterprise_redis_data:/src \
  -v /backup:/dest alpine tar czf /dest/redis_backup.tar.gz -C /src .'
```

#### Step 3: Update Compose Files

Copy new files with standard naming to both replicas:

```bash
scp docker-compose-cluster.yml akushnir@192.168.168.31:~/code-server-enterprise/docker-compose.yml
scp .env.cluster akushnir@192.168.168.31:~/code-server-enterprise/.env

scp docker-compose-cluster.yml akushnir@192.168.168.42:~/code-server-enterprise/docker-compose.yml
scp .env.cluster akushnir@192.168.168.42:~/code-server-enterprise/.env
```

#### Step 4: Clean Up Old Volumes (If Renaming)

```bash
# Only if you're recreating volumes with new names
ssh akushnir@192.168.168.31 'docker volume prune -f'
ssh akushnir@192.168.168.42 'docker volume prune -f'
```

#### Step 5: Deploy with New Naming

```bash
# Replica 1
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose up -d'

# Wait for services to stabilize
sleep 30

# Replica 2
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose up -d'

# Wait for services to stabilize
sleep 30
```

#### Step 6: Verify New Naming

```bash
# Check Replica 1
ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}\t{{.Status}}" | sort'

# Check Replica 2
ssh akushnir@192.168.168.42 'docker ps --format "table {{.Names}}\t{{.Status}}" | sort'

# Count containers (should be 35 on each)
ssh akushnir@192.168.168.31 'docker ps -q | wc -l'  # Should show 35
ssh akushnir@192.168.168.42 'docker ps -q | wc -l'  # Should show 35
```

---

## Cluster Access Points

### Via VIP (Recommended for Production)
```
Primary Endpoint: 192.168.168.250
Domain: kushnir.cloud (after DNS configuration)

Service Ports:
├── Grafana:            :3000  (Dashboards)
├── Prometheus:         :9090  (Metrics)
├── Loki:               :3100  (Logs)
├── Alertmanager:       :9093  (Alerts)
├── Redpanda Console:   :8085  (Broker UI)
├── OPA:                :8181  (Policy Engine)
├── Ollama:             :11434 (LLM)
├── OAuth2-Proxy:       :4180  (Authentication)
├── Caddy:              :80/:443 (API Gateway)
└── PostgreSQL:         :5432  (Database - internal only)
```

### Direct Replica Access (Development/Debug)
```
Replica 1: http://192.168.168.31:3000 (Grafana example)
Replica 2: http://192.168.168.42:3000 (Grafana example)
```

---

## Operational Commands

### Check All Container Status

```bash
# Replica 1
ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | sort'

# Replica 2
ssh akushnir@192.168.168.42 'docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | sort'

# Both at once
echo "=== REPLICA 1 ===" && \
ssh akushnir@192.168.168.31 'docker ps --format "{{.Names}}" | sort' && \
echo "" && \
echo "=== REPLICA 2 ===" && \
ssh akushnir@192.168.168.42 'docker ps --format "{{.Names}}" | sort'
```

### View Service Logs

```bash
# PostgreSQL replication
ssh akushnir@192.168.168.31 'docker logs code-server-postgres -f'

# Redis 
ssh akushnir@192.168.168.31 'docker logs code-server-redis -f'

# Redpanda broker
ssh akushnir@192.168.168.31 'docker logs code-server-redpanda -f'

# Grafana
ssh akushnir@192.168.168.31 'docker logs code-server-grafana -f'
```

### Verify Replication

```bash
# Check PostgreSQL replication status
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -c \
  "SELECT client_addr, state FROM pg_stat_replication;"'

# Check Redis replication
ssh akushnir@192.168.168.31 'docker exec code-server-redis redis-cli info replication'

# Check Redpanda cluster status
ssh akushnir@192.168.168.31 'docker exec code-server-redpanda rpk cluster info'
```

### Restart a Specific Service

```bash
# Restart Grafana on Replica 1
ssh akushnir@192.168.168.31 'docker-compose -f ~/code-server-enterprise/docker-compose.yml \
  restart code-server-grafana'

# Restart all services on Replica 1
ssh akushnir@192.168.168.31 'docker-compose -f ~/code-server-enterprise/docker-compose.yml restart'
```

### Container Resource Usage

```bash
# Real-time stats for all code-server containers
ssh akushnir@192.168.168.31 'docker stats --no-stream $(docker ps -q -f label=com.docker.compose.project=code-server-enterprise) 2>/dev/null || docker stats'
```

---

## Health Checks

### Service Connectivity (From Control Host)

```bash
# Grafana
curl -I http://192.168.168.31:3000

# Prometheus
curl -I http://192.168.168.31:9090/api/v1/status/runtimeinfo

# Loki
curl -I http://192.168.168.31:3100/ready

# Redpanda
curl -I http://192.168.168.31:8085

# OPA Health
curl http://192.168.168.31:8181/health
```

### Cross-Replica Connectivity (From Replica 1)

```bash
# Ping Replica 2 Grafana
ssh akushnir@192.168.168.31 'docker exec code-server-grafana \
  curl -I http://192.168.168.42:3000'

# Replicate test data between PostgreSQL instances
ssh akushnir@192.168.168.31 'docker exec code-server-postgres \
  psql -U postgres -h 192.168.168.42 -c "SELECT version();"'
```

---

## Troubleshooting

### Container Not Starting

```bash
# Check logs
ssh akushnir@192.168.168.31 'docker logs code-server-postgres'

# Inspect container
ssh akushnir@192.168.168.31 'docker inspect code-server-postgres'

# Check resource constraints
ssh akushnir@192.168.168.31 'docker stats code-server-postgres'
```

### Network Connectivity Issues

```bash
# From Replica 1, test connection to Replica 2
ssh akushnir@192.168.168.31 'docker exec code-server-postgres \
  bash -c "nc -zv 192.168.168.42 5432"'

# Test DNS resolution
ssh akushnir@192.168.168.31 'docker exec code-server-grafana \
  nslookup code-server-prometheus'
```

### Replication Issues

```bash
# PostgreSQL replication lag
ssh akushnir@192.168.168.31 'docker exec code-server-postgres \
  psql -U postgres -c "SELECT slot_name, confirmed_flush_lsn FROM pg_replication_slots;"'

# Redis info
ssh akushnir@192.168.168.31 'docker exec code-server-redis redis-cli info'

# Redpanda partition status
ssh akushnir@192.168.168.31 'docker exec code-server-redpanda \
  rpk topic list -a'
```

---

## Performance Tuning

### Container Resource Limits

Edit `docker-compose.yml` to add resource constraints:

```yaml
services:
  code-server-postgres:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
```

### Database Query Optimization

```bash
# Connect to PostgreSQL
ssh akushnir@192.168.168.31 'docker exec -it code-server-postgres psql -U postgres'

# Run inside psql:
\timing on
EXPLAIN ANALYZE SELECT * FROM table_name WHERE condition;
```

---

## Backup & Recovery

### Automated Database Backup

```bash
# Backup script (run on control host)
#!/bin/bash
BACKUP_DIR="/backup/postgres"
mkdir -p $BACKUP_DIR
DATE=$(date +%Y%m%d_%H%M%S)

ssh akushnir@192.168.168.31 "docker exec code-server-postgres \
  pg_dump -U postgres kushnir_db" > $BACKUP_DIR/backup_$DATE.sql

echo "Backup saved to $BACKUP_DIR/backup_$DATE.sql"
```

### Restore from Backup

```bash
# Connect to PostgreSQL container and restore
ssh akushnir@192.168.168.31 'docker exec -i code-server-postgres \
  psql -U postgres kushnir_db' < /backup/postgres/backup_20260428_120000.sql
```

---

## Next Steps

1. ✅ **Naming Standardization**: Completed - all containers named `code-server-<service>`
2. ⏳ **VIP Configuration**: Update load balancer to use 192.168.168.250
3. ⏳ **DNS Configuration**: Point kushnir.cloud to VIP
4. ⏳ **SSL/TLS**: Configure certificates for HTTPS
5. ⏳ **Monitoring**: Set up external monitoring and alerting

---

## Support

For issues with the new naming convention or VIP configuration, refer to:
- [CLUSTER_NAMING_CONVENTION.md](CLUSTER_NAMING_CONVENTION.md)
- [ACTIVE_ACTIVE_CLUSTER_STATUS.md](ACTIVE_ACTIVE_CLUSTER_STATUS.md)
- Docker Compose logs: `docker-compose logs <service-name>`

