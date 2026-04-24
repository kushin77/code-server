# Zero-Trust Implementation Guide - P0 #1273

## Executive Summary

This guide covers the complete implementation of zero-trust network access (mTLS, 24h certificate rotation, egress firewall, audit logging) for kushin77/code-server production infrastructure.

## Phase 1: Immediate Actions (Today)

### 1.1 Generate Root and Intermediate CA

```bash
# Generate CA certificates
bash scripts/security/provision-mtls-certificates.sh --generate-ca

# Verify CA
bash scripts/security/provision-mtls-certificates.sh --verify
```

**Output:**
- `/config/mtls-certs/ca-root/ca-cert.pem` - Root CA (10-year validity)
- `/config/mtls-certs/ca-intermediate/ca-intermediate-cert.pem` - Signing CA
- All private keys stored securely

### 1.2 Generate Service Certificates

```bash
# Generate all service certificates
bash scripts/security/provision-mtls-certificates.sh --generate-certs

# Result: config/mtls-certs/services/<service>/{cert.pem, key.pem, fullchain.pem}
```

**Services Covered:**
- redis, postgres, pgbouncer (data plane)
- code-server, caddy (app/edge)
- prometheus, alertmanager, loki, promtail (observability)
- error-triage-engine (automation)
- 3x redis-sentinel (HA orchestration)

### 1.3 Mount Certificates to Docker

**Update docker-compose.yml:**

```yaml
services:
  redis:
    volumes:
      - ./config/mtls-certs/services/redis:/run/secrets/redis-cert:ro
      - ./config/mtls-certs/ca-intermediate:/run/secrets/ca:ro
    environment:
      REDIS_TLS_CERT: /run/secrets/redis-cert/cert.pem
      REDIS_TLS_KEY: /run/secrets/redis-cert/key.pem
      REDIS_TLS_CA: /run/secrets/ca/ca-chain.pem
    command: [...existing..., "--tls-port", "6379", "--port", "0", "--tls-cert-file", "/run/secrets/redis-cert/cert.pem", "--tls-key-file", "/run/secrets/redis-cert/key.pem"]
  
  postgres:
    volumes:
      - ./config/mtls-certs/services/postgres:/run/secrets/postgres-cert:ro
    environment:
      POSTGRES_HOST_AUTH_METHOD: trust  # Already scoped to docker network
    command: [...existing..., "-c", "ssl=on", "-c", "ssl_cert_file=/run/secrets/postgres-cert/cert.pem", "-c", "ssl_key_file=/run/secrets/postgres-cert/key.pem"]
```

**Apply Changes:**
```bash
docker compose down
docker compose up -d
docker compose logs redis  # Verify startup
```

## Phase 2: Verify mTLS Operation (Day 1-2)

### 2.1 Test mTLS Connections

```bash
# Test Redis mTLS
docker exec redis-sentinel-1 redis-cli -p 26379 \
  --tls \
  --cert /run/secrets/redis-sentinel-cert/cert.pem \
  --key /run/secrets/redis-sentinel-cert/key.pem \
  --cacert /run/secrets/ca/ca-chain.pem \
  INFO SENTINEL

# Output: Should show master status=ok
```

### 2.2 Monitor Certificate Expiry

```bash
# Check all certificates
for service in redis postgres caddy; do
  echo "=== $service ==="
  docker exec $service openssl x509 -in /run/secrets/$service-cert/cert.pem -noout -dates
done
```

### 2.3 Verify Service Connectivity

```bash
# All services should be healthy
docker compose ps

# Logs should not show certificate errors
docker compose logs | grep -i "cert\|tls\|ssl"
```

## Phase 3: Automate Rotation (Day 2-3)

### 3.1 Deploy Systemd Timer

```bash
# Copy timer and service files to host
scp etc/systemd/system/cert-rotation.* \
  akushnir@192.168.168.31:/etc/systemd/system/

# Enable and start
ssh akushnir@192.168.168.31 << 'EOF'
sudo systemctl daemon-reload
sudo systemctl enable cert-rotation.timer
sudo systemctl start cert-rotation.timer
sudo systemctl status cert-rotation.timer
EOF
```

### 3.2 Test Rotation

```bash
# Trigger manual rotation
ssh akushnir@192.168.168.31 << 'EOF'
cd /root/code-server-enterprise
bash scripts/security/rotate-mtls-certificates.sh
EOF

# Monitor rotation log
ssh akushnir@192.168.168.31 "tail -f /var/log/audit/mtls-rotation.log"
```

## Phase 4: Configure Egress Firewall (Day 3-4)

### 4.1 Preview Firewall Rules (no changes yet)

```bash
bash scripts/security/configure-egress-firewall.sh --dry-run
```

### 4.2 Enable on Test Server First

```bash
# Test on replica (192.168.168.42) first
ssh akushnir@192.168.168.42 << 'EOF'
sudo bash /root/code-server-enterprise/scripts/security/configure-egress-firewall.sh --enable
EOF

# Monitor for 24 hours for any connectivity issues
ssh akushnir@192.168.168.42 "sudo iptables -L OUTPUT -n"
```

### 4.3 Enable on Production

```bash
# Once verified on replica, enable on primary
ssh akushnir@192.168.168.31 << 'EOF'
sudo bash /root/code-server-enterprise/scripts/security/configure-egress-firewall.sh --enable
EOF
```

### 4.4 Verify All Services Functional

```bash
# Full connectivity test suite
bash tests/e2e/zero-trust-connectivity.sh
```

## Phase 5: Audit Logging (Day 4-5)

### 5.1 Deploy Audit Logger Sidecar

**Update docker-compose.yml:**
```yaml
services:
  mtls-audit-logger:
    image: ubuntu:22.04
    volumes:
      - ./scripts/observability/mtls-audit-logger.sh:/usr/local/bin/mtls-audit-logger.sh:ro
      - /var/log/audit:/var/log/audit
      - /var/run/docker.sock:/var/run/docker.sock:ro
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        apt-get update && apt-get install -y curl
        bash /usr/local/bin/mtls-audit-logger.sh
    networks:
      - net-management
    depends_on:
      - loki
```

### 5.2 Deploy and Verify

```bash
docker compose up -d mtls-audit-logger
docker compose logs mtls-audit-logger
```

### 5.3 Create Loki Dashboards

```bash
# Connections over time
{job="mtls-audit", log_type="mtls_connections"}

# Certificate expiry warnings
{job="mtls-audit", log_type="cert_warnings"}
```

## Phase 6: Testing & Validation (Day 5-7)

### 6.1 Load Testing with mTLS

```bash
# Measure latency impact of mTLS
bash tests/perf/measure-mtls-overhead.sh

# Expected overhead: <5% for intra-service communication
```

### 6.2 Failover Testing with Cert Rotation

```bash
# Simulate primary failure during cert rotation
bash tests/resilience/failover-during-rotation.sh
```

### 6.3 Security Validation

```bash
# Verify no unencrypted traffic between services
bash tests/security/audit-network-encryption.sh

# Check for certificate pinning opportunities
bash tests/security/analyze-cert-pinning.sh
```

## Rollback Procedures

### If Rotation Fails

```bash
# Restore previous certificates
BACKUP_DATE="2026-04-23-0200"  # Check /var/lib/cert-rotation/backups/
cd /root/code-server-enterprise/config/mtls-certs
tar -xzf /var/lib/cert-rotation/backups/certs-$BACKUP_DATE.tar.gz
docker compose restart redis postgres caddy
```

### If Firewall Breaks Connectivity

```bash
# Disable firewall temporarily
ssh akushnir@192.168.168.31 << 'EOF'
sudo bash /root/code-server-enterprise/scripts/security/configure-egress-firewall.sh --disable
EOF

# Diagnose blocked ports
sudo bash scripts/security/configure-egress-firewall.sh --status
sudo iptables -L OUTPUT -n -v | grep DROP
```

## Monitoring & Alerts

### Key Metrics

1. **Certificate Expiry**: Alert if cert expires within 7 days
2. **Rotation Success**: Alert if daily rotation fails
3. **Firewall Drops**: Alert if DROP count >1000/hour (possible attack)
4. **mTLS Handshake Errors**: Alert if error rate >1%

### Prometheus Queries

```promql
# Certificate expiry countdown
increase(cert_days_until_expiry[5m])

# Rotation success rate
rate(cert_rotation_complete[1h])

# Firewall drops
rate(iptables_output_drop_packets[5m])
```

## Documentation

- [Zero-Trust Architecture](docs/ZERO-TRUST-NETWORK-ARCHITECTURE.md)
- [mTLS Certificate Management](docs/CERTIFICATE-MANAGEMENT.md)
- [Egress Firewall Policies](docs/EGRESS-FIREWALL-POLICIES.md)
- [Audit Log Format](docs/AUDIT-LOG-SPECIFICATION.md)

## Timeline

| Phase | Task | Duration | Owner | Status |
|-------|------|----------|-------|--------|
| 1 | CA generation & service certs | 1 day | Copilot | In Progress |
| 2 | mTLS verification | 1 day | Copilot | Pending |
| 3 | Rotation automation | 1 day | Copilot | Pending |
| 4 | Egress firewall | 1 day | Copilot | Pending |
| 5 | Audit logging | 1 day | Copilot | Pending |
| 6 | Testing & validation | 2 days | QA | Pending |
| 7 | Documentation & runbooks | 1 day | Copilot | Pending |

**Total Implementation Time: 7-8 days**

## References

- [Cloudflare mTLS Guide](https://www.cloudflare.com/learning/access-management/what-is-mtls/)
- [CFSSL Documentation](https://github.com/cloudflare/cfssl/wiki)
- [Zero Trust Network Architecture](https://www.nist.gov/publications/zero-trust-architecture)
- [iptables Firewall Guide](https://wiki.archlinux.org/title/Iptables)
