# Operational Runbooks for 192.168.168.31
## Daily Operations, Common Issues, Scaling & Disaster Recovery

**Version**: 1.0  
**Date**: April 13, 2026  
**Audience**: Site Reliability Engineers, DevOps, On-Call Support

---

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Common Issues & Solutions](#common-issues--solutions)
3. [Scaling Procedures](#scaling-procedures)
4. [Backup & Restore](#backup--restore)
5. [Disaster Recovery](#disaster-recovery)
6. [On-Call Escalation](#on-call-escalation)

---

## Daily Operations

### Morning Health Check (5 minutes)

```bash
# 1. Check all services running
docker ps

# Expected: code-server, ollama, prometheus, cadvisor, grafana all UP

# 2. Check GPU health
nvidia-smi

# Expected: GPU 0, GPU 1 visible, 0 processes consuming VRAM initially

# 3. Check NAS mounts
df -h /mnt/nas-primary /mnt/nas-backup

# Expected: Both mounted, >90% available

# 4. Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# Expected: 8+ targets (prometheus, node-exporter, nvidia-dcgm, ollama, code-server, etc.)

# 5. Check for active alerts
curl -s http://localhost:9090/api/v1/alerts | jq '.data | length'

# Expected: 0 (or known, acknowledged alerts)
```

### Backup Status Check (Daily 8 AM)

```bash
# Check last successful backup
stat /mnt/nas-primary/.backup-timestamp

# Expected: Modified time within last 24 hours

# Check backup logs
tail -100 /var/log/nas-backup.log

# Expected: "Backup completed successfully at..."
```

### Capacity Planning (Weekly)

```bash
# Check free disk space trend
df -h / /mnt/nas-primary /mnt/nas-backup

# Check for growing directories
du -sh /mnt/nas-primary/* | sort -hr | head -10

# Action if >80% full:
# - Archive old logs
# - Prune unused models
# - Remove cached data
```

---

## Common Issues & Solutions

### Issue 1: GPU Not Visible

**Symptom**: `nvidia-smi` command not found or shows no GPUs

**Diagnosis**:
```bash
# Check if NVIDIA driver is loaded
lsmod | grep nvidia

# Check if nvidia-docker runtime is available
docker run --rm --runtime=nvidia ubuntu nvidia-smi
```

**Solutions**:

**Solution A: NVIDIA Driver Missing**
```bash
# Reinstall NVIDIA drivers
sudo apt-get install nvidia-driver-535  # or latest version

# Reboot
sudo reboot

# Verify
nvidia-smi
```

**Solution B: Container Runtime Not Configured**
```bash
# Check docker daemon config
cat /etc/docker/daemon.json

# Should contain:
# {
#   "runtimes": {
#     "nvidia": {
#       "path": "nvidia-container-runtime",
#       "runtimeArgs": []
#     }
#   }
# }

# Restart Docker
sudo systemctl restart docker

# Test
docker run --rm --gpus all ubuntu nvidia-smi
```

**Solution C: NVIDIA Container Runtime Not Installed**
```bash
# Install nvidia-container-runtime
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install nvidia-container-runtime

# Restart Docker
sudo systemctl restart docker
```

### Issue 2: NAS Mount Point Down

**Symptom**: `df /mnt/nas-primary` shows "Transport endpoint is not connected"

**Diagnosis**:
```bash
# Check mount status
mountpoint /mnt/nas-primary

# Check NAS network connectivity
ping 192.168.168.10  # primary NAS IP

# Check NFS port
sudo nmap -p 2049 192.168.168.10
```

**Solutions**:

**Solution A: Network Issue**
```bash
# Check network connectivity
ifconfig eth0

# If IP missing, renew DHCP
sudo dhclient eth0

# Ping NAS
ping 192.168.168.10

# If still down, check NAS physical health
# (Contact NAS admin or check NAS web UI)
```

**Solution B: Graceful Remount**
```bash
# Try lazy unmount first
sudo umount -l /mnt/nas-primary

# Wait 30 seconds
sleep 30

# Remount
sudo mount /mnt/nas-primary

# Verify
df /mnt/nas-primary
```

**Solution C: Force Remount (Data Corruption Risk!)**
```bash
# WARNING: Only use if lazy unmount fails

# Kill any processes using the mount
fuser -km /mnt/nas-primary

# Unmount
sudo umount -f /mnt/nas-primary

# Clear mount point
sudo rm -rf /mnt/nas-primary
sudo mkdir -p /mnt/nas-primary

# Remount
sudo mount /mnt/nas-primary

# Verify immediately
ls /mnt/nas-primary
```

**Failover to Secondary NAS**:
```bash
# If primary NAS permanently down, failover to backup
sudo umount /mnt/nas-primary

# Update /etc/fstab to use backup NAS
# Change: 192.168.168.10:/export/data to 192.168.168.11:/export/backup

# Remount
sudo mount /mnt/nas-primary

# Verify data present
ls /mnt/nas-primary
```

### Issue 3: Code-Server Not Responding

**Symptom**: Browser shows "Connection refused" on http://localhost:8443

**Diagnosis**:
```bash
# Check if container is running
docker ps | grep code-server

# Check logs
docker logs code-server | tail -50

# Check port binding
sudo netstat -tlun | grep 8443

# Check CPU/memory
docker stats code-server
```

**Solutions**:

**Solution A: Simple Restart**
```bash
# Restart container
docker restart code-server

# Wait 10 seconds, then verify
sleep 10
curl http://localhost:8443
```

**Solution B: Increase Resource Limits**
```bash
# If memory-limited, increase allocation
docker update --memory=8g code-server

# Restart
docker restart code-server
```

**Solution C: Rebuild Container**
```bash
# Rebuild image
docker-compose build code-server

# Restart service
docker-compose up -d code-server

# Verify
curl http://localhost:8443
```

### Issue 4: Ollama Inference Timeout

**Symptom**: Ollama requests timeout or take >5 seconds

**Diagnosis**:
```bash
# Check GPU utilization
nvidia-smi

# Check Ollama logs
docker logs ollama | tail -20

# Check if multiple models loaded (memory pressure)
curl http://localhost:11434/api/tags | jq '.models | length'

# Check system load
top -bn1 | head -20
```

**Solutions**:

**Solution A: GPU Memory Pressure**
```bash
# Unload unused models
curl -X POST http://localhost:11434/api/generate -d '{
  "model": "unused-model", "keep_alive": 0
}'

# Or restart Ollama to clear memory
docker restart ollama

# Wait 5 seconds for container to be ready
sleep 5

# Test inference again
curl -X POST http://localhost:11434/api/generate -d '{"model":"llama2","prompt":"hello"}'
```

**Solution B: Reduce Batch Size**
```bash
# Edit docker-compose.yml
# Reduce OLLAMA_BATCH_SIZE or model quantization

# Restart
docker-compose up -d ollama

# Monitor latency
curl -X POST http://localhost:11434/api/generate -d '{"model":"llama2","prompt":"hello","raw":true}' \
  | jq '.total_duration / 1e9'
```

**Solution C: Check System Load**
```bash
# If CPU or memory pressure high, pause other workloads
ps aux --sort=-%cpu | head -10

# Kill or pause resource-intensive processes
sudo systemctl stop backup-job  # if applicable
```

---

## Scaling Procedures

### Add Storage Capacity

**When**: NAS >80% full

**Procedure**:

1. **Assess available capacity**
   ```bash
   # Check current NAS capacity
   df /mnt/nas-primary
   
   # Estimate growth rate
   # Growth = (Current Size Today - Size 30 Days Ago) / 30 days
   ```

2. **Initiate NAS expansion**
   ```bash
   # Contact NAS admin or storage team
   # Request: Add 1TB to existing NAS
   # Timeline: 1-2 weeks (zero-downtime expansion)
   ```

3. **Verify expanded capacity**
   ```bash
   # After NAS expansion completes:
   df /mnt/nas-primary
   
   # Should show larger size (e.g., 3TB -> 4TB)
   ```

4. **Update capacity alerts**
   ```bash
   # Edit /etc/prometheus/alert-rules-31.yml
   # Increase capacity thresholds proportionally
   
   # Reload Prometheus
   sudo systemctl reload prometheus
   ```

### Increase GPU Utilization

**When**: p99 inference latency approaching 500ms SLA

**Options**:

**Option 1: GPU Upgrade (if available)**
```bash
# Install faster GPU (e.g., A100 -> H100)
# Requires: Service downtime ~30 min

# 1. Shutdown containers
docker-compose down

# 2. Physical GPU replacement
# 3. Restart containers
docker-compose up -d

# 4. Verify GPU visible
nvidia-smi
```

**Option 2: Model Optimization**
```bash
# Reduce model size or quantization
#  Change: llama2:70b -> llama2:7b-chat
#  Or: Use quantized version (int4, int8)

# Update docker-compose.yml
# Restart Ollama
docker-compose up -d ollama
```

**Option 3: Add Inference Queue**
```bash
# Implement request queueing at application level
# Batch requests, process in priority order
# Reduces latency variance
```

### Add System CPU/Memory

**When**: System CPU >75% sustained or memory >85%

**Procedure**:

1. **Check current usage pattern**
   ```bash
   # High CPU: Check top processes
   top -bn1 | head -20
   
   # High memory: Check docker stats
   docker stats
   ```

2. **Options**:
   - **Reduce workload**: fewer concurrent users
   - **Add more compute**: additional server
   - **Optimize code**: reduce ML model inference time

---

## Backup & Restore

### Incremental Backup (Hourly)

**Automated Process**:
```bash
# Runs automatically every hour via cron
# Command: rsync -av /mnt/nas-primary/ /mnt/nas-backup/

# Check backup status
tail /var/log/nas-backup.log

# Expected output: "Backup completed at HH:MM:SS"
```

### Full Backup (Daily)

**Automated Process**:
```bash
# Runs at 2 AM daily
# Command: tar czf /archive/nas-backup-$(date +%Y%m%d).tar.gz /mnt/nas-primary/

# Check size
du -sh /archive/nas-backup-*.tar.gz
```

### Manual Backup (On-Demand)

```bash
# Create manual backup
backup_file="/archive/nas-backup-manual-$(date +%Y%m%d-%H%M%S).tar.gz"
tar czf "$backup_file" /mnt/nas-primary/ 2>&1 | tee /tmp/backup.log

# Verify
echo "Backup size: $(du -sh $backup_file | cut -f1)"
echo "File count: $(tar tzf $backup_file | wc -l)"
```

### Restore from Backup

**Restore Single File**:
```bash
# Find file in backup
tar tzf /archive/nas-backup-20260413.tar.gz | grep "filename.ext"

# Extract to temporary location
mkdir /tmp/restore
tar xzf /archive/nas-backup-20260413.tar.gz -C /tmp/restore

# Copy back to NAS
cp /tmp/restore/mnt/nas-primary/filename.ext /mnt/nas-primary/
```

**Restore Full Directory**:
```bash
# WARNING: This overwrites current NAS data!

# Verify backup is valid
tar tzf /archive/nas-backup-20260413.tar.gz > /dev/null

# Backup current data first (BCP)
tar czf /archive/nas-backup-pre-restore.tar.gz /mnt/nas-primary/

# Restore from backup
sudo umount /mnt/nas-primary
sudo rm -rf /mnt/nas-primary
sudo mkdir -p /mnt/nas-primary

tar xzf /archive/nas-backup-20260413.tar.gz -C /

# Remount and verify
sudo mount /mnt/nas-primary
ls /mnt/nas-primary
```

---

## Disaster Recovery

### RTO/RPO Targets

| Disaster | RTO | RPO | Procedures |
|----------|-----|-----|-----------|
| Single GPU failure | <5 min | N/A | Container restart, workload shift to CPU |
| NAS latency | <5 min | <1 hour | Failover to secondary NAS, continue operations |
| NAS loss | <30 min | <1 hour | Restore from backup, verify checksums |
| Complete host failure | <2 hours | <24 hours | Redeploy IaC to new host, restore latest backup |

### GPU Failure Recovery

**Automatic**:
- Docker automatically restarts Ollama container on GPU error
- Application should retry inference with exponential backoff

**Manual Recovery**:
```bash
# If container doesn't auto-restart
docker restart ollama

# Monitor recovery
docker logs -f ollama

# Wait for models to load (30-60 seconds)
```

### NAS Failure Recovery

**Failover to Secondary**:
```bash
# 1. Detect primary NAS down
- Prometheus alerts "NASMountPointDown"  
- Pager notification sent to on-call

# 2. Manual failover (if backup not automatic)
sudo cp /etc/fstab /etc/fstab.backup

# Edit fstab: change 192.168.168.10 to 192.168.168.11
sudo sed -i 's/192.168.168.10/192.168.168.11/g' /etc/fstab

# 3. Remount NAS
sudo umount /mnt/nas-primary
sudo mount /mnt/nas-primary

# 4. Verify data accessible
ls /mnt/nas-primary

# 5. Restore primary NAS
# Contact storage team to investigate primary failure
# Once fixed, switch back to primary
```

### Data Restoration from Backup

```bash
# 1. Detect data corruption or loss
# Alert: "NASCapacityCritical" or manual detection

# 2. Identify last good backup
ls -lht /archive/nas-backup-*.tar.gz

# 3. Verify backup integrity
tar tzf /archive/nas-backup-20260413.tar.gz > /dev/null
echo "Backup valid: OK"

# 4. Restore from backup
# See "Restore from Backup" section above

# 5. Verify file integrity
# Compare checksums if available: md5sum -c backup.md5
```

### Complete Host Failure

**If 192.168.168.31 becomes unavailable**:

```bash
# 1. Redeploy using IaC from feat-phase-10 branch
git checkout feat/phase-10-on-premises-optimization-final

# 2. Configure new target host
export DEPLOY_HOST=192.168.168.32  # new host
export DEPLOY_SSH_KEY=~/.ssh/akushnir

# 3. Run Terraform

cd terraform/192.168.168.31/
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply

# 4. Wait for deployment complete (~30 min)

# 5. Restore latest backup
tar xzf /archive/nas-backup-latest.tar.gz -C / --strip-components=2

# 6. Verify services operational
./scripts/deployment-validation-31.sh

# 7. Restore DNS/routing if necessary
# Update: /etc/hosts or DNS records to point to new IP
```

---

## On-Call Escalation

### Who to Contact

| Issue | First Responder | Secondary | Escalation |
|-------|-----------------|-----------|-----------|
| GPU failure | DevOps (on-call) | Hardware team | CTO |
| NAS down | Storage team | DevOps | VP Ops |
| Ollama timeout | ML Engineer | DevOps | ML Lead |
| Code-Server crash | DevOps | Backend team | VP Eng |
| Data loss | Storage admin | DevOps | Security |
| Complete outage | Incident commander | All teams | Executive sponsor |

### Escalation Time SLAs

- **P1 (Complete outage)**: Escalate immediately, target resolution <2 hours
- **P2 (Degraded)**: Escalate after 15 minutes, target <4 hours
- **P3 (Minor)**: No escalation required, target <24 hours

### Incident Communication

1. **Alert received**: Automated notification to on-call
2. **Investigation** (5 min): Gather logs, run diagnostics
3. **Initial response** (15 min): Send status update to stakeholders
4. **Escalation** (15-30 min): If not resolved, escalate to next level
5. **Resolution**: Update status, document root cause
6. **Post-incident**: Incident review within 48 hours

---

**Last Updated**: April 13, 2026  
**Next Review**: July 13, 2026 (quarterly)

