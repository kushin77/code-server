# Quick Reference: Crash Prevention & Recovery

## 🚨 Emergency: Immediate Actions

### If VS Code is crashing frequently:

```bash
# 1. Disable extensions (this usually fixes it)
code --disable-extensions

# 2. If that didn't help, clear workspace metadata
rm -rf ~/.config/Code/User/workspaceStorage
rm -rf ~/.config/Code/Cache

# 3. Check system resources
free -h          # Linux/WSL
Get-Process code # PowerShell

# 4. Restart VS Code fresh
code .
```

### If Docker containers are crashing:

```bash
# 1. Check all container statuses
docker ps -a

# 2. View recent errors
docker logs code-server --tail 20
docker logs ollama --tail 20

# 3. Restart containers gracefully
docker-compose down
docker-compose up -d

# 4. Check health status
docker inspect code-server --format='{{.State.Health.Status}}'
```

---

## 📊 Quick Health Checks

Run these commands regularly to detect issues early:

```bash
# VS Code stability
ps aux | grep code | grep -v grep
code --list-extensions | head -20

# Docker health
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"
docker stats --no-stream

# System resources
df -h /
free -h              # Linux only (production platform)

# Network connectivity
curl -s https://ide.kushnir.cloud/health | jq .
ssh -o ConnectTimeout=5 192.168.168.31 "docker ps"
```

---

## 🔍 Debugging Crash Symptoms

### Symptom: VS Code freezes then crashes

**Likely Cause**: Language server OOM or file watcher overload

**Recovery Steps**:
```bash
# 1. Check memory
ps aux | sort -k6 -rn | head -10

# 2. Disable file watchers
# Already configured in .vscode/settings.json

# 3. Disable extensions one by one
code --disable-extensions github.copilot-chat
code --disable-extensions redhat.vscode-yaml
```

---

### Symptom: Docker container exits with code 137

**Likely Cause**: Out of Memory (OOM) killer

**Recovery Steps**:
```bash
# 1. Check logs for OOM
docker logs code-server | tail -10

# 2. Increase memory limit
docker update --memory=6g code-server
docker-compose down && docker-compose up -d

# 3. Monitor memory
docker stats code-server --interval 1
```

---

### Symptom: Extensions not loading / "Extension host crashed"

**Likely Cause**: Broken or incompatible extension

**Recovery Steps**:
```bash
# 1. Disable all extensions
code --disable-extensions

# 2. Wait 10 seconds, should work now
# 3. Re-enable one at a time:
code --install-extension github.copilot
# Test → If crashes, that's the culprit
```

---

### Symptom: "Connection timeout" or "gateway errors"

**Likely Cause**: Caddy/Cloudflare tunnel issue

**Recovery Steps**:
```bash
# 1. Check Caddy status
docker logs caddy --tail 30

# 2. Check tunnel status
docker logs ssh-proxy --tail 30

# 3. Verify OAuth2 proxy
docker logs oauth2-proxy --tail 30 2>/dev/null || echo "oauth2-proxy not running"

# 4. Force recreate
docker-compose up -d --force-recreate caddy
```

---

## 🛡️ Prevention Best Practices

### Daily Checklist
- [ ] Run `docker ps` — verify all containers healthy
- [ ] Check `free -h` — ensure >1GB free memory
- [ ] Monitor `docker logs` — scan for errors

### Weekly Checklist
- [ ] Review crash dumps: `ls -la ~/.config/Code/logs/`
- [ ] Check disk space: `df -h`
- [ ] Update VS Code: `code --version` vs latest
- [ ] Audit extensions: `code --list-extensions | wc -l`

### Monthly Checklist
- [ ] Full backup: `docker-compose down && tar -czf backup.tar.gz .`
- [ ] Security scan: `npm audit` + `docker scan code-server`
- [ ] Performance baseline: Save `docker stats` output
- [ ] Update dependencies: `npm update`, `pip update`

---

## 📈 Monitoring Setup

### Automated Health Checks (Background)

```bash
# Terminal 1: Memory monitor
bash scripts/memory-monitor.sh &

# Terminal 2: Docker health
bash scripts/docker-health-monitor.sh &

# Terminal 3: VS Code
code .

# Check logs
tail -f /tmp/memory-monitor.log
tail -f /tmp/docker-health-monitor.log
```

---

## 🔧 Configuration Optimizations

### For large workspaces (100K+ files):

```json
{
  "files.watcherExclude": {
    "**/node_modules/**": true,
    "**/.git/**": true,
    "**/.terraform/**": true,
    "**/*.tfstate*": true
  },
  "search.followSymlinks": false
}
```

### For high-performance machines (8GB+ RAM):

```json
{
  "editor.autoSave": "afterDelay",
  "editor.autoSaveDelay": 5000,
  "extensions.autoUpdate": true
}
```

### For resource-constrained machines (<4GB RAM):

```json
{
  "editor.formatOnSave": false,
  "editor.autoSave": "off",
  "extensions.autoUpdate": false,
  "[yaml]": {
    "editor.defaultFormatter": null
  }
}
```

---

## 📞 Escalation Path

If issues persist after trying above steps:

1. **Collect diagnostic bundle**:
   ```bash
   mkdir crash-diagnostic
   cp ~/.config/Code/logs/* crash-diagnostic/
   docker logs code-server > crash-diagnostic/docker-code-server.log
   docker logs ollama > crash-diagnostic/docker-ollama.log
   ps aux > crash-diagnostic/processes.txt
   free -h > crash-diagnostic/memory.txt
   docker stats --no-stream > crash-diagnostic/docker-stats.txt
   tar -czf crash-diagnostic.tar.gz crash-diagnostic/
   ```

2. **File issue on GitHub**:
   - Title: "CRASH: [symptom] — [frequency]"
   - Labels: `P0-crash`, `bug`
   - Attach diagnostic bundle
   - Include timestamps and reproduction steps

3. **Contact infrastructure team**:
   - Slack: #infrastructure
   - Email: devops@kushnir.cloud

---

## Reference

- **Crash Scan Report**: [CRASH_VULNERABILITY_SCAN.md](CRASH_VULNERABILITY_SCAN.md)
- **Troubleshooting Guide**: [VSCODE_CRASH_TROUBLESHOOTING.md](VSCODE_CRASH_TROUBLESHOOTING.md)
- **Docker Compose**: [docker-compose.yml](docker-compose.yml)
- **VS Code Settings**: [.vscode/settings.json](.vscode/settings.json)

---

**Last Updated**: April 13, 2026  
**Maintained By**: Infrastructure Team  
**Review Frequency**: Quarterly
