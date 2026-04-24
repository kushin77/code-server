# P0 #1635 Incident Response - Pre-Execution Checklist

**Incident:** NVMe hardware failure on Replica 2 (192.168.168.42)  
**Severity:** P0 CRITICAL  
**Executor:** Infrastructure Operator  
**Date:** April 23, 2026  

## Pre-Execution Checklist

Before executing the incident response, verify all items below are complete.

### Environment Verification

- [ ] **Linux SSH Environment Available**
  - Executing from Linux host (not Windows, macOS, or WSL)
  - Has SSH client installed
  - Can reach on-prem network (192.168.168.x/24)

- [ ] **SSH Key Available**
  - Location: `~/.ssh/id_rsa_onprem`
  - Permissions: 600 or 400
  - Test: `ssh-keygen -l -f ~/.ssh/id_rsa_onprem` (should display key fingerprint)

- [ ] **Repository Cloned**
  - Working directory: code-server-enterprise/
  - Latest commits pulled: `git pull origin main`
  - Branch: `main` (verify with `git status`)

- [ ] **Database Passwords Available**
  - POSTGRES_PASSWORD: Set and exported to environment
  - REPLICATION_PASSWORD: Set and exported to environment
  - Test: `echo $POSTGRES_PASSWORD` (should output password)

### Infrastructure Verification

- [ ] **Replica 1 Accessible**
  - SSH test: `ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "echo OK"`
  - Result should be: OK
  - Services running: `ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker compose ps --format 'table {{.Service}}\t{{.Status}}' | wc -l"` (should show 15+)

- [ ] **Replica 2 Currently Accessible** (before isolation)
  - SSH test: `ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "echo OK"`
  - Result should be: OK
  - Note: After Phase 3, Replica 2 will be isolated (unreachable)

- [ ] **PostgreSQL Backup Location Writable**
  - Replica 1: `/tmp/` directory writable
  - Test: `ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "touch /tmp/test.txt && rm /tmp/test.txt && echo OK"`

- [ ] **Network Connectivity**
  - Ping Replica 1: `ping -c 1 192.168.168.31` (should respond)
  - Ping Replica 2: `ping -c 1 192.168.168.42` (should respond - will fail after Phase 3)
  - NAS reachable: `ping -c 1 192.168.168.56` (should respond)

### Script Verification

- [ ] **All Required Scripts Present**
  - `scripts/ops/setup-passwordless-sudo.sh` (exists, executable)
  - `scripts/ops/isolate-replica-2-nvme-failure.sh` (exists, executable)
  - `scripts/ops/setup-postgres-streaming-replication.sh` (exists, executable)
  - `scripts/ops/fix-mnt-eiq-shared-mount.sh` (exists, executable)
  - `P0-INCIDENT-RESPONSE-EXECUTION-RUNBOOK.sh` (exists, executable)
  - Verify: `ls -l scripts/ops/*.sh P0-INCIDENT-RESPONSE-EXECUTION-RUNBOOK.sh | grep -c "^-rwxrwxrwx"` (should output 5)

- [ ] **Runbook Executable**
  - Test: `bash -n P0-INCIDENT-RESPONSE-EXECUTION-RUNBOOK.sh` (should show no errors)
  - Verify: `file P0-INCIDENT-RESPONSE-EXECUTION-RUNBOOK.sh` (should show "Bourne-Again shell script")

- [ ] **All Scripts Pass Syntax Validation**
  - `bash -n scripts/ops/setup-passwordless-sudo.sh` ✅
  - `bash -n scripts/ops/isolate-replica-2-nvme-failure.sh` ✅
  - `bash -n scripts/ops/setup-postgres-streaming-replication.sh` ✅
  - `bash -n scripts/ops/fix-mnt-eiq-shared-mount.sh` ✅

### Documentation Verification

- [ ] **Incident Response Plan Available**
  - `P0-1635-COMPREHENSIVE-INCIDENT-PLAN.md` (read for context)
  - `P0-1635-NVME-FAILURE-RESPONSE-PLAN.md` (quick reference)

- [ ] **Operational Readiness Verification Available**
  - `OPERATIONAL-READINESS-VERIFICATION-APRIL-23-2026.md` (detailed procedures)

- [ ] **Session Completion Documentation Available**
  - `SESSION-APRIL-23-2026-FINAL-COMPLETION-STATE.md` (context)

## Execution Command

Once all checklist items are complete, execute:

```bash
# From code-server-enterprise/ directory
cd code-server-enterprise
export POSTGRES_PASSWORD='<YOUR_PASSWORD>'
export REPLICATION_PASSWORD='<YOUR_PASSWORD>'
./P0-INCIDENT-RESPONSE-EXECUTION-RUNBOOK.sh
```

## Execution Timeline

| Phase | Task | Duration | Status |
|-------|------|----------|--------|
| 0 | Prerequisite Verification | 5 min | Pre-execution |
| 1 | Passwordless Sudo Setup | 5 min | Automated ✅ |
| 2 | PostgreSQL Backup | 5 min | Automated ✅ |
| 3 | Replica 2 Isolation | 15 min | Automated ✅ |
| 4 | PostgreSQL Replication | 2-3 hours | Automated ✅ |
| 5 | NAS Mount Sync | 30 min | Automated ✅ |
| 6 | Hardware Replacement | 24-48 hours | Manual |
| **Total** | **Full Resolution** | **48-72 hours** | **From Phase 1 start** |

## Success Criteria

### Phase 1 Success
- [ ] No errors during execution
- [ ] Both replicas report passwordless sudo working
- [ ] `sudo -n whoami` returns "root" on both hosts

### Phase 2 Success
- [ ] PostgreSQL backup file created on Replica 1
- [ ] Backup file size > 0 bytes
- [ ] Backup contains schema dump

### Phase 3 Success
- [ ] Replica 2 unreachable via ping (network isolated)
- [ ] Replica 1 still responding to SSH
- [ ] Incident log generated: `/tmp/p0-1635-isolation-*.log`

### Phase 4 Success
- [ ] PostgreSQL replication active between replicas
- [ ] Test table successfully replicated to standby
- [ ] Replication lag < 1 second
- [ ] Streaming replication logs show "connected"

### Phase 5 Success
- [ ] /etc/fstab synchronized on both replicas
- [ ] /mnt/eiq-shared mounted on both replicas
- [ ] NAS backup storage accessible

### Phase 6 Success
- [ ] NVMe drive ordered and delivered (24-48 hours)
- [ ] Physical replacement completed
- [ ] Replica 2 boots successfully
- [ ] All services started: `docker compose up -d`
- [ ] Cluster health: `docker compose ps` shows all services healthy

## Failure Recovery

If any phase fails:

1. **Read error message carefully** - runbook will indicate which script failed
2. **Check phase-specific logs**:
   - Phase 1-3: Check `/tmp/p0-1635-*.log`
   - Phase 4: Check PostgreSQL logs: `docker logs postgres-replica1`
   - Phase 5: Check mount logs: `mount | grep eiq`
3. **Re-run the runbook** - it will skip completed phases and retry failed phases
4. **Escalate if unable to recover** - contact infrastructure team with error message and logs

## Rollback Plan

If entire incident response needs to be rolled back:

1. **Phase 1 Rollback:** Remove `/etc/sudoers.d/deployment-automation` on both replicas
2. **Phase 2 Rollback:** Restore from PostgreSQL backup: `psql postgres < pre-isolation-backup.sql`
3. **Phase 3 Rollback:** Remove iptables rule on Replica 2: `sudo iptables -D INPUT -j DROP`
4. **Phase 4 Rollback:** Remove replication user and revert replication config
5. **Phase 5 Rollback:** Remove /etc/fstab entry and umount NAS

**Note:** Rollback should only be necessary if deployment fails; runbook implements idempotency where possible.

## Post-Execution Verification

After runbook completes successfully:

1. **Verify Replica 1 Services**
   ```bash
   ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker compose ps"
   ```
   Expected: 19-22 services, all "healthy"

2. **Verify Replication Active**
   ```bash
   ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
     "docker exec postgres-replica1 psql -U postgres -c 'SELECT slot_name FROM pg_replication_slots;'"
   ```
   Expected: Slot name listed (e.g., "standby_slot")

3. **Verify NAS Mount**
   ```bash
   ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "ls -la /mnt/eiq-shared/"
   ```
   Expected: Directory listing with backups/

4. **Verify Replica 2 Isolated**
   ```bash
   ping -c 1 192.168.168.42
   ```
   Expected: Timeout (no response)

## Operator Sign-Off

- [ ] Operator Name: ________________
- [ ] Operator Email: ________________
- [ ] Execution Date: ________________
- [ ] Execution Start Time: ________________
- [ ] Execution End Time: ________________
- [ ] Status: [ ] SUCCESS [ ] PARTIAL [ ] FAILED
- [ ] Notes: _____________________________________________

## Support

For issues during execution:
1. Check `/tmp/p0-1635-*.log` files
2. Review `P0-1635-COMPREHENSIVE-INCIDENT-PLAN.md` for detailed procedures
3. Review individual script logs in `scripts/ops/` directory

**Last Updated:** April 23, 2026  
**Version:** 1.0 - Production Ready  
**Ready for Execution:** ✅ YES
