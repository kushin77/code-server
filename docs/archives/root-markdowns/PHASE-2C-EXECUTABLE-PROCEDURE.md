# PHASE 2C EXECUTABLE PROCEDURE - Direct Implementation Steps

**Status**: Ready to Execute  
**Prerequisites**: GCP credentials must be fresh, SSH access to 192.168.168.31 active  
**Estimated Duration**: 2-3 hours  
**Date**: April 22, 2026

---

## PHASE 2C.1: GSM SERVICE ACCOUNT PROVISIONING (30 minutes)

### Prerequisites
- [ ] GCP project set to `gcp-eiq`
- [ ] gcloud CLI authenticated with active credentials
- [ ] openssl available on local machine

### Step-by-Step Execution

```bash
# 1. Authenticate with fresh GCP credentials (if expired)
gcloud auth login

# 2. Set project
gcloud config set project gcp-eiq

# 3. Generate session-broker secret (32 random characters)
SB_SECRET=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
echo "Session-broker secret: $SB_SECRET"

# 4. Generate backend secret (32 random characters)
BACKEND_SECRET=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
echo "Backend secret: $BACKEND_SECRET"

# 5. Generate load balancer session secret (64 hex = 32 bytes)
LB_SECRET=$(openssl rand -hex 32)
echo "LB session secret: $LB_SECRET"

# 6. Create or update secrets in GSM

# Session-broker secret
if gcloud secrets describe "service-client-session-broker-secret" --project=gcp-eiq >/dev/null 2>&1; then
  echo "$SB_SECRET" | gcloud secrets versions add "service-client-session-broker-secret" --data-file=- --project=gcp-eiq
else
  echo "$SB_SECRET" | gcloud secrets create "service-client-session-broker-secret" --replication-policy=automatic --data-file=- --project=gcp-eiq
fi

# Backend secret
if gcloud secrets describe "service-client-backend-secret" --project=gcp-eiq >/dev/null 2>&1; then
  echo "$BACKEND_SECRET" | gcloud secrets versions add "service-client-backend-secret" --data-file=- --project=gcp-eiq
else
  echo "$BACKEND_SECRET" | gcloud secrets create "service-client-backend-secret" --replication-policy=automatic --data-file=- --project=gcp-eiq
fi

# LB session secret
if gcloud secrets describe "ide-session-lb-secret" --project=gcp-eiq >/dev/null 2>&1; then
  echo "$LB_SECRET" | gcloud secrets versions add "ide-session-lb-secret" --data-file=- --project=gcp-eiq
else
  echo "$LB_SECRET" | gcloud secrets create "ide-session-lb-secret" --replication-policy=automatic --data-file=- --project=gcp-eiq
fi

# 7. Verify secrets created
gcloud secrets list --project=gcp-eiq | grep -E "service-client|ide-session"

# Expected output:
# ide-session-lb-secret                     never          2026-04-22T...
# service-client-backend-secret             never          2026-04-22T...
# service-client-session-broker-secret      never          2026-04-22T...
```

### Verification
```bash
# Verify all 3 secrets exist
EXPECTED=3
ACTUAL=$(gcloud secrets list --project=gcp-eiq | grep -E "service-client|ide-session" | wc -l)
if [ "$ACTUAL" -eq "$EXPECTED" ]; then
  echo "✓ Phase 2C.1 PASSED: All 3 secrets created"
else
  echo "✗ Phase 2C.1 FAILED: Expected $EXPECTED secrets, got $ACTUAL"
fi
```

**Success Criteria**:
- [ ] 3 secrets visible in `gcloud secrets list`
- [ ] Each secret has a version (created within last minute)
- [ ] No errors during secret creation

---

## PHASE 2C.2: CONFIGURATION MERGE (20 minutes)

### On Primary Host (192.168.168.31)

```bash
ssh akushnir@192.168.168.31 << 'EOF'
cd code-server-enterprise

# 1. Fetch all secrets from GSM and export to environment
export GCP_PROJECT=gcp-eiq

# Load service-client-session-broker-secret
SESSION_BROKER_SECRET=$(gcloud secrets versions access latest --secret="service-client-session-broker-secret" --project=$GCP_PROJECT)
export SERVICE_CLIENT_SESSION_BROKER_SECRET="$SESSION_BROKER_SECRET"

# Load service-client-backend-secret
BACKEND_SECRET=$(gcloud secrets versions access latest --secret="service-client-backend-secret" --project=$GCP_PROJECT)
export SERVICE_CLIENT_BACKEND_SECRET="$BACKEND_SECRET"

# Load ide-session-lb-secret
LB_SECRET=$(gcloud secrets versions access latest --secret="ide-session-lb-secret" --project=$GCP_PROJECT)
export IDE_SESSION_LB_SECRET="$LB_SECRET"

# 2. Verify all variables loaded
echo "Loaded environment variables:"
echo "SERVICE_CLIENT_SESSION_BROKER_SECRET length: ${#SERVICE_CLIENT_SESSION_BROKER_SECRET}"
echo "SERVICE_CLIENT_BACKEND_SECRET length: ${#SERVICE_CLIENT_BACKEND_SECRET}"
echo "IDE_SESSION_LB_SECRET length: ${#IDE_SESSION_LB_SECRET}"

# 3. Create/update .env file with JWT configuration
cat > .env.phase-2 << 'ENVFILE'
# Phase 2C JWT Configuration
SERVICE_CLIENT_SESSION_BROKER_SECRET={SESSION_BROKER_SECRET}
SERVICE_CLIENT_BACKEND_SECRET={BACKEND_SECRET}
IDE_SESSION_LB_SECRET={LB_SECRET}

# OIDC Issuer Configuration
OIDC_ISSUER_URL=http://localhost:6969
OIDC_CLIENT_ID=code-server
OIDC_CLIENT_SECRET=test-secret
OAUTH2_PROXY_CLIENT_ID=code-server
OAUTH2_PROXY_CLIENT_SECRET=test-secret

# JWT Configuration
JWT_ISSUER_URL=http://oauth2-oidc-issuer:6969
JWT_JWKS_CACHE_TTL_MINUTES=60
JWT_TOKEN_CACHE_TTL_MINUTES=55
JWT_TOKEN_REFRESH_BUFFER_MINUTES=5
JWT_VALIDATION_TIMEOUT_MS=5000
JWT_METRICS_ENABLED=true
JWT_AUTH_LOGGING_ENABLED=true

# Service Subjects & Audiences
CODE_SERVER_JWT_SUBJECT=code-server@svc.internal
CODE_SERVER_JWT_AUDIENCE=code-server,api,github-actions,kubernetes
SESSION_BROKER_JWT_SUBJECT=session-broker@svc.internal
SESSION_BROKER_JWT_AUDIENCE=session-broker,api,kubernetes

# Caching
REDIS_URL=redis://redis:6379
REDIS_CACHE_KEY_PREFIX=jwt-cache
ENVFILE

# 4. Substitute actual values
sed -i "s/{SESSION_BROKER_SECRET}/$SESSION_BROKER_SECRET/" .env.phase-2
sed -i "s/{BACKEND_SECRET}/$BACKEND_SECRET/" .env.phase-2
sed -i "s/{LB_SECRET}/$LB_SECRET/" .env.phase-2

# 5. Verify .env file created
echo "✓ .env.phase-2 created with $(wc -l < .env.phase-2) lines"
EOF
```

### Verification
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && test -f .env.phase-2 && echo '✓ .env.phase-2 exists' || echo '✗ .env.phase-2 missing'"
```

**Success Criteria**:
- [ ] .env.phase-2 file created on remote
- [ ] File contains all 12+ JWT-related variables
- [ ] No secrets contain plaintext "gcp-eiq" or "{PLACEHOLDER}"

---

## PHASE 2C.3: SERVICE DEPLOYMENT (45 minutes)

### Prerequisites
- [ ] Phase 2C.2 completed (.env.phase-2 created)
- [ ] docker-compose.yml exists on remote
- [ ] All services defined: oauth2-oidc-issuer, jwt-validator, session-broker, etc.

### On Primary Host

```bash
ssh akushnir@192.168.168.31 << 'EOF'
cd code-server-enterprise

# 1. Load .env.phase-2 into current session
set -a
source .env.phase-2
set +a

# 2. Verify critical variables loaded
echo "Verifying JWT environment variables:"
echo "CODE_SERVER_JWT_SUBJECT: $CODE_SERVER_JWT_SUBJECT"
echo "SESSION_BROKER_JWT_SUBJECT: $SESSION_BROKER_JWT_SUBJECT"
echo "OIDC_ISSUER_URL: $OIDC_ISSUER_URL"

# 3. Update docker-compose.yml with JWT services
# (Assume docker-compose.yml already exists with service definitions)
# Services that should be present:
# - caddy (load balancer)
# - oauth2-proxy (OIDC proxy)
# - oauth2-oidc-issuer (JWT issuer)
# - code-server (IDE)
# - session-broker (session manager)
# - jwt-validator (JWT validation service)
# - redis (token/JWKS cache)
# - prometheus (metrics)
# - grafana (dashboards)

# 4. Start all services with JWT configuration
docker-compose up -d

# 5. Wait for services to be healthy
echo "Waiting for services to be healthy..."
sleep 15

# 6. Check service status
echo "Service Status:"
docker-compose ps

# Expected: All services "Up" or "Up (healthy)"
EOF
```

### Verification
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose ps | grep -E 'oauth2-oidc-issuer|jwt-validator|session-broker' | awk '{print \$1, \$6}'"

# Expected output:
# oauth2-oidc-issuer   Up (health: starting)
# jwt-validator        Up (healthy)
# session-broker       Up (health: starting)
```

**Success Criteria**:
- [ ] All services running (status: Up)
- [ ] No services showing (unhealthy) or (Exited)
- [ ] oauth2-oidc-issuer responding on port 6969
- [ ] JWT validator responding on port 8081

---

## PHASE 2C.4: TOKEN ACQUISITION TEST (30 minutes)

### On Primary Host

```bash
ssh akushnir@192.168.168.31 << 'EOF'
# Wait for OIDC issuer to fully start
echo "Waiting for OIDC issuer to be ready..."
for i in {1..30}; do
  if docker-compose logs oauth2-oidc-issuer 2>/dev/null | grep -q "listening\|ready\|running"; then
    echo "✓ OIDC issuer ready"
    break
  fi
  echo "  Attempt $i/30..."
  sleep 2
done

# 1. Acquire JWT token from /oauth2/token endpoint
TOKEN=$(curl -s -X POST \
  http://localhost:6969/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=code-server&client_secret=test-secret&audience=api" \
  | jq -r '.access_token // empty')

if [ -z "$TOKEN" ]; then
  echo "✗ Token acquisition failed - no token returned"
  exit 1
fi

echo "✓ Token acquired: ${TOKEN:0:50}..."

# 2. Decode and verify JWT structure
echo ""
echo "JWT Header:"
echo "$TOKEN" | jq -R 'split(".") | .[0] | @base64d | fromjson'

echo ""
echo "JWT Payload:"
PAYLOAD=$(echo "$TOKEN" | jq -R 'split(".") | .[1] | @base64d | fromjson')
echo "$PAYLOAD"

# 3. Verify required claims
echo ""
echo "Claim Verification:"
echo -n "aud (audience): "
echo "$PAYLOAD" | jq '.aud'
echo -n "sub (subject): "
echo "$PAYLOAD" | jq '.sub'
echo -n "iss (issuer): "
echo "$PAYLOAD" | jq '.iss'
echo -n "iat (issued at): "
echo "$PAYLOAD" | jq '.iat'
echo -n "exp (expiration): "
echo "$PAYLOAD" | jq '.exp'

# Calculate if token expiration is ~1 hour from now
EXP=$(echo "$PAYLOAD" | jq '.exp')
IAT=$(echo "$PAYLOAD" | jq '.iat')
TTL=$((EXP - IAT))
echo -n "Token TTL: "
if [ "$TTL" -eq "3600" ]; then
  echo "✓ 3600 seconds (1 hour)"
else
  echo "⚠ $TTL seconds (expected 3600)"
fi
EOF
```

### Verification
```bash
# Expected output shows:
# - Token acquired successfully
# - Header: alg=RS256, typ=JWT, kid present
# - Payload: all required claims present
# - exp is ~3600 seconds in future
```

**Success Criteria**:
- [ ] HTTP 200 response from /oauth2/token
- [ ] Token is valid JWT (3 base64-separated parts)
- [ ] alg=RS256, typ=JWT in header
- [ ] sub, aud, iss, iat, exp in payload
- [ ] exp is approximately 3600 seconds (1 hour) from iat

---

## PHASE 2C.5: SERVICE-TO-SERVICE TEST (30 minutes)

### On Primary Host

```bash
ssh akushnir@192.168.168.31 << 'EOF'
# 1. Acquire token for service-to-service communication
TOKEN=$(curl -s -X POST \
  http://localhost:6969/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=code-server&client_secret=test-secret&audience=session-broker" \
  | jq -r '.access_token // empty')

if [ -z "$TOKEN" ]; then
  echo "✗ Service token acquisition failed"
  exit 1
fi

echo "✓ Service token acquired"

# 2. Test bearer token acceptance by session-broker
echo ""
echo "Testing bearer token acceptance..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
  http://localhost:7777/health \
  -H "Authorization: Bearer $TOKEN")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "✓ Session-broker accepted bearer token (HTTP 200)"
  echo "Response: $BODY"
elif [ "$HTTP_CODE" = "401" ]; then
  echo "⚠ Session-broker rejected bearer token (HTTP 401)"
  echo "Response: $BODY"
else
  echo "⚠ Unexpected HTTP status: $HTTP_CODE"
  echo "Response: $BODY"
fi

# 3. Test invalid token rejection
echo ""
echo "Testing invalid token rejection..."
INVALID_RESPONSE=$(curl -s -w "\n%{http_code}" \
  http://localhost:7777/health \
  -H "Authorization: Bearer invalid-token-12345")

INVALID_CODE=$(echo "$INVALID_RESPONSE" | tail -1)

if [ "$INVALID_CODE" = "401" ]; then
  echo "✓ Invalid token correctly rejected (HTTP 401)"
else
  echo "✗ Invalid token not rejected (HTTP $INVALID_CODE)"
fi

# 4. Check JWT validator metrics in Prometheus
echo ""
echo "Checking JWT validation metrics..."
METRICS=$(curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=jwt_validator_validation_total{status="success"}' 2>/dev/null)

if echo "$METRICS" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
  echo "✓ JWT validator metrics being collected"
  echo "$METRICS" | jq '.data.result[0]'
else
  echo "⚠ JWT validator metrics not yet available (may need to wait)"
fi
EOF
```

### Verification
```bash
# Expected results:
# - Bearer token accepted by session-broker (HTTP 200)
# - Invalid token rejected (HTTP 401)
# - Prometheus metrics showing jwt_validator_validation_total
```

**Success Criteria**:
- [ ] Valid bearer token accepted (HTTP 200)
- [ ] Invalid bearer token rejected (HTTP 401)
- [ ] JWKS cache is being used (no direct issuer calls)
- [ ] Prometheus metrics recorded for JWT validation
- [ ] Service logs show successful JWT validation

---

## PHASE 2C COMPLETION CHECKLIST

- [ ] C.1: GSM Secrets Provisioned
  - [ ] service-client-session-broker-secret created
  - [ ] service-client-backend-secret created
  - [ ] ide-session-lb-secret created

- [ ] C.2: Configuration Merged
  - [ ] .env.phase-2 created with all 12+ variables
  - [ ] All JWT configuration loaded into environment
  - [ ] Secrets securely stored in GSM

- [ ] C.3: Services Deployed
  - [ ] docker-compose up -d successful
  - [ ] All 9 services running (status: Up)
  - [ ] Health checks passing

- [ ] C.4: Token Acquisition Working
  - [ ] /oauth2/token endpoint responding (HTTP 200)
  - [ ] JWT token structure valid (3 parts)
  - [ ] Claims present: sub, aud, iss, iat, exp
  - [ ] Token TTL is 3600 seconds

- [ ] C.5: Service-to-Service Auth Working
  - [ ] Bearer token accepted by services
  - [ ] Invalid tokens rejected (HTTP 401)
  - [ ] JWKS cache functional
  - [ ] Prometheus metrics collecting

**Phase 2C Status**: When all items above are checked ✓, Phase 2C is COMPLETE

---

## TROUBLESHOOTING

| Issue | Solution |
|-------|----------|
| GCP credentials expired | Run `gcloud auth login` with fresh credentials |
| Secret already exists error | Script handles this - creates new version instead |
| OIDC issuer not responding | Check: `docker-compose logs oauth2-oidc-issuer` |
| Token acquisition timeout | Check network connectivity: `curl -v http://localhost:6969/health` |
| Bearer token rejected | Verify `CODE_SERVER_JWT_AUDIENCE` matches service expectation |
| Prometheus metrics missing | May need 30-60 seconds for metrics collection |

---

## TIMELINE

- Phase 2C.1 (GSM): 30 minutes
- Phase 2C.2 (Config): 20 minutes
- Phase 2C.3 (Deploy): 45 minutes
- Phase 2C.4 (Token): 30 minutes
- Phase 2C.5 (S2S): 30 minutes
- **Total**: 2-3 hours

---

**Ready to execute.** Follow steps sequentially. Verify after each phase before proceeding to next.
