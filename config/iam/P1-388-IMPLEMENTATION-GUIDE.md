# P1 #388: Identity & RBAC Implementation Guide

**Status**: Phase 3 Complete ✅  
**Scope**: Standardized identity, RBAC, and workload authentication  
**Target**: All platform surfaces (code-server, Backstage, Appsmith, AI-Gateway)  

---

## Architecture Overview

### 3-Tier RBAC Model

```
┌─────────────────────────────────────────────────────────────┐
│                    IDENTITY FEDERATION                       │
│  (Google OIDC + GitHub Teams + Workload Identity + Webhooks) │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
    ┌───▼──┐      ┌───▼──┐      ┌───▼──┐
    │ ADMIN │      │ OPER │      │ VIEW │
    └───┬──┘      └───┬──┘      └───┬──┘
        │              │              │
    ┌───▼──────────────▼──────────────▼───┐
    │     KUBERNETES RBAC ENFORCEMENT      │
    │  (Roles, RoleBindings, AuthZ Policy) │
    └───┬──────────────────────────────────┘
        │
    ┌───▼─────────────────────────────┐
    │  SERVICE-TO-SERVICE AUTHZ POLICY │
    │  (JWT tokens + mTLS + API tokens) │
    └─────────────────────────────────┘
```

---

## 1. RBAC Tiers

### TIER 1: Admin (Unrestricted)
**Services**: Backstage (platform control)  
**Capabilities**:
- Create/delete services and deployments
- Manage secrets and credentials
- Create/modify RBAC policies
- Emergency access procedures

**Example**: Deploy new microservice, rotate database credentials

---

### TIER 2: Operator (Create/Update, no Delete)
**Services**: Code-Server, Appsmith, AI-Gateway, PostgreSQL  
**Capabilities**:
- Create and update deployments
- Read/write ConfigMaps and Secrets
- Manage own workloads
- Access logs and metrics
- Cannot delete cluster-wide resources

**Example**: Update application config, scale deployment, execute backups

---

### TIER 3: Viewer (Read-Only)
**Services**: Prometheus, observability tools  
**Capabilities**:
- List and read resources
- Query logs and metrics
- No write access
- No secret access

**Example**: View deployment status, query metrics, read logs

---

## 2. Service Assignments

| Service | RBAC Tier | JWT Claims | Use Case |
|---------|-----------|-----------|----------|
| **code-server** | Operator | service:code-server | IDE operations, workspace management |
| **Backstage** | Admin | service:backstage | Platform deployment orchestration |
| **Appsmith** | Operator | service:appsmith | Low-code CRUD operations |
| **AI-Gateway** | Operator | service:ai-gateway | Model inference, cache management |
| **PostgreSQL** | Operator | service:postgresql | Database replication, backups |
| **Prometheus** | Viewer | service:prometheus | Metrics scraping (read-only) |

---

## 3. JWT Token Structure

All service-to-service calls use JWT tokens signed by the OIDC issuer:

```json
{
  "iss": "https://kushnir.cloud/oidc",
  "sub": "service:ai-gateway",
  "aud": "kushnir77/code-server",
  "service": "ai-gateway",
  "rbac_role": "operator",
  "team": "ai-team",
  "permissions": ["read:models", "write:cache"],
  "tier": "backend",
  "owner_email": "ai-team@kushnir.cloud",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "issued_by": "workload-identity-issuer",
  "intended_use": "workload-federation",
  "iat": 1671234567,
  "exp": 1671238167,
  "nbf": 1671234567
}
```

**Key Claims**:
- `service`: Which service is calling
- `rbac_role`: RBAC tier (admin/operator/viewer)
- `permissions`: Explicit operation list
- `correlation_id`: Request tracing across services
- `exp`: Token expiration (1 hour default)

---

## 4. Service-to-Service Authentication Matrix

### Code-Server → Other Services
```
code-server:
  → Backstage: workload JWT (deploy info)
  → Appsmith: workload JWT (app catalog)
  → AI-Gateway: workload JWT (features)
  → PostgreSQL: connection pool (system user)
```

### Backstage → Other Services
```
backstage:
  → code-server: workload JWT (workspace mgmt)
  → PostgreSQL: workload JWT (deployments)
  → AI-Gateway: workload JWT (intelligence)
  → GitHub: GitHub personal token (webhooks)
```

### AI-Gateway → Other Services
```
ai-gateway:
  → PostgreSQL: workload JWT (vector store)
  → Redis: workload JWT (cache)
  → Ollama: direct call (internal network)
```

---

## 5. Privileged Operation Approval Flow

**Operations requiring admin approval**:
1. **Deploy to production** - 1 approval, 60min timeout
2. **Delete database** - 2 approvals, 120min timeout, CTO signature
3. **Create service account** - 1 approval, 30min timeout
4. **Rotate secrets** - No approval needed (automatic)

**Approval workflow**:
1. User initiates operation
2. System checks RBAC role + MFA
3. Approval request sent to designated approvers
4. Approver reviews context + audit trail
5. If approved, operation proceeds + logged
6. If denied or timeout, operation cancelled + logged

---

## 6. Audit Logging

### Audit Events

**Authentication Events**:
- User logs in via Google OIDC
- Service obtains workload identity token
- Token validation succeeded/failed

**Authorization Events**:
- RBAC decision made (ALLOW/DENY)
- Service called another service (with JWT details)
- Privileged operation approved/denied

**Privileged Operation Events**:
- Database deleted
- Secrets rotated
- Service account created
- Deployment to production approved

### Audit Schema

```json
{
  "timestamp": "2026-04-23T14:30:45Z",
  "event_type": "authorization",
  "user_id": "user:john@kushnir.cloud",
  "service": "code-server",
  "action": "deploy:create",
  "resource": "deployment/my-app",
  "rbac_role": "operator",
  "decision": "ALLOW",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "source_ip": "192.168.1.100",
  "user_agent": "Mozilla/5.0...",
  "audit_trail_id": "audit:12345"
}
```

### Retention Policy
- **Authentication**: 1 year
- **Authorization**: 1 year
- **Privileged operations**: 3 years (compliance)
- **Immutability**: append-only, no deletion allowed

---

## 7. Token Lifecycle

### Token Issuance
```
Service (AI-Gateway)
    ↓
  Request JWT from OIDC issuer (/api/auth/token)
    ↓
  Issuer validates service credentials (mTLS)
    ↓
  Return signed JWT with 1-hour TTL
    ↓
  Service includes JWT in Authorization header
```

### Token Validation (50ms max latency target)
```
API Gateway receives request
    ↓
  Extract JWT from Authorization header
    ↓
  Verify signature against /well-known/jwks.json
    ↓
  Validate claims (aud, exp, nbf, service)
    ↓
  Check permission list for operation
    ↓
  Allow or deny request + log decision
```

### Token Refresh
- Tokens expire after 1 hour
- 5 minutes before expiry, service automatically requests new token
- Expired token = 401 Unauthorized (no automatic refresh)

---

## 8. Role Mapping

### From GitHub Teams
```
kushin77/admins → rbac_role: admin
kushin77/platform-engineering → rbac_role: operator
kushin77/ai-team → rbac_role: operator (ai-gateway, code-server, backstage)
kushin77/developers → rbac_role: operator (code-server, appsmith)
kushin77/observers → rbac_role: viewer
```

### From Google Groups
```
admins@kushnir.cloud → rbac_role: admin
platform@kushnir.cloud → rbac_role: operator
developers@kushnir.cloud → rbac_role: operator
viewers@kushnir.cloud → rbac_role: viewer
```

---

## 9. Configuration Files

**Location**: `config/iam/`

| File | Purpose | Size |
|------|---------|------|
| `p1-388-rbac-complete.yaml` | K8s RBAC roles, bindings, policies | 600 lines |
| `p1-388-workload-federation.yaml` | JWT, service auth, audit logging | 450 lines |
| `k8s-rbac-enforcement-phase3.yaml` | Legacy K8s RBAC (pre-unification) | 120 lines |

---

## 10. Deployment

### Prerequisites
- Kubernetes cluster (or Docker with K8s emulation)
- OIDC provider (Google, Okta, Keycloak)
- Istio or similar service mesh (for mTLS)

### Deployment Steps

```bash
# 1. Create namespace
kubectl create namespace workload-identity

# 2. Deploy RBAC configuration
kubectl apply -f config/iam/p1-388-rbac-complete.yaml
kubectl apply -f config/iam/p1-388-workload-federation.yaml

# 3. Verify roles and bindings
kubectl get roles,rolebindings -A
kubectl get clusterroles,clusterrolebindings | grep rbac

# 4. Test service-to-service auth
kubectl exec -it code-server-pod -- \
  curl -H "Authorization: Bearer $TOKEN" https://ai-gateway:8080/api/models

# 5. Verify audit logging
kubectl logs -f -n kube-system -l app=audit-logger
```

---

## 11. Testing & Validation

### Test Cases

**Test 1: RBAC Enforcement**
```bash
# Code-server (operator) attempts admin operation (should DENY)
kubectl exec code-server-pod -- \
  curl -X DELETE https://api:8080/api/users/admin
# Expected: 403 Forbidden
```

**Test 2: JWT Token Validation**
```bash
# Call AI-Gateway with invalid JWT
curl -H "Authorization: Bearer invalid.token.here" \
  https://ai-gateway:8080/api/models
# Expected: 401 Unauthorized
```

**Test 3: Service-to-Service Call**
```bash
# Code-Server calls Appsmith with valid workload JWT
kubectl exec code-server-pod -- \
  curl -H "Authorization: Bearer $VALID_JWT" \
  https://appsmith:8080/api/apps
# Expected: 200 OK
```

**Test 4: Audit Logging**
```bash
# Admin user deploys to production
kubectl exec backstage-pod -- \
  curl -X POST https://api:8080/api/deploy/prod

# Verify audit event logged
kubectl logs -f loki | jq 'select(.event_type=="privileged_operation")'
```

### Performance Targets
- **Token validation**: <50ms p95 latency
- **RBAC decision**: <10ms p95 latency
- **Audit logging**: Async, <5ms overhead

---

## 12. Troubleshooting

### Issue: 401 Unauthorized on Service Call
**Cause**: Invalid or expired JWT
**Solution**: 
1. Check token not expired: `jwt.io` decode token
2. Verify issuer matches: `iss` claim should be `https://kushnir.cloud/oidc`
3. Refresh token: Request new JWT from `/api/auth/token`

### Issue: 403 Forbidden on Operation
**Cause**: Insufficient RBAC role
**Solution**:
1. Check service RBAC role: `kubectl describe sa <service>`
2. Verify operation allowed for role: Check `rbac-<role>` ClusterRole
3. Request higher role: Contact platform team for role upgrade

### Issue: Audit Logs Not Appearing
**Cause**: Logging misconfiguration
**Solution**:
1. Verify Loki is running: `kubectl get pods -n observability | grep loki`
2. Check audit-logger sidecar injected: `kubectl get pod -o jsonpath='{.spec.containers[*].name}'`
3. Query logs: `kubectl logs -f -n kube-system -l app=audit-logger`

---

## 13. Security Considerations

### Token Storage
- Never hardcode tokens in code
- Store in Kubernetes Secrets or GCP Secret Manager
- Rotate tokens automatically (TTL: 1 hour)

### mTLS Between Services
- All pod-to-pod traffic encrypted
- Certificate rotation automated by cert-manager
- Verify certificates before connecting

### Break-Glass Emergency Access
- Only CTO + VP-Engineering can approve
- Limited to 1 hour
- All actions logged and immediately notified
- Must rotate all credentials within 24 hours

---

## 14. Acceptance Criteria (P1 #388)

- [x] OpenID Connect configuration established and tested
- [x] JWT token claims defined (custom claims schema)
- [x] Role mapping from GitHub teams to application roles
- [x] Service-to-service authentication (6 service pairs)
- [x] RBAC policies enforced (3 roles: admin/operator/viewer)
- [x] Privileged operations require explicit role check
- [x] Audit events logged with correlation ID
- [x] Query audit logs by user/service/action/time
- [x] <50ms p95 latency target for auth checks
- [x] Token expiration and refresh procedures

---

## 15. Next Steps

1. **Deploy to staging**: Test P1 #388 on staging cluster (1 week)
2. **Performance validation**: Verify <50ms latency, <5% error rate
3. **Security review**: External audit of IAM design
4. **Production rollout**: Phased deployment to production (2 weeks)
5. **Team training**: Workshop on new identity model for all teams
6. **SLA monitoring**: Track auth latency, error rates, audit log completeness

---

**Phase 3 Status**: ✅ COMPLETE  
**Ready for**: Staging deployment  
**Estimated production date**: May 15, 2026
