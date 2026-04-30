# Phase 2b Pre-Execution Environment Verification

**Version:** 1.0  
**Purpose:** Quick pre-execution checklist (Day 0 - before Week 1 Day 1)  
**Status:** Critical verification  
**Duration:** 30 minutes  

---

## Overview

Quick 15-item checklist to verify Phase 2b infrastructure is truly ready for execution before Week 1 Day 1. This is your "go/no-go" gate for proceeding with PR creation.

---

## Pre-Execution Checklist (Run on Day 0)

### Infrastructure Verification

- [ ] **PRIMARY Host SSH Access**
  ```bash
  ssh -o ConnectTimeout=5 root@$PRIMARY_HOST "echo 'PRIMARY OK'"
  ```
  Expected: "PRIMARY OK"  
  If failed: Check IP, firewall, SSH key permissions

- [ ] **REPLICA Host SSH Access**
  ```bash
  ssh -o ConnectTimeout=5 root@$REPLICA_HOST "echo 'REPLICA OK'"
  ```
  Expected: "REPLICA OK"  
  If failed: Check IP, firewall, SSH key permissions

- [ ] **Docker Running on PRIMARY**
  ```bash
  ssh root@$PRIMARY_HOST "docker ps -q | wc -l"
  ```
  Expected: >= 50  
  If failed: Restart Docker or investigate container issues

- [ ] **Docker Running on REPLICA**
  ```bash
  ssh root@$REPLICA_HOST "docker ps -q | wc -l"
  ```
  Expected: >= 50  
  If failed: Restart Docker or investigate container issues

- [ ] **Database Replication Active**
  ```bash
  ssh root@$PRIMARY_HOST \
    "docker exec gitlab-postgresql psql -U postgres -t -c \
    'SELECT COUNT(*) FROM pg_replication_slots;' 2>&1"
  ```
  Expected: >= 1  
  If failed: Check replication configuration

- [ ] **Redis Connected**
  ```bash
  ssh root@$PRIMARY_HOST "docker exec gitlab-redis redis-cli PING"
  ```
  Expected: "PONG"  
  If failed: Check Redis container or configuration

- [ ] **GitLab API Responding**
  ```bash
  ssh root@$PRIMARY_HOST \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:8101/api/v4/version"
  ```
  Expected: "200"  
  If failed: Wait 30 seconds, try again; GitLab may still be loading

- [ ] **Disk Space Adequate**
  ```bash
  ssh root@$PRIMARY_HOST "df / | awk '/\// {print \$5}' | sed 's/%//'"
  ```
  Expected: < 80%  
  If failed: Clean up old data or expand disk

### Git & Code Verification

- [ ] **Current Branch: main**
  ```bash
  git rev-parse --abbrev-ref HEAD
  ```
  Expected: "main"  
  If failed: Checkout main branch first

- [ ] **Latest Code Pulled**
  ```bash
  git status
  ```
  Expected: "working tree clean"  
  If failed: Commit or stash changes

- [ ] **Phase 2b Scripts Present**
  ```bash
  ls -la scripts/ops/orchestrate-deployment.sh \
       scripts/ops/gcp-deploy.sh \
       scripts/ops/check-gitlab-compose-parity.sh
  ```
  Expected: All files exist  
  If failed: Pull latest code from main

- [ ] **Docker Compose Config Valid**
  ```bash
  docker-compose -f docker-compose.enterprise.yml config > /dev/null
  ```
  Expected: No errors  
  If failed: Check config file syntax

### Team & Environment Verification

- [ ] **Environment Variables Set**
  ```bash
  [ -n "$PRIMARY_HOST" ] && [ -n "$REPLICA_HOST" ] && echo "OK"
  ```
  Expected: "OK"  
  If failed: Export PRIMARY_HOST and REPLICA_HOST variables

- [ ] **Team Notifications Sent**
  - [ ] Slack channel created: #phase2b-staging
  - [ ] Team calendar blocked: Week 1-2
  - [ ] All team members: Review PHASE_2B_QUICK_START.md
  - [ ] Expected: 100% of team notified

- [ ] **Documentation Accessible**
  - [ ] All 14 Phase 2b docs available
  - [ ] Master Index accessible (PHASE_2B_MASTER_INDEX.md)
  - [ ] Week-by-week guide printed/bookmarked (PHASE_2B_WEEK_BY_WEEK_EXECUTION_GUIDE.md)
  - [ ] Expected: Team can reference all docs

---

## Quick Scoring

**13-15 items ✅:**  
✅ **PROCEED** - Infrastructure ready for Week 1 Day 1 execution  
→ Go to PHASE_2B_WEEK_BY_WEEK_EXECUTION_GUIDE.md  
→ Start Week 1 Day 1 tasks  

**11-12 items ⚠️:**  
⚠️ **CAUTION** - Fix missing items before proceeding  
→ Address failed items from checklist above  
→ Re-run verification (should take 5 minutes)  
→ Then proceed  

**< 11 items ❌:**  
❌ **HOLD** - Wait until critical issues resolved  
→ Investigate failed items  
→ Schedule recovery plan  
→ Re-test in 24 hours  
→ Then proceed  

---

## If Any Item Fails

### Troubleshooting Map

**SSH Access Failure:**
1. Verify IP addresses (check /etc/hosts or DNS)
2. Check SSH key permissions: `chmod 600 ~/.ssh/id_rsa`
3. Test ping: `ping -c 5 $PRIMARY_HOST`
4. Check firewall on target host: `iptables -L | grep 22`

**Docker Running Failure:**
1. SSH to host: `ssh root@$PRIMARY_HOST`
2. Check Docker: `docker ps`
3. If hung: `systemctl restart docker`
4. If still failing: Contact infrastructure team

**Database Replication Failure:**
1. Check PostgreSQL logs: `docker logs gitlab-postgresql | tail -20`
2. Verify replication config: `docker exec gitlab-postgresql psql -U postgres -c "\du"`
3. Check REPLICA connection: `ssh root@$REPLICA_HOST "nc -zv $PRIMARY_HOST 5432"`
4. Contact database specialist if not resolved

**GitLab API Failure:**
1. Wait 30 seconds - GitLab takes time to start
2. Check status: `ssh root@$PRIMARY_HOST "docker logs gitlab-main | tail -20"`
3. If still down: `ssh root@$PRIMARY_HOST "docker restart gitlab-main"`
4. Wait 2-3 minutes for startup

**Disk Space Failure:**
1. Identify large directories: `ssh root@$PRIMARY_HOST "du -sh /data/* | sort -h"`
2. Archive old artifacts: `docker exec gitlab-main gitlab-rake gitlab:cleanup:admin_verify`
3. If still insufficient: Stop GitLab, expand disk (GCP only), restart

**Environment Variable Failure:**
1. Set variables in your shell:
   ```bash
   export PRIMARY_HOST="192.168.168.31"
   export REPLICA_HOST="192.168.168.42"
   ```
2. Add to ~/.bashrc for persistence:
   ```bash
   echo 'export PRIMARY_HOST="192.168.168.31"' >> ~/.bashrc
   echo 'export REPLICA_HOST="192.168.168.42"' >> ~/.bashrc
   source ~/.bashrc
   ```

---

## When Ready to Proceed

✅ **All 13-15 items passing**

→ **Next Step:** PHASE_2B_WEEK_BY_WEEK_EXECUTION_GUIDE.md (Week 1, Day 1)

**Week 1 Day 1 Tasks:**
1. Team standup (announce Week 1-2 timeline)
2. Create GitHub PR (3 methods in GITHUB_PR_CREATION_GUIDE.md)
3. Request reviewers (2+ team leads)
4. Distribute documentation

---

## Time Estimate

- Quick run (with all passing): 15-20 minutes
- With 1-2 failures to fix: 30-45 minutes
- With major issues: 1-2 hours (may delay start)

---

## Pre-Execution Verification Log

```
Run Date: ________________
Run Time: ________________
Run By: ________________

Results:
  Infrastructure items: ____ / 8 ✅
  Git & Code items: ____ / 4 ✅
  Team & Environment items: ____ / 3 ✅
  Total: ____ / 15 ✅

Status: ✅ PROCEED / ⚠️ CAUTION / ❌ HOLD

Issues found:
_________________________________________________
_________________________________________________

Resolutions applied:
_________________________________________________
_________________________________________________

Final status for Week 1 Day 1: ✅ READY / ❌ NOT READY

Approved by: ________________ (Infrastructure Lead)
```

---

## Quick Links to Detailed Procedures

If multiple items fail, reference detailed procedures:
- **Infrastructure issues:** PHASE_2B_DEPLOYMENT_VALIDATION_PROCEDURES.md (Level 1-3)
- **Setup issues:** PHASE_2B_QUICK_START.md (Setup section)
- **SSH/connectivity:** PHASE_2B_GCP_DEPLOYMENT_READINESS.md (Section 3)
- **Docker/compose:** PHASE_2B_STAGING_DEPLOYMENT_CHECKLIST.md (Pre-deployment phase)

---

**Status:** ✅ READY FOR USE  
**Created:** April 30, 2026  
**Use Before:** Week 1 Day 1  
**Duration:** 30 minutes  

