# Phase 2: Service-to-Service Authentication & Workload Federation

**Issue**: #389 (P1 High) — Service-to-Service Auth  
**Phase**: 2 (of 4 for complete IAM)  
**Status**: IMPLEMENTING  
**Effort**: 21-30 hours  
**Dependencies**: Phase 1 IAM (#388) — Complete ✅  
**Blocked By**: PR #462 merge (Phase 1 implementation)  

---

## Executive Summary

Phase 2 implements zero-trust authentication between services using OpenID Connect (OIDC) workload federation and mutual TLS (mTLS). This eliminates long-lived secrets, enables automatic token rotation, and provides complete audit trails for all service-to-service communication.

**Key Deliverables**:
1. Kubernetes OIDC issuer configuration (on-prem 192.168.168.31)
2. GitHub Actions workload federation (self-hosted + cloud)
3. Service-to-service mTLS certificate auto-rotation
4. API token management microservice
5. Token validation and enforcement at service boundaries

---

## Architecture

### Service Identity Model

```
┌─────────────────────────────────────────────────────────────┐
│                    Workload Federation                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  code-server ◄──→ Prometheus ◄──→ Grafana                  │
│     (JWT)          (JWT)           (JWT)                     │
│     + mTLS         + mTLS          + mTLS                    │
│                                                              │
│  Services prove identity via:                               │
│  1. OIDC token (from K8s ServiceAccount)                    │
│  2. mTLS certificate (auto-rotated every 24h)              │
│  3. Request signing (HMAC SHA256)                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Token Flow

```
1. Service requests token from K8s OIDC issuer
   ↓
2. K8s issuer (on 192.168.168.31:8080/oidc) returns signed JWT
   ├── Subject: code-server:default
   ├── Audience: prometheus.kushnir.cloud
   ├── Expires: 1 hour
   ├── Contains: namespace, pod name, service account
   ↓
3. Service uses JWT to authenticate with target service
   ├── JWT in Authorization: Bearer header
   ├── mTLS cert in TLS handshake
   ├── Request signature in X-Request-Signature header
   ↓
4. Target service validates:
   ├── JWT signature (JWKS from K8s issuer)
   ├── JWT claims (subject, audience, expiry)
   ├── mTLS certificate chain
   ├── Request signature
   ↓
5. If all pass: request allowed
   If any fail: request denied (logged for audit)
```

---

## Implementation Roadmap

### Phase 2.1: Kubernetes OIDC Issuer (Days 1-2)

**Objective**: Expose K8s API's OIDC issuer publicly so services can verify tokens.

**Tasks**:
1. [ ] Deploy Caddy reverse proxy for OIDC issuer
   - Listen on 192.168.168.31:8080/oidc
   - Proxy to K8s API server OIDC endpoint (.well-known/openid-configuration)
   - Add mTLS certificate chain
   - Cache JWKS for 1 hour (reduce API load)

2. [ ] Configure K8s OIDC issuer
   - Enable service account token projection
   - Set issuer URL: https://192.168.168.31:8080/oidc
   - Configure audience: https://prometheus.kushnir.cloud (+ other services)

3. [ ] Test token generation
   - From code-server pod: curl -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://192.168.168.31:8080/oidc/.well-known/openid-configuration
   - Verify JWT is valid JSON Web Token

**Files to Create**:
- `config/k8s/oidc-issuer.yaml` - OIDC issuer configuration
- `config/caddy/oidc-proxy.conf` - Caddy reverse proxy rules
- `scripts/deploy-oidc-issuer.sh` - Automated deployment

**Success Criteria**:
- OIDC issuer responds at 192.168.168.31:8080/oidc
- All K8s pods can fetch valid JWTs
- JWKS endpoint accessible from all services

---

### Phase 2.2: mTLS Certificate Infrastructure (Days 2-3)

**Objective**: Automatic mTLS certificate generation, distribution, and rotation.

**Tasks**:
1. [ ] Deploy Vault or cert-manager for cert management
   - Vault: preferred (available on 192.168.168.31)
   - Alternative: cert-manager (Kubernetes native)
   - Mode: auto-rotation every 24 hours

2. [ ] Configure certificate issuance policy
   - CA cert: self-signed or root CA (192.168.168.31 PKI)
   - Service certs: one per service (code-server, prometheus, grafana, loki, etc.)
   - Cert validity: 365 days, rotation at 24-hour intervals
   - Key algorithms: RSA 4096 (or ECDSA P-256)

3. [ ] Distribute certificates to services
   - Mount via volume: /etc/tls/certs/{cert.pem, key.pem}
   - Or via secrets: kubernetes-secret / vault-agent injection
   - Mount CA cert: /etc/tls/ca/ca.pem (for peer verification)

4. [ ] Implement certificate rotation without downtime
   - Vault PKI uses gradual rollover
   - Services reload certs on change (no restart required)
   - Monitoring: alert on cert expiry < 7 days

**Files to Create**:
- `config/vault/pki-mTLS.hcl` - Vault PKI configuration
- `config/k8s/cert-rotation.yaml` - Cert rotation CronJob
- `scripts/distribute-mtls-certs.sh` - Certificate distribution script
- `terraform/modules/mtls-infrastructure/` - IaC for cert management

**Success Criteria**:
- All services have valid mTLS certificates
- Certificates rotate automatically every 24 hours
- No service downtime during rotation
- Expired certs trigger alerts

---

### Phase 2.3: Service-to-Service JWT Token Validation (Days 3-4)

**Objective**: Validate incoming JWTs and enforce service identity at request boundary.

**Tasks**:
1. [ ] Implement JWT validator middleware
   - Language: Bash (common to all services) or Go (high performance)
   - Check JWT signature against JWKS from 192.168.168.31:8080/oidc
   - Validate claims: subject, audience, expiry
   - Extract service identity from JWT: `sub = code-server:default`

2. [ ] Integrate into service entry points
   - Prometheus scrape targets: validate JWT from each job's HTTP client
   - Grafana datasource proxy: validate source service identity
   - Loki log aggregation: validate log source
   - Code-server API: validate inbound requests

3. [ ] Create allowlist-based service discovery
   - File: `config/service-authz-allowlist.yaml`
   - Format: source_service → target_service → actions
   - Example:
     ```yaml
     prometheus:
       - target: code-server
         actions: [read-metrics]
       - target: loki
         actions: [write-logs]
     ```

4. [ ] Implement deny-by-default with audit logging
   - All service-to-service requests default: DENY
   - Log all denials to central audit store
   - Alert on repeated failures (possible attack)

**Files to Create**:
- `scripts/jwt-validator.sh` - JWT validation library (bash)
- `config/service-authz-allowlist.yaml` - Service authorization rules
- `scripts/enforce-service-authz.sh` - Enforcement at Caddy layer
- `docs/SERVICE-TO-SERVICE-AUTH-TROUBLESHOOTING.md` - Debugging guide

**Success Criteria**:
- All inter-service requests authenticated via JWT
- Authorization enforced via allowlist
- 100% audit trail of all service-to-service calls
- Zero legitimate requests rejected

---

### Phase 2.4: GitHub Actions Workload Federation (Days 4-5)

**Objective**: Integrate GitHub Actions CI/CD with service identity.

**Tasks**:
1. [ ] Configure GitHub Actions OIDC issuer
   - Endpoint: github.com/.well-known/openid-configuration
   - Token request flow: GitHub Actions → GitHub OIDC issuer → JWT

2. [ ] Set up workload federation for kushin77/code-server repo
   - Target service: code-server (deployment automation)
   - Conditions: 
     - `github_owner: kushin77`
     - `github_repo: code-server`
     - `github_workflow: deploy.yml`
     - `github_ref: main` (only merge to main, not feature branches)

3. [ ] Create GitHub Actions deployment workflow
   ```yaml
   - name: Get identity token
     uses: actions/github-script@v7
     with:
       script: |
         const token = core.getIDToken('https://192.168.168.31:8080/oidc');
         // Use token to authenticate to code-server API for deployment
   ```

4. [ ] Implement deploy-only mode for GitHub Actions
   - Limited permissions (no secrets, limited to deployment)
   - Cannot modify infrastructure or IAM policies
   - Signed requests only (prevent replay attacks)

**Files to Create**:
- `.github/workflows/deploy-via-workload-federation.yml` - Deployment workflow
- `config/github-actions-federation.yaml` - OIDC configuration
- `scripts/github-actions-token-handler.sh` - Token validation for GitHub Actions
- `docs/GITHUB-ACTIONS-WORKLOAD-FEDERATION.md` - Setup guide

**Success Criteria**:
- GitHub Actions can authenticate using JWT tokens
- Deployments only via authenticated workflow
- No long-lived GitHub Personal Access Tokens
- Audit trail of all GitHub Actions deployments

---

### Phase 2.5: API Token Management Microservice (Days 5-6)

**Objective**: Manage short-lived API tokens for service-to-service communication.

**Tasks**:
1. [ ] Design token microservice API
   - Endpoint: /api/v1/token/request
   - Auth: JWT + mTLS
   - Returns: access_token, refresh_token, expires_in, token_type
   - Example request:
     ```bash
     curl -X POST \
       --cert /etc/tls/certs/code-server.pem \
       --key /etc/tls/certs/code-server-key.pem \
       -H "Authorization: Bearer $JWT" \
       https://192.168.168.31:8080/api/v1/token/request \
       -d '{"audience": "prometheus.kushnir.cloud"}'
     ```

2. [ ] Implement token storage (Redis)
   - Keys: service:audience:token_id
   - TTL: 1 hour (access_token), 7 days (refresh_token)
   - Encryption: AES-256-GCM per token
   - Revocation: immediate (on security event)

3. [ ] Create token refresh mechanism
   - Refresh tokens valid for 7 days
   - New access_token issued on refresh (1-hour validity)
   - Refresh tokens cannot be refreshed (prevent infinite chains)

4. [ ] Implement token audit logging
   - Log all token requests: who, when, audience, outcome
   - Alert on: token exhaustion, repeated failures, rate limit exceeded
   - Archive logs: GCP Secret Manager or on-prem storage

**Files to Create**:
- `services/token-microservice/main.go` - Token microservice
- `config/token-microservice/policy.yaml` - Token policies
- `scripts/deploy-token-microservice.sh` - Deployment script
- `docs/TOKEN-MANAGEMENT-OPERATIONS.md` - Operations guide

**Success Criteria**:
- Token microservice available at 192.168.168.31:8080/api/v1/token
- All services can request and use tokens
- Token refresh working correctly
- Complete audit trail of all token operations

---

## Testing Strategy

### Unit Tests (All components)
- JWT validation: correct sig, expired, invalid audience
- mTLS: cert validation, chain verification, rotation
- Service authz: allowlist enforcement, deny-by-default

### Integration Tests
- Full flow: K8s pod → OIDC issuer → JWT → service validation
- mTLS handshake: cert exchange, peer verification
- Token refresh: request new token, refresh existing token

### Load Testing
- 1000 concurrent JWT validations per second
- Token microservice: 500 token requests per second
- Certificate rotation: no service downtime

### Security Testing
- JWT tampering: signature validation
- Expired tokens: rejection
- mTLS bypass: enforce TLS 1.3+
- Replay attacks: request signatures prevent replay

### Audit Testing
- All service-to-service calls logged
- Audit entries immutable (sent to central log store)
- No sensitive data in logs (secrets redacted)

---

## Rollback Plan

If Phase 2 fails to deploy:
1. **In-progress deployments**: kubectl rollout undo
2. **Failed components**: revert to Phase 1 (service identities still work via Phase 1 OIDC)
3. **Broken mTLS**: services fall back to plaintext HTTP (temporary, 24h max)
4. **Token microservice failure**: services use JWT directly (no token refresh)

**Recovery Time**: < 15 minutes for any component

---

## Success Criteria

✅ **Implementation Complete**:
- Kubernetes OIDC issuer accessible and functioning
- All services have valid mTLS certificates
- Service-to-service JWT validation enforced
- GitHub Actions workload federation working
- Token microservice operational
- Complete audit trail for all service-to-service communication

✅ **Testing Complete**:
- Unit tests: 100% coverage for critical paths
- Integration tests: all flows passing
- Load testing: 1000+ JWT validations/sec
- Security testing: all attack vectors blocked

✅ **Production Ready**:
- No long-lived secrets in service-to-service communication
- Automatic certificate rotation every 24 hours
- Token expiry/refresh: all services handle gracefully
- Monitoring and alerting for all components

---

## Timeline

| Phase | Week | Effort | Owner |
|-------|------|--------|-------|
| 2.1 OIDC Issuer | Week 1 | 8h | @kushin77 |
| 2.2 mTLS Infra | Week 1-2 | 6h | @infra-team |
| 2.3 JWT Validation | Week 2 | 8h | @kushin77 |
| 2.4 GitHub Actions | Week 2 | 4h | @platform-team |
| 2.5 Token Microservice | Week 2-3 | 6h | @backend-team |
| **Total Phase 2** | **3 weeks** | **32h** | **Full team** |

---

## Dependencies & Sequencing

```
Phase 1 ✅ (complete in PR #462)
  ↓
Phase 2 (← YOU ARE HERE)
  ├─ 2.1 OIDC Issuer (foundation)
  ├─ 2.2 mTLS Infrastructure (foundation)
  ├─ 2.3 JWT Validation (depends on 2.1)
  ├─ 2.4 GitHub Actions (depends on 2.1)
  └─ 2.5 Token Microservice (depends on 2.1-2.3)
    ↓
Phase 3: RBAC Enforcement (depends on Phase 2)
  ↓
Phase 4: Compliance Automation (depends on Phase 3)
```

---

## Deliverables (Phase 2 Complete)

1. ✅ Kubernetes OIDC issuer publicly accessible
2. ✅ All services have valid, auto-rotating mTLS certificates
3. ✅ Service-to-service requests require valid JWT + mTLS
4. ✅ GitHub Actions can authenticate and deploy
5. ✅ Token management microservice operational
6. ✅ 100% audit trail for service-to-service communication
7. ✅ Runbooks for incident response
8. ✅ Complete monitoring and alerting

---

## Notes for Implementation

- **On-prem focus**: All infrastructure on 192.168.168.31 (+ replica .42)
- **Zero trust**: All service-to-service communication authenticated and authorized
- **Immutable IaC**: All configuration in Terraform/Ansible
- **Audit everything**: Every service-to-service call logged for compliance

---

**Status**: Ready for implementation after PR #462 merges to main  
**Next Phase**: Phase 3 - RBAC Enforcement (8-10 hours)  
**Owner**: @kushin77 (can distribute to team members)  

---

Last Updated: April 16, 2026  
Session: #3 (Execution Phase)
