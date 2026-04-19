# Runbook: Caddy Reverse Proxy Down

**Alert**: CaddyDown  
**Severity**: CRITICAL  
**SLA**: Resolve within 10 minutes (external access blocked)  
**Owner**: Infrastructure Team  

## Symptoms

- Alert: "Caddy reverse proxy is down"
- External users cannot access any service (code-server, Grafana, Prometheus)
- Health endpoint http://192.168.168.31/health returns 503

## Root Causes

1. Container crashed (config reload failure, panic)
2. Port 80/443 in use by another process
3. TLS certificate invalid
4. Configuration syntax error
5. Caddyfile reload failed

## Diagnosis

```bash
# Check container
docker ps | grep caddy
docker logs caddy | tail -50

# Test health endpoint
curl -I http://localhost/health

# Check port availability
netstat -tuln | grep ":80 \|:443 "

# Validate Caddyfile
docker exec caddy caddy validate --config /etc/caddy/Caddyfile
```

## Remediation

### Step 1: Check Container Status (1 min)
```bash
docker ps -a | grep caddy
```

**If running**: Health check failed (likely config issue) → Step 3  
**If stopped**: Container crashed → Step 2  

### Step 2: Restart Container (2 min)
```bash
docker-compose restart caddy
sleep 5
curl -I http://localhost/health
```

**If healthy**: Resolved  
**If still down**: Go to Step 3  

### Step 3: Validate Configuration (3 min)
```bash
# Check Caddyfile syntax
docker exec caddy caddy validate --config /etc/caddy/Caddyfile

# If syntax error: fix and reload
# See: docs/Caddyfile (golden copy)
```

**If syntax error found**:
```bash
# Restore from backup
cp /data/caddy/Caddyfile.backup /etc/caddy/Caddyfile

# Reload
docker exec caddy caddy reload --config /etc/caddy/Caddyfile

# Verify
curl -I http://localhost/health
```

### Step 4: Check Port Conflicts (2 min)
```bash
# Check what's using ports 80/443
sudo netstat -tuln | grep -E ":80 |:443 "
sudo lsof -i :80
sudo lsof -i :443

# Kill conflicting process if needed
sudo kill -9 <PID>

# Restart Caddy
docker-compose restart caddy
```

### Step 5: Full Restart (3 min)
```bash
docker-compose down caddy
sleep 3
docker-compose up -d caddy
sleep 5
curl -I http://localhost/health
```

## Prevention

- [ ] Review recent Caddyfile changes (git log docs/Caddyfile)
- [ ] Test configuration in staging before production
- [ ] Implement Caddyfile change review workflow
- [ ] Add backup copy of known-good Caddyfile
- [ ] Monitor config reload errors in logs

## Escalation

If unresolved after 10 minutes:
1. All external access is blocked
2. Page infrastructure on-call lead immediately
3. Prepare rollback (previous docker-compose config)
4. Consider failover to secondary host (192.168.168.42)

---

**Status**: Ready for production deployment  
**Last Updated**: April 16, 2026  
**Runbook Owner**: Infrastructure Team
