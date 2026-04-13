# Enterprise Code-Server Deploymen

## Quick Start (HTTPS + Reverse Proxy)

### Prerequisites
- Docker & Docker Compose installed
- WSL2 or Linux environmen

### Deployment Steps

1. **Start enterprise stack:**
```bash
cd ~/code-server-enterprise
docker-compose up -d


2. **Access via HTTPS:**

https://localhos


3. **Get initial password:**
```bash
grep password ~/.config/code-server/config.yaml


---

## Enterprise Features Included

✅ **HTTPS/TLS Encryption** - Automatic cert generation via Caddy
✅ **Reverse Proxy** - Caddy handles all HTTP requests
✅ **WebSocket Support** - For real-time IDE features
✅ **Security Headers** - HSTS, X-Frame-Options, CSP ready
✅ **Container Isolation** - Docker network segmentation
✅ **Persistent Storage** - Volumes for code and configuration

---

## Next Steps (Post-Deployment)

### Add OAuth2 Authentication (GitHub/Google)
Install `oauth2-proxy` alongside Caddy for SSO:
```yaml
oauth2-proxy:
  image: quay.io/oauth2-proxy/oauth2-proxy:lates
  environment:
    - OAUTH2_PROXY_CLIENT_ID=your-github-app-id
    - OAUTH2_PROXY_CLIENT_SECRET=your-github-secre
    - OAUTH2_PROXY_PROVIDER=github


### Add Multi-User Suppor
Use Coder platform instead of standalone code-server for:
- Team workspaces
- RBAC (Role-Based Access Control)
- Resource quotas
- Audit logging

### Enable Monitoring
Add Prometheus + Grafana for metrics:
```yaml
prometheus:
  image: prom/prometheus:lates
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml


---

## Security Checklis

- [ ] Change default passwords in docker-compose.yml
- [ ] Set up GitHub OAuth app (Settings → Developer Settings)
- [ ] Configure firewall rules (only allow 80/443 from trusted IPs)
- [ ] Enable audit logging in code-server config
- [ ] Set resource limits in docker-compose
- [ ] Backup volumes regularly
- [ ] Rotate passwords monthly

---

## Troubleshooting

**Can't access HTTPS?**
- Caddy generates self-signed cert on first run
- Browser will show security warning (expected for self-signed)
- Click "Advanced" → "Proceed" to bypass

**WebSocket errors?**
- Verify `websocket` directive in Caddyfile
- Check code-server logs: `docker logs code-server-enterprise_code-server_1

**Permission denied?**
- Ensure WSL volumes have correct permissions
- Run: `chmod 755 ~/code-server-enterprise/workspaces
