# HTTPS Deployment Guide — Cloudflare Tunnel + TLS

## Status
✅ **Infrastructure code ready**
⏳ **Blocked on Cloudflare Tunnel token acquisition**

## Quick Start (Production Domain: ide.kushnir.cloud)

### Prerequisites
1. Cloudflare account with control of `ide.kushnir.cloud`
2. Production SSH access to 192.168.168.31
3. Cloudflare Tunnel token (see "Obtaining Token" section below)

### Step 1: Obtain Cloudflare Tunnel Token

**From Cloudflare Dashboard:**
```
1. Go to: https://dash.cloudflare.com
2. Select your domain (kushnir.cloud)
3. Navigate to: Networks > Tunnels
4. Find or create tunnel "ide-home-dev"
5. Select the tunnel → Copy the token (starts with NNNN-)
```

**Token format expected:**
```
NNNN-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

### Step 2: Deploy on Production Server

```bash
# SSH to production
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Method A: Set token directly (quick test)
echo "CLOUDFLARE_TUNNEL_TOKEN=<paste-token-here>" >> .env
docker-compose up -d cloudflared

# Method B: Store in GSM and use fetch script (recommended)
# (Requires gcloud auth to nexusshield-prod project)
bash scripts/fetch-gsm-secrets.sh > .env
docker-compose up -d cloudflared
```

### Step 3: Verify Tunnel Connection

```bash
# Watch cloudflared logs
docker logs cloudflared -f

# Look for:
# INF connected to edge with protocol http2
# INF established connection with edge
```

### Step 4: Test HTTPS

```
Browser: https://ide.kushnir.cloud
Expected: code-server login page (no SSL errors)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       Internet                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ DNS: ide.kushnir.cloud → 173.77.179.148
                       │
        ┌──────────────▼──────────────┐
        │   Cloudflare Global Network │
        │   (173.77.179.148)          │
        └──────────────┬──────────────┘
                       │
                ┌──────▼────────┐
                │  cloudflared  │ ◄── Tunnel daemon (this container)
                │  (tunnel run) │     Uses CLOUDFLARE_TUNNEL_TOKEN
                └──────┬────────┘
                       │
               ┌───────▼────────┐
               │  Caddy Proxy   │ ◄── TLS termination
               │ (reverse_proxy)│     HTTPS → HTTP bridge
               └───────┬────────┘
                       │
            ┌──────────▼──────────┐
            │   code-server:8080  │
            │  (IDE application)  │
            └─────────────────────┘
```

**Traffic flow:**
1. Browser connects to `ide.kushnir.cloud` over HTTPS
2. Cloudflare edge routes to cloudflared tunnel
3. cloudflared forwards to Caddy (local reverse proxy)
4. Caddy handles TLS, proxies HTTP to code-server
5. code-server serves IDE interface

---

## Troubleshooting

### Error: "CLOUDFLARE_TUNNEL_TOKEN" not set
- **Cause**: Token not in .env file
- **Fix**: Add `CLOUDFLARE_TUNNEL_TOKEN=<your-token>` to .env
- **Verify**: `grep TUNNEL .env`

### Error: "cloudflared" service won't start
```bash
docker logs cloudflared
# Check for:
# - Authentication failures (bad token)
# - Connection issues (firewall blocking)
# - Configuration errors (bad config.yml)
```

### Error: "SSL_PROTOCOL_ERROR" on browser
- **Cause**: cloudflared not connected (check above) OR Caddy not running
- **Fix**:
  ```bash
  docker logs cloudflared
  docker logs caddy
  ```

### GSM Secret Fetch Fails
- **Current issue**: Account akushnir@bioenergystrategies.com lacks access to nexusshield-prod
- **Workaround**: Manually inject token (Method A above)
- **Fix**: Add IAM role allowing secret access to nexusshield-prod

---

## Environment Files

| File | Purpose | Status |
|------|---------|--------|
| `.env` | Runtime environment variables | ⏳ Needs CLOUDFLARE_TUNNEL_TOKEN |
| `.env.production` | Production template (Vault refs) | ✅ Ready |
| `.env.example` | Documentation of all variables | ✅ Complete |
| `scripts/fetch-gsm-secrets.sh` | Auto-fetch secrets from GSM | ✅ Code ready, needs auth |

---

## Services Configuration

### cloudflared
- **Image**: cloudflare/cloudflared:2024.12.0
- **Command**: `tunnel run --token=${CLOUDFLARE_TUNNEL_TOKEN}`
- **Config**: `config/cloudflare/config.yml` (tunnel routing rules)
- **Health check**: `cloudflared tunnel info` (30s interval)

### caddy
- **Image**: caddy:2.8
- **Config**: `Caddyfile` (reverse proxy + TLS)
- **Routes**:
  - `ide.kushnir.cloud` → code-server:8080 (HTTPS)
  - `code-server.192.168.168.31.nip.io` → code-server:8080 (HTTP, on-prem)

### code-server
- **Image**: codercom/code-server:4.115.0
- **Port**: 8080 (internal, accessed via Caddy)
- **Workspace**: `/home/coder/workspace` (mounted volume)

---

## Production Checklist

- [ ] Cloudflare Tunnel token obtained
- [ ] Token injected into .env on 192.168.168.31
- [ ] cloudflared service running: `docker-compose up -d cloudflared`
- [ ] Tunnel connected to edge: `docker logs cloudflared | grep connected`
- [ ] HTTPS accessible: `https://ide.kushnir.cloud` loads without SSL errors
- [ ] User authentication working (oauth2-proxy integration)
- [ ] Monitoring in place (Prometheus + Grafana)

---

## References

- **Cloudflare Tunnel Documentation**: https://developers.cloudflare.com/cloudflare-one/connections/connect-applications/
- **config/cloudflare/config.yml**: Tunnel routing ingress rules
- **docker-compose.yml**: Lines 240-273 (cloudflared service definition)
- **Caddyfile**: Reverse proxy and TLS configuration
- **scripts/fetch-gsm-secrets.sh**: Secret fetching from Google Secret Manager
