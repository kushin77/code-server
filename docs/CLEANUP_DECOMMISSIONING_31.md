# Cleanup & Decommissioning Plan for Old Infrastructure
## Safely Retire Legacy code-server-enterprise After 192.168.168.31 is Operational

**Version**: 1.0  
**Date**: April 13, 2026  
**Priority**: LOW - Execute only after 4+ weeks of stable 192.168.168.31 operation

---

## Preconditions (ALL must be met before proceeding)

- ✅ 192.168.168.31 deployment complete and validated
- ✅ All services operational with performance baselines established
- ✅ 4 weeks of continuous stable operation (no critical incidents)
- ✅ Backup of old infrastructure data completed and verified
- ✅ DNS/routing exclusively pointing to 192.168.168.31
- ✅ Team trained on new infrastructure
- ✅ No active users or scheduled jobs on old infrastructure
- ✅ Executive sign-off for decommissioning

---

## Phase 1: Final Data Backup (2 hours)

### 1.1 Complete Backup of All Volumes

```bash
# Backup all persistent data from old infrastructure
backup_date=$(date +%Y%m%d-%H%M%S)
backup_dir="/backup/legacy-final-${backup_date}"

mkdir -p "$backup_dir"

# Backup code-server data
docker run --rm -v code-server-data:/data -v "$backup_dir":/backup \
  ubuntu tar czf /backup/code-server-data.tar.gz /data

# Backup ollama models
docker run --rm -v ollama-data:/data -v "$backup_dir":/backup \
  ubuntu tar czf /backup/ollama-data.tar.gz /data

# Backup workspace
docker run --rm -v workspace-data:/data -v "$backup_dir":/backup \
  ubuntu tar czf /backup/workspace-data.tar.gz /data

# Verify backup sizes
du -sh "$backup_dir"/*

echo "Final backup completed: $backup_dir"
```

### 1.2 Backup Database (if applicable)

```bash
# If PostgreSQL is in use
docker exec postgres-container pg_dump -U postgres mydb > "$backup_dir"/database.sql

# Compress
gzip "$backup_dir"/database.sql

# Verify
gunzip -t "$backup_dir"/database.sql.gz && echo "Database backup valid"
```

### 1.3 Archive Backup Off-Site

```bash
# Upload to S3 or external storage for long-term retention
aws s3 cp "$backup_dir" s3://backups/legacy-final-$backup_date/ --recursive

# Or copy to external drive
cp -r "$backup_dir" /mnt/external-drive/

# Document backup manifest
cat > "$backup_dir"/MANIFEST.txt << 'EOF'
Legacy code-server-enterprise Final Backup
Generated: $(date)
Contents:
- code-server-data.tar.gz: Code-Server configs and data
- ollama-data.tar.gz: LLM models and cache
- workspace-data.tar.gz: Workspace files
- database.sql.gz: PostgreSQL database dump

To restore: tar xzf <file>.tar.gz -C /path/to/restore/
EOF

# Archive manifest
echo "$(cat $backup_dir/MANIFEST.txt)"
```

### Success Criteria
- ✅ All 3 volume backups completed
- ✅ Backup integrity verified
- ✅ Off-site copy created
- ✅ Manifest documented

---

## Phase 2: Infrastructure Decommissioning (30 minutes)

### 2.1 Graceful Service Shutdown

```bash
# Stop accepting new connections
# (If applicable, set maintenance mode 15 minutes prior)

# Gracefully stop docker-compose services
cd /path/to/old-infrastructure
docker-compose stop

# Wait for graceful shutdown (up to 5 minutes)
sleep 60

# Force stop if needed
docker-compose kill

# Verify all stopped
docker ps | grep -E "code-server|ollama|traefik" || echo "All services stopped"
```

### 2.2 Preserve Docker Volumes

```bash
# DON'T DELETE - Keep for archival

# List all volumes
docker volume ls | grep -E "code-server|ollama|workspace"

# Archive volume list for documentation
docker volume ls > /backup/legacy-volumes-list.txt

# Each volume preserved with backup in $backup_dir
```

### 2.3 Disable Monitoring & Alerting

```bash
# Stop monitoring old infrastructure to avoid false alerts
curl -X POST http://prometheus:9090/api/v1/admin/tsdb/delete_series \
  -d 'match[]=instance="old-host"'

# Or disable scrape job in Prometheus
# In prometheus.yml, comment out old infrastructure job

# Remove old infrastructure from Grafana dashboards
# Via UI: Remove data source or disable

# Delete any cron jobs tied to old infrastructure
crontab -l | grep -v legacy | crontab -

# Verify no processes running
ps aux | grep -v grep | grep -E "code-server|ollama" || echo "No processes found"
```

### 2.4 Document Any Lingering Configuration

```bash
# Export any custom configurations not yet migrated
docker inspect code-server > /backup/legacy-code-server-config.json
docker inspect ollama > /backup/legacy-ollama-config.json

# Export firewall rules (if applicable)
sudo iptables-save > /backup/legacy-iptables.rules

# Export DNS entries
nslookup code-server.internal > /backup/legacy-dns-entries.txt

echo "Legacy configurations archived for reference"
```

### Success Criteria
- ✅ All services gracefully stopped
- ✅ No running processes
- ✅ Docker volumes preserved
- ✅ Monitoring disabled for old infrastructure
- ✅ Custom configs documented

---

## Phase 3: Storage Cleanup (1 hour)

### 3.1 Archive Old Docker Volumes

```bash
# Create compressed archive of volumes
docker run --rm -v code-server-data:/data -v /backup:/backup \
  ubuntu tar czf /backup/legacy-volumes.tar.gz /data

# Store in cold storage
aws s3 cp /backup/legacy-volumes.tar.gz s3://backups/legacy/ --storage-class GLACIER

# Verify upload
aws s3 ls s3://backups/legacy/legacy-volumes.tar.gz
```

### 3.2 Cleanup Temporary Files

```bash
# Remove temporary files (leave actual data)
rm -rf /tmp/code-server-*
find /var/cache -name "*code-server*" -o -name "*ollama*" | xargs rm -rf

# Clear Docker build cache
docker system prune -f

# Cleanup old logs
journalctl --vacuum=7d  # Keep 7 days of logs only

# Report freed space
df -h /
```

### 3.3 Validate No Sensitive Data Remains

```bash
# Search for any leftover credentials or API keys
grep -r "password\|secret\|api.key" /etc/ /home/ /opt/ 2>/dev/null | wc -l
# Should be: 0

# If found, securely overwrite:
shred -vfz -n 3 /path/to/sensitive/file

# Check for any unencrypted password files
find / -name "*.txt" -o -name "*.conf" 2>/dev/null | xargs grep -l "password" || echo "No plaintext creds found"
```

### Success Criteria
- ✅ Volumes archived off-site
- ✅ Temporary files deleted
- ✅ Build cache cleared
- ✅ Old logs pruned
- ✅ No sensitive data remains

---

## Phase 4: DNS/Network Cleanup (30 minutes)

### 4.1 Verify DNS Points to New Infrastructure

```bash
# Check DNS resolution
nslookup code-server.internal
# Should return: 192.168.168.31

nslookup ollama.internal
# Should return: 192.168.168.31

# If not, update DNS:
# /etc/hosts (local):
# 192.168.168.31 code-server.internal ollama.internal

# Or DNS server (if using centralized DNS):
# Update A records to point to 192.168.168.31
```

### 4.2 Update Routing Rules

```bash
# Remove any special routing for old infrastructure
ip route list
# Verify no routes to old host exist

# If old traffic still routes to legacy host:
ip route del <old-route> || echo "No old routes found"

# Check firewall rules
sudo ufw status
# Verify no rules explicitly allow old host

# Remove load balancer entries
# If using HAProxy/Nginx, remove old backend servers
```

### 4.3 Verify No Split-Brain Routing

```bash
# Trace route to confirm all traffic goes to new host
traceroute code-server.internal
# Should show path to 192.168.168.31, not old host

# Test from multiple clients
ssh client1 "nslookup code-server.internal" | grep -q "192.168.168.31" && echo "Client 1: OK"
ssh client2 "nslookup code-server.internal" | grep -q "192.168.168.31" && echo "Client 2: OK"
```

### Success Criteria
- ✅ DNS exclusively points to 192.168.168.31
- ✅ No routing to old infrastructure
- ✅ No split-brain scenarios
- ✅ All clients use new infrastructure

---

## Phase 5: CI/CD Pipeline Updates (1 hour)

### 5.1 Update GitHub Actions Workflows

```yaml
# Before: Deploy to old host
# After: Deploy to 192.168.168.31

# In .github/workflows/deploy.yml:

jobs:
  deploy:
    name: Deploy to 192.168.168.31
    runs-on: ubuntu-latest
    steps:
      - name: SSH to 192.168.168.31
        run: ssh -i ${{ secrets.DEPLOY_KEY }} akushnir@192.168.168.31 "make deploy-31"
```

### 5.2 Update CI/CD Secrets

```bash
# Remove old infrastructure secrets
gh secret delete OLD_HOST_IP
gh secret delete OLD_HOST_SSH_KEY

# Verify new secrets present
gh secret list | grep "31\|192.168.168"
```

### 5.3 Test End-to-End Pipeline

```bash
# Trigger a test deployment via GitHub Actions
git commit --allow-empty -m "test: CI/CD pipeline to new infrastructure"
git push

# Monitor: GitHub Actions > Actions > Latest workflow
# Expected: Deploy succeeds to 192.168.168.31
```

### 5.4 Update Documentation

```bash
# Update deployment docs
sed -i 's/old-host/192.168.168.31/g' docs/DEPLOYMENT.md
sed -i 's/legacy/current/g' README.md

# Remove old infrastructure references
grep -r "old-infrastructure\|legacy-setup" docs/ && rm -f docs/OLD_SETUP.md

# Commit
git add docs/ && git commit -m "docs: Remove legacy infrastructure references"
```

### Success Criteria
- ✅ GitHub Actions workflows updated
- ✅ CI/CD pipeline tests to 192.168.168.31
- ✅ Old secrets removed
- ✅ Documentation updated

---

## Phase 6: Monitoring & Alerting Update (30 minutes)

### 6.1 Remove Old Infrastructure Metrics

```bash
# Connect to Prometheus
curl -X POST http://prometheus:9090/api/v1/admin/tsdb/delete_series \
  -d 'match[]=job="old-infrastructure"'

# Remove old targets from prometheus.yml
# Restart Prometheus
docker-compose restart prometheus

# Verify targets cleaned
curl http://prometheus:9090/api/v1/targets | jq '.data.activeTargets | length'
# Should not include old infrastructure
```

### 6.2 Archive Historical Metrics

```bash
# Export Prometheus metrics for old infrastructure (if needed for analysis)
docker exec prometheus promtool query instant 'up{job="old-infrastructure"}' \
  --time 1640995200 > /backup/legacy-metrics.json

# Backup Prometheus DB
docker exec prometheus tar czf /backup/prometheus-db.tar.gz /prometheus
```

### 6.3 Update Alert Rules

```bash
# In alert-rules-31.yml, verify no references to old infrastructure
grep -r "old\|legacy" /etc/prometheus/rules/ && echo "Found legacy references" || echo "No legacy references"

# Remove any dual-target alerts
# Example: Remove alert that monitors both old and new infrastructure

# Reload Prometheus rules
curl -X POST http://prometheus:9090/-/reload
```

### 6.4 Consolidate Grafana Dashboards

```bash
# Remove old infrastructure dashboards
# Via Grafana UI: Settings > Data Sources > Remove "Old Infrastructure"

# Consolidate metrics if running dual dashboards
# All metrics now feed from 192.168.168.31 only

# Verify: Grafana should show only 192.168.168.31 data source
curl http://grafana:3000/api/datasources | jq '.[] | .name'
# Should show: "Prometheus (192.168.168.31)"
```

### Success Criteria
- ✅ Old metrics purged from Prometheus
- ✅ Alert rules updated
- ✅ Grafana cleaned (single data source)
- ✅ No references to old infrastructure

---

## Phase 7: Final Documentation & Lessons Learned (1 hour)

### 7.1 Document Migration Insights

```bash
# Create post-mortem document
cat > docs/MIGRATION_LESSONS_LEARNED.md << 'EOF'
# Migration from Legacy to 192.168.168.31: Lessons Learned

## What Went Well
- IaC-based deployment was fully reproducible
- Testing suite caught 3 issues before production
- Monitoring/alerting enabled quick troubleshooting

## Challenges
- GPU driver initial compatibility issues (resolved in 4 hours)
- NAS latency optimization took 2 weeks of tuning
- DNS propagation delayed traffic migration by 2 hours

## Improvements for Next Time
- Pre-validate docker images before deployment
- Establish NAS performance baseline before cutover
- Plan DNS migration in advance

## Recommendations
- Keep IaC-driven approach for all infrastructure
- Automate validation in CI/CD
- Document all custom configs in code
EOF
```

### 7.2 Remove Old Infrastructure Runbooks

```bash
# Archive old documentation
mkdir -p /backup/legacy-docs
mv docs/OLD_*.md /backup/legacy-docs/
mv docs/LEGACY_*.md /backup/legacy-docs/

# Keep core documentation:
# - MIGRATION_LESSONS_LEARNED.md (new)
# - Old docs archived in /backup/legacy-docs/
```

### 7.3 Update Team Runbooks

```bash
# On-call procedures now reference only 192.168.168.31
# Update on-call wiki/docs to remove old host references

# Emergency procedures reference new host
# Rollback procedures document how to restore from backup to new host

# Training materials updated for new infrastructure
```

### 7.4 Create Decommissioning Checklist

```bash
cat > /backup/DECOMMISSIONING_COMPLETE.txt << 'EOF'
Legacy code-server-enterprise Decommissioning Complete
Date: $(date)
Completed By: (Your Name)

Phase 1: Data Backup ........................... ✓
Phase 2: Infrastructure Shutdown .............. ✓
Phase 3: Storage Cleanup ...................... ✓
Phase 4: DNS/Network Cleanup .................. ✓
Phase 5: CI/CD Pipeline Updates .............. ✓
Phase 6: Monitoring & Alerting Update ........ ✓
Phase 7: Documentation & Lessons Learned .... ✓

Total Execution Time: ~5 hours
Risk Level: LOW (fully tested before cleanup)
Data Integrity: VERIFIED (backups confirmed)

Next Steps:
- [ ] Archive /backup to off-site storage
- [ ] Decommission old host hardware (if applicable)
- [ ] Close legacy infrastructure tickets
- [ ] Update team on new procedures

Post-Decommissioning:
- Monitor 192.168.168.31 for 2 weeks
- Verify no issues with migrated data
- Document any remaining issues
EOF

# Email team with completion status
echo "Legacy infrastructure decommissioning complete"
```

### Success Criteria
- ✅ Lessons learned documented
- ✅ Old docs archived
- ✅ Checklists verified
- ✅ Team notified

---

## Rollback Procedure (If Needed During Cleanup)

If any critical issue occurs during decommissioning:

1. **Stop cleanup immediately** - Do not delete additional resources
2. **Emergency restore**:
   ```bash
   # Restore from backup to 192.168.168.31
   tar xzf /backup/legacy-final-YYYYMMDD-HHMMSS/code-server-data.tar.gz -C /
   ```
3. **Verify service**: `curl http://192.168.168.31:8443`
4. **Alert team** - Declare incident
5. **Post-incident review** - Identify what went wrong

---

## Risk Assessment

| Phase | Risk | Mitigation |
|-------|------|-----------|
| Backup | Data loss | Verify integrity before proceeding |
| Shutdown | Service interruption | Execute during maintenance window |
| DNS update | Split-brain | Verify from multiple clients |
| Cleanup | Accidental deletion | Use 'rm -i' for confirmation |
| Total | **LOW** | Fully backed up, tested approach |

---

## Timeline Estimate

- **Total Duration**: ~5 hours
- **Downtime Required**: 30 minutes (during shutdown/DNS cutover)
- **Risk Level**: LOW (fully backed up)
- **Rollback Time**: <15 minutes (restore from backup)

---

## Sign-Off

| Role | Name | Date | Sign-Off |
|------|------|------|----------|
| DevOps Lead | ____________ | ______ | _______ |
| Infrastructure Owner | ____________ | ______ | _______ |
| Executive Sponsor | ____________ | ______ | _______ |

---

**DO NOT PROCEED WITH DECOMMISSIONING UNTIL ALL SIGN-OFFS COMPLETE**

**Lowest Priority** - Execute only after 4+ weeks stable operation of 192.168.168.31.

