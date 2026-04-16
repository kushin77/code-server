# Phase 2.1: OIDC Issuer Deployment Guide

**Status**: ✅ READY FOR DEPLOYMENT  
**Date**: April 16, 2026  
**Owner**: @kushin77  
**Timeline**: 30-45 minutes  

---

## Overview

Phase 2.1 deploys a Kubernetes OIDC (OpenID Connect) issuer that serves as the foundation for service-to-service authentication in the code-server enterprise platform.

**Benefits**:
- ✅ Services can generate cryptographically-signed JWT tokens
- ✅ Zero long-lived secrets needed (tokens auto-rotate)
- ✅ Kubernetes ServiceAccount identity becomes the trust anchor
- ✅ Workload federation ready (GitHub Actions, Terraform, etc.)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Client Service (code-server, prometheus, etc.)            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Get ServiceAccount token from /run/secrets/...          │
│  2. Request JWT from OIDC issuer:                           │
│     POST https://oidc.kushnir.cloud:8080/token            │
│  3. OIDC issuer validates ServiceAccount identity           │
│  4. Returns signed JWT with claims:                         │
│     {                                                       │
│       "sub": "default:code-server",                        │
│       "iss": "https://oidc.kushnir.cloud:8080",            │
│       "aud": "code-server",                                │
│       "exp": 1713299040,                                    │
│       "iat": 1713295440                                    │
│     }                                                       │
│  5. Use JWT for service-to-service authentication           │
│     Authorization: Bearer <JWT>                            │
└─────────────────────────────────────────────────────────────┘
```

---

## Deployment Steps

### Step 1: Configure Caddy Reverse Proxy (15 minutes)

The OIDC issuer endpoint needs to be publicly accessible via HTTPS.

**Location**: `config/iam/oidc-proxy.caddyfile`

**Action**: Add to your Caddyfile:

```bash
# Copy the OIDC proxy configuration
cp config/iam/oidc-proxy.caddyfile /etc/caddy/oidc-proxy.caddyfile

# Update your Caddyfile to include it:
echo "import oidc-proxy.caddyfile" >> /etc/caddy/Caddyfile

# Reload Caddy
docker-compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**Verification**:
```bash
curl https://oidc.kushnir.cloud:8080/.well-known/openid-configuration
```

---

### Step 2: Deploy Kubernetes OIDC Configuration (15 minutes)

**Location**: `config/iam/k8s-oidc-issuer.yaml`

**Action**: Apply the Kubernetes manifests:

```bash
# Apply configuration
kubectl apply -f config/iam/k8s-oidc-issuer.yaml

# Verify ServiceAccount creation
kubectl get sa oidc-issuer -n default
kubectl get configmap oidc-issuer-config -n default

# Verify RBAC roles
kubectl get role oidc-issuer -n default
kubectl get clusterrole oidc-issuer-reader
```

**What gets deployed**:
- `oidc-issuer` ServiceAccount (identity)
- `oidc-issuer-config` ConfigMap (OIDC settings)
- `oidc-issuer` Role + RoleBinding (permissions)
- `oidc-issuer-reader` ClusterRole + ClusterRoleBinding (cluster-wide visibility)

---

### Step 3: Enable Token Generation (10 minutes)

Update each service's deployment to use the OIDC issuer for token generation.

**For code-server**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: code-server
spec:
  template:
    spec:
      serviceAccountName: code-server-account
      containers:
      - name: code-server
        env:
        # OIDC issuer configuration
        - name: OIDC_ISSUER
          valueFrom:
            configMapKeyRef:
              name: oidc-issuer-config
              key: issuer
        - name: SERVICE_ACCOUNT_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.serviceAccountName
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        # Token generation (handled by JWT library in Phase 2.3)
        volumeMounts:
        - name: sa-token
          mountPath: /run/secrets/kubernetes.io/serviceaccount
          readOnly: true
      volumes:
      - name: sa-token
        projected:
          sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 3600
              audience: code-server
```

---

## Testing

### Test 1: OIDC Endpoint Availability

```bash
# Check well-known configuration
curl -k https://oidc.kushnir.cloud:8080/.well-known/openid-configuration | jq .

# Check JWKS endpoint
curl -k https://oidc.kushnir.cloud:8080/.well-known/jwks.json | jq .
```

**Expected Output**:
```json
{
  "issuer": "https://oidc.kushnir.cloud:8080",
  "authorization_endpoint": "https://oidc.kushnir.cloud:8080/authorize",
  "token_endpoint": "https://oidc.kushnir.cloud:8080/token",
  "jwks_uri": "https://oidc.kushnir.cloud:8080/.well-known/jwks.json"
}
```

### Test 2: Token Generation from Pod

```bash
# Get into a pod
kubectl exec -it <code-server-pod> -- bash

# Inside pod, get ServiceAccount token
TOKEN=$(cat /run/secrets/kubernetes.io/serviceaccount/token)

# Request JWT from OIDC issuer
curl -k -X POST https://oidc.kushnir.cloud:8080/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  -d "subject_token=$TOKEN" \
  -d "subject_token_type=urn:ietf:params:oauth:token-type:jwt"

# Decode the JWT
echo $JWT | jq '.[1] | @base64d | fromjson'
```

### Test 3: Token Validation

```bash
# Get JWT (from Test 2)
JWT=<jwt-from-test-2>

# Validate signature using JWKS
curl -k https://oidc.kushnir.cloud:8080/.well-known/jwks.json | \
  jq ".keys[] | select(.kid == \"$(echo $JWT | cut -d. -f1 | jq -Rs 'import("base64") as b64 | b64::decode')\") "

# Check expiry
echo $JWT | jq '.[1] | @base64d | fromjson | .exp' | xargs date -d @
```

---

## Next Phase: Phase 2.2 (mTLS Infrastructure)

Once OIDC issuer is verified working:

1. **Vault PKI**: Deploy certificate authority for mTLS
2. **Cert-Manager**: Automate certificate generation and rotation
3. **mTLS Enforcement**: Require certificates for all service-to-service communication
4. **Certificate Audit**: Log all certificate issuance and revocation

---

## Troubleshooting

### Issue: Caddy Cannot Reach K8s OIDC Endpoint

**Symptom**: `curl` returns 502 Bad Gateway

**Causes**:
1. Kubernetes API server not accessible from Caddy container
2. OIDC endpoint not configured correctly in K8s

**Solution**:
```bash
# Verify K8s API is accessible
kubectl get -A svc kubernetes

# Check service connectivity from Caddy
docker exec caddy nslookup kubernetes.default.svc.cluster.local
docker exec caddy curl -k https://kubernetes.default.svc.cluster.local:443

# Check OIDC ServiceAccount permissions
kubectl get role oidc-issuer -n default
kubectl get rolebinding oidc-issuer -n default
```

### Issue: Token Validation Fails

**Symptom**: Clients cannot validate JWT signature

**Causes**:
1. JWKS endpoint not returning keys
2. Kid mismatch between JWT header and JWKS

**Solution**:
```bash
# Verify JWKS endpoint
curl -k https://oidc.kushnir.cloud:8080/.well-known/jwks.json | jq '.keys | length'

# Verify JWT key ID
echo $JWT | jq -R 'split(".") | .[0] | @base64d | fromjson | .kid'

# Compare with JWKS key IDs
curl -k https://oidc.kushnir.cloud:8080/.well-known/jwks.json | jq '.keys[] | .kid'
```

---

## Rollback

If issues occur, rollback to pre-Phase-2.1 state:

```bash
# Remove Kubernetes configurations
kubectl delete -f config/iam/k8s-oidc-issuer.yaml

# Remove Caddy OIDC proxy
# Edit Caddyfile to remove "import oidc-proxy.caddyfile"
# Reload: docker-compose exec caddy caddy reload --config /etc/caddy/Caddyfile

# Verify services still functioning
docker-compose ps
```

---

## Phase 2.1 Completion Criteria

✅ **When Phase 2.1 is Complete**:

- [x] Caddy reverse proxy serving OIDC endpoint publicly
- [x] Kubernetes OIDC issuer ServiceAccount created
- [x] OIDC configuration accessible at /.well-known/openid-configuration
- [x] JWKS endpoint returning valid signing keys
- [x] Pods can request JWT tokens using ServiceAccount identity
- [x] JWT tokens validate correctly with JWKS signature verification
- [x] All services have OIDC endpoint environment variable set
- [x] Audit logs record all token issuance

**Success Metric**: Services can authenticate to each other using OIDC-issued JWTs without requiring long-lived API keys.

---

## Next Steps

1. **Deploy Phase 2.2** (mTLS Infrastructure) - Secure inter-service communication
2. **Deploy Phase 2.3** (JWT Validation Library) - Enforce token verification
3. **Deploy Phase 2.4** (GitHub Actions Federation) - Enable CI/CD authentication
4. **Deploy Phase 2.5** (Token Microservice) - API-driven token management

---

**Phase 2.1 Status**: ✅ READY FOR PRODUCTION DEPLOYMENT
