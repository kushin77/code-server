# Zero-Trust Network Access - P0 #1273

## Overview

Implement mutual TLS (mTLS) authentication between all services, 24h certificate rotation, egress firewall policies, and connection audit logging.

## Architecture

### 1. Certificate Infrastructure

**Components:**
- Root CA: Self-signed CA certificate (valid 10 years)
- Intermediate CA: Signing intermediate certificates (valid 2 years)  
- Service Certificates: Per-service certs signed by intermediate (valid 30 days, rotated every 24h)
- Client Certificates: Per-service client certs for outbound connections (valid 30 days, rotated every 24h)

**Storage:**
- Root CA: `/etc/secrets/ca-root/` (read-only, mounted as secret)
- Intermediate CA: `/etc/secrets/ca-intermediate/` (read-only)
- Service certs: `/etc/secrets/certs/<service>/` (mounted per service)
- Rotation artifacts: `/var/lib/cert-rotation/` (persistent volume for automation)

**Generation Method:**
- Use cfssl for certificate generation (deterministic, repeatable)
- All certs generated with:
  - Subject CN: `<service>.<network>.local`
  - DNS SANs: `<service>`, `<service>.<network>.local`, `localhost`
  - Extended Key Usage: both TLS Server Auth and TLS Client Auth
  - Validity: 30 days (rotated daily, safety margin 29d before expiry)

### 2. mTLS Implementation Per Service

**Services requiring mTLS:**
- redis → sentinel (authenticated sentinel access)
- postgres ← pgbouncer (pg connection pooling)
- code-server ← caddy (reverse proxy)
- prometheus → all exporters (scrape auth)
- alertmanager ← prometheus (alert delivery auth)
- error-triage-engine ← loki (log queries)
- all services ← metrics collection endpoints

**Configuration Pattern (Docker Compose):**

```yaml
services:
  redis:
    environment:
      REDIS_TLS_CERT: /run/secrets/redis-cert
      REDIS_TLS_KEY: /run/secrets/redis-key
      REDIS_TLS_CA_CERT: /run/secrets/ca-cert
      REDIS_TLS_PORT: 6379  # mTLS on 6379, unauth removed
    volumes:
      - redis-certs:/run/secrets:ro
    command: ["redis-server", "--tls-port", "6379", "--port", "0", "--tls-cert-file", "/run/secrets/redis-cert/cert.pem", ...]

  postgres:
    environment:
      POSTGRES_TLS_CERT: /run/secrets/postgres-cert
      POSTGRES_TLS_KEY: /run/secrets/postgres-key
    command: ["-c", "ssl=on", "-c", "ssl_cert_file=/run/secrets/postgres-cert/cert.pem", ...]
```

### 3. Certificate Rotation (24h Cycle)

**Rotation Script:** `scripts/security/rotate-mtls-certificates.sh`

**Cycle:**
- Every 24h at 02:00 UTC:
  1. Generate new certificate pair (30-day validity)
  2. Verify CSR and sign with intermediate CA  
  3. Validate new cert chain before deployment
  4. Deploy to all services simultaneously (zero-downtime):
     - Write new certs to temporary location
     - `docker exec <service> reload` or restart with new certs mounted
     - Verify connectivity after rotation
  5. Cleanup old certs (keep 7-day backups)
  6. Log rotation event to audit log

**Systemd Timer:**
```ini
[Unit]
Description=mTLS Certificate Rotation

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

### 4. Iptables Egress Policy

**Default Deny Principle:**
- All egress traffic is DROP by default
- Whitelist only required connections:
  - DNS (53/UDP): for domain resolution
  - NTP (123/UDP): for time sync
  - NAS (2049/TCP): for backup/storage
  - Outbound HTTPS (443/TCP): for GitHub API, external registries
  - Inter-service mTLS (defined per service pair)

**Implementation:**
```bash
# Default policies
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow docker bridge (inter-service)
iptables -A OUTPUT -o docker0 -j ACCEPT
iptables -A OUTPUT -o br-* -j ACCEPT

# Allow essential services
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT  # DNS
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT # NTP
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT # HTTPS

# Allow NAS
iptables -A OUTPUT -d 192.168.168.56 -p tcp --dport 2049 -j ACCEPT

# Deny by default
iptables -A OUTPUT -j DROP
```

### 5. Connection Audit Logging

**Log All mTLS Connections:**
- Log file: `/var/log/audit/mtls-connections.log`
- Format: `timestamp | source_service | source_cert_cn | dest_service | dest_cert_cn | protocol | action`

**Implementation:**
- Sidecar audit logger container (one per host)
- Monitor `/proc/net/tcp` and cross-reference with certificate CNs
- Extract from Docker logs for each service startup/shutdown
- Send events to Loki for retention and query

**Example Log Entry:**
```
2026-04-23T02:15:30Z | redis-sentinel-1 | redis-sentinel.net-app.local | redis | redis.net-app.local | TLS_1.3 | CONNECTED
2026-04-23T02:15:31Z | redis-sentinel-1 | redis-sentinel.net-app.local | redis | redis.net-app.local | TLS_1.3 | DISCONNECTED
```

## Implementation Phases

### Phase 1: Certificate Infrastructure (Days 1-2)
- [ ] Create CA and intermediate CA certificates
- [ ] Generate service certificates for all services
- [ ] Create certificate provisioning script (`scripts/security/provision-mtls-certificates.sh`)
- [ ] Mount certificates to services in docker-compose.yml
- [ ] Test certificate validation with curl/openssl
- [ ] Document certificate structure and lifecycle

### Phase 2: Service mTLS Configuration (Days 2-3)
- [ ] Configure Redis to use mTLS (redis-tls)
- [ ] Configure PostgreSQL to use SSL
- [ ] Configure pgbouncer to use client certificates
- [ ] Configure each service to validate peer certificates
- [ ] Add health checks for mTLS endpoints
- [ ] Test end-to-end mTLS connectivity

### Phase 3: Certificate Rotation Automation (Days 3-4)
- [ ] Implement `scripts/security/rotate-mtls-certificates.sh`
- [ ] Create systemd timer for daily rotation
- [ ] Test rotation without downtime
- [ ] Implement fallback/rollback procedure
- [ ] Log all rotation events

### Phase 4: Egress Firewall Rules (Days 4-5)
- [ ] Audit all current egress connections
- [ ] Implement default-deny iptables policies
- [ ] Whitelist required outbound traffic
- [ ] Test application functionality with firewall enabled
- [ ] Document required exceptions

### Phase 5: Audit Logging & Monitoring (Days 5-6)
- [ ] Implement audit sidecar container
- [ ] Configure mTLS connection logging
- [ ] Create Loki dashboards for audit events
- [ ] Add alerts for certificate rotation failures
- [ ] Add alerts for unauthorized connection attempts

### Phase 6: Testing & Verification (Days 6-7)
- [ ] Load testing with mTLS overhead
- [ ] Failover testing with certificate rotation
- [ ] Security scanning for cert vulnerabilities
- [ ] Documentation of operational procedures
- [ ] Runbook for emergency cert revocation

## Related Issues

- #1272 - EPIC Security & Compliance
- #1123 - EPIC Zero-Trust Network Access
- #1392 - Firewall hardening (complementary)

## Dependencies

- `cfssl` - Certificate generation tool
- `jq` - JSON processing
- `openssl` - Certificate validation
- `logrotate` - Log rotation
- Docker mTLS support (built-in)

## Security Considerations

1. **Key Storage**: Private keys never leave the host, only mounted as secrets
2. **Key Rotation**: Daily cert rotation minimizes impact of key compromise
3. **Audit Trail**: All connections logged for forensic analysis
4. **Zero Trust**: Deny-by-default, whitelist only required traffic
5. **Default Passwords**: All certificates generated deterministically, no manual secrets

## References

- [mTLS best practices](https://www.cloudflare.com/learning/access-management/what-is-mtls/)
- [cfssl documentation](https://github.com/cloudflare/cfssl)
- [Zero Trust Networking](https://www.cloudflare.com/learning/security/glossary/zero-trust-security/)
