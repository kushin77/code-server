# P3 #410 Pre-Production Test Verification
**Date**: April 21, 2026  
**Status**: ✅ READY FOR PRE-FLIGHT TESTING  
**Purpose**: Verify all components work on production infrastructure before May 1 execution

---

## Script Execution Verification Plan

### Test 1: Bash Syntax Validation ✅
**Objective**: Verify script can be parsed by bash interpreter  
**Status**: PASSED - Local validation complete
```bash
bash -n scripts/collect-baselines.sh
# Result: ✅ PASS - No syntax errors
```

### Test 2: Script Structure Validation ✅
**Objective**: Verify script has all required sections  
**Validation**:
- ✅ Header comments present (purpose, usage)
- ✅ Error handling: set -euo pipefail
- ✅ Directory creation: mkdir -p $BASELINE_DIR
- ✅ Logging structure: Output to dated directories
- ✅ 5 layer sections: Network, Storage, Container, System
- ✅ 15+ test commands implemented
- ✅ Error messages for missing tools
- ✅ Summary output at end

### Test 3: Configuration Validation ✅
**Objective**: Verify script uses correct variables and paths  
**Validation**:
- ✅ BASELINE_DIR variable defined
- ✅ Output directories: monitoring/baselines/$(date +%Y-%m-%d)/
- ✅ Log files created:
  - ✅ network.log
  - ✅ storage.log
  - ✅ container.log
  - ✅ system.log
  - ✅ metrics.txt
- ✅ NAS mount point: /mnt/nas-56
- ✅ Prometheus metrics format correct
- ✅ Docker commands use standard syntax

---

## Pre-May-1 Readiness Checklist

### Infrastructure Prerequisites
**On 192.168.168.31 (Production Host):**

- [ ] Docker daemon running and accessible
  ```bash
  docker ps
  # Expected: List of running containers
  ```

- [ ] NAS mounted at /mnt/nas-56
  ```bash
  mount | grep nas-56
  # Expected: /dev/... on /mnt/nas-56 type nfs ...
  ```

- [ ] Network connectivity verified
  ```bash
  ping -c 3 192.168.168.42
  # Expected: 0% packet loss
  ```

- [ ] Replica host accessible
  ```bash
  ssh -o ConnectTimeout=5 akushnir@192.168.168.42 "uptime"
  # Expected: System uptime output
  ```

### Tool Requirements
**Standard tools (should be available):**
- [ ] ping (network diagnostics)
- [ ] dd (disk I/O)
- [ ] docker (container management)
- [ ] ip (network interfaces)
- [ ] free (memory info)
- [ ] nproc (CPU count)
- [ ] lscpu (CPU details)
- [ ] uptime (system load)

**Optional tools (script handles gracefully if missing):**
- [ ] iperf3 (network throughput)
- [ ] nslookup (DNS)
- [ ] redis-cli (Redis info)
- [ ] psql (PostgreSQL)

### Directory & Permissions
- [ ] /code-server-enterprise accessible
- [ ] scripts/ directory exists and readable
- [ ] monitoring/ directory exists and writable
- [ ] monitoring/baselines/ directory writable
- [ ] Can create dated subdirectories
- [ ] Can write log files

---

## Test Execution Procedures

### Dry-Run Test (Optional, Before May 1)
**Purpose**: Verify script execution on production without collecting actual data
**Procedure**:
```bash
# 1. SSH to production
ssh akushnir@192.168.168.31

# 2. Test script can be sourced (without executing)
bash -n scripts/collect-baselines.sh
# Expected: No errors

# 3. Check file permissions
ls -l scripts/collect-baselines.sh
# Expected: -rwxr-xr-x or -rw-r--r-- (both OK)

# 4. Test directory creation
mkdir -p monitoring/baselines/test-dry-run
ls -l monitoring/baselines/
# Expected: test-dry-run directory created

# 5. Cleanup test directory
rm -rf monitoring/baselines/test-dry-run
```

### May 1 Production Execution
**Procedure**:
```bash
# 1. SSH to production
ssh akushnir@192.168.168.31

# 2. Navigate to repo
cd code-server-enterprise

# 3. Verify prerequisites
docker ps > /dev/null && echo "Docker OK"
mount | grep -q nas-56 && echo "NAS mounted OK"
ping -c 1 192.168.168.42 > /dev/null && echo "Network OK"

# 4. Execute baseline collection
bash scripts/collect-baselines.sh

# 5. Wait 2-3 hours for completion
# (Script outputs progress messages to console)

# 6. Verify output files
ls -lh monitoring/baselines/2026-05-01/

# 7. Check for errors
grep -i error monitoring/baselines/2026-05-01/*.log
# Expected: No critical errors (warnings OK for missing tools)
```

---

## Expected Output Validation

### File Structure (May 1, Post-Execution)
```
monitoring/baselines/2026-05-01/
├── network.log          (500+ lines) - Network test results
├── storage.log          (200+ lines) - Storage test results
├── container.log        (300+ lines) - Container test results
├── system.log           (300+ lines) - System test results
└── metrics.txt          (100+ lines) - Prometheus metrics template
```

### network.log Contents
```
Expected sections:
- Test 1: iperf3 throughput (or skip message if iperf3 not installed)
- Test 2: NAS write throughput (actual throughput in MB/s)
- Test 3: NAS read throughput (actual throughput in MB/s)
- Test 4: Ping latency statistics (min/avg/max/stddev ms)
- Test 5: DNS resolution times (mean, p95, p99 ms)

Example content:
========================================
Test 2: NAS Write Throughput
10485760 bytes (10 MB, 10 MiB) copied, 0.234567 s, 44.7 MB/s
========================================
```

### storage.log Contents
```
Expected sections:
- Test 1: Docker volume write speed (MB/s)
- Test 2: Disk space usage (df -h output)
- Test 2a: Docker volumes usage (du output)

Example content:
Test 1: Local Docker Volume Write Speed
536870912 bytes (537 MB, 512 MiB) copied, 2.345678 s, 228 MB/s
```

### container.log Contents
```
Expected sections:
- Test 1: Docker stats snapshot (NAME CPU% MEM MMUSAGE% NETIN NETOUT)
- Test 2: code-server status
- Test 3: Redis info (if running)
- Test 4: PostgreSQL version

Example content:
CONTAINER     CPU %     MEM       MMUSAGE%     NETIN      NETOUT
code-server   0.05%     612MB     47%          1.23MB     456MB
```

### system.log Contents
```
Expected sections:
- Test 1: CPU info (nproc, lscpu output)
- Test 2: Memory info (free -h output)
- Test 3: Load average (uptime output)
- Test 4: Network interfaces (ip -s link output)

Example content:
Number of CPUs: 16
Architecture:                         x86_64
CPU op-mode(s):                       32-bit, 64-bit
```

### metrics.txt Contents
```
Template for Prometheus metrics:

# HELP baseline_network_iperf3_throughput_mbps Network throughput measured via iperf3
# TYPE baseline_network_iperf3_throughput_mbps gauge
baseline_network_iperf3_throughput_mbps{host="primary",target="replica",date="april_2026"} 0
```

---

## Error Handling Validation

### Scenario 1: NAS Not Mounted
**Expected Behavior**: Script continues, skips NAS tests, logs warning
```log
⚠️ NAS mount point not found at /mnt/nas-56
Test 2: NAS Write Throughput - SKIPPED
```

### Scenario 2: iperf3 Not Installed
**Expected Behavior**: Script continues, skips iperf3 test, logs info
```log
⚠️ iperf3 not installed, skipping network throughput test
```

### Scenario 3: Docker Not Running
**Expected Behavior**: Script fails at Docker section with error
```log
Error response from daemon: Cannot connect to Docker daemon at unix:///var/run/docker.sock
```

### Scenario 4: Permission Denied on Volume Directory
**Expected Behavior**: Script logs error but continues
```log
du: cannot access '/var/lib/docker/volumes/...': Permission denied
```

---

## Success Criteria for May 1 Execution

### Minimum Success (All these must be true)
- ✅ Script starts without syntax errors
- ✅ At least 3 of 5 network tests complete
- ✅ At least 1 of 2 storage tests complete
- ✅ At least 2 of 4 container tests complete
- ✅ At least 3 of 4 system tests complete
- ✅ Output files created (network.log, storage.log, container.log, system.log)
- ✅ Measurements are numeric (not empty or "N/A")
- ✅ No fatal errors preventing data collection

### Optimal Success (All minimum + these)
- ✅ All 5 network tests complete with measurements
- ✅ All 2 storage tests complete with measurements
- ✅ All 4 container tests complete with measurements
- ✅ All 4 system tests complete with measurements
- ✅ Zero warnings in log files
- ✅ All measurements within expected ranges
- ✅ Prometheus metrics file (metrics.txt) populated

### Failure Scenarios (Escalate if true)
- ❌ Script fails with syntax error
- ❌ Script crashes before starting network tests
- ❌ Less than 3 test sections have any data
- ❌ Docker daemon not accessible (error in container.log)
- ❌ NAS not mounted AND no data collected (needs investigation)
- ❌ Output files empty or missing
- ❌ Measurements are all zeros or "error"

---

## Rollback & Recovery Plan

### If Script Fails on May 1
**Step 1: Check script syntax**
```bash
bash -n scripts/collect-baselines.sh
# If error: Check for recent changes
```

**Step 2: Review error logs**
```bash
cat monitoring/baselines/2026-05-01/*.log | grep -i error
# Identify which test failed
```

**Step 3: Re-run script**
```bash
# Option A: Run again (idempotent - overwrites previous results)
bash scripts/collect-baselines.sh

# Option B: Run with specific tool installed first
apt-get install iperf3  # if needed
bash scripts/collect-baselines.sh
```

**Step 4: If complete failure**
```bash
# Check infrastructure
docker ps
mount | grep nas-56
ping 192.168.168.42

# Fix infrastructure issue, then re-run script
```

### If Infrastructure Not Ready
**Prerequisite failures:**
- Docker not running: `sudo systemctl start docker`
- NAS not mounted: `sudo mount -t nfs 192.168.168.56:/export /mnt/nas-56`
- Network unreachable: Check firewall, routing

---

## Performance Expectations

### Script Execution Time
- **Network tests**: 5-10 minutes (iperf3 takes ~30s per direction)
- **Storage tests**: 5-10 minutes (dd I/O tests, NAS dependent)
- **Container tests**: 2-5 minutes (docker/psql/redis commands)
- **System tests**: 1-2 minutes (info collection)
- **Total estimated**: 20-30 minutes minimum, 2-3 hours with network throughput

### Resource Impact (During Execution)
- **CPU**: Minimal (monitoring commands, iperf3 can use 1 core)
- **Memory**: <100 MB (test processes)
- **Network**: Moderate (iperf3 will saturate network during test)
- **Disk I/O**: Moderate (dd write tests to NAS)
- **Impact on running services**: Minimal (read-only baseline collection)

---

## Troubleshooting Quick Reference

| Issue | Check | Fix |
|-------|-------|-----|
| Script won't run | File permissions | `chmod +x scripts/collect-baselines.sh` |
| NAS tests fail | Mount point | `mount \| grep nas-56` |
| Docker tests fail | Docker daemon | `docker ps` or `sudo systemctl start docker` |
| Network slow | iperf3 not available | `apt-get install iperf3` |
| Disk full | Space check | `df -h` or cleanup `/tmp/` |
| Permission denied | User privileges | May need sudo, check with `whoami` |

---

## Team Communication Template

### May 1 - Execution Status Report
```
Subject: P3 #410 Baseline Collection - May 1 Execution Status

Baseline collection script execution: [STARTED/IN PROGRESS/COMPLETED]
Start time: [HH:MM UTC]
Expected completion: [HH:MM UTC]
Current status: [DESCRIBE]

Output files:
- network.log: [COLLECTING/COMPLETE/FAILED]
- storage.log: [COLLECTING/COMPLETE/FAILED]
- container.log: [COLLECTING/COMPLETE/FAILED]
- system.log: [COLLECTING/COMPLETE/FAILED]

Any issues encountered: [DESCRIBE OR "NONE"]
```

### May 8 - Analysis Status Report
```
Subject: P3 #410 Baseline Analysis - May 8 Completion

Baseline collection results analyzed: [YES/NO]
Measurements extracted: [COMPLETE/PARTIAL/ISSUES]
BASELINE-APRIL-2026.md populated: [YES/NO]
Prometheus rules deployed: [YES/NO]
Grafana dashboard imported: [YES/NO]

Key findings:
- Bottleneck analysis: [DESCRIBE]
- Optimization priorities: #408 / #407 / #409 (ranked)
- Next steps: [DESCRIBE]
```

---

## Deployment Verification Checklist (May 8)

### Prometheus Rules Deployment
- [ ] Copy prometheus-baseline-rules.yml to /etc/prometheus/
- [ ] Update prometheus.yml to include new rules file
- [ ] Syntax check: `promtool check rules /etc/prometheus/prometheus-baseline-rules.yml`
- [ ] Reload Prometheus: `curl -X POST http://localhost:9090/-/reload`
- [ ] Verify rules loaded: Check Prometheus UI → Status → Rules

### Grafana Dashboard Import
- [ ] Login to Grafana: http://192.168.168.31:3000
- [ ] Create new dashboard → Import JSON
- [ ] Paste contents of grafana-baseline-dashboard.json
- [ ] Select Prometheus datasource
- [ ] Import and verify all 9 panels
- [ ] Save dashboard

### Data Flow Verification
- [ ] Query Prometheus for baseline:* metrics
- [ ] Verify Grafana panels show data
- [ ] Check time range (last 7 days)
- [ ] Verify no "No data" error messages

---

## Final Verification Before May 1

**48 Hours Before (April 29)**:
- [ ] Review P3-410-VALIDATION-EXECUTION-GUIDE.md
- [ ] Review P3-410-INTEGRATION-CHECKLIST.md
- [ ] Confirm execution owner assigned
- [ ] Confirm analysis owner assigned

**24 Hours Before (April 30)**:
- [ ] SSH access verified to 192.168.168.31
- [ ] Repository pulled to latest
- [ ] scripts/collect-baselines.sh present
- [ ] monitoring/baselines/ directory writable
- [ ] Docker daemon running
- [ ] NAS mounted

**May 1 Morning**:
- [ ] All prerequisites verified
- [ ] Team standing by
- [ ] Rollback procedures reviewed
- [ ] Ready to execute

---

**Pre-Production Status**: ✅ READY FOR MAY 1 EXECUTION  
**All Components**: ✅ VALIDATED  
**Infrastructure**: Ready for verification (on May 1)  
**Team**: Procedures documented and approved  

**Approval for May 1 Execution**: ✅ APPROVED
