# 🔐 CLOUDFLARE TOKEN SETUP GUIDE

## Problem
- `https://ide.kushnir.cloud` returns `ERR_SSL_PROTOCOL_ERROR`
- Root cause: `cloudflared` tunnel daemon needs authentication token from Cloudflare
- GSM authentication not working over SSH (interactive token refresh required)

## Solution: Get Token & Deploy

### Step 1: Obtain Cloudflare Tunnel Token

**From Cloudflare Dashboard (takes 2 minutes):**
```
1. Open browser:     https://dash.cloudflare.com/
2. Select domain:    kushnir.cloud
3. Left sidebar:     Networks > Tunnels
4. Find tunnel:      ide-home-dev  
5. Click tunnel name
6. Copy button under "Token:"
   (format: aaaa-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb)
```

### Step 2: Deploy Token to Production

```bash
# On your local machine (NOT production server):
export CLOUDFLARE_TOKEN="<paste-token-from-dashboard-here>"

# SSH to production and inject the token:
ssh akushnir@192.168.168.31 << EOF
cd code-server-enterprise

# Add token to .env file
echo "CLOUDFLARE_TUNNEL_TOKEN=\$CLOUDFLARE_TOKEN" >> .env

# Verify it's in there:
grep CLOUDFLARE_TUNNEL_TOKEN .env

# Start cloudflared service:
docker-compose up -d cloudflared

# Watch startup (should complete in 10-20 seconds):
docker logs cloudflared -f
EOF
```

### Step 3: Verify HTTPS Works

```bash
# Test with curl:
curl -I https://ide.kushnir.cloud

# Should return:
# HTTP/2 200
# OR redirect to oauth2-proxy login

# Test in browser:
https://ide.kushnir.cloud
```

---

## What Happens After Token Deploy

```
┌──────────────────────────────────────────────────────────────┐
│ Browser: https://ide.kushnir.cloud                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │  Cloudflare Global Edge  │
        │  (173.77.179.148)        │
        │  Routes to cloudflared   │
        └──────────────┬───────────┘
                       │
                       ▼ (via tunnel with token)
        ┌──────────────────────────┐
        │  cloudflared daemon      │
        │  (container on 192.168.   │
        │   168.31)                │
        └──────────────┬───────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │  Caddy reverse proxy     │
        │  HTTP:80 →               │
        │  HTTPS TLS termination   │
        └──────────────┬───────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │  code-server:8080        │
        │  (IDE in browser)        │
        └──────────────────────────┘
```

---

## Troubleshooting

### "CLOUDFLARE_TUNNEL_TOKEN is empty"
```bash
# Check if token was set:
grep CLOUDFLARE_TUNNEL_TOKEN .env
# Should show actual token, not empty

# Fix:
echo "CLOUDFLARE_TUNNEL_TOKEN=<actual-token>" >> .env
```

### "cloudflared not connecting"
```bash
# Watch logs:
docker logs cloudflared -f

# Look for one of:
# ✅ "[INF] connected to edge"       ← SUCCESS
# ❌ "[ERR] Bad auth"                  ← Invalid token
# ❌ "[ERR] Unauthorized"              ← Token expired
# ❌ "[ERR] Connection refused"        ← Network issue
```

### "ERR_SSL_PROTOCOL_ERROR" still appears
1. Verify cloudflared is running: `docker ps | grep cloudflared`
2. Check tunnel connected: `docker logs cloudflared | grep connected`
3. Verify Caddyfile configured: `grep ide.kushnir.cloud Caddyfile`
4. Restart it: `docker-compose restart cloudflared`

### "Cannot reach dashboard to get token"
- Verify you have access to the Cloudflare account that owns kushnir.cloud domain
- Check: https://dash.cloudflare.com/ loads correctly
- If not, contact whoever manages the kushnir.cloud domain

---

## Files Involved

| File | Purpose | Status |
|------|---------|--------|
| `.env` | Runtime environment (CLOUDFLARE_TUNNEL_TOKEN) | Ready for token |
| `docker-compose.yml` | Service definition for cloudflared | ✅ In place (lines 240-273) |
| `config/cloudflare/config.yml` | Tunnel routing rules | ✅ Configured |
| `Caddyfile` | HTTPS/TLS reverse proxy | ✅ Ready |
| `scripts/fetch-gsm-secrets.sh` | Auto-fetch from GSM (blocked on auth) | ✅ Code ready |

---

## Direct Manual Deployment (No GSM)

If GSM authentication continues to fail, you can manually inject all secrets:

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Create .env with all required secrets:
cat >> .env << EOF
CLOUDFLARE_TUNNEL_TOKEN=<from-dashboard>
GOOGLE_CLIENT_ID=<from-gcp-console>
GOOGLE_CLIENT_SECRET=<from-gcp-console>
OAUTH2_PROXY_COOKIE_SECRET=867e5c21f89d4b162a3dbe5924761c8a
GODADDY_KEY=<optional-for-dns-updates>
GODADDY_SECRET=<optional-for-dns-updates>
EOF

# Verify all vars are set:
grep -E "CLOUDFLARE|GOOGLE|OAUTH2_PROXY_COOKIE|GODADDY" .env

# Deploy:
docker-compose up -d cloudflared
docker logs cloudflared -f
```

---

## GSM Issue (Why It's Failing)

Current error: `Could not fetch prod-cloudflare-tunnel-token from GSM project=gcp-eiq`

**Root cause**: gcloud interactive token refresh doesn't work over SSH  
**Workaround**: Use manual token injection (above) OR configure service account credentials

**To enable GSM long-term:**
1. Create GCP service account with Secret Manager access
2. Download JSON key file to production server
3. Set: `export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json`
4. Then: `bash scripts/fetch-gsm-secrets.sh > .env`

---

## Next Action

1. Get token from Cloudflare dashboard (5 min)
2. SSH into production (1 min)
3. Add token to .env (1 min)
4. Restart cloudflared (2 min)
5. Test HTTPS (2 min)

**Total time: ~10 minutes**  
**Result: Full HTTPS working on ide.kushnir.cloud**
