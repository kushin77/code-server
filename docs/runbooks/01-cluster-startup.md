# Cluster Startup Procedure

## Quick Start (Both Nodes Offline)

```bash
# 1. Start Primary (192.168.168.31)
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose -f docker-compose.enterprise.yml up -d'

# 2. Wait for databases to initialize
sleep 30

# 3. Start Replica (192.168.168.42)
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose -f docker-compose.enterprise.yml up -d'

# 4. Verify cluster
./scripts/final-validation.sh
```

## Health Checks After Startup

- **Database**: `docker exec code-server-postgres psql -U postgres -c "SELECT version();"`
- **Redis**: `docker exec code-server-redis redis-cli PING`
- **Prometheus**: `curl http://localhost:9090/api/v1/status/config`
- **Grafana**: `curl http://localhost:3000/api/health`
- **OPA**: `curl http://localhost:8181/health`

## Rolling Restart (Maintain HA)

### Restart Replica First
```bash
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose -f docker-compose.enterprise.yml restart'
sleep 10
# Verify: docker ps and health checks

# Wait for replication to catch up
docker exec code-server-postgres psql -U postgres -tc "SELECT slot_name, active FROM pg_replication_slots;"
```

### Restart Primary
```bash
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose -f docker-compose.enterprise.yml restart'
sleep 10
# All traffic shifts to replica during primary restart
```

## Expected Startup Sequence

1. PostgreSQL: 10-20s to start
2. Redis: 5-10s to start
3. Application services: 15-30s to become healthy
4. Replication: 10-30s to establish
5. Observability: 20-40s for all stacks ready

## Troubleshooting

- **Containers not starting**: Check logs: `docker logs code-server-SERVICE`
- **Replication not active**: Check WAL config: `docker exec code-server-postgres psql -U postgres -tc "SELECT wal_level, max_wal_senders;"`
- **Redis not responding**: Verify credentials in .env.production
- **High latency**: Check resource limits: `docker stats`

