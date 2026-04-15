# Runbook: Endpoint Down

## Alert
`EndpointDown` - Triggered when an HTTP endpoint fails health checks for 1+ minute.

## Severity
🔴 CRITICAL

## Impact
- Service unavailable to users
- Zero availability for affected endpoint during outage
- Error budget consumption accelerated

## Diagnostics

### 1. Check endpoint accessibility
```bash
# Test from local machine
curl -v https://ide.kushnir.cloud/

# Test from production host
ssh akushnir@192.168.168.31 "curl -I http://localhost:8080"
```

### 2. Check relevant service status
```bash
# SSH to production
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Check all services
docker-compose ps

# Check specific service logs
docker-compose logs code-server | tail -20
docker-compose logs caddy | tail -20
docker-compose logs oauth2-proxy | tail -20
```

### 3. Check Prometheus/Grafana for context
- Go to Prometheus: http://192.168.168.31:9090
- Search for: `probe_success{instance="..."}`
- Check HTTP status codes and latency

### 4. Check network connectivity
```bash
# From production host
docker exec -it blackbox curl -v https://ide.kushnir.cloud/
ping -c 5 192.168.168.31
netstat -tlnp | grep LISTEN
```

## Resolution

### Quick Fix (Service Restart)
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker-compose restart code-server caddy oauth2-proxy"
```

### Full Stack Restart
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker-compose down --remove-orphans && \
  docker-compose up -d"
```

### If PostgreSQL/Redis Down
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker-compose restart postgresql redis"
```

### Network Issues
```bash
# Check DNS
dig ide.kushnir.cloud
nslookup ide.kushnir.cloud

# Check firewall
sudo iptables -L -n
```

## Prevention

1. **Alerting** - This alert should trigger before users notice
2. **HA** - Deploy HA overlay (Issue #422): `docker-compose -f docker-compose.yml -f docker-compose.ha.yml up`
3. **Health Checks** - Ensure all services have health checks configured
4. **Monitoring** - Enable continuous synthetic monitoring (blackbox exporter)

## Escalation

- **5 min** - Page on-call engineer
- **15 min** - Escalate to platform team
- **30 min** - Escalate to management

---
**Last Updated**: April 15, 2026  
**Owner**: Platform Team  
**Severity**: Critical  
**RTO Target**: <5 minutes
