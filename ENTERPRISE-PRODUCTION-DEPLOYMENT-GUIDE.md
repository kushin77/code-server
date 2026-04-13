# ENTERPRISE PRODUCTION DEPLOYMENT GUIDE
## Complete Multi-Tier Infrastructure with 99.99% SLA

**Version:** 1.0 Enterprise Edition  
**Status:** PRODUCTION READY  
**Target SLA:** 99.99% (4 nines) with <5min MTTR  
**Date:** 2026-04-13  

---

## Table of Contents

1. [Pre-Deployment Requirements](#pre-deployment-requirements)
2. [Week 1: Infrastructure Setup](#week-1-infrastructure-setup)
3. [Week 2: Credential & Security Setup](#week-2-credential--security-setup)
4. [Week 3: Application Deployment](#week-3-application-deployment)
5. [Week 4: Validation & Optimization](#week-4-validation--optimization)
6. [Ongoing Operations](#ongoing-operations)

---

## Pre-Deployment Requirements

### Hardware & Infrastructure

**Production Environment (192.168.168.31):**
- CPU: 8+ cores (minimum: 4 physical cores)
- RAM: 32GB minimum (16GB for development, 64GB recommended for peak load)
- Storage: 500GB+ SSD for application data
- Network: 1Gbps+ with DDoS protection (CloudFlare)
- Backup: Off-site replication (daily snapshots, cross-region)

### Software Stack

- Docker: 20.10+
- Docker Compose: 2.10+
- Linux: Ubuntu 22.04 LTS (or equivalent)
- Kernel: 5.10+ with eBPF support (for advanced observability)

### Team & Skills

- **DevOps Engineer:** Infrastructure, Kubernetes/Docker, monitoring
- **Security Engineer:** Vault, TLS, network policies, compliance
- **Database Administrator:** PostgreSQL, replication, backup/recovery
- **SRE Lead:** On-call rotation, incident response, SLO management

---

## Week 1: Infrastructure Setup

### Day 1-2: Provision Cloud Infrastructure

```bash
# Using Terraform for infrastructure-as-code
terraform init
terraform workspace new production
terraform plan
terraform apply

# Created resources:
# - Compute instances (primary + warm standby)
# - Load balancer (CloudFlare)
# - Network security groups
# - Storage volumes (persistent)
# - Backup snapshots
```

### Day 3: Install Base System

```bash
# SSH into 192.168.168.31
ssh akushnir@192.168.168.31

# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose v2
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version
```

### Day 4: Network & Storage Setup

```bash
# Create persistent storage directories
sudo mkdir -p /data/{redis,postgres,ollama,coder,prometheus,jaeger,elasticsearch}
sudo chown -R 1000:1000 /data/*
sudo chmod -R 755 /data

# Configure Docker bridge network
docker network create \
  --driver bridge \
  --subnet 10.0.8.0/24 \
  production-enterprise

# Setup off-site backup replication
sudo apt-get install -y rsync
# Configure rsync to S3 or GCS (daily snapshots)
```

### Day 5: Clone Repository & Prepare Files

```bash
# Clone deployment repository
git clone https://github.com/kushin77/code-server-enterprise.git
cd code-server-enterprise

# Copy production files
cp docker-compose.production.yml docker-compose.yml
cp Caddyfile.production Caddyfile
cp .env.production .env

# Review configuration files
ls -la *.production *.yml *.sql .env
```

---

## Week 2: Credential & Security Setup

### Day 8-9: HashiCorp Vault Setup

```bash
# Create Vault directory
sudo mkdir -p /etc/vault /opt/vault/data
sudo chmod 700 /opt/vault/data

# Start Vault container
docker run -d \
  --name vault \
  -p 8200:8200 \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=my-root-token' \
  -e 'VAULT_ADDR=http://0.0.0.0:8200' \
  vault:latest

# Initialize Vault (production uses raft storage with HSM seal)
vault operator init -key-shares=5 -key-threshold=3

# Unseal Vault (use 3 of 5 keys)
vault operator unseal <key-1>
vault operator unseal <key-2>
vault operator unseal <key-3>

# Verify Vault is running
curl -L http://localhost:8200/v1/sys/health | jq
```

### Day 10-11: Load Secrets into Vault

```bash
# Create secret engine
vault secrets enable -version=2 -path=secret kv

# Create all production secrets
vault kv put secret/production/cloudflare/api-token \
  value='<your-cloudflare-api-token>'

vault kv put secret/production/google/oauth \
  client-id='<your-google-client-id>' \
  client-secret='<your-google-client-secret>'

vault kv put secret/production/oauth2-proxy \
  cookie-secret='<32-byte-random-string>'

vault kv put secret/production/duo \
  integration-key='<duo-integration-key>' \
  secret-key='<duo-secret-key>' \
  api-host='<duo-api-host>'

vault kv put secret/production/code-server \
  password='<strong-32-character-password>'

vault kv put secret/production/redis \
  password='<strong-32-character-password>'

vault kv put secret/production/postgres \
  password='<strong-32-character-password>'

vault kv put secret/production/elasticsearch \
  password='<strong-32-character-password>'

vault kv put secret/production/github \
  token='<github-personal-access-token>'

vault kv put secret/production/slack \
  webhook-url='<slack-webhook-url>'

vault kv put secret/production/pagerduty \
  integration-key='<pagerduty-integration-key>'

# List all secrets
vault kv list secret/production/

# Verify secrets can be read
vault kv get secret/production/cloudflare/api-token
```

### Day 12: Update .env with Vault Secrets

```bash
# Create .env by replacing VAULT_* placeholders
source_vault_secrets() {
  export CLOUDFLARE_API_TOKEN=$(vault kv get -field=value secret/production/cloudflare/api-token)
  export GOOGLE_CLIENT_ID=$(vault kv get -field=client-id secret/production/google/oauth)
  export GOOGLE_CLIENT_SECRET=$(vault kv get -field=client-secret secret/production/google/oauth)
  # ... repeat for all secrets
}

source_vault_secrets

# Verify .env is complete
grep -E "^\w+=" .env | wc -l  # Should have 20+ variables
```

---

## Week 3: Application Deployment

### Day 15: Docker Image Preparation

```bash
# Build custom images
docker-compose build code-server ssh-proxy

# List built images
docker images | grep -E "code-server|ssh-proxy"

# Pull pre-built images
docker-compose pull caddy ollama redis postgres prometheus elasticsearch

# Verify all images available
docker-compose images
```

### Day 16: Start Infrastructure Services (Tier 5 - Data Layer)

```bash
# Start PostgreSQL
docker-compose up -d postgres
sleep 30
docker-compose logs postgres

# Start Redis
docker-compose up -d redis
docker-compose logs redis

# Health check
docker-compose exec postgres pg_isready
docker-compose exec redis redis-cli ping
```

### Day 17: Start Security & Auth Services (Tier 3a)

```bash
# Start Vault
docker-compose up -d vault
sleep 20

# Start OAuth2-Proxy
docker-compose up -d oauth2-proxy
docker-compose logs oauth2-proxy

# Verify OAuth2-Proxy is responding
curl -L http://localhost:4180/ping
```

### Day 18: Start Observability Stack (Tier 3b)

```bash
# Start Prometheus
docker-compose up -d prometheus
sleep 10

# Start Elasticsearch
docker-compose up -d elasticsearch
sleep 60  # takes time to initialize

# Start Kibana
docker-compose up -d kibana

# Start Jaeger
docker-compose up -d jaeger

# Start AlertManager
docker-compose up -d alertmanager

# Verify all are healthy
docker-compose ps | grep -E "healthy|running"
```

### Day 19: Start Application Services (Tier 4)

```bash
# Start Caddy reverse proxy
docker-compose up -d caddy

# Start Code-Server
docker-compose up -d code-server

# Start Ollama
docker-compose up -d ollama
sleep 120  # Ollama takes time to warm up

# Start monitoring agents
docker-compose up -d node-exporter cadvisor

# Verify all services
docker-compose ps

# Expected output: All 13 services running/healthy
```

### Day 20: Full System Verification

```bash
# Check all containers
docker-compose ps -a

# Verify network connectivity
docker-compose exec caddy curl -L http://oauth2-proxy:4180/ping
docker-compose exec code-server curl -L http://ollama:11434/api/tags

# Check logs for errors
docker-compose logs --tail=50 | grep -i error

# Performance verification
docker stats --no-stream
```

---

## Week 4: Validation & Optimization

### Day 22: Security Hardening Validation

```bash
# 1. Verify TLS configuration
openssl s_client -connect ide.kushnir.cloud:443 -tls1_3 | head -20

# 2. Check security headers
curl -I https://ide.kushnir.cloud | grep -E "Strict-Transport|Content-Security|X-"

# 3. Verify no hardcoded secrets
docker-compose config | grep -i "password\|secret\|token" | grep -v "${" | wc -l
# Should be 0

# 4. Test authentication flow
curl -L -c cookies.txt https://ide.kushnir.cloud
# Should redirect to Google OAuth

# 5. Security scanning
docker run --rm aquasec/trivy image code-server-patched:latest
docker run --rm aquasec/trivy image caddy:latest
```

### Day 23: Performance Testing & Optimization

```bash
# Load testing (using Apache Bench)
ab -n 10000 -c 100 https://ide.kushnir.cloud/health

# Running vegeta for sustained load
echo "GET https://ide.kushnir.cloud/health" | \
  vegeta attack -duration=60s -rate=100 | \
  vegeta report -type=text

# Expected metrics:
# - p95 latency: < 200ms
# - p99 latency: < 500ms
# - Error rate: < 0.1%

# Collect baseline metrics
curl http://localhost:9090/api/v1/query?query=request_duration_seconds_bucket | jq .
```

### Day 24-25: Monitoring Dashboard Setup

```bash
# Create Grafana dashboards (or use vendor-provided)
# Import dashboard JSON files from grafana.com repository

# Example: Navigate to Grafana at http://localhost:3000
# 1. Add Prometheus datasource: http://prometheus:9090
# 2. Add Elasticsearch datasource: http://elasticsearch:9200
# 3. Import community dashboards:
#    - Docker monitoring
#    - PostgreSQL monitoring
#    - Redis monitoring
#    - Application metrics

# Setup alert rules in Prometheus
docker-compose exec prometheus promtool check rules /etc/prometheus/rules/*.yml

# Test AlertManager integration
curl -X POST http://localhost:9093/api/v1/alerts \
  -d '[{"labels":{"alertname":"TestAlert","severity":"critical"},"annotations":{"summary":"Test"}}]'
```

---

## Ongoing Operations

### Daily Operations Checklist

```bash
#!/bin/bash
# daily-operations.sh

echo "=== Daily Production Health Check ==="
date

# 1. Service status
docker-compose ps | grep -v "Up"
echo "Services: $(docker-compose ps -q | wc -l)/13 running"

# 2. Resource usage
docker stats --no-stream | tail -n +2 | awk '{print $1, $3, $4}'

# 3. Disk space
df -h /data | tail -1 | awk '{print "Disk: "$5" used"}'

# 4. Database connectivity
docker-compose exec -T postgres pg_isready && echo "PostgreSQL: OK" || echo "PostgreSQL: ERROR"

# 5. Key service health
curl -s http://localhost:9090/-/healthy && echo "Prometheus: OK" || echo "ERROR"
curl -s http://localhost:9200/_cluster/health | jq .status

# 6. Recent alerts
curl -s http://localhost:9093/api/v1/alerts?active=1 | jq '.data | length'

# 7. Backup status
ls -lh /backups/latest 2>/dev/null || echo "No recent backup"

# 8. Error rate (last 5 minutes)
curl -s 'http://localhost:9090/api/v1/query?query=rate(errors_total%5B5m%5D)' | jq

echo "=== End Health Check ==="
```

### Weekly Operations

```bash
# Test disaster recovery procedure (weekly)
# - Simulate service failure
# - Verify automatic failover
# - Check backup restoration

# Review metrics and trends
# - Look for performance degradation
# - Check cost trends
# - Identify optimization opportunities

# Security review
# - Check audit logs
# - Review failed login attempts
# - Verify credential rotation
```

### Monthly Operations

```bash
# Full backup validation
# Test restore procedure on warm standby

# Capacity planning
# Analyze growth trends
# Plan for scale-out if needed

# Compliance audit
# Review security controls
# Verify data retention policies

# Team training
# Incident response drills
# On-call rotation training
```

### Quarterly Operations

```bash
# Disaster recovery drill (all regions)
# Failover to secondary data center
# Test RTO/RPO targets

# Architecture review
# Identify technical debt
# Plan improvements

# Cost optimization
# Review vendor contracts
# Evaluate new services

# Security assessment
# Third-party vulnerability scan
# Compliance certification review
```

---

## Troubleshooting Guide

### Services Won't Start

```bash
# Check logs
docker-compose logs <service-name>

# Common issues:
# 1. Port already in use: sudo netstat -tlnp | grep -E "80|443|8200"
# 2. Disk full: df -h
# 3. Permission denied: sudo chown -R 1000:1000 /data
# 4. Out of memory: free -h
```

### High Error Rate

```bash
# Check individual service logs
docker-compose logs code-server | tail -50
docker-compose logs ollama | tail -50

# Monitor metrics in real-time
watch -n 1 'curl -s http://localhost:9090/api/v1/query?query=errors_total | jq'

# Check circuit breaker status
curl http://localhost:9090/api/v1/query?query=circuit_breaker_state | jq
```

### Slow Response Times

```bash
# Check latency percentiles
curl 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,request_duration_seconds_bucket)' | jq

# Check resource utilization
docker stats --no-stream

# Profile application
# Enable pprof: http://localhost:6060/debug/pprof
```

---

## Success Criteria

✅ **Deployment Successful When:**

- All 13 services running and healthy
- HTTPS certificate valid (A+ SSL Labs rating)
- OAuth authentication working
- Prometheus collecting metrics
- Alerts firing and routing correctly
- PostgreSQL replicating to standby
- Response times meeting targets (p95 < 200ms)
- Zero hardcoded secrets in configuration
- All audit logs flowing to ELK
- Backup/restore validated and working

---

## Next Phases

### Phase 2: High Availability (Week 5-6)
- Deploy second region (us-east1)
- Set up active-active failover
- Global load balancing
- Cross-region replication

### Phase 3: Advanced Observability (Week 7-8)
- Machine learning anomaly detection
- Predictive autoscaling
- Cost attribution per user
- Advanced performance profiling

### Phase 4: Compliance & Audit (Week 9-10)
- SOC2 Type II assessment
- GDPR compliance verification
- Automated compliance reporting
- Security policy hardening

---

**Status:** READY FOR PRODUCTION DEPLOYMENT  
**Estimated Timeline:** 4 weeks (infrastructure → validation)  
**Next Action:** Begin Week 1 infrastructure setup  

