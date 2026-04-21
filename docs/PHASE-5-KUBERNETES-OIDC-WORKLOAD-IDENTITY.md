# Phase 5: Kubernetes Workload Identity Integration

## Overview

Phase 5 integrates the OIDC JWT auth system (Phases 2-4) with Kubernetes ServiceAccounts to enable **workload identity** - allowing pods to acquire JWT tokens and authenticate to APIs without hardcoded credentials.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster (GKE/EKS/AKS)                             │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐         ┌─────────────────┐               │
│  │ Pod (App)    │────────┤ ServiceAccount   │               │
│  │              │         │  (workload id)   │               │
│  └──────┬───────┘         └────────┬────────┘               │
│         │                          │                        │
│         │ 1. Request token via    │ 2. Projected volume    │
│         │    /var/run/secrets/     │    with JWT binding    │
│         │                          │                        │
│  ┌──────▼──────────────────────────▼────────────┐          │
│  │ Kubernetes API Server (OIDC handler)         │          │
│  │ - Validates ServiceAccount binding            │          │
│  │ - Projects token via volume mount             │          │
│  │ - Verifies issuer signature                   │          │
│  └────────┬─────────────────────────────────────┘          │
└───────────┼────────────────────────────────────────────────┘
            │
            │ 3. Query OIDC discovery (.well-known/openid-configuration)
            │    & JWKS (.well-known/jwks.json)
            │
┌───────────▼──────────────────────────────────────────────────┐
│ OIDC Issuer (oauth2-oidc-issuer service)                     │
│ - Discovery endpoint                                         │
│ - JWKS endpoint (public key distribution)                    │
│ - Token endpoint (for direct token acquisition)              │
└───────────────────────────────────────────────────────────────┘
            │
            │ 4. Pod acquires token (JWT)
            │    with Kubernetes claims
            │
            │ 5. Pod calls API with token
            │    Authorization: Bearer <JWT>
            │
┌───────────▼──────────────────────────────────────────────────┐
│ API Server (session-broker)                                  │
│ - Verifies JWT signature using JWKS                          │
│ - Extracts Kubernetes claims:                                │
│   - kubernetes.io/namespace                                  │
│   - kubernetes.io/serviceaccount/name                        │
│   - kubernetes.io/pod/name                                   │
│ - Maps to RBAC roles & permissions                           │
│ - Processes request with pod identity                        │
└────────────────────────────────────────────────────────────────┘
```

## Components Implemented

### 1. KubernetesOIDCService (`kubernetes-oidc.ts`)

Core service providing:

- **Discovery Endpoint** (`/.well-known/openid-configuration`)
  - Returns OIDC provider metadata
  - Includes Kubernetes-specific claims
  - Used by Kubernetes API servers for automatic discovery

- **JWKS Endpoint** (`/.well-known/jwks.json`)
  - Distributes public signing key
  - Allows API servers to verify token signatures
  - Key rotation support via `kid` (key ID)

- **Token Endpoint** (`/token`)
  - Generates JWT tokens for ServiceAccounts
  - Accepts token exchange grant type
  - Includes Kubernetes claims (namespace, SA name, pod identity)

- **Token Verification**
  - Validates JWT signatures
  - Checks token expiration
  - Enforces issuer and audience claims
  - Validates Kubernetes claims presence

### 2. Configuration

```typescript
interface KubernetesOIDCConfig {
  enabled: boolean;
  issuerURL: string;                        // https://ide.kushnir.cloud/oidc
  keyID: string;                            // Key ID for key rotation
  publicKeyPEM: string;                     // RSA public key for verification
  privateKeyPEM: string;                    // RSA private key for signing
  jwsAlgorithm: 'RS256' | 'ES256';          // Signature algorithm
  tokenExpiration: number;                  // Seconds (default: 3600)
  supportedAudiences: string[];             // ['kubernetes', 'api', 'github-actions']
}
```

### 3. Kubernetes Claims

Tokens include standard Kubernetes claims for workload identification:

```json
{
  "iss": "https://ide.kushnir.cloud/oidc",
  "sub": "system:serviceaccount:default:my-app",
  "aud": "kubernetes",
  "exp": 1713787200,
  "iat": 1713783600,
  "kubernetes.io/namespace": "default",
  "kubernetes.io/serviceaccount/name": "my-app",
  "kubernetes.io/serviceaccount/uid": "abc-123",
  "kubernetes.io/pod/name": "my-app-xyz",
  "kubernetes.io/pod/uid": "pod-123"
}
```

## Deployment

### Prerequisites

- Phase 2.1 OIDC Issuer deployment complete (signing keys in GSM)
- Kubernetes cluster with OIDC issuer discovery support (GKE, EKS, AKS 1.20+)
- oauth2-oidc-issuer service running and accessible

### 1. Enable OIDC in session-broker

```bash
export KUBERNETES_OIDC_ENABLED=true
export KUBERNETES_OIDC_ISSUER_URL=https://ide.kushnir.cloud/oidc
export KUBERNETES_OIDC_KEY_ID=default
export KUBERNETES_OIDC_PUBLIC_KEY_PEM=$(gcloud secrets versions access latest --secret="oidc-issuer-public-key")
export KUBERNETES_OIDC_PRIVATE_KEY_PEM=$(gcloud secrets versions access latest --secret="oidc-issuer-signing-key")
export KUBERNETES_OIDC_TOKEN_EXPIRATION=3600
export KUBERNETES_OIDC_SUPPORTED_AUDIENCES=kubernetes,api,github-actions
```

### 2. Mount oauth2-oidc-issuer endpoints

```yaml
# docker-compose.yml or Kubernetes service
services:
  oauth2-oidc-issuer:
    image: oauth2-oidc-issuer:latest
    ports:
      - "8443:443"
    environment:
      OIDC_ISSUER_URL: https://ide.kushnir.cloud/oidc
      OIDC_SIGNING_KEY: ${OIDC_ISSUER_SIGNING_KEY}
      OIDC_DISCOVERY_ENABLED: "true"
      OIDC_JWKS_ENABLED: "true"
```

### 3. Configure Kubernetes cluster for OIDC

**For Google GKE**:
```bash
gcloud container clusters create my-cluster \
  --enable-kubernetes-engine=true \
  --workload-pool=my-project.iam.goog.com \
  --oidc-provider-config=https://ide.kushnir.cloud/oidc
```

**For AWS EKS**:
```bash
aws eks associate-identity-provider-config \
  --cluster-name my-cluster \
  --oidc-config issuerUrl=https://ide.kushnir.cloud/oidc,clientId=api
```

### 4. Enable ServiceAccount token projection

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app
  containers:
  - name: app
    image: my-app:latest
    volumeMounts:
    - name: oidc-token
      mountPath: /var/run/secrets/oidc
  volumes:
  - name: oidc-token
    projected:
      sources:
      - serviceAccountToken:
          audience: api
          expirationSeconds: 3600
          path: token
```

## Usage: Pod to API Authentication

### 1. Pod acquires OIDC token

```bash
# Token projected into container at startup
export OIDC_TOKEN=$(cat /var/run/secrets/oidc/token)
```

### 2. Pod calls API with JWT bearer token

```bash
curl -H "Authorization: Bearer $OIDC_TOKEN" \
  https://api.kushnir.cloud/v1/sessions
```

### 3. API verifies token

```typescript
// In API middleware
const token = extractBearerToken(req.headers.authorization);
const claims = await kubernetesOIDCService.verifyToken(token);

// claims now contains:
// {
//   'kubernetes.io/namespace': 'production',
//   'kubernetes.io/serviceaccount/name': 'my-app',
//   'kubernetes.io/pod/name': 'my-app-xyz'
// }

// Use namespace + SA name for RBAC lookup
const rbacRole = await rbacService.getRole(
  claims['kubernetes.io/namespace'],
  claims['kubernetes.io/serviceaccount/name']
);
```

## Testing

### Unit Tests

```bash
cd apps/session-broker
pnpm test -- src/services/kubernetes-oidc/__tests__/kubernetes-oidc.test.ts

# Output:
# ✓ Discovery Endpoint
#   ✓ should return OpenID Connect discovery document
#   ✓ should include Kubernetes-specific claims
# ✓ JWKS Endpoint
#   ✓ should return JWKS with public key
# ✓ ServiceAccount Token Generation (8 tests)
# ✓ Token Verification (5 tests)
# ✓ Namespace Isolation (2 tests)
# ✓ Multi-Audience Support (2 tests)
```

### Integration Test: Pod Token Acquisition

```bash
#!/bin/bash
# scripts/test/test-k8s-oidc-workload-identity.sh

# 1. Deploy test pod with OIDC token projection
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: oidc-test-pod
  namespace: default
spec:
  serviceAccountName: test-sa
  containers:
  - name: test
    image: curlimages/curl
    command:
    - sh
    - -c
    - |
      sleep 1
      TOKEN=$(cat /var/run/secrets/oidc/token)
      echo "Token acquired: \${TOKEN:0:50}..."
      curl -H "Authorization: Bearer \$TOKEN" \
        http://session-broker:5000/v1/verify-token
    volumeMounts:
    - name: oidc-token
      mountPath: /var/run/secrets/oidc
  volumes:
  - name: oidc-token
    projected:
      sources:
      - serviceAccountToken:
          audience: api
          expirationSeconds: 3600
          path: token
  restartPolicy: Never
EOF

# 2. Wait for pod to complete
kubectl wait --for=condition=ready pod/oidc-test-pod --timeout=30s

# 3. Check logs
kubectl logs oidc-test-pod
```

### E2E Test: Service-to-Service Authentication

```bash
#!/bin/bash
# scripts/test/test-k8s-oidc-e2e.sh

# Deploy two services:
# 1. client-app - makes requests with JWT token
# 2. api-server - verifies JWT and processes request

# Expected flow:
# client-app:
#   1. Gets token from /var/run/secrets/oidc/token
#   2. Makes request: curl -H "Authorization: Bearer $TOKEN" http://api-server:8080/api/data
#
# api-server:
#   1. Extracts JWT from Authorization header
#   2. Verifies signature using OIDC issuer's public key
#   3. Checks 'kubernetes.io/namespace' == 'default'
#   4. Checks 'kubernetes.io/serviceaccount/name' == 'client-app'
#   5. Returns 200 OK with client identity in response
```

## Security Considerations

### 1. Token Signing & Verification

- **Algorithm**: RS256 (RSA-2048)
- **Key Management**: Private key stored in Google Secret Manager, never in git
- **Key Rotation**: Supported via `kid` (key ID) in token header
- **Public Key Distribution**: Via JWKS endpoint for Kubernetes API server caching

### 2. Token Lifecycle

- **Expiration**: Default 3600 seconds (1 hour)
- **Issued At (iat)**: Enforced to prevent token reuse
- **Audience**: Validated per audience claim (kubernetes, api, github-actions)

### 3. Namespace Isolation

- **Claim**: `kubernetes.io/namespace` in every token
- **Enforcement**: API servers MUST validate namespace claim
- **RBAC**: Combined with ServiceAccount name for fine-grained access control

### 4. Pod Identity Binding

- **Optional Claims**: Pod name & UID included when available
- **Use Case**: Audit logging, rate limiting per pod
- **Enforcement**: Can require pod identity for sensitive operations

### 5. Discovery Endpoint Protection

- **Caching**: Kubernetes API servers cache discovery document
- **Rate Limiting**: Implement rate limits on discovery and JWKS endpoints
- **HTTPS Only**: All endpoints require TLS

## Performance SLAs

| Metric | Target | Notes |
|--------|--------|-------|
| Token Generation | < 10ms | Crypto operations on modern hardware |
| Token Verification | < 5ms | Signature validation only (no DB lookups) |
| Discovery Endpoint | < 50ms | Cached by Kubernetes API server |
| JWKS Endpoint | < 50ms | Public key retrieval, no secrets |
| Pod Token Acquisition | < 500ms | Kubernetes + issuer propagation |

## Migration Path

### Phase 5.1: Foundation (Current)
- ✅ KubernetesOIDCService implementation
- ✅ Discovery and JWKS endpoints
- ✅ Token generation with Kubernetes claims
- ✅ Unit and integration tests

### Phase 5.2: Kubernetes Integration
- Token projection configuration
- ServiceAccount binding
- Cluster OIDC discovery setup

### Phase 5.3: API Integration
- JWT verification middleware
- RBAC integration
- Pod identity enforcement

### Phase 5.4: Production Hardening
- Key rotation automation
- Rate limiting
- Audit logging
- SLA monitoring

## Related Documentation

- [OIDC Issuer Deployment](../PHASE-2-1-OIDC-ISSUER-DEPLOYMENT.md)
- [Phase 4 Audit Logging](../PHASE-4-AUDIT-LOGGING-COMPLETE.md)
- [Kubernetes ServiceAccount Workload Identity](https://cloud.google.com/docs/authentication/workload-identity)
- [OpenID Connect Discovery 1.0](https://openid.net/specs/openid-connect-discovery-1_0.html)

## Files Changed

- `apps/session-broker/src/services/kubernetes-oidc/kubernetes-oidc.ts` (350 LOC)
- `apps/session-broker/src/services/kubernetes-oidc/__tests__/kubernetes-oidc.test.ts` (360 LOC)
- `apps/session-broker/src/services/kubernetes-oidc/index.ts` (10 LOC)
- `docs/PHASE-5-KUBERNETES-OIDC-WORKLOAD-IDENTITY.md` (This file)
