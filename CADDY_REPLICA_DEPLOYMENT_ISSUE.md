# Caddy Deployment Issue on Replica Host (.42)

**Issue**: Caddy reverse proxy is not running on replica host (192.168.168.42)  
**Root Cause**: Kubernetes nginx-ingress-controller holds port 80/443  
**Status**: Documented, awaiting manual resolution or sudo access  
**Date**: April 29, 2026

## Problem Analysis

### Container Status
- **Primary (.31)**: Caddy running ✓
  - PID: bbe5183834ff  
  - Ports: 0.0.0.0:80→80/tcp, 0.0.0.0:443→443/tcp
  - Status: Up 23 minutes
  
- **Replica (.42)**: Caddy NOT running ✗
  - Missing from docker-compose stack
  - Port 80 blocked by nginx-ingress-controller

### Port 80 Blocker

The replica has a Kubernetes-like ingress controller holding port 80:

```bash
/nginx-ingress-controller --publish-service=ingress-nginx/ingress-nginx-controller ...
```

This process (PID ~17349) is preventing Docker from binding Caddy to port 80/443.

**Evidence**:
```bash
netstat -tlnp 2>/dev/null | grep ":80"
# Shows ~40 listening sockets on port 80, all with PID "-" (orphaned)
# and the nginx-ingress-controller process
```

### Deployment Attempts

1. **Docker direct (bridge network)** ✗
   - Error: "failed to bind host port for 0.0.0.0:80"
   
2. **Docker direct (host network)** ✗  
   - Error: Still blocked by nginx-ingress-controller
   
3. **Docker-compose** ✗
   - Syntax error in qdrant ports configuration
   - Missing env vars (OAUTH2_COOKIE_SECRET, DB_PASSWORD, etc.)
   
4. **OS-level nginx service** ✗
   - No systemctl/service nginx to stop
   - Ingress controller is the actual blocker

## Solutions

### Option 1: Kill nginx-ingress-controller (Recommended)

```bash
# Stop the ingress controller
sudo kill 17349  # or use pkill -f nginx-ingress-controller

# Verify port is free
netstat -tlnp 2>/dev/null | grep ":80"

# Start Caddy on replica
ssh -o BatchMode=yes akushnir@192.168.168.42 <<'EOF'
docker rm -f code-server-caddy 2>/dev/null || true
docker run -d \
  --name code-server-caddy \
  --network host \
  --restart unless-stopped \
  -v /tmp/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v caddy-data:/data \
  -e APEX_DOMAIN=kushnir.cloud \
  caddy:2.7.4 caddy run --config /etc/caddy/Caddyfile
EOF
```

**Risk**: If the ingress controller is managing Kubernetes/production traffic, killing it could cause outages. Verify it's not being used first.

### Option 2: Reconfigure Caddy on Different Port

Run Caddy on port 8000 or 9000 instead:

```bash
docker run -d \
  --name code-server-caddy \
  --network services \
  --restart unless-stopped \
  -p 8000:80 \
  -v /tmp/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v caddy-data:/data \
  -e APEX_DOMAIN=kushnir.cloud \
  caddy:2.7.4 caddy run --config /etc/caddy/Caddyfile
```

**Downside**: Router would need to forward to port 8000 instead of 80, breaking DNS resolution.

### Option 3: Fix docker-compose Deployment

1. Fix qdrant ports syntax error:
   ```yaml
   # In docker-compose.yml, change:
   # ports: [6333:6333, 6334:6334]
   # To proper format
   ports:
     - "6333:6333"
     - "6334:6334"
   ```

2. Provide missing env vars in .env.production or at deploy time:
   ```bash
   export OAUTH2_COOKIE_SECRET="<generated-secret>"
   export DB_PASSWORD="<postgres-password>"
   export OAUTH2_CLIENT_ID="<client-id>"
   export OAUTH2_CLIENT_SECRET="<client-secret>"
   export SCHEDULER_API_KEY="<api-key>"
   ```

3. Redeploy:
   ```bash
   cd ~/code-server-enterprise
   docker-compose -f docker-compose.enterprise.yml up -d
   ```

## Current Workaround

**Temporary**: Caddy is running on primary (.31) only. The shared VIP (192.168.168.30) for keepalived HA is not yet deployed.

**Impact**: 
- ✓ kushnir.cloud accessible via primary host
- ✗ No automatic failover to replica if primary goes down
- ✗ Replica cannot serve traffic until Caddy is deployed

## Files Staged for Deployment

- `/tmp/Caddyfile` on replica: Caddy configuration (deployed via SCP)
- `/tmp/keepalived.conf` on both hosts: HA failover config (ready for deployment)

## Next Steps

**Manual Action Required** (requires SSH access):

1. **Check ingress controller status**:
   ```bash
   ssh akushnir@192.168.168.42
   ps aux | grep nginx-ingress
   ```

2. **If safe to remove** (ingress not running production):
   ```bash
   sudo pkill -f nginx-ingress-controller
   ```

3. **Start Caddy**:
   ```bash
   docker rm -f code-server-caddy 2>/dev/null
   docker run -d \
     --name code-server-caddy \
     --network host \
     --restart unless-stopped \
     -v /tmp/Caddyfile:/etc/caddy/Caddyfile:ro \
     -v caddy-data:/data \
     -e APEX_DOMAIN=kushnir.cloud \
     caddy:2.7.4 caddy run --config /etc/caddy/Caddyfile
   ```

4. **Verify**:
   ```bash
   docker ps | grep caddy
   curl -s http://192.168.168.42/health
   ```

5. **Then deploy keepalived for HA** (see KEEPALIVED_HA_DEPLOYMENT.md)

## References

- [KEEPALIVED_HA_DEPLOYMENT.md](KEEPALIVED_HA_DEPLOYMENT.md) - VIP failover configuration (staged, awaiting deployment)
- [Caddyfile](../../config/caddy/Caddyfile) - Reverse proxy configuration (deployed to both hosts)
- [GSM_SECRETS_RUNBOOK.md](GSM_SECRETS_RUNBOOK.md) - Secrets management for missing env vars
