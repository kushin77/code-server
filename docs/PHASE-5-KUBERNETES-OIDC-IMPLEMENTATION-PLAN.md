# Phase 5: Kubernetes Workload Identity Integration - Implementation Plan

## Current State ✅

The oauth2-oidc-issuer service (Phase 2.1) is already configured for Kubernetes:
- ✅ RS256 JWT signing enabled
- ✅ Kubernetes audience included  
- ✅ JWKS discovery endpoints (/.well-known/openid-configuration, /.well-known/jwks.json)
- ✅ JWT claims include: sub, aud, iss, iat, exp, email, groups, actor, repository
- ✅ Available on port 4182 with /.well-known prefix routing

## What's Needed (Phase 5)

### 1. Kubernetes ServiceAccount Configuration
- Create ServiceAccounts for system workloads (CI/CD, batch jobs, etc.)
- Configure projected volume with OIDC tokens
- Map ServiceAccount to JWT identity in issuer

### 2. Kubernetes Manifests
- ServiceAccount definitions for each workload type
- Pod spec templates showing token projection
- Example deployment using OIDC tokens

### 3. API Integration
- Verify JWT bearer token endpoints work
- Test RBAC authorization based on ServiceAccount/role binding
- Validate token claims match expected format

### 4. Testing Framework
- Unit tests for Kubernetes OIDC configuration
- Integration tests: Pod acquires token and calls API
- E2E test verifying service-to-service authentication
- Load test: Token acquisition under high concurrency

### 5. Documentation
- Architecture overview (OIDC issuer → K8s federation)
- Deployment guide for Kubernetes clusters
- Troubleshooting guide for token validation failures
- Examples of different workload types (CI/CD, batch, webhooks)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (GKE / On-Prem)                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────┐  ┌──────────────────────────────┐  │
│  │  ServiceAccount     │  │  Pod (workload)              │  │
│  │  - name: gh-actions │  │  - uses: gh-actions          │  │
│  │  - namespace: ci    │  │  - projected volume: token   │  │
│  └─────────────────────┘  └──────────────────────────────┘  │
│          ↓                        ↓                          │
│          └────────────────┬───────┘                          │
│                           │                                  │
│            Token projection volume (/var/run/secrets/...)    │
│                   Contains: JWT token                        │
│                           │                                  │
└───────────────────────────┼──────────────────────────────────┘
                            │
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  OIDC Issuer (on-prem at 192.168.168.31:4182)              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  POST /.well-known/oauth2/token                             │
│  Content-Type: application/x-www-form-urlencoded            │
│                                                              │
│  grant_type=urn:ietf:params:oauth:grant-type:token-exchange │
│  subject_token_type=urn:ietf:params:oauth:token-type:jwt    │
│  subject_token=<JWT from projected volume>                   │
│  audience=kubernetes                                        │
│                                                              │
│  Response: JSON with access_token (RS256 signed JWT)        │
│  Claims: sub, aud, iss, iat, exp, groups, actor, repository │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  API Server (192.168.168.31, port varies)                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Authorization middleware validates JWT:                    │
│  1. Verify RS256 signature against JWKS                     │
│  2. Check audience matches expected value                   │
│  3. Verify service account in 'actor' claim                 │
│  4. Apply RBAC based on groups in JWT                       │
│  5. Audit log: ServiceAccount action                        │
│                                                              │
│  Response: 200 OK or 403 Forbidden                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Sequence

### Step 1: Kubernetes Manifests (4 hours)
- [ ] Create `k8s/oidc-serviceaccounts.yaml` with ServiceAccount definitions
- [ ] Create `k8s/oidc-workload-deployments.yaml` with example deployments
- [ ] Document token projection in pod specs
- [ ] Verify manifests are syntactically correct

### Step 2: Test Pod Setup (3 hours)
- [ ] Create test pod that mounts OIDC token volume
- [ ] Script to acquire token from projected volume
- [ ] Script to exchange token for API access_token
- [ ] Verify token format and claims

### Step 3: API Integration Tests (3 hours)
- [ ] Write test: Pod can acquire token via OIDC issuer
- [ ] Write test: Token bearer header in API calls works
- [ ] Write test: RBAC enforcement based on pod's ServiceAccount
- [ ] Test invalid/expired token rejection

### Step 4: Documentation (2 hours)
- [ ] Architecture overview
- [ ] Kubernetes deployment guide
- [ ] Token acquisition flow diagram
- [ ] Troubleshooting guide

---

## Files to Create/Modify

```
kubernetes/
├── oidc-serviceaccounts.yaml          (NEW)
├── oidc-workload-deployments.yaml     (NEW)
├── github-actions-integration.yaml    (NEW)
└── token-exchange-test-pod.yaml       (NEW)

scripts/
├── kubernetes/
│   ├── test-oidc-token-acquisition.sh (NEW)
│   ├── test-api-integration.sh        (NEW)
│   └── verify-kubernetes-rbac.sh      (NEW)

tests/
├── kubernetes-oidc.spec.ts            (NEW)
├── k8s-token-exchange.test.ts         (NEW)
└── k8s-api-integration.test.ts        (NEW)

docs/
└── KUBERNETES-OIDC-INTEGRATION.md     (NEW)
```

---

## Estimated Effort

- Step 1 (Manifests): 4 hours
- Step 2 (Test Pod): 3 hours
- Step 3 (API Tests): 3 hours
- Step 4 (Documentation): 2 hours
- **Total: 12 hours** (matches issue estimate)

## Success Criteria ✅

- [ ] Kubernetes ServiceAccounts created and documented
- [ ] Pod successfully mounts OIDC token from projected volume
- [ ] Pod can acquire access_token from OIDC issuer
- [ ] API accepts JWT bearer tokens from pods
- [ ] RBAC enforcement verified (pod ServiceAccount → API permissions)
- [ ] All tests passing (unit, integration, E2E)
- [ ] Comprehensive documentation with examples
- [ ] Ready for GKE / on-prem Kubernetes deployment

---

**Next Step**: Begin Step 1 - Create Kubernetes manifests for ServiceAccount federation
**Status**: Phase 5 architecture documented, ready to implement
