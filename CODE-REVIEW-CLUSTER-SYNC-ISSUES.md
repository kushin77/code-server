# Code Review: Failover/Load Balancing Cluster Pair Sync Issues

**Date**: April 25, 2026  
**Status**: ⚠️ CRITICAL - Out-of-Sync Cluster Architecture  
**Affected Hosts**: 192.168.168.31 (Primary), 192.168.168.42 (Replica)  
**Impact**: Failover unreliable, load balancing ineffective, cluster pair inconsistent  

---

## Executive Summary

The failover/load balancing cluster architecture has **three critical sync failures**:

1. **File Mount Mismatch**: Config files mounted as directories instead of files on one or both replicas
2. **No Active Sync Mechanism**: Replicas diverge when configs are updated on only one node
3. **Load Balancer Not Configured**: Services only route to `localhost` containers, not across cluster nodes

This causes:
- ❌ Failover failures (replica nodes out of sync with primary)
- ❌ Load balancing ineffective (no cross-node routing)
- ❌ Configuration drift (manual updates don't propagate)
- ❌ Service startup failures (config file/directory mismatch)

---

## Problem Analysis

### Issue #1: File vs Directory Mount Mismatch

**Location**: [docker-compose.yml](docker-compose.yml#L242)

#### Current Configuration
```yaml
caddy:
  volumes:
    - ./config/caddy:/etc/caddy:ro
    - caddy_data:/data
    - caddy_config:/config

prometheus:
  volumes:
    - ./config:/prometheus-config:ro          # ← Directory mount
    - ./monitoring/alerts:/etc/prometheus/rules:ro
    - prometheus_data:/prometheus
```

#### Root Cause
When `docker-compose up` runs on the replica node, Docker's bind mount behavior depends on whether the source exists:
- **If `/code-server-enterprise/config/caddy` is a DIRECTORY**: Docker creates `/etc/caddy` as a directory
- **If `/code-server-enterprise/config/caddy` is a FILE**: Docker creates `/etc/caddy` as a file
- **If path doesn't exist**: Docker creates it as a DIRECTORY by default

The problem occurs because:
1. **Replica node cloned git repo**: The directory structure is identical to primary
2. **However, rsync with `--archive` flag**: Copies empty dirs, then populates from source
3. **Docker bind mount sees directory first**: Creates mount point as directory before files are populated
4. **Service starts and fails**: Caddy expects file, gets directory

#### Evidence from fix-replica-config-sync.sh

[scripts/operations/fix-replica-config-sync.sh#L110-L130](scripts/operations/fix-replica-config-sync.sh#L110-L130):
```bash
# Phase 2: Remove Incorrect Directory Mounts
if [ -d "$REPLICA_CADDY_DIR/Caddyfile" ]; then
    log_error "$REPLICA_CADDY_DIR/Caddyfile is a DIRECTORY (should be file)"
    rm -rf "$REPLICA_CADDY_DIR/Caddyfile"
fi
```

This indicates the fix has been applied, but the **root cause remains**:

**The docker-compose.yml design is fragile** — it relies on:
- Identical directory structure across replicas
- Correct order of operations (mount setup before file population)
- Manual intervention when replication fails

### Issue #2: No Active Sync Mechanism Between Replicas

**Architectural Problem**: Configuration drift is inevitable

#### Current State
- **Primary (192.168.168.31)**: Git repo at commit `6fd3c77b`
- **Replica (192.168.168.42)**: Git repo at commit `6fd3c77b` (should be)
- **Config Sync**: ❌ **NONE** — Files updated on primary don't auto-propagate

#### Deployment Model (from [production-cluster-architecture-v2.md](memories/repo/production-cluster-architecture-v2.md))
```bash
# Each replica deployed independently
ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose up -d'
ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker compose up -d'
```

**Problem**: This approach requires:
1. Manual SSH to each replica
2. Same git commit on both (hope)
3. No detection of divergence
4. No automatic sync when one node changes

#### Example Failure Scenario
```bash
# Developer updates config on primary
cd /code-server-enterprise
echo "new_config=value" >> config/prometheus.yml
git add config/prometheus.yml && git commit -m "Update prometheus config"
git push origin main

# Primary node updates
ssh 192.168.168.31 'cd code-server-enterprise && git pull && docker compose up -d'

# ❌ Replica is now out of sync
# Failover to 192.168.168.42 still has old config
```

#### Evidence from Scripts
[scripts/operations/fix-replica-config-sync.sh](scripts/operations/fix-replica-config-sync.sh) is a **one-time fix**, not ongoing sync:
- Runs once when replication fails
- Requires manual SSH execution
- No scheduled runs or continuous monitoring
- No rollback if sync fails mid-way

### Issue #3: Load Balancer Not Configured for Cross-Node Routing

**Location**: [config/caddy/Caddyfile](config/caddy/Caddyfile#L100-L140)

#### Current Configuration
```caddyfile
# Production domain
{$APEX_DOMAIN} {
  # API routes - ONLY routes to localhost
  handle /api/* {
    reverse_proxy http://backend:8000  # ← Fixed to internal network
  }
  
  # IDE endpoints - ONLY routes to localhost  
  handle /ide* {
    reverse_proxy http://code-server:8443  # ← Fixed to internal network
  }
}
```

#### Missing: Load Balancer Upstream Definition
For multi-replica cluster, needs:
```caddyfile
# ❌ MISSING: This should exist for load balancing
upstream backend_cluster {
  least_conn;  # or random, round_robin
  server 192.168.168.31:8000;
  server 192.168.168.42:8000;
}
```

#### Architecture Says Active Multi-Replica
[production-cluster-architecture-v2.md#L15-L40](memories/repo/production-cluster-architecture-v2.md#L15-L40):
```yaml
# Architecture Direction: FROM → TO
From: Primary/Replica (active/passive)
To:   Active multi-replica cluster with:
  - Load balancing: Distribute traffic across all replicas
  - Failover: Automatic detection
  - Scaling: Add replicas without disruption
```

But the **actual code** only configures `localhost` routing:
- Each replica is independent
- No cross-node communication
- No load distribution
- No automatic failover

#### How Load Balancing SHOULD Work

**Correct Configuration**:
```caddyfile
# Global upstream pool
(upstream_backend) {
  reverse_proxy http://backend-pool:8000 {
    policy round_robin
    to 192.168.168.31:8000
    to 192.168.168.42:8000
    health_uri /health
    health_timeout 5s
  }
}

# Use upstream for all backends
handle /api/* {
  import upstream_backend
}

handle /ide* {
  to http://ide-pool:8443 {
    to 192.168.168.31:8443
    to 192.168.168.42:8443
  }
}
```

**Currently Missing**:
- ❌ No upstream pool definitions
- ❌ No health checks across replicas
- ❌ No round-robin policy
- ❌ No automatic failover detection
- ❌ Static routes only to `localhost`

---

## Impact Analysis

### Failover Failures

**Scenario**: Primary node (192.168.168.31) goes down
1. Load balancer routes to 192.168.168.42 (replica)
2. ❌ Replica config is out of sync (missed recent updates on primary)
3. ❌ Services fail to start (file/dir mount mismatch)
4. ❌ Users experience service unavailability

**SLA Breach**: RTO > 5 minutes (should be < 1 minute)

### Load Balancing Ineffective

**Current State**: Each replica is an island
```
User → {$APEX_DOMAIN} 
  → Caddy (192.168.168.31) 
    → backend:8000 (inside same container)
    → code-server:8443 (inside same container)

User → {$APEX_DOMAIN}
  → Caddy (192.168.168.42)
    → backend:8000 (inside same container) 
    → code-server:8443 (inside same container)
```

**What Should Happen**:
```
User → Load Balancer (HAProxy/AWS ELB)
  → Replica 1 (192.168.168.31) - 50% of traffic
  → Replica 2 (192.168.168.42) - 50% of traffic

Both replicas have identical backends and can serve any user
```

**Problem**: No cross-node routing means:
- ❌ Each node handles only its own traffic
- ❌ No load distribution
- ❌ No use of spare capacity
- ❌ Failover requires DNS/external LB change (slow)

### Configuration Drift

**3-Day Timeline**:

| Time | Action | Primary | Replica | Status |
|------|--------|---------|---------|--------|
| Day 1 | Deploy v1 | ✅ config v1 | ✅ config v1 | 🟢 IN SYNC |
| Day 1 PM | Update Prometheus rules on primary | ✅ config v1.1 | ✅ config v1 | 🟡 DRIFT |
| Day 2 | SSH to replica, git pull | ✅ config v1.1 | ✅ config v1.1 | 🟢 IN SYNC |
| Day 2 PM | Fix Caddy config on primary | ✅ config v1.2 | ✅ config v1.1 | 🟡 DRIFT |
| Day 3 | Failover test: replica used as primary | 💥 FAILS | ✅ config v1.1 | 🔴 **OUTAGE** |

**Drift Sources**:
- Manual updates to one replica
- Git pulls done at different times
- Hotfixes applied only to primary
- No sync automation

---

## Root Cause Summary

### Core Problem
The cluster is designed as **active multi-replica** but implemented as **active/passive primary/secondary** with **manual sync**.

| Aspect | Design | Implementation |
|--------|--------|-----------------|
| Topology | Multi-node active cluster | Two independent nodes |
| Failover | Automatic < 5s | Manual SSH required |
| Sync | Continuous | One-time fix script |
| Load Balancing | Across all replicas | Internal only |
| Config Consistency | Guaranteed | Manual verification |
| Service Routing | Multi-path | Single-path (localhost) |

### Why It Breaks
1. **Assumption Mismatch**: Code assumes passive standby, but designed for active multi-node
2. **No Automation**: Config sync is manual, not continuous
3. **No Validation**: No checks that both replicas are in sync before failover
4. **Fragile Mounts**: File/directory mount logic is environment-dependent

---

## Recommendations

### Immediate Fixes (< 2 hours)

#### Fix #1: Standardize Mount Points to ALWAYS Use Files
**File**: [docker-compose.yml](docker-compose.yml#L242)

```yaml
# Current (problematic - uses directory mount)
caddy:
  volumes:
    - ./config/caddy:/etc/caddy:ro

# Fixed (explicit file mount - more reliable)
caddy:
  volumes:
    - ./config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
    - ./config/caddy:/etc/caddy/custom:ro  # For optional includes
```

**Reason**: File mounts are more explicit and avoid the directory-vs-file ambiguity.

#### Fix #2: Add Pre-Deployment Validation
**New File**: [scripts/ci/validate-cluster-sync.sh](scripts/ci/validate-cluster-sync.sh)

```bash
#!/usr/bin/env bash
# Validate both replicas have identical:
# - Git commits
# - Config file checksums  
# - Service versions

PRIMARY_HOST="${PRIMARY_HOST:?}"
REPLICA_HOST="${REPLICA_HOST:?}"

# Check git commits match
PRIMARY_COMMIT=$(ssh akushnir@${PRIMARY_HOST} 'git rev-parse HEAD')
REPLICA_COMMIT=$(ssh akushnir@${REPLICA_HOST} 'git rev-parse HEAD')

if [ "$PRIMARY_COMMIT" != "$REPLICA_COMMIT" ]; then
  echo "ERROR: Cluster out of sync"
  echo "  Primary: $PRIMARY_COMMIT"
  echo "  Replica: $REPLICA_COMMIT"
  exit 1
fi

# Check config checksums
PRIMARY_CADDY_SHA=$(ssh akushnir@${PRIMARY_HOST} 'sha256sum config/caddy/Caddyfile | awk "{print $1}"')
REPLICA_CADDY_SHA=$(ssh akushnir@${REPLICA_HOST} 'sha256sum config/caddy/Caddyfile | awk "{print $1}"')

if [ "$PRIMARY_CADDY_SHA" != "$REPLICA_CADDY_SHA" ]; then
  echo "ERROR: Caddyfile out of sync"
  exit 1
fi

echo "✓ Cluster in sync"
```

Run this before any failover test.

### Short-Term Fixes (< 8 hours)

#### Fix #3: Implement Continuous Config Sync
**Option A - Git-Based Sync** (Recommended)

Add to both replicas as cron job:
```bash
# /etc/cron.d/git-sync-cluster
*/5 * * * * root cd /code-server-enterprise && git pull origin main >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1
```

**Option B - Rsync-Based Sync** (If git pull too slow)

```bash
# Primary -> Replica sync every 5 minutes
*/5 * * * * root rsync -av --delete --exclude=.git /code-server-enterprise/ root@192.168.168.42:/code-server-enterprise/ >/dev/null 2>&1
```

#### Fix #4: Configure Load Balancer Routing
**File**: [config/caddy/Caddyfile](config/caddy/Caddyfile) - Add upstream blocks

```caddyfile
# Upstream pool definitions
(backend_pool) {
  reverse_proxy http://backend:8000 {
    # For intra-replica routing only (localhost)
    # This is for services WITHIN each replica
  }
}

(ide_pool) {
  reverse_proxy http://code-server:8443 {
    # Intra-replica routing
  }
}

# Use the pools
{$APEX_DOMAIN} {
  handle /api/* {
    import backend_pool
  }
  
  handle /ide* {
    import ide_pool
  }
}
```

**Note**: Currently each replica routes to its own services. For true load balancing across replicas, need external LB (HAProxy, AWS ELB, etc).

### Long-Term Architecture (Sprint Planning)

#### Recommended: Move to Kubernetes Cluster
Instead of manual multi-host Docker, use Kubernetes for:
- ✅ Automatic node sync via etcd
- ✅ Built-in load balancing (kube-proxy)
- ✅ Automatic failover (pod scheduling)
- ✅ Configuration management (ConfigMaps)
- ✅ Health checks & self-healing

#### If Staying on Docker Compose:

**Proper Active/Passive Setup**:
1. **Primary** (192.168.168.31): Accepts all traffic, writes data
2. **Replica** (192.168.168.42): Read-only copy, activated only on failover
3. **Shared Storage**: NAS (192.168.168.56) with all data
4. **Monitoring**: Detects primary failure
5. **DNS Failover**: Switches replica to primary on failure

**OR: True Active/Active Setup**:
1. **Load Balancer**: HAProxy or external LB in front
2. **Both nodes**: Active, serving traffic
3. **Shared State**: Redis Cluster for distributed cache
4. **Database**: PostgreSQL streaming replication
5. **Sync**: Continuous data replication via DB, not files

---

## Verification Checklist

- [ ] Git commits identical on both replicas: `git rev-parse HEAD`
- [ ] Config file checksums match: `sha256sum config/**/*`
- [ ] Both Caddy services running: `docker ps | grep caddy`
- [ ] Both Prometheus services running: `docker ps | grep prometheus`
- [ ] Cross-node health checks passing
- [ ] Failover test: Stop primary, verify replica takes over
- [ ] All services healthy after failover: `docker ps`
- [ ] No configuration drift after 24 hours of operations

---

## Files Requiring Review

1. **[docker-compose.yml](docker-compose.yml)** - Line 242: File mount configuration
2. **[config/caddy/Caddyfile](config/caddy/Caddyfile)** - Lines 100-140: Route configuration  
3. **[scripts/operations/fix-replica-config-sync.sh](scripts/operations/fix-replica-config-sync.sh)** - Currently one-time fix
4. **[terraform/modules/core/](terraform/modules/core/)** - No replica management
5. **[scripts/ci/](scripts/ci/)** - Missing sync validation

---

## References

- Architecture: [production-cluster-architecture-v2.md](memories/repo/production-cluster-architecture-v2.md)
- Status: [april-26-2026-final-status.md](memories/repo/april-26-2026-final-status.md)
- Current Issues: #1536 (Networking), #1545 (SSO), #1532 (Observability)

---

**Review Status**: 🔴 CRITICAL  
**Recommendation**: Implement fixes #1-3 before next failover test  
**Effort**: ~4 hours to implement immediate fixes, ~2 days for long-term solution
