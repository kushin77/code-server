# Comprehensive Logging Pipeline to GitHub Issues — Implementation Guide
# Phase 22+ | Infrastructure Observability & Incident Automation
# ════════════════════════════════════════════════════════════════════════════════════════════

## Overview

This comprehensive logging pipeline automatically collects logs from all infrastructure layers and converts them into GitHub issues for tracking and resolution.

### Architecture

```
Bare Metal Hosts
├── Kernel Logs (journalctl)
├── System Logs (/var/log)
└── Docker Container Logs (docker logs)
        ↓
    Promtail (Log Shipper)
        ↓
    Loki (Log Aggregation)
        ↓
    Error Triage Engine (Pattern Detection)
        ↓
    GitHub Issues (Automated Tracking)

Terraform
├── Apply/Plan Logs
└── State Changes
        ↓
    Terraform Log Collector
        ↓
    Loki
        ↓
    GitHub Issues

HAProxy
├── Failover Events
├── Backend Status
└── Health Check Results
        ↓
    HAProxy Failover Logger
        ↓
    Loki + GitHub Issues

Kubernetes (if deployed)
├── Pod Logs
├── Container Events
└── Resource Events
        ↓
    K8s Log Aggregator
        ↓
    Loki
        ↓
    GitHub Issues
```

---

## Components

### 1. Error Triage Engine (`scripts/error-triage-engine.sh`)

**Purpose**: Detects error patterns in Loki and creates GitHub issues

**Features**:
- Queries Loki for ERROR/FATAL level logs
- Groups similar errors using pattern clustering
- Creates/updates GitHub issues with context
- Tracks error lifecycle (new → investigating → resolved)
- SQLite database for deduplication

**Usage**:
```bash
# Single run
./scripts/error-triage-engine.sh

# Daemon mode (continuous monitoring)
./scripts/error-triage-engine.sh --daemon --interval 300
```

**Database Schema**:
- `error_patterns`: Unique error patterns, occurrence count, GitHub issue link
- `error_occurrences`: Individual error occurrences with source job/pod

**GitHub Labels**: `error-triage`, `P1`, `automated`

---

### 2. Terraform Log Collector (`scripts/observability/terraform-log-collector.sh`)

**Purpose**: Captures Terraform apply/plan/destroy logs and ships to Loki

**Features**:
- Parses Terraform output in real-time or from file
- Detects error patterns (apply failures, validation errors)
- Creates GitHub issues for critical failures
- Supports stream mode (pipes terraform command output)
- Tracks operation type (apply, plan, destroy, init)

**Usage**:
```bash
# From file
./terraform-log-collector.sh --operation apply --log-file /tmp/tf.log

# Stream mode (pipe terraform output)
TERRAFORM_LOG=DEBUG terraform apply | ./terraform-log-collector.sh --stream --operation apply
```

**Error Detection**:
- Apply failures
- Validation errors
- Resource conflicts
- Network timeouts (503, 502, 504, connection refused)
- Deprecated warnings

**GitHub Labels**: `infrastructure`, `terraform`, `P1`

---

### 3. HAProxy Failover Event Logger (`scripts/observability/haproxy-failover-event-logger.sh`)

**Purpose**: Monitors HAProxy stats and logs failover events to Loki and GitHub

**Features**:
- Polls HAProxy stats API every 30 seconds (configurable)
- Detects failover transitions (primary DOWN → replica UP)
- Detects failback transitions (recovery)
- Logs full context to Loki with timestamps
- Creates GitHub incidents for failovers
- Tracks failover duration and RTO

**Usage**:
```bash
# Single check
./haproxy-failover-event-logger.sh

# Daemon mode
./haproxy-failover-event-logger.sh --daemon --interval 10

# Custom HAProxy URL
./haproxy-failover-event-logger.sh --haproxy-url http://haproxy:8404/haproxy-stats;csv
```

**Failover Detection**:
- **Triggered**: Primary DOWN, Replica UP
- **Recovered**: Primary recovers and back to active
- **Degraded**: Primary or Replica unhealthy

**GitHub Labels**: `infrastructure`, `failover`, `incident`, `P1`

---

### 4. System Log Shipper (`scripts/observability/system-log-shipper.sh`)

**Purpose**: Ships host and container logs from /var/log and Docker to Loki

**Features**:
- Collects kernel logs from journalctl
- Collects system logs from /var/log
- Collects Docker container stderr/stdout
- Batches logs for efficiency (100 log lines per request)
- Detects kernel panics and critical errors
- Creates GitHub issues for critical system events

**Usage**:
```bash
# Collect once
./system-log-shipper.sh

# Follow mode (stream kernel logs)
./system-log-shipper.sh --follow --daemon

# Custom log directory
./system-log-shipper.sh --log-dir /var/log --daemon
```

**Log Sources**:
- Kernel logs: `journalctl --no-pager -u kernel`
- Docker logs: `docker logs <container>`
- System logs: `/var/log/syslog`, `/var/log/auth.log`, `/var/log/kern.log`

**Critical Patterns**:
- Kernel panics
- System OOM events
- Docker daemon crashes
- Authentication failures

**GitHub Labels**: `infrastructure`, `system`, `P0` (for critical events)

---

### 5. Kubernetes Log Aggregator (`scripts/observability/k8s-container-log-aggregator.sh`)

**Purpose**: Aggregates Kubernetes pod logs and container events to Loki

**Features**:
- Collects logs from all pods in specified namespaces
- Monitors Kubernetes events (restarts, crashes)
- Detects CrashLoopBackOff, OOMKilled, ImagePullBackOff
- Ships logs with pod/namespace/container labels
- Creates GitHub issues for pod crashes

**Usage**:
```bash
# Collect once
./k8s-container-log-aggregator.sh

# Daemon mode (default namespaces: default, kube-system, monitoring)
./k8s-container-log-aggregator.sh --daemon --interval 30

# Custom namespaces
./k8s-container-log-aggregator.sh --daemon --namespaces "default,app,database"
```

**Pod Event Detection**:
- **CrashLoopBackOff**: Container exits immediately (check logs)
- **OOMKilled**: Pod exceeded memory limit (increase resources)
- **ImagePullBackOff**: Image not found or pull failed (check image name)
- **ErrImagePull**: Similar to above (check image registry access)

**GitHub Labels**: `infrastructure`, `kubernetes`, `P1` (pod crashes)

---

### 6. Log-to-GitHub Bridge (`scripts/observability/log-to-github-bridge.sh`)

**Purpose**: Central bridge that reads from Loki and creates GitHub issues

**Features**:
- Unified query interface for all log sources
- Groups similar errors from multiple sources
- Deduplicates issues (1 issue = 1 error pattern)
- Provides flexible querying (by job, severity, component)
- Tracks issue links in SQLite database

**Usage**:
```bash
# Query specific job
./log-to-github-bridge.sh --query '{job="terraform"}' --severity ERROR

# Query by component
./log-to-github-bridge.sh --query '{component="database"}' --severity WARN

# Daemon mode (queries every 10 minutes)
./log-to-github-bridge.sh --daemon --interval 600
```

**Query Examples**:
```bash
# All errors
--query '{level="ERROR"}'

# Specific service
--query '{job="code-server"}'

# Multiple services
--query '{job=~"code-server|caddy|redis"}'

# Kubernetes pods
--query '{namespace="production", pod_status="CrashLoopBackOff"}'
```

---

## Installation & Setup

### 1. One-Shot Installation

```bash
# Run the comprehensive setup script
sudo bash scripts/observability/comprehensive-log-pipeline-setup.sh --install

# Dry-run (preview without making changes)
sudo bash scripts/observability/comprehensive-log-pipeline-setup.sh --install --dry-run
```

This creates:
- Systemd services for all collectors
- Promtail configuration
- Validates Loki, Prometheus, and GitHub connectivity

### 2. Verify Installation

```bash
# Check services
sudo systemctl status error-triage.service
sudo systemctl status haproxy-failover.service
sudo systemctl status log-github-bridge.service

# View logs
sudo journalctl -u error-triage -f
sudo journalctl -u haproxy-failover -f
sudo journalctl -u log-github-bridge -f
```

### 3. Environment Configuration

Set environment variables for all services:

```bash
export LOKI_ENDPOINT="http://loki:3100"
export PROMETHEUS_ENDPOINT="http://prometheus:9090"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export GITHUB_REPO="kushin77/code-server"
export PRIMARY_HOST="192.168.168.31"
export REPLICA_HOST="192.168.168.42"
export HAPROXY_STATS_URL="http://localhost:8404/haproxy-stats;csv"
export HAPROXY_USER="admin"
export HAPROXY_PASSWORD="admin123"
```

For systemd services, add to `/etc/systemd/system/<service>.service`:
```ini
[Service]
Environment="LOKI_ENDPOINT=http://loki:3100"
Environment="GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
...
```

---

## Log Flow Examples

### Example 1: Terraform Apply Failure

```
1. User runs: terraform apply
2. Terraform Log Collector captures output
3. Error detected: "Error: aws_instance.web_server: error creating instance"
4. Sent to Loki: job=terraform, level=ERROR, operation=apply
5. Error Triage Engine queries Loki every 5 minutes
6. Pattern detected 3+ times
7. GitHub Issue created: "[AUTO-TRIAGE] Error: aws_instance.web_server..."
8. Issue assigned to kushin77, labeled P1, infrastructure, terraform
```

### Example 2: Primary Host Failover

```
1. Primary host (192.168.168.31) experiences connectivity issue
2. HAProxy health check fails 3 times (30 seconds)
3. HAProxy redirects traffic to Replica (192.168.168.42)
4. HAProxy Failover Logger detects transition
5. Event logged to Loki: job=haproxy, event_type=triggered, RTO=~30s
6. GitHub Issue created: "🚨 INCIDENT: Automatic Failover Triggered"
7. Incident assigned, links to primary host status page
8. When primary recovers, failback detected
9. Follow-up issue created: "✅ Failover Recovered: Primary Restored"
```

### Example 3: Kubernetes Pod CrashLoopBackOff

```
1. K8s Container Log Aggregator polling namespaces every 30 seconds
2. Detects event: pod "api-server" status CrashLoopBackOff
3. Gets pod logs: "panic: database connection failed"
4. Sent to Loki: job=kubernetes, namespace=production, pod=api-server
5. Error Triage Engine detects pattern
6. GitHub Issue created: "🔴 CRITICAL: Kubernetes Pod CrashLoopBackOff in production"
7. Issue includes: pod status, logs, suggested investigation steps
8. Links to: kubectl commands, runbooks, related incidents
```

---

## GitHub Issue Examples

### Terraform Error Issue

**Title**: `[AUTO-TRIAGE] Error: aws_instance.web_server: error creating instance`

**Labels**: `error-triage`, `P1`, `automated`, `infrastructure`

**Body**:
```markdown
## Automated Error Triage Report

**Severity**: P1 (Automated Detection)
**Detected**: 2026-04-22 14:30:45 UTC
**Occurrence Count**: 3

### Error Pattern
Error: aws_instance.web_server: error creating instance

### Stack Trace Context
Creating aws_instance.web_server...
Error: Error creating instance...

### Detection Metadata
- **System**: Automated Error Triage Engine
- **Source**: Terraform Apply Logs
- **Threshold**: Triggered at 3+ occurrences
```

### Failover Incident Issue

**Title**: `🚨 INCIDENT: Automatic Failover Triggered`

**Labels**: `infrastructure`, `failover`, `incident`, `P1`

**Body**:
```markdown
## Failover Event Report

**Event Type**: triggered
**Timestamp**: 2026-04-22 14:25:00 UTC
**Primary Status**: DOWN
**Replica Status**: UP
**Duration**: 28ms

### Details
- **Primary Host**: 192.168.168.31
- **Replica Host**: 192.168.168.42
- **Failover Detection**: Automatic HAProxy health check
- **Service Impact**: Minimal (HAProxy redirected traffic automatically)

### Metrics
- **RTO**: 28ms
- **Health Check Interval**: 10s
- **Failover Threshold**: 3 consecutive failures
```

---

## Troubleshooting

### Services not starting

```bash
# Check service status
sudo systemctl status error-triage.service

# View service logs
sudo journalctl -u error-triage -n 50

# Restart service
sudo systemctl restart error-triage.service
```

### Loki not accessible

```bash
# Test Loki connectivity
curl -s http://loki:3100/ready

# Check Loki container
docker-compose ps loki
docker-compose logs loki

# Verify network
docker network ls
docker network inspect code-server-enterprise_monitoring
```

### GitHub issues not creating

```bash
# Verify GitHub token
curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  https://api.github.com/user

# Check rate limit
curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  https://api.github.com/rate_limit | jq .
```

### No logs appearing in Loki

```bash
# Check Promtail
docker-compose logs promtail

# Verify log shipping
docker-compose exec loki loki-logcli query '{job="code-server"}'

# Check Docker daemon logging
docker inspect <container> | grep -A 5 LogDriver
```

---

## Performance & Scaling

### Tuning Parameters

**Error Triage Engine**:
- `CHECK_INTERVAL`: 300 seconds (5 min) - balance between CPU and freshness
- `MIN_OCCURRENCE_THRESHOLD`: 3 - raise to reduce noise, lower for sensitivity
- `ERROR_RETENTION_DAYS`: 30 - balance between storage and history

**HAProxy Failover Logger**:
- `CHECK_INTERVAL`: 10 seconds - must be < HAProxy failover threshold
- State file updates only on transitions (no continuous writes)

**System Log Shipper**:
- `BATCH_SIZE`: 100 log lines - balance batch efficiency vs. latency
- Reads last 1000 lines from each log file (avoid re-shipping)

**Log-to-GitHub Bridge**:
- `CHECK_INTERVAL`: 600 seconds (10 min) - GitHub API rate limit friendly
- SQLite deduplication prevents duplicate issues

### Scalability Notes

- All scripts are stateless (except for state tracking files)
- Can run on multiple hosts with central Loki
- Database files are not shared (no locking needed)
- Safe to run multiple instances of same script

---

## Operational Runbook

### Daily Checks

```bash
# Check service health
for svc in error-triage haproxy-failover log-github-bridge system-log-shipper; do
  systemctl is-active --quiet "$svc" || echo "ALERT: $svc is down"
done

# Check recent issues created
gh issue list --repo kushin77/code-server --label automated --state open
```

### Issue Management

```bash
# Find related issues
gh issue list --repo kushin77/code-server --label error-triage --state open

# Close resolved issue
gh issue close <number> --repo kushin77/code-server --comment "Verified fix in commit abc123"

# Bulk label
gh issue list --repo kushin77/code-server --label error-triage --json number -q '.[] | .number' | \
  xargs -I {} gh issue edit {} --repo kushin77/code-server --add-label "monitoring"
```

### Incident Response

```bash
# Find all failover incidents (last 24 hours)
gh issue list --repo kushin77/code-server --label failover --state open --search "updated:>=$(date -u -d '1 day ago' +%Y-%m-%d)"

# Get incident details
gh issue view <number> --repo kushin77/code-server

# Create incident response task
gh issue create --repo kushin77/code-server \
  --title "INC-001: Post-mortem for failover at 2026-04-22 14:25" \
  --body "Root cause: ... Preventive measures: ..." \
  --label incident,postmortem
```

---

## Links & References

- **Loki**: http://localhost:3100/explore
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000
- **GitHub Repo**: https://github.com/kushin77/code-server/issues
- **Error Triage Engine**: [error-triage-engine.sh](../error-triage-engine.sh)
- **Comprehensive Setup**: [comprehensive-log-pipeline-setup.sh](./comprehensive-log-pipeline-setup.sh)

---

**Status**: ✅ Production Ready (Phase 22+)  
**Last Updated**: April 22, 2026  
**Maintainer**: @kushin77  
**Runbook Version**: 1.0.0
