# Code-Server Health Check & Troubleshooting

> **Note**: This guide covers the **code-server container** (server-side) running on Linux.
> This project uses **Linux-only deployment**. Windows is NOT a supported platform.
> For development, use Linux (native) or WSL2.

## Server Health Status

### Quick Health Check

```bash
# Check code-server container status
docker-compose ps code-server

# Expected output: code-server ... Up ... (healthy)

# Check container logs
docker-compose logs code-server | tail -20

# Verify web interface responds
curl -s http://localhost:8080/healthz | jq .
```

### Common Issues

#### 1. Code-Server Container Crashes
```bash
# Check logs for errors
docker-compose logs code-server --tail 50

# Restart container
docker-compose restart code-server

# Verify it stays running (wait 10 seconds)
sleep 10 && docker-compose ps code-server
```

#### 2. Workspace Connection Timeout
```bash
# Check network connectivity to code-server
curl -v http://localhost:8080

# Check OAuth proxy health (required for auth)
docker-compose logs oauth2-proxy | grep -i error | tail -10

# Verify code-server is accepting connections
docker-compose exec code-server ps aux | grep coder-server
```

#### 3. High Memory Usage
```bash
# Monitor resource usage
docker stats code-server

# Check for runaway processes
docker-compose exec code-server top -b -n 1 | head -15

# Clear extension cache (inside container)
docker-compose exec code-server rm -rf ~/.local/share/code-server/extensions/*
docker-compose restart code-server
```

#### 4. File Sync Issues
```bash
# Check workspace directory permissions
ls -la /home/coder/workspace/

# Verify NAS mount is active
docker-compose exec code-server mount | grep /mnt

# Test NAS connectivity from container
docker-compose exec code-server nslookup nas-56.local
```

## Debugging

### Enable Debug Logging
```bash
# Add to docker-compose.yml environment
- CODE_SERVER_LOG_LEVEL=debug

# Restart
docker-compose restart code-server
docker-compose logs code-server -f
```

### Monitor Health Over Time
```bash
# Watch container status continuously
watch -n 5 'docker-compose ps code-server'

# Monitor resource usage
docker stats code-server --no-stream
```

## Production Monitoring

Code-server health is monitored via:
- ✅ Prometheus health check (port 8080)
- ✅ Alerting on down status
- ✅ Automatic restart on failure
- ✅ Grafana dashboard showing uptime

See monitoring docs for detailed observability setup.

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — System overview
- [DEPLOYMENT-EXECUTION-PROCEDURE.md](DEPLOYMENT-EXECUTION-PROCEDURE.md) — Docker Compose management
- [CONTRIBUTING.md](CONTRIBUTING.md) — Development setup (Linux)
