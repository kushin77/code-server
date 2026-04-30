# Domain Fix Deployment Instructions - IMMEDIATE ACTION REQUIRED

## Status
✅ Configuration files updated and committed to git
⏳ **PENDING: Container deployment with new configuration**

## What Was Fixed
- Caddyfile root route now reverse proxies to Appsmith service
- docker-compose.enterprise.yml configured with OAuth environment variables
- .env.production updated with APPSMITH_DOMAIN and OAuth settings

## What Needs to Happen Next (You Must Execute This)

### Step 1: Pull Latest Configuration
```bash
cd /home/akushnir/code-server
git pull origin fix/domain-variability-caddy
```

### Step 2: Verify Environment Variables
```bash
source .env.production
echo "APPSMITH_DOMAIN=$APPSMITH_DOMAIN"
echo "OAUTH_ENABLED=$OAUTH_ENABLED"
```

### Step 3: Restart Appsmith Container with New Config
```bash
# Option A: Using docker-compose v2 (preferred)
docker compose -f docker-compose.enterprise.yml up -d appsmith

# Option B: Using docker-compose v1
docker-compose -f docker-compose.enterprise.yml up -d appsmith
```

### Step 4: Verify Appsmith is Running
```bash
docker ps | grep code-server-appsmith
docker logs -f code-server-appsmith --tail 50
```

Expected output: Appsmith startup logs showing port 8080 listening

### Step 5: Test Domain Access
```bash
# From any machine that can reach the domain:
curl -I https://kushnir.cloud/

# Expected response:
# HTTP/1.1 200 OK
# Content-Type: text/html
# (Appsmith OAuth login page HTML)
```

### Step 6: Verify in Browser
1. Open https://kushnir.cloud in a web browser
2. Should see: Appsmith OAuth login page (NOT Hermes Executive Assistant)
3. Should see OAuth provider buttons (Google, GitHub)
4. Click to test OAuth flow

## Git Commits to Deploy
- `dbe7cccb` - fix: domain configuration - route kushnir.cloud to Appsmith OAuth IDE
- `d23bf6a6` - doc: Domain fix verification and deployment guide - May 1, 2026

## Important Notes
- Caddy service must also be reloaded/restarted for the new Caddyfile configuration to take effect
- Both Caddy and Appsmith containers need to be running
- OAuth provider credentials should be set in environment if using real Google/GitHub OAuth
- This fix is NON-BREAKING - existing services remain operational during restart

## If Something Goes Wrong
1. Check Caddyfile syntax: `caddy fmt Caddyfile` (optional validation)
2. Check docker compose config: `docker compose config | grep -A 20 appsmith:`
3. Review Appsmith logs: `docker logs code-server-appsmith`
4. Review Caddy logs: `docker logs code-server-caddy` or `docker logs code-server-reverse-proxy`
5. Revert if needed: `git reset --hard dbe7cccb~1` (to previous working state)

## Timeline
- Config changes committed: ✅ Complete
- Files ready for deployment: ✅ Complete  
- **NEXT:** Execute deployment steps above (requires docker/container restart authority)
- **THEN:** Verify at https://kushnir.cloud shows Appsmith login
- **THEN:** Test OAuth flow works

---

**Current Status:** Configuration fix is code-complete and committed. Deployment requires running the docker compose restart commands above to activate the new Caddy reverse proxy and Appsmith OAuth configuration.
