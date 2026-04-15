# Phase 7c Pre-Flight Checklist

Before running Phase 7c Disaster Recovery tests, verify ALL of the following:

## Network Connectivity ✅
- [ ] Can ping 192.168.168.31 (primary): `ping 192.168.168.31`
- [ ] Can ping 192.168.168.42 (replica): `ping 192.168.168.42`
- [ ] Can ping 192.168.168.55 (NAS): `ping 192.168.168.55`
- [ ] SSH port 22 open on all three: `Test-NetConnection -ComputerName 192.168.168.31 -Port 22`

## SSH Access ✅
- [ ] Can SSH to primary: `ssh akushnir@192.168.168.31 "echo OK"`
- [ ] Can SSH to replica: `ssh akushnir@192.168.168.42 "echo OK"`
- [ ] Can SSH to NAS: `ssh akushnir@192.168.168.55 "echo OK"`
- [ ] SSH key is loaded and not password-protected

## Primary Server Health ✅
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose ps"
```

Verify these containers are **healthy**:
- [ ] code-server (port 8080)
- [ ] caddy (port 80, 443)
- [ ] oauth2-proxy (port 4180)
- [ ] postgres (port 5432)
- [ ] redis (port 6379)
- [ ] prometheus (port 9090)
- [ ] grafana (port 3000)
- [ ] alertmanager (port 9093)
- [ ] jaeger (port 16686)

## Replica Server Sync ✅
```bash
ssh akushnir@192.168.168.42 "cd code-server-enterprise && docker-compose ps"
```

Replica should have:
- [ ] Code-server deployment (same as primary)
- [ ] PostgreSQL replication running
- [ ] Redis replication running
- [ ] At least "starting" or "healthy" state

## Production Data Backup ✅
```bash
ssh akushnir@192.168.168.31 "ls -lh /backups/"
```

Should show:
- [ ] PostgreSQL dump < 1 hour old
- [ ] Redis dump < 1 hour old
- [ ] Application state backup < 24 hours old

## Network Routes ✅
```bash
ssh akushnir@192.168.168.31 "route -n | grep -E '192.168.168|10.0.0'"
```

Verify:
- [ ] Primary can reach replica (192.168.168.42)
- [ ] Primary can reach NAS (192.168.168.55)
- [ ] Failover route is NOT active (shouldn't be 0.0.0.0)

## Storage Paths ✅
```bash
ssh akushnir@192.168.168.31 "df -h /data /backups /var/lib/docker"
```

Verify:
- [ ] /data has > 50GB free
- [ ] /backups has > 100GB free
- [ ] /var/lib/docker has > 50GB free

## Cluster State ✅
```bash
ssh akushnir@192.168.168.31 "cat code-server-enterprise/cluster-state.json 2>/dev/null | jq '.primary_role'"
```

Should show:
- [ ] PRIMARY is marked as active primary
- [ ] REPLICA is marked as standby
- [ ] No conflicting roles

## Script Executable ✅
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && ls -l scripts/phase-7c-disaster-recovery-test.sh"
```

Should show:
- [ ] File exists
- [ ] Has executable permission (starts with `rwxr-x`)

## Ready to Proceed ✅

Once ALL checklist items are verified:

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
bash scripts/phase-7c-disaster-recovery-test.sh
```

This will:
1. Run 5 disaster recovery tests (5-10 minutes total)
2. Validate RTO < 5 minutes
3. Validate RPO < 1 hour
4. Test automatic failover
5. Generate detailed report in `/tmp/phase-7c-dr-test-*.log`

---

## If Any Checklist Item Fails

**Network Fails?**
- Check firewall rules on primary/replica/NAS
- Verify SSH is running: `ssh akushnir@192.168.168.31 "ps aux | grep sshd"`
- Check DNS resolution: `nslookup 192.168.168.31`

**Docker Container Not Healthy?**
- Check logs: `docker logs <container_name>`
- Restart if needed: `docker-compose restart <service>`
- Full restart: `docker-compose down && docker-compose up -d`

**Replication Not Working?**
- Check PostgreSQL replication status: `psql -U postgres -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"`
- Check Redis replication status: `redis-cli info replication`

---

## Timeline

- Checklist validation: **2-5 minutes**
- Phase 7c execution: **5-10 minutes**
- Result review: **2-3 minutes**
- **Total: 10-20 minutes**

After this completes successfully, you can proceed to Phase 7d (Load Balancing) immediately.
