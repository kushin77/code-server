# Health Checks & Automatic Failover (Phase 7d-003)

## Status: ACTIVE (Phase 7d Implementation)

This document describes the automated health monitoring and failover system for code-server High Availability.

## Overview

A robust health monitoring and automatic recovery system ensures High Availability (HA) and minimizes downtime for the on-prem environment.

### Components

1. **`health-check.sh`**: Continuous health monitoring of all infrastructure (Postgres, Redis, HAProxy) and application services (code-server, Prometheus, Grafana).
2. **`health-recover.sh`**: Automatic service recovery using backoff and max-restart policies.
3. **`automatic-failover.sh`**: Automated failover between Primary and Replica nodes based on HAProxy backend health status.

## Installation and Setup

### Prerequisites
- Docker & Docker Compose.
- HAProxy 2.8 (installed in Phase 7d-002).
- GitHub CLI (`gh`) for incident reporting.

### Step 1: Health Check Script Setup
Run the health check initialization script:
```bash
chmod +x scripts/health/*.sh
./scripts/health/health-check.sh
```

### Step 2: Systemd Integration (Production Only)
On the production host (primary), configure health checks as a systemd timer.

**Location**: `/etc/systemd/system/health-check.timer`
**Run every**: 30 seconds

```ini
[Unit]
Description=Code Server Health Check Timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
Persistent=true

[Install]
WantedBy=timers.target
```

### Step 3: Automatic Failover Setup
Configure the failover monitor to check HAProxy status.

**Command**: `./scripts/health/automatic-failover.sh`

## Failover Policy

| Scenario | Primary Status | Replica Status | Action |
|----------|----------------|----------------|--------|
| Healthy  | UP             | UP (Backup)    | No action (Primary active) |
| Failover | DOWN           | UP             | Replica promoted (HAProxy handles routing) |
| Recovery | UP             | UP             | Replica returned to backup state |
| Outage   | DOWN           | DOWN           | Alert: Service Outage |

## Monitoring and Alerting
Health check failures are logged to `journalctl` and incidents are automatically created in GitHub via the CLI.

### Health Metrics
Exported Prometheus metrics:
- `health_check_status{status="HEALTHY"}`: 1 (Healthy), 0 (Degraded)
- `service_up{service="code-server"}`: 1 (UP), 0 (DOWN)

## Troubleshooting
Check health check logs:
```bash
journalctl -u health-check.service -f
```

View HAProxy backend status:
`http://localhost:8404/haproxy-stats`
