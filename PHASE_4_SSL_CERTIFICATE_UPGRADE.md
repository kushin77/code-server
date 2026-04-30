# Phase 4: SSL Certificate Upgrade to kushnir.cloud
**Date:** April 30, 2026 | **Priority:** HIGH  
**Current Status:** Using shared certificate (d8r978f08m4.d.firewalla.org)  
**Target:** kushnir.cloud-specific Let's Encrypt certificate

---

## Executive Summary

Current nginx deployment uses a shared infrastructure certificate (d8r978f08m4.d.firewalla.org) for kushnir.cloud domain. This causes browser SSL warnings and reduces security posture. Phase 4 includes upgrading to a kushnir.cloud-specific Let's Encrypt certificate with automatic renewal.

**Current Certificate Status:**
```
Subject: CN = d8r978f08m4.d.firewalla.org
Valid: Apr 30 03:23:22 2026 - Apr 30 03:23:22 2027
Issue: Domain mismatch with kushnir.cloud
Impact: Browser SSL warnings, reduced trust
```

---

## SSL Certificate Upgrade Procedure

### Step 1: Prepare Primary Host for Certificate Generation

SSH to primary host:
```bash
ssh on-prem-primary
```

Verify certbot is available:
```bash
which certbot || sudo apt-get update && sudo apt-get install -y certbot
```

### Step 2: Obtain Let's Encrypt Certificate for kushnir.cloud

**Option A: Standalone Mode (Preferred - No existing web server interference)**

Stop nginx temporarily to free port 80 and 443:
```bash
docker stop hermes-nginx
```

Generate certificate:
```bash
sudo certbot certonly --standalone -d kushnir.cloud \
  --email infrastructure@kushnir.cloud \
  --agree-tos \
  --non-interactive
```

**Option B: DNS Challenge (If port conflicts)**

If standalone fails due to port conflicts:
```bash
sudo certbot certonly --dns-route53 -d kushnir.cloud \
  --email infrastructure@kushnir.cloud \
  --agree-tos \
  --non-interactive
```
*(Requires AWS Route53 credentials in environment)*

### Step 3: Verify Certificate Generated Successfully

```bash
sudo ls -la /etc/letsencrypt/live/kushnir.cloud/
```

Expected files:
```
cert.pem       (public certificate)
chain.pem      (intermediate certificates)
fullchain.pem  (cert + chain combined)
privkey.pem    (private key)
```

Verify certificate validity:
```bash
sudo openssl x509 -in /etc/letsencrypt/live/kushnir.cloud/cert.pem -noout -subject -dates
```

### Step 4: Update nginx Configuration

On primary host, identify nginx config location:
```bash
docker inspect hermes-nginx --format '{{.Mounts}}' | grep -o '/etc/nginx'
```

Update nginx configuration with new certificate paths. Edit the kushnir.cloud server block:

**Current configuration:**
```nginx
server {
    listen 443 ssl;
    server_name kushnir.cloud;
    
    ssl_certificate /etc/letsencrypt/live/d8r978f08m4.d.firewalla.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/d8r978f08m4.d.firewalla.org/privkey.pem;
```

**Updated configuration:**
```nginx
server {
    listen 443 ssl;
    server_name kushnir.cloud;
    
    ssl_certificate /etc/letsencrypt/live/kushnir.cloud/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/kushnir.cloud/privkey.pem;
```

**Copy updated nginx.conf to container:**
```bash
# From local machine:
scp -i ~/.ssh/on-prem-primary /path/to/updated/nginx.conf \
  akushnir@192.168.168.31:/tmp/nginx.conf.new

# On primary host:
docker cp /tmp/nginx.conf.new hermes-nginx:/etc/nginx/nginx.conf
```

### Step 5: Reload nginx with New Certificate

Verify nginx config syntax:
```bash
docker exec hermes-nginx nginx -t
```

Expected output: `nginx: configuration file ... is ok`

Restart nginx container to apply configuration:
```bash
docker restart hermes-nginx
```

Verify nginx health:
```bash
docker inspect hermes-nginx --format '{{.State.Status}} | {{.State.Health.Status}}'
```

Expected: `running | healthy`

### Step 6: Verify Certificate in Browser

From external network (NOT via SSH tunnel):
```bash
curl -I https://kushnir.cloud/
```

Expected successful TLS handshake with kushnir.cloud certificate.

From browser:
1. Navigate to https://kushnir.cloud
2. Click on SSL certificate icon (lock)
3. Verify certificate is for **kushnir.cloud**
4. Verify issued by **Let's Encrypt**
5. Verify no SSL warnings

### Step 7: Setup Automatic Certificate Renewal

Create renewal hook script on primary host:

```bash
sudo mkdir -p /etc/letsencrypt/renewal-hooks/post
sudo cat > /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh << 'EOF'
#!/bin/bash
# Reload nginx after certificate renewal
docker restart hermes-nginx
echo "$(date): nginx reloaded after certificate renewal" >> /var/log/nginx-renewal.log
EOF

sudo chmod +x /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
```

Verify renewal hook:
```bash
sudo certbot renew --dry-run
```

Setup cron job for automatic renewal (already done by certbot):
```bash
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

Verify cron job:
```bash
sudo systemctl status certbot.timer
```

---

## SSL Certificate Upgrade Verification

### Pre-Upgrade Checklist
- [ ] SSH access to on-prem-primary verified
- [ ] Port 80 and 443 accessible for certificate generation
- [ ] Certbot installed on primary host
- [ ] Current nginx configuration backed up
- [ ] Team notified of upgrade window (5-10 minutes)

### Post-Upgrade Verification
- [ ] Certificate file exists: `/etc/letsencrypt/live/kushnir.cloud/fullchain.pem`
- [ ] Private key exists: `/etc/letsencrypt/live/kushnir.cloud/privkey.pem`
- [ ] nginx config updated with new certificate paths
- [ ] nginx service restarted successfully (health: healthy)
- [ ] External curl test: `curl -I https://kushnir.cloud/` returns 200
- [ ] Browser test: Navigate to https://kushnir.cloud (no SSL warnings)
- [ ] Certificate subject: CN = kushnir.cloud
- [ ] Certificate issuer: Let's Encrypt
- [ ] Certificate expiration: 90 days from generation date

### Rollback Procedure (If needed)
If upgrade fails, revert to previous certificate:

```bash
ssh on-prem-primary

# Restore backed-up nginx config
docker cp /backup/nginx.conf.old hermes-nginx:/etc/nginx/nginx.conf

# Reload nginx
docker exec hermes-nginx nginx -s reload

# Or restart container
docker restart hermes-nginx
```

---

## Certificate Lifecycle Management

### Renewal Schedule
- **Automatic renewal:** Certbot automatically renews 30 days before expiration
- **Manual renewal trigger:** `sudo certbot renew --force-renewal`
- **Renewal frequency:** Check monthly for any renewal issues

### Monitoring Certificate Expiration
Add to alerting system:
- [ ] Alert at 30 days before expiration (automatic renewal should trigger)
- [ ] Alert at 14 days before expiration (manual intervention window)
- [ ] Alert at 7 days before expiration (escalation required)
- [ ] Alert at 1 day before expiration (critical - manual action required)

Check current certificate expiration:
```bash
echo | openssl s_client -servername kushnir.cloud -connect kushnir.cloud:443 2>/dev/null | \
  openssl x509 -noout -dates
```

### Automatic Renewal Troubleshooting
If certificate fails to renew automatically:

```bash
# Check certbot renewal status
sudo certbot renew --dry-run -v

# Check systemd timer
sudo systemctl status certbot.timer
sudo journalctl -u certbot.timer

# Manual renewal attempt
sudo certbot renew -v
```

---

## Known Issues & Mitigations

### Issue 1: Port 443 Conflicts During Certificate Generation
**Cause:** nginx already running on port 443  
**Solution:** Stop nginx temporarily during generation (`docker stop hermes-nginx`)  
**Timeline:** 5-10 minutes downtime (acceptable during maintenance window)

### Issue 2: DNS Resolution Delay
**Cause:** DNS propagation for kushnir.cloud verification  
**Solution:** Use DNS-01 challenge instead of HTTP-01 (certbot --dns-route53)  
**Timeline:** May add 5 minutes to certificate generation

### Issue 3: ACME Rate Limiting
**Cause:** Too many certificate requests in short time  
**Solution:** Use staging environment first (`--test-mode`) or wait between requests  
**Timeline:** Rate limits reset hourly

### Issue 4: Certificate Renewal Failure
**Cause:** Misconfigured renewal hook or DNS issues  
**Solution:** Check certbot logs (`/var/log/letsencrypt/`) and systemd journal  
**Timeline:** Investigate within 7 days of expiration warning

---

## Cost & Resource Impact

**Cost:** FREE (Let's Encrypt is free)  
**Downtime:** ~5-10 minutes (acceptable during maintenance window)  
**Resource Usage:**
- CPU: Minimal (OpenSSL operations)
- Memory: <50MB (certbot process)
- Disk: <100MB (certificate files)
- Bandwidth: <1MB (Let's Encrypt communication)

---

## Phase 4 Certificate Upgrade Timeline

| Step | Task | Estimated Time | Status |
|------|------|-----------------|--------|
| 1 | Prepare host (SSH, verify certbot) | 2 min | Pending |
| 2 | Stop nginx, generate certificate | 5 min | Pending |
| 3 | Verify certificate generated | 1 min | Pending |
| 4 | Update nginx configuration | 3 min | Pending |
| 5 | Reload nginx with new cert | 2 min | Pending |
| 6 | Verify certificate in browser | 2 min | Pending |
| 7 | Setup automatic renewal | 2 min | Pending |
| **Total** | **SSL Certificate Upgrade** | **~17 minutes** | |

---

## Success Criteria

| Criterion | Target | Status |
|-----------|--------|--------|
| Certificate subject | CN = kushnir.cloud | Pending verification |
| Certificate issuer | Let's Encrypt | Pending verification |
| Certificate valid | ✅ Not expired | Pending verification |
| Browser SSL warnings | NONE | Pending verification |
| nginx health | healthy | Pending verification |
| External access | ✅ 200 OK | Pending verification |
| Automatic renewal | ✅ Configured | Pending verification |
| Renewal hook | ✅ Working | Pending verification |

**Overall Status:** ⏳ READY FOR EXECUTION

---

## Reference Documentation

**Let's Encrypt Documentation:** https://letsencrypt.org  
**Certbot Documentation:** https://certbot.eff.org  
**nginx SSL Configuration:** https://nginx.org/en/docs/http/ngx_http_ssl_module.html

---

## Next Steps

1. **Immediate (Hour 2 of Phase 4):** Execute SSL certificate upgrade
2. **Short-term:** Verify browser SSL warnings resolved
3. **Ongoing:** Monitor certificate expiration and automatic renewal

**Execution Owner:** DevOps/Infrastructure Team  
**Last Updated:** April 30, 2026  
**Status:** READY FOR EXECUTION
