# Infrastructure as Code (IaC) Deployment Guide
## Production Cluster - Automated, Declarative, Version-Controlled

**Last Updated:** April 29, 2026  
**Status:** Production-Ready IaC  
**Approach:** Ansible + Docker Compose  
**Deployment Type:** Automated Infrastructure as Code (no manual steps)  

---

## Overview

All infrastructure is now **declarative and automated**. No manual procedures, no shell scripts, everything version-controlled and reproducible.

## Configuration SSOT

The deployment scripts source shell-style env files in a fixed order instead of treating them as ad hoc dotenv fragments:

1. `.env.infrastructure` for endpoint construction and shared service URLs
2. `.env.deployment` for deployment-time defaults and local overrides
3. `.env.cluster` for HA and cluster topology values
4. `.env.production` for production service ports, credentials, and runtime settings

Use [`.env.schema.json`](.env.schema.json) as the authoritative variable inventory when adding or renaming configuration.

On the production host, the working tree may contain unrelated local drift. Do not replace or reset that state during deployment unless the operator explicitly asks for it.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Infrastructure as Code (Git Repository)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ansible/                    - IaC automation                   │
│  ├── deploy-cluster.yml      - Cluster deployment              │
│  ├── observability.yml       - Grafana + Prometheus setup     │
│  ├── inventory.yml           - Host definitions (IaC)          │
│  └── templates/              - Configuration templates          │
│      └── alertmanager-config.yml.j2                            │
│                                                                  │
│  terraform/                  - Optional: Terraform modules      │
│  ├── root.tf                 - Root configuration               │
│  └── modules/                - Component modules               │
│                                                                  │
│  docker-compose.production-replica.yml  - Container definitions│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
         ⬇️
    Executed by Ansible
         ⬇️
┌─────────────────────────────────────────────────────────────────┐
│ PRODUCTION CLUSTER (Deployed & Managed)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PRIMARY (192.168.168.31)                                       │
│  ├─ PostgreSQL (master)                                         │
│  ├─ Redis (master)                                              │
│  ├─ MongoDB, Elasticsearch, Qdrant                              │
│  ├─ Prometheus, Grafana, Loki, Tempo                            │
│  ├─ AlertManager, Caddy                                         │
│  └─ 5 microservices (api, web, user, data, analytics)         │
│                                                                  │
│  REPLICA (192.168.168.42)                                       │
│  ├─ PostgreSQL (replica, streaming replication)                │
│  ├─ Redis (synchronized)                                        │
│  ├─ MongoDB, Elasticsearch, Qdrant (synced)                     │
│  ├─ Prometheus, Grafana, Loki, Tempo                            │
│  ├─ AlertManager, Caddy                                         │
│  └─ 5 microservices (identical)                                │
│                                                                  │
│  TOTAL: 18 services per node (36 total)                        │
│  STATUS: ✅ Identical, monitored, replicated                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## IaC Components

### 1. Ansible Playbooks

#### `ansible/deploy-cluster.yml` - Cluster Deployment
Deploys and configures entire production cluster:
- **Step 1:** Infrastructure (networks, volumes)
- **Step 2:** Service deployment (containers)
- **Step 3:** Database replication setup
- **Step 4:** Service consistency verification
- **Step 5:** Health checks and monitoring

**Run:**
```bash
ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml
```

**Idempotent:** ✅ Safe to run multiple times (only changes what differs)

---

#### `ansible/observability.yml` - Monitoring Stack
Configures observability infrastructure:
- **Step 1:** Wait for Grafana readiness
- **Step 2:** Add datasources (Prometheus, Loki, Tempo)
- **Step 3:** Create 4 Grafana dashboards
- **Step 4:** Configure 10 alert rules
- **Step 5:** Setup AlertManager notification channels
- **Step 6:** Verify complete deployment

**Run:**
```bash
ansible-playbook -i ansible/inventory.yml ansible/observability.yml
```

---

### 2. Ansible Inventory (`ansible/inventory.yml`)

Defines cluster topology:
```yaml
all:
  children:
    primary:      # PRIMARY NODE
      hosts:
        primary.code-server: 192.168.168.31
    replica:      # REPLICA NODE
      hosts:
        replica.code-server: 192.168.168.42
    cluster:      # Shared configuration
      vars:
        - Database settings
        - Monitoring config
        - Service parameters
```

**All infrastructure defined in code** - no manual configuration.

---

### 3. Ansible Templates

#### `ansible/templates/alertmanager-config.yml.j2`
AlertManager notification routing configuration:
- Slack channels for different alert severities
- PagerDuty integration for critical alerts
- Alert inhibition rules
- Grouping and repeat policies

**Rendered at deployment time** with actual values.

---

### 4. Docker Compose

#### `docker-compose.production-replica.yml`
Container definitions for all 18 services:
- **Infrastructure:** PostgreSQL, Redis, MongoDB, Elasticsearch, Qdrant
- **Monitoring:** Prometheus, Grafana, Loki, Tempo, AlertManager
- **Gateway:** Caddy
- **Microservices:** 5 core services

**Deployed identically on both nodes** via Ansible.

---

## Deployment Process

### Phase 1: Preparation

```bash
# 1. Clone repository with IaC
git clone <repo> code-server
cd code-server

# 2. Verify Ansible installed
ansible --version

# 3. Update SSH keys (if needed)
ssh-copy-id akushnir@192.168.168.31
ssh-copy-id akushnir@192.168.168.42

# 4. Test connectivity
ansible -i ansible/inventory.yml all -m ping
```

### Phase 2: Deploy Infrastructure

```bash
# Deploy cluster with IaC
ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml

# This will:
# ✅ Create networks and volumes
# ✅ Pull Docker images
# ✅ Start 18 services on each node
# ✅ Setup database replication
# ✅ Verify health checks
```

**Time:** ~10 minutes

### Phase 3: Configure Observability

```bash
# Configure monitoring stack
ansible-playbook -i ansible/inventory.yml ansible/observability.yml

# This will:
# ✅ Create 4 Grafana dashboards
# ✅ Configure 10 alert rules
# ✅ Setup notification channels
# ✅ Verify all datasources connected
```

**Time:** ~5 minutes

### Phase 4: Verify Deployment

```bash
# SSH to PRIMARY and verify
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise-ops && docker-compose ps"

# SSH to REPLICA and verify identical services
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise-ops && docker-compose ps"

# Check that service lists match
ansible -i ansible/inventory.yml cluster -m shell -a "docker-compose ps --services | sort"
```

**Expected:** 18 identical services on both nodes

### Phase 5: Validate Infrastructure

```bash
# Test database replication
ssh akushnir@192.168.168.31 << 'EOF'
docker exec code-server-enterprise-postgres psql -U postgres -d app_db -c \
  "SELECT client_addr, state, write_lag FROM pg_stat_replication;"
EOF

# Expected: REPLICA (192.168.168.42) in 'streaming' state with <1s lag

# Test API Gateway
curl http://192.168.168.31/health
curl http://192.168.168.42/health
# Expected: 200 OK

# Test Monitoring
curl http://192.168.168.31:3000/api/health   # Grafana
curl http://192.168.168.31:9090/api/v1/targets  # Prometheus
# Expected: 200 OK on both
```

---

## IaC Benefits

### ✅ Reproducibility
- Deploy to new cluster identically
- No manual procedures means no human error
- Complete infrastructure from git

### ✅ Version Control
- All infrastructure in git
- Track changes over time
- Review/approve before deployment

### ✅ Idempotency
- Run playbooks multiple times safely
- Only change what differs
- Safe to re-run for updates

### ✅ Documentation
- Playbooks are self-documenting
- No separate procedures manual needed
- Code is the documentation

### ✅ Consistency
- Both nodes always identical
- No configuration drift
- Automated verification

### ✅ Scalability
- Add new nodes by updating inventory
- Same playbook deploys to 3, 5, 10+ nodes
- No manual step changes

---

## Making Changes (Infrastructure as Code)

### Add New Service

1. **Update docker-compose.production-replica.yml**
   ```yaml
   new-service:
     image: new-service:1.0
     environment:
       CONFIG: value
     # ... rest of config
   ```

2. **Commit to git**
   ```bash
   git add docker-compose.production-replica.yml
   git commit -m "Add new-service to cluster"
   ```

3. **Deploy via Ansible**
   ```bash
   ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml
   ```

**Everything tracked, auditable, reproducible.**

---

### Modify Configuration

1. **Update ansible/inventory.yml**
   ```yaml
   postgres:
     max_connections: 300  # Changed from 200
   ```

2. **Commit to git**
   ```bash
   git add ansible/inventory.yml
   git commit -m "Increase PostgreSQL max_connections to 300"
   ```

3. **Re-run deployment**
   ```bash
   ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml
   ```

**All changes tracked, no manual SSH commands needed.**

---

### Scale Cluster

1. **Add new node to inventory**
   ```yaml
   node3.code-server:
     ansible_host: 192.168.168.43
     node_role: replica
   ```

2. **Commit to git**
   ```bash
   git commit -m "Add node3 to cluster"
   ```

3. **Deploy**
   ```bash
   ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml
   ```

**Single playbook handles 2, 3, 5, 10+ nodes identically.**

---

## Monitoring & Validation

### Playbook Execution Report

Each playbook generates comprehensive reports:

```
✅ CLUSTER DEPLOYMENT REPORT
================================
PRIMARY (192.168.168.31):
  Services: 18/18 ✅
  Health: All healthy ✅
  Database: Master ✅
  
REPLICA (192.168.168.42):
  Services: 18/18 ✅
  Health: All healthy ✅
  Database: Replica (lag 0.3s) ✅

✅ OBSERVABILITY REPORT
================================
Grafana Dashboards: 4 ✅
Alert Rules: 10 ✅
Prometheus Targets: 25+ ✅
Notification Channels: 3 (Slack, Email, PagerDuty) ✅
```

---

## Troubleshooting

### Service Not Running

```bash
# Identify issue
ansible -i ansible/inventory.yml cluster -m shell \
  -a "docker-compose ps | grep SERVICE_NAME"

# Check logs
ansible -i ansible/inventory.yml cluster -m shell \
  -a "docker-compose logs -f SERVICE_NAME"

# Re-run deployment
ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml
```

### Replication Lag Too High

```bash
# SSH to PRIMARY
ssh akushnir@192.168.168.31

# Check replication status
docker exec code-server-enterprise-postgres psql -U postgres -c \
  "SELECT client_addr, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# Check network latency
ping -c 10 192.168.168.42
```

### Alert Rule Not Triggering

```bash
# Verify alert rule loaded
curl http://192.168.168.31:9090/api/v1/rules | jq '.data.groups'

# Check alert firing status
curl http://192.168.168.31:9093/api/v1/alerts | jq '.data'

# Reload configuration
ansible -i ansible/inventory.yml primary -m shell \
  -a "docker exec code-server-enterprise-prometheus kill -HUP 1"
```

---

## Best Practices

### 1. Always Use Version Control
```bash
# GOOD ✅
git add ansible/
git commit -m "Update alert rules"

# AVOID ❌ - Manual SSH changes
ssh 192.168.168.31 "docker exec ... modify config"
```

### 2. Test Changes on REPLICA First
```bash
# Update ansible/inventory.yml
# Run on REPLICA only
ansible -i ansible/inventory.yml replica ansible/deploy-cluster.yml

# Verify works
# Then deploy to full cluster
ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml
```

### 3. Commit Frequently
```bash
# Each change separately
git commit -m "Add new monitoring dashboard"
git commit -m "Increase PostgreSQL memory"
```

### 4. Review Changes Before Deployment
```bash
# Show what will change
ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml --check

# Review diffs
git diff
```

### 5. Document in Commit Messages
```bash
git commit -m "Fix: Increase PostgreSQL max_connections to handle load

- Previous: 200 connections (hitting limit during peak hours)
- New: 300 connections (supports projected Q3 growth)
- Tested: Replica node verified stable with new setting
- Impact: 0 downtime, applied during maintenance window"
```

---

## Files & Structure

```
.
├── ansible/
│   ├── inventory.yml              # Cluster definition (IaC)
│   ├── deploy-cluster.yml         # Deployment automation
│   ├── observability.yml          # Monitoring setup
│   └── templates/
│       └── alertmanager-config.yml.j2  # Alert routing
│
├── docker-compose.production-replica.yml  # Container definitions
│
├── config/
│   ├── prometheus/                # Prometheus configuration
│   ├── grafana/                   # Grafana config
│   ├── alertmanager/              # AlertManager config
│   ├── caddy/                     # API Gateway config
│   └── ...
│
├── terraform/                     # Optional Terraform modules
│   └── ...
│
└── README-IaC.md                 # This file
```

---

## Summary

✅ **Everything is Infrastructure as Code:**
- No manual procedures
- All infrastructure in git
- Version controlled and auditable
- Reproducible and consistent
- Scalable to any number of nodes

✅ **Deployment Process:**
1. Update IaC (ansible/inventory.yml, docker-compose.yml, etc.)
2. Commit to git
3. Run playbook
4. Verify deployment
5. Done

✅ **Production Ready:**
- Database replication: <1s lag
- Monitoring: 4 dashboards, 10 alerts
- API Gateway: Load balanced
- High Availability: Ready for failover

---

**Next Steps:**
1. Review ansible/inventory.yml
2. Run `ansible-playbook -i ansible/inventory.yml ansible/deploy-cluster.yml`
3. Configure notification channels (Slack/PagerDuty tokens)
4. Deploy observability: `ansible-playbook -i ansible/inventory.yml ansible/observability.yml`
5. Verify: `docker-compose ps` on both nodes

**Status:** ✅ Production-Ready Infrastructure as Code
