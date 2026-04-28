# Cluster Container Naming Convention & VIP Configuration

## Overview

This document establishes the standard naming convention for all containers in the code-server cluster and describes the Virtual IP (VIP) configuration for load balancing.

---

## Container Naming Convention

### Standard Format
```
code-server-<service-name>
```

### Purpose
- **Consistency**: All project containers follow the same pattern
- **Clarity**: Easily identify containers belonging to the code-server project
- **Scalability**: Supports multiple projects on the same infrastructure

### Applied Services

| Service | Container Name | Purpose |
|---------|----------------|---------|
| PostgreSQL | `code-server-postgres` | Primary database with replication |
| Redis | `code-server-redis` | Cache layer with persistence |
| Redpanda | `code-server-redpanda` | Message broker (Kafka-compatible) |
| Redpanda Console | `code-server-redpanda-console` | Broker UI and management |
| Prometheus | `code-server-prometheus` | Metrics collection |
| Grafana | `code-server-grafana` | Visualization & dashboards |
| Loki | `code-server-loki` | Log aggregation |
| Alertmanager | `code-server-alertmanager` | Alert management |
| OPA | `code-server-opa` | Policy enforcement engine |
| Ollama | `code-server-ollama` | Local LLM inference |
| Qdrant | `code-server-qdrant` | Vector database |
| OAuth2-Proxy | `code-server-oauth2-proxy` | Authentication proxy |
| Caddy | `code-server-caddy` | API gateway & reverse proxy |

---

## Cluster VIP Configuration

### Virtual IP Address
```
CLUSTER_VIP = 192.168.168.250
```

### Purpose
The VIP provides a single endpoint for load balancing across both cluster replicas:
- **Primary use**: External access point
- **Load balancing**: Automatically routes traffic to both replicas
- **Failover**: If one replica fails, traffic seamlessly moves to the other
- **DNS**: Maps to `kushnir.cloud` domain

### Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     EXTERNAL CLIENTS                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                    kushnir.cloud
                    (DNS points to VIP)
                         │
                         ▼
        ┌────────────────────────────────────┐
        │   CLUSTER VIP                      │
        │   192.168.168.250                  │
        │   (Load Balancer/HAProxy/nginx)    │
        └────────────────────────────────────┘
                    │              │
        ┌───────────┴──────┐      ┌─────────────────┐
        ▼                  ▼      ▼                 ▼
    Replica 1         Replica 2  Monitoring    Direct Access
    192.168.168.31     192.168.168.42
    
    ✓ code-server-   ✓ code-server-   (via VIP)
      postgres         postgres
    ✓ code-server-   ✓ code-server-
      redis            redis
    ✓ (13 total)     ✓ (13 total)
```

### Access Methods

#### 1. Via VIP (Recommended for Production)
```
http://192.168.168.250              # Primary entry point
https://kushnir.cloud               # Production domain (after DNS setup)
```

**Advantages:**
- Single endpoint for all clients
- Automatic load balancing
- Automatic failover if one replica is down
- Same URL regardless of which replica is processing the request

#### 2. Replica 1 (Direct Access)
```
http://192.168.168.31:3000          # Grafana
http://192.168.168.31:9090          # Prometheus
http://192.168.168.31:3100          # Loki
```

**Use Cases:**
- Debugging and diagnostics
- Direct replica monitoring
- Administrative tasks
- Testing specific replica behavior

#### 3. Replica 2 (Direct Access)
```
http://192.168.168.42:3000          # Grafana
http://192.168.168.42:9090          # Prometheus
http://192.168.168.42:3100          # Loki
```

**Use Cases:**
- Same as Replica 1
- Verifying symmetric replication
- Backup replica verification

---

## Service Discovery

### Internal DNS (Docker)
All containers communicate using internal DNS on `127.0.0.11:53`:

```bash
# Container can reach services using service name (no port needed for internal)
curl http://code-server-postgres:5432    # Inside cluster
curl http://code-server-redis:6379       # Inside cluster
```

### Environment Variables
All services reference each other using standardized names:

```env
# In .env.cluster
REDPANDA_BROKERS=code-server-redpanda:9092
```

---

## Configuration Files

### Updated Files

1. **docker-compose-cluster.yml**
   - All containers renamed to `code-server-<service>`
   - Updated internal references (depends_on, service names)
   - Standard configuration for both replicas

2. **.env.cluster**
   - Added `CLUSTER_VIP=192.168.168.250`
   - Updated `REDPANDA_BROKERS` reference
   - Centralized VIP configuration

### Configuration Locations

```
/home/akushnir/code-server/
├── docker-compose-cluster.yml       # Standard naming (deployed to both hosts)
├── .env.cluster                     # VIP configuration
├── CLUSTER_NAMING_CONVENTION.md     # This file
└── CLUSTER_DEPLOYMENT_GUIDE.md      # Deployment instructions
```

---

## Deployment with New Naming

### Prerequisites
- Both replicas must have the updated compose file
- VIP must be configured in load balancer/HAProxy
- DNS updated to point domain to VIP

### Deployment Steps

```bash
# 1. Backup current deployments
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && \
  docker-compose down'
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && \
  docker-compose down'

# 2. Copy new files to both replicas
scp docker-compose-cluster.yml akushnir@192.168.168.31:~/code-server-enterprise/docker-compose.yml
scp .env.cluster akushnir@192.168.168.31:~/code-server-enterprise/.env
scp docker-compose-cluster.yml akushnir@192.168.168.42:~/code-server-enterprise/docker-compose.yml
scp .env.cluster akushnir@192.168.168.42:~/code-server-enterprise/.env

# 3. Deploy on both replicas
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker-compose up -d'
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker-compose up -d'

# 4. Verify containers are running with new names
ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}" | sort'
ssh akushnir@192.168.168.42 'docker ps --format "table {{.Names}}" | sort'
```

### Verification

```bash
# Verify all code-server- prefixed containers
ssh akushnir@192.168.168.31 'docker ps | grep code-server | wc -l'
ssh akushnir@192.168.168.42 'docker ps | grep code-server | wc -l'

# Expected output: 13 services on each replica
```

---

## Monitoring with New Names

### Container Logs
```bash
# View logs for specific service
ssh akushnir@192.168.168.31 'docker logs code-server-postgres -f'
ssh akushnir@192.168.168.31 'docker logs code-server-grafana -f'
ssh akushnir@192.168.168.31 'docker logs code-server-redis -f'
```

### Health Checks
```bash
# Check health of database
ssh akushnir@192.168.168.31 'docker ps | grep code-server-postgres'

# Check Redpanda cluster status
ssh akushnir@192.168.168.31 'docker logs code-server-redpanda | tail -20'

# Check replication status
ssh akushnir@192.168.168.31 'docker exec code-server-postgres psql -U postgres -c "SELECT * FROM pg_stat_replication"'
```

### Dashboard Access

Via VIP:
```
Grafana:          http://192.168.168.250:3000
Prometheus:       http://192.168.168.250:9090
Loki:             http://192.168.168.250:3100
Redpanda Console: http://192.168.168.250:8085
```

Via Direct Replica Access:
```
Replica 1: http://192.168.168.31:3000
Replica 2: http://192.168.168.42:3000
```

---

## Benefits of Standard Naming

1. **Clarity**: Easy to identify all cluster services
2. **Scalability**: Can deploy multiple projects on same infrastructure
3. **Automation**: Tools can easily identify and manage code-server containers
4. **Documentation**: Clear naming makes documentation more maintainable
5. **Operational Excellence**: Standard naming reduces confusion and errors

---

## Example Commands with New Names

### Restart a specific service
```bash
ssh akushnir@192.168.168.31 'docker-compose -f ~/code-server-enterprise/docker-compose.yml restart code-server-postgres'
```

### Check specific container status
```bash
ssh akushnir@192.168.168.31 'docker inspect code-server-grafana | jq ".[] | {Name: .Name, Status: .State.Status}"'
```

### View container resource usage
```bash
ssh akushnir@192.168.168.31 'docker stats code-server-postgres code-server-redis code-server-redpanda'
```

### Network connectivity check
```bash
ssh akushnir@192.168.168.31 'docker exec code-server-grafana ping code-server-prometheus'
```

---

## VIP Configuration Notes

### Current VIP: 192.168.168.250
- Assumes /24 network (192.168.168.0/24)
- Can be changed if network topology requires it
- Must be configured in HAProxy or load balancer

### To Change VIP
1. Update `CLUSTER_VIP` in `.env.cluster`
2. Update HAProxy/load balancer configuration
3. Update DNS records if using domain
4. Document the change in this file

### High Availability Setup (HAProxy Example)
```
frontend cluster_frontend
    bind 192.168.168.250:80
    bind 192.168.168.250:443
    default_backend cluster_replicas

backend cluster_replicas
    balance roundrobin
    server replica1 192.168.168.31:80 check
    server replica2 192.168.168.42:80 check
```

---

## Next Steps

1. **Identify actual VIP address** - Confirm 192.168.168.250 is correct or update
2. **Configure load balancer** - Set up HAProxy/nginx at VIP to round-robin to both replicas
3. **Test failover** - Verify traffic switches when one replica is down
4. **Update DNS** - Point kushnir.cloud to VIP once production-ready
5. **Document runbooks** - Create operational procedures for the new naming scheme

---

## Summary

✅ **Container Naming**: All containers follow `code-server-<service>` convention  
✅ **VIP Configuration**: 192.168.168.250 as single entry point  
✅ **Load Balancing**: Both replicas equally distributed  
✅ **Automatic Failover**: Ready for HA setup  
✅ **Clear Documentation**: Standard naming throughout

