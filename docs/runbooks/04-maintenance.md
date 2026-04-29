# Maintenance & Updates Guide

## Regular Maintenance Schedule

### Daily (Automated)
- Backup verification (in Prometheus rules)
- Health checks (every 30s per service)
- Replication status check

### Weekly
- Review alerting rules
- Check disk space usage
- Verify backup completion

### Monthly
- Failover drill (test but don't complete)
- Review access logs
- Audit trail analysis

### Quarterly
- Major security patches
- Dependency updates
- Capacity planning review

## PostgreSQL Maintenance

### Vacuum & Analyze
```bash
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -c "VACUUM ANALYZE;"'
```

### Backup Current State
```bash
ssh akushnir@192.168.168.31 'docker exec code-server-postgres pg_basebackup -D /tmp/backup -F tar -z'
```

### Monitor Replication Slot
```bash
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -tc "SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;"'
```

## Redis Maintenance

### Memory Optimization
```bash
docker exec code-server-redis redis-cli MEMORY DOCTOR
```

### Persistence Verification
```bash
docker exec code-server-redis redis-cli BGSAVE
```

## Container Updates

### Update Strategy
1. Stop replica service first
2. Update image
3. Start replica
4. Verify replication
5. Repeat on primary

### Update Single Container
```bash
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose pull code-server-SERVICE && docker-compose up -d code-server-SERVICE'
```

## Log Rotation

### Docker Logs
```bash
# Check log size
docker inspect code-server-SERVICE | grep LogPath

# Rotate manually
docker exec code-server-SERVICE logrotate -f /etc/logrotate.d/app
```

## Secrets Rotation

### Quarterly Rotation
```bash
# 1. Generate new passwords
# 2. Update .env.production
# 3. Update terraform.tfvars
# 4. Restart services on both hosts
# 5. Update client configurations
# 6. Document in CHANGELOG
```

