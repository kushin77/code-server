# Kubernetes Workload Identity Integration (Phase 5)

## Overview

Phase 5 extends the OIDC and JWT authentication infrastructure (Phases 2-4) to Kubernetes, enabling workloads running in Kubernetes clusters to authenticate as service identities and call protected APIs using JWT bearer tokens.

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ ServiceAccount "github-actions-ci"                             │
│   ├── Projected Volume: OIDC Token (JWT from Kubernetes)       │
│   └── Pod mounts token at: /var/run/secrets/tokens/oidc/token  │
│                                                                  │
│ Pod (GitHub Actions Runner)                                    │
│   ├── Reads token from projected volume                        │
│   ├── Exchanges with OIDC Issuer for access_token             │
│   └── Calls API with: Authorization: Bearer <access_token>    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                         ↓
        ┌────────────────────────────────┐
        │  OIDC Issuer                   │
        │  (oauth2-oidc-issuer)          │
        │  Port: 4182                    │
        │  Endpoint: /.well-known/oauth2/token  │
        └────────────────────────────────┘
                         ↓
        ┌────────────────────────────────┐
        │  API Server                    │
        │  JWT Validation Middleware     │
        │  RBAC Enforcement              │
        │  Audit Logging                 │
        └────────────────────────────────┘
```

### Token Flow

1. **Kubernetes Generates Token**
   - ServiceAccount has a projected volume with OIDC token
   - Token is a JWT signed by Kubernetes
   - Available at pod runtime: `/var/run/secrets/tokens/oidc/token`

2. **Pod Exchanges Token**
   ```bash
   POST /.well-known/oauth2/token
   grant_type=urn:ietf:params:oauth:grant-type:token-exchange
   subject_token_type=urn:ietf:params:oauth:token-type:jwt
   subject_token=<k8s-jwt>
   audience=kubernetes
   ```

3. **OIDC Issuer Issues Access Token**
   - Response includes JWT `access_token`
   - Signed with RS256 private key
   - Contains claims: sub, aud, iss, iat, exp, groups, actor, repository

4. **Pod Calls API with Token**
   ```bash
   curl -H "Authorization: Bearer <access_token>" \
     https://api.example.com/api/v1/jobs
   ```

5. **API Validates and Authorizes**
   - Verifies RS256 signature against JWKS
   - Checks token claims (expiration, audience, etc.)
   - Looks up RBAC rules for ServiceAccount
   - Applies authorization based on pod's role
   - Logs audit event with pod identity

## Deployment Guide

### Prerequisites

- Kubernetes cluster (1.24+) with service account token projection enabled
- OIDC issuer deployed (Phase 2.1)
- API server with JWT validation middleware (Phases 3-4)
- kubectl configured and authenticated to cluster

### Step 1: Deploy ServiceAccounts and RBAC

```bash
# Apply ServiceAccount definitions
kubectl apply -f kubernetes/oidc-serviceaccounts.yaml

# Verify ServiceAccounts created
kubectl get sa -n code-server-workloads
```

This creates:
- `github-actions-ci` - For CI/CD workloads
- `batch-processor` - For batch jobs
- `webhook-receiver` - For webhook handlers
- `cluster-admin` - For admin operations

### Step 2: Deploy Example Workload

```bash
# Option A: Deploy the example deployment
kubectl apply -f kubernetes/oidc-workload-deployments.yaml

# Option B: Run manual test pod
bash kubernetes/token-exchange.sh --verify
```

### Step 3: Verify Token Acquisition

```bash
# Run test pod with OIDC token projection
bash kubernetes/test-oidc-integration.sh --namespace code-server-workloads

# Or manually:
kubectl run test-token \
  -n code-server-workloads \
  --image=curlimages/curl:latest \
  --serviceaccount=github-actions-ci \
  --command -- sleep 3600

# Check token exists in pod
kubectl exec -n code-server-workloads test-token -- \
  cat /var/run/secrets/tokens/oidc/token | head -c 50
```

### Step 4: Test Token Exchange and API Calls

```bash
# Copy token exchange script to pod
kubectl cp kubernetes/token-exchange.sh \
  code-server-workloads/test-token:/tmp/

# Exchange token for access_token
kubectl exec -n code-server-workloads test-token -- \
  bash /tmp/token-exchange.sh \
  --issuer-url https://ide.kushnir.cloud:4182 \
  --audience kubernetes

# Call API with JWT token
kubectl exec -n code-server-workloads test-token -- \
  curl -H "Authorization: Bearer $(cat /tmp/access_token.jwt)" \
  http://api:3000/api/v1/health
```

## Usage Examples

### Example 1: GitHub Actions CI/CD

Deploy a CI runner that authenticates as a ServiceAccount:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: github-actions-runner
  namespace: code-server-workloads
spec:
  replicas: 3
  selector:
    matchLabels:
      app: github-actions
  template:
    metadata:
      labels:
        app: github-actions
    spec:
      serviceAccountName: github-actions-ci
      containers:
      - name: runner
        image: ghcr.io/actions/runner:latest
        env:
        - name: RUNNER_TOKEN
          valueFrom:
            secretKeyRef:
              name: github-runner-token
              key: token
        volumeMounts:
        - name: oidc-token
          mountPath: /var/run/secrets/tokens/oidc
      volumes:
      - name: oidc-token
        projected:
          sources:
          - serviceAccountToken:
              path: token
              expirationSeconds: 3600
              audience: kubernetes
```

Runner can authenticate to API:

```bash
#!/bin/bash
TOKEN=$(cat /var/run/secrets/tokens/oidc/token)
ACCESS_TOKEN=$(curl -s -X POST \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=$TOKEN&audience=kubernetes" \
  https://api.example.com/.well-known/oauth2/token | jq -r .access_token)

curl -H "Authorization: Bearer $ACCESS_TOKEN" \
  https://api.example.com/api/v1/jobs/start \
  -d '{"job": "deploy"}'
```

### Example 2: Batch Processing

Scheduled Kubernetes CronJob that acquires token and processes data:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: data-processor
  namespace: code-server-workloads
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: batch-processor
          containers:
          - name: processor
            image: myregistry.azurecr.io/data-processor:latest
            volumeMounts:
            - name: oidc-token
              mountPath: /var/run/secrets/tokens/oidc
            env:
            - name: OIDC_ISSUER_URL
              value: "https://ide.kushnir.cloud:4182"
            - name: API_SERVER_URL
              value: "https://api.example.com"
          volumes:
          - name: oidc-token
            projected:
              sources:
              - serviceAccountToken:
                  path: token
                  expirationSeconds: 3600
                  audience: kubernetes
          restartPolicy: OnFailure
```

### Example 3: Custom Workload

Build your own workload using the helper scripts:

```bash
#!/bin/bash
# Inside pod with OIDC token projection

# Source the API client helper
source /opt/kubernetes/api-client-example.sh

# Get JWT token
TOKEN=$(get_jwt_token)

# Make authenticated API call
response=$(call_api_with_jwt GET "/api/v1/status")

# Process response
echo "API Response: $response"
```

## Troubleshooting

### Token Not Found in Pod

**Symptom**: `/var/run/secrets/tokens/oidc/token` not found

**Causes**:
1. ServiceAccount not specified in pod
2. Pod not part of token projection volume mount
3. Kubernetes version too old (need 1.24+)

**Solution**:
```bash
# Verify service account is set
kubectl get pod <pod-name> -o yaml | grep serviceAccountName

# Check volume mounts
kubectl get pod <pod-name> -o yaml | grep -A 5 volumeMounts

# Update pod spec to include projected volume
```

### Token Exchange Fails

**Symptom**: `NOAUTH Authentication required` or `error: invalid_grant`

**Causes**:
1. OIDC issuer not accessible from pod
2. Token not valid JWT
3. Audience mismatch

**Solution**:
```bash
# Check OIDC issuer accessibility
kubectl exec <pod> -- curl -v https://ide.kushnir.cloud:4182/.well-known/openid-configuration

# Verify token format
kubectl exec <pod> -- cat /var/run/secrets/tokens/oidc/token | cut -d'.' -f2 | base64 -d | jq '.'

# Check OIDC issuer logs
kubectl logs -f deployment/oauth2-oidc-issuer
```

### API Returns 403 Forbidden

**Symptom**: JWT token is valid but API returns 403

**Causes**:
1. RBAC permissions missing for ServiceAccount
2. Service account not in expected role
3. JWT claims don't match API expectations

**Solution**:
```bash
# Check ServiceAccount permissions
kubectl auth can-i list deployments \
  --as=system:serviceaccount:code-server-workloads:github-actions-ci

# Verify ClusterRoleBinding
kubectl describe clusterrolebinding code-server-github-actions-binding

# Check API RBAC logs
kubectl logs <api-pod> | grep RBAC
```

### Token Expired

**Symptom**: API returns 401 with "Token expired"

**Causes**:
1. Token TTL set too low
2. Pod running for too long
3. No token refresh mechanism

**Solution**:
```bash
# Increase token TTL in pod spec
serviceAccountToken:
  expirationSeconds: 86400  # 24 hours

# Or implement token refresh loop in application:
while true; do
  TOKEN=$(cat /var/run/secrets/tokens/oidc/token)
  # Use token...
  sleep 3600  # Refresh hourly
done
```

## Security Considerations

### 1. Token Projection

✅ **Secure by Default**:
- Tokens are cryptographically signed by Kubernetes
- Projected into container filesystem (not env var)
- Automatic rotation (expires every hour by default)
- Non-transferable (bound to pod UID)

### 2. RBAC Authorization

✅ **Least Privilege**:
- Each ServiceAccount has minimal ClusterRole
- RBAC enforced at API gateway
- Audit logs track every API call with pod identity
- No shared credentials between pods

### 3. Token Transport

✅ **Best Practices**:
- Use HTTPS/TLS for all token exchanges
- Never log or print full tokens
- Validate certificate chains when possible
- Rotate signing keys regularly (external process)

### 4. Pod Security

✅ **Enforced via NetworkPolicy**:
- Pods can only reach OIDC issuer and API server
- Egress restricted to necessary ports
- Ingress restricted to monitoring/logs
- Non-root user by default

## Monitoring and Observability

### Metrics

Track token acquisition and API usage:

```prometheus
# Token exchange duration
histogram_observe("token_exchange_duration_seconds", duration)

# Token expiration events
counter_increment("token_expirations_total")

# API calls by ServiceAccount
counter_increment("api_calls_by_serviceaccount", labels={"account": "github-actions-ci"})

# RBAC denials
counter_increment("rbac_denials_total", labels={"account": "github-actions-ci"})
```

### Logs

Audit trail of all OIDC and API operations:

```json
{
  "timestamp": "2026-04-22T10:30:45Z",
  "event": "token_exchange",
  "serviceaccount": "github-actions-ci",
  "namespace": "code-server-workloads",
  "pod": "github-actions-runner-abc123",
  "duration_ms": 145,
  "status": "success"
}
```

### Alerts

Key alerts to configure:

```yaml
- alert: HighTokenExchangeFailureRate
  expr: rate(token_exchange_failures_total[5m]) > 0.1
  for: 5m

- alert: RBACDenialSpike
  expr: increase(rbac_denials_total[1m]) > 10
  for: 1m

- alert: OIDCIssuerDown
  expr: up{job="oauth2-oidc-issuer"} == 0
  for: 2m
```

## References

- [RFC 8693 - OAuth 2.0 Token Exchange](https://tools.ietf.org/html/rfc8693)
- [Kubernetes Service Account Token Projection](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-token-volume-projection)
- [Kubernetes OIDC Discovery](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/#options)
- [OpenID Connect Discovery](https://openid.net/specs/openid-connect-discovery-1_0.html)

## Next Steps

1. ✅ Deploy ServiceAccounts and RBAC
2. ✅ Test token projection in pods
3. ✅ Verify token exchange with OIDC issuer
4. ✅ Test API calls with JWT tokens
5. 🔄 Deploy to production Kubernetes
6. 🔄 Migrate CI/CD to use OIDC authentication
7. 🔄 Enable for batch jobs and webhooks
8. 🔄 Setup monitoring and alerting

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review pod and issuer logs
3. Test token acquisition manually
4. Consult architecture documentation (Phase 2-4)
