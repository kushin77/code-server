# Domain Fix - Deploy Now

## Quick Start (3 steps)

### Step 1: Run the automatic deployment script
```bash
cd /home/akushnir/code-server
bash deploy-domain-fix.sh
```

This script will:
- Pull the latest configuration from git
- Load environment variables
- Restart Appsmith container with OAuth configuration
- Restart Caddy reverse proxy
- Verify services are running
- Show you the domain access status

### Step 2: Wait for services to stabilize
The script runs verification automatically, but services may need 30-60 seconds to fully start.

### Step 3: Verify in browser
Navigate to: **https://kushnir.cloud**

**Expected result:** Appsmith OAuth login page (Google/GitHub buttons)  
**NOT expected:** Hermes Executive Assistant page

## Manual Deployment (if script doesn't work)

```bash
# Step 1: Pull changes
cd /home/akushnir/code-server
git pull origin fix/domain-variability-caddy

# Step 2: Load environment
source .env.production

# Step 3: Restart containers
docker compose -f docker-compose.enterprise.yml up -d appsmith caddy

# Step 4: Verify
sleep 10
curl -I https://kushnir.cloud/

# Step 5: Check logs if needed
docker logs code-server-appsmith -f
```

## Troubleshooting

### If you see "Hermes Executive Assistant" page:
- Services may still be starting (wait 60 seconds)
- Caddy may not have reloaded the config
- Try: `docker compose restart caddy`

### If you get connection timeout:
- Caddy service may not be running
- Check: `docker ps | grep caddy`
- Restart: `docker compose up -d caddy`

### If OAuth buttons don't appear:
- Appsmith may not have restarted properly
- Check: `docker logs code-server-appsmith | tail -50`
- Restart: `docker compose restart appsmith`

## What Changed

✅ **Caddyfile** - kushnir.cloud now routes to Appsmith instead of Hermes  
✅ **docker-compose.enterprise.yml** - OAuth configuration added to Appsmith  
✅ **Committed to git** - All changes are in commits dbe7cccb and d23bf6a6  

## Status

- Configuration: ✅ COMPLETE
- Git commits: ✅ COMPLETE  
- Deployment script: ✅ READY
- **Next:** Run `bash deploy-domain-fix.sh` to activate changes
