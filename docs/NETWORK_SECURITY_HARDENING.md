# Network Security Hardening - Comprehensive Guide

**Document**: Network Security Implementation  
**Version**: Phase 12  
**Date**: April 30, 2026  
**Purpose**: Zero-trust network security with firewall, isolation, and access control

---

## Overview

Network security hardening provides:
- **Firewall Rules**: Strict ingress/egress control
- **Network Isolation**: 5 separate networks by tier
- **Zero-Trust Model**: Explicit allow rules, default deny
- **Access Control**: Service-to-service authentication
- **Audit Trail**: All access logged and monitored

---

## Architecture

```
INTERNET
   ↓
┌─────────────────────────────────────┐
│ Firewall (UFW/firewalld)            │
│ - Allow: 80, 443 (HTTP/HTTPS)       │
│ - Allow: 22 (SSH, internal only)    │
│ - Deny: Everything else             │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────────────────────────┐
│ Frontend Network (10.1.0.0/16)                         │
│ ├─ code-server (public)                                │
│ ├─ nginx (public)                                      │
│ └─ CDN cache                                           │
└──────────────┬──────────────────────────────────────────┘
               ↓
┌─────────────────────────────────────────────────────────┐
│ Backend Network (10.2.0.0/16)                          │
│ ├─ API servers (authenticated)                        │
│ ├─ Workers (authenticated)                            │
│ └─ Message queue                                       │
└──────────────┬──────────────────────────────────────────┘
               ├──────────────────────┐
               ↓                      ↓
  ┌────────────────────┐  ┌────────────────────┐
  │ Data Network       │  │ Monitoring Network │
  │ (10.3.0.0/16)      │  │ (10.4.0.0/16)      │
  │ ├─ PostgreSQL      │  │ ├─ Prometheus      │
  │ ├─ Redis           │  │ ├─ Grafana         │
  │ └─ Backups         │  │ └─ Log aggregation │
  └────────────────────┘  └────────────────────┘
               ↑
  ┌────────────────────┐
  │ Management Network │
  │ (10.5.0.0/16)      │
  │ ├─ Terraform       │
  │ ├─ Admin tools     │
  │ └─ CI/CD pipeline  │
  └────────────────────┘

Network Connectivity:
  ✓ Frontend → Backend
  ✓ Backend → Data
  ✓ Monitoring → All (read-only)
  ✓ Management → Backend (deploy)
  ✗ Frontend → Data (blocked)
  ✗ Frontend → Management (blocked)
```

---

## Component 1: Firewall Rules (configure-firewall.sh)

**Purpose**: OS-level network access control

**Features**:
- UFW (Ubuntu) or firewalld (CentOS) support
- Default deny incoming, allow outgoing
- Explicit allow rules for known services
- Logging for audit trail

**Rules**:
```
ALLOW:
  - 22/tcp (SSH, internal only)
  - 80/tcp (HTTP)
  - 443/tcp (HTTPS)
  - 9090/tcp (Prometheus, internal)
  - 9100/tcp (Node Exporter, internal)
  - 9091/tcp (Custom metrics, internal)
  - 8080/tcp (cAdvisor, internal)
  - 3000/tcp (Grafana, internal)
  - 9000/tcp (MinIO, internal)
  - 112 (VRRP, internal)
  - 5432/tcp (PostgreSQL replica, internal)
  - 514/udp (Syslog, internal)
  - ICMP (ping, internal)

DENY:
  - All other traffic (default)
```

**Usage**:
```bash
# Apply firewall rules
sudo bash scripts/security/configure-firewall.sh apply

# View current rules
sudo bash scripts/security/configure-firewall.sh show

# Rollback to defaults
sudo bash scripts/security/configure-firewall.sh rollback
```

---

## Component 2: Network Isolation (configure-network-isolation.sh)

**Purpose**: Docker network segmentation by tier

**5 Networks Created**:

| Network | Subnet | Purpose | Tier |
|---------|--------|---------|------|
| frontend-network | 10.1.0.0/16 | Public services | Public |
| backend-network | 10.2.0.0/16 | Application services | Internal |
| data-network | 10.3.0.0/16 | Databases/caches | Internal |
| monitoring-network | 10.4.0.0/16 | Observability stack | Internal |
| management-network | 10.5.0.0/16 | Deployment/admin | Internal |

**Connectivity Rules**:
```
✓ frontend    ← → backend      (HTTP/HTTPS)
✓ backend     ← → data         (SQL/Redis)
✓ monitoring  ← → all networks (metrics, read-only)
✓ management  ← → backend      (Terraform deploy)
✗ frontend    ← → data         (BLOCKED - no direct DB)
✗ frontend    ← → management   (BLOCKED - no admin from public)
✗ data        ← → monitoring   (BLOCKED - no direct DB monitoring)
```

**Service Placement**:
```yaml
code-server:
  networks:
    - frontend-network
    - backend-network
  # Can access: public internet + backend services

api-service:
  networks:
    - backend-network
    - data-network
    - monitoring-network
  # Can access: code-server + databases + metrics

postgres:
  networks:
    - data-network
  # Can access: backend services only (inbound)

prometheus:
  networks:
    - monitoring-network
    - backend-network
  # Can access: all services for metrics
```

**Usage**:
```bash
# Create isolated networks
bash scripts/security/configure-network-isolation.sh

# Verify networks
docker network ls | grep -E "frontend|backend|data|monitoring|management"

# Inspect network
docker network inspect frontend-network
```

---

## Component 3: Zero-Trust Access Control (configure-zero-trust.sh)

**Purpose**: Explicit allow rules, default deny model

**Principles**:
1. **Never Trust**: All traffic untrusted by default
2. **Always Verify**: Authentication required for all flows
3. **Explicit Allow**: Only approved traffic permitted
4. **Least Privilege**: Minimum access needed per service
5. **Audit Everything**: All access logged

**Policy Format**:
```yaml
access_rule:
  source: "code-server"
  destination: "api-service"
  protocol: "tcp"
  port: 8080
  action: "allow"
  requires_authentication: true
  requires_encryption: true
  rate_limit: 1000  # req/min
  audit_level: "detailed"
```

**Example Rules**:

```yaml
# Frontend → Backend API
- source: "code-server"
  destination: "api-service"
  port: 8080
  action: "allow"
  reason: "API access"
  requires_authentication: true

# Backend → PostgreSQL
- source: "api-service"
  destination: "postgres"
  port: 5432
  action: "allow"
  reason: "Database access"
  requires_authentication: true
  requires_encryption: true

# Backend → Redis
- source: "api-service"
  destination: "redis"
  port: 6379
  action: "allow"
  reason: "Cache access"
  requires_authentication: true

# Prometheus → All (metrics)
- source: "prometheus"
  destination: "all-services"
  port: [9090, 9100, 9091, 8080]
  action: "allow"
  read_only: true

# SSH - Admin only
- source: "192.168.168.0/24"
  destination: "all-hosts"
  port: 22
  action: "allow"
  requires_mfa: true
  audit_level: "detailed"

# Default Deny
- source: "any"
  destination: "any"
  action: "deny"
  reason: "Zero-trust model"
```

**Audit Trail**:
```
Authentication attempts: 90-day retention
Denied connections: 90-day retention
Policy violations: 1-year retention
Exception approvals: Permanent documentation
```

**Usage**:
```bash
# Apply zero-trust policies
bash scripts/security/configure-zero-trust.sh

# Validate policies
bash scripts/security/configure-zero-trust.sh validate

# Review audit logs
cat /var/log/zero-trust-audit.log | tail -50
```

---

## Operational Procedures

### Procedure 1: Initial Firewall Setup (30 min)

**Step 1: Update system**
```bash
sudo apt update && sudo apt upgrade -y
```

**Step 2: Install UFW (if needed)**
```bash
sudo apt install -y ufw
```

**Step 3: Apply firewall rules**
```bash
sudo bash scripts/security/configure-firewall.sh apply
```

**Step 4: Verify rules**
```bash
sudo ufw status numbered
```

**Step 5: Test connectivity**
```bash
# SSH access (should work)
ssh akushnir@192.168.168.31

# Web access (should work)
curl http://192.168.168.31

# Blocked port (should fail quickly)
nc -zv -w 2 192.168.168.31 9999  # Should refuse
```

---

### Procedure 2: Network Isolation Setup (20 min)

**Step 1: Create networks**
```bash
bash scripts/security/configure-network-isolation.sh
```

**Step 2: Verify networks created**
```bash
docker network ls
```

**Step 3: Update docker-compose files**
```yaml
services:
  code-server:
    networks:
      - frontend-network
      - backend-network  # For backend access

  api-service:
    networks:
      - backend-network
      - data-network      # For DB access
      - monitoring-network
```

**Step 4: Redeploy containers**
```bash
docker-compose up -d --force-recreate
```

**Step 5: Verify connectivity**
```bash
# Test intra-network communication
docker exec code-server ping api-service

# Should fail cross-network
docker exec code-server ping postgres  # Should fail
```

---

### Procedure 3: Zero-Trust Policy Deployment (30 min)

**Step 1: Review policies**
```bash
cat /tmp/zero-trust-policies.yaml
```

**Step 2: Apply policies**
```bash
bash scripts/security/configure-zero-trust.sh
```

**Step 3: Validate policies**
```bash
bash scripts/security/configure-zero-trust.sh validate
```

**Step 4: Test authentication**
```bash
# Should require credentials
curl -i http://api-service:8080  # 401 Unauthorized

# With credentials
curl -i -H "Authorization: Bearer TOKEN" http://api-service:8080  # Success
```

**Step 5: Monitor audit trail**
```bash
tail -f /var/log/zero-trust-audit.log
```

---

## Monitoring & Maintenance

### Daily Tasks (5 min)
```bash
# Check firewall status
sudo ufw status

# Review denied connections
sudo journalctl -u ufw --since today | grep BLOCK

# Verify network connectivity
docker network ls
```

### Weekly Tasks (15 min)
```bash
# Audit firewall rules
sudo ufw status numbered

# Review zero-trust violations
cat /var/log/zero-trust-audit.log | grep "denied"

# Test failover network access
ssh akushnir@192.168.168.42 'docker network ls'
```

### Monthly Tasks (30 min)
```bash
# Security audit
bash scripts/security/configure-zero-trust.sh validate

# Exception review
grep -i "exception" /tmp/zero-trust-policies.yaml

# Update policies
# - Remove expired exceptions
# - Add necessary new rules
# - Review denied traffic patterns

# Test disaster recovery with network policies
# - Simulate host failure
# - Verify failover still respects policies
```

---

## Troubleshooting

### Issue 1: Containers Cannot Communicate

**Symptoms**: `Connection refused` between containers

**Diagnosis**:
```bash
# Check containers are on same network
docker inspect container1 | grep Networks
docker inspect container2 | grep Networks

# Test DNS resolution
docker exec container1 ping container2  # by name
docker exec container1 ping 10.2.0.5    # by IP
```

**Solutions**:
1. Ensure both containers on same network
2. Check firewall not blocking Docker networks
3. Verify DNS resolver configured
4. Check policy doesn't block this connection

### Issue 2: SSH Access Blocked

**Symptoms**: SSH connection refused

**Diagnosis**:
```bash
# Check if port 22 is open
sudo ufw status | grep 22

# Check if source IP allowed
sudo ufw show added | grep 22
```

**Solutions**:
1. Add source IP to allowed list: `sudo ufw allow from 192.168.168.0/24 to any port 22`
2. For external access: Add VPN/bastion host as whitelist
3. Verify SSH service running: `sudo systemctl status ssh`

### Issue 3: Policy Violations Blocked Legitimate Traffic

**Symptoms**: Services cannot communicate (all denied)

**Solutions**:
1. Create exception: `exceptions.policy_bypass` in config
2. Require approver sign-off
3. Set expiration date for exception
4. Update permanent policy if needed

---

## Security Benefits

### Before (No Network Security)
- ❌ All containers can reach each other
- ❌ No firewall protection
- ❌ Public access to internal services
- ❌ No audit trail for access

### After (Network Security)
- ✅ Tier-based network isolation
- ✅ OS-level firewall protection
- ✅ Zero-trust access model
- ✅ Complete audit trail
- ✅ Reduced blast radius if container compromised
- ✅ Compliance-ready logging

---

## Risk Mitigation

### Threat 1: Lateral Movement
**Risk**: Compromised container spreads to others

**Mitigation**:
- Network isolation limits spread
- Only allowed connections work
- Audit trail shows what was attempted

### Threat 2: Data Exfiltration
**Risk**: Attacker extracts database contents

**Mitigation**:
- Frontend cannot reach databases
- Encryption required for data flows
- Rate limiting prevents bulk transfers
- Audit logs show suspicious access

### Threat 3: Privilege Escalation
**Risk**: Attacker gains admin access

**Mitigation**:
- SSH requires MFA
- All admin access logged
- Exceptions require approval
- Network segmentation limits impact

---

**Status**: ✅ **NETWORK SECURITY HARDENING COMPLETE**

All three components deployed: firewall, network isolation, and zero-trust access control.

