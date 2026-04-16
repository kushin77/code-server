# Code Server Enterprise - Production Quick Start

**Status:** Production Ready  
**Last Updated:** April 21, 2026  
**Owner:** Infrastructure Team

---

## 🚀 Quick Reference

### Access Points

| Service | URL | Port | Credentials |
|---------|-----|------|-------------|
| **Code Server** | http://code-server.192.168.168.31.nip.io | 8080 | OAuth2 (via proxy) |
| **Prometheus** | http://192.168.168.31:9090 | 9090 | None (local only) |
| **Grafana** | http://192.168.168.31:3000 | 3000 | admin/admin123 |
| **AlertManager** | http://192.168.168.31:9093 | 9093 | None (local only) |
| **Jaeger** | http://192.168.168.31:16686 | 16686 | None (local only) |

---

## 📊 System Status

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Check container status
docker-compose ps

# View recent logs
docker-compose logs -f --tail=50

# Check system health
curl -s http://localhost:8080/health | jq .
```

---

## 🚨 Common Operations

### Deploy Changes
```bash
# From Windows
deploy.bat remote apply

# From Linux/WSL
./deploy.sh remote apply --auto-approve

# Or SSH and deploy directly
ssh akushnir@192.168.168.31
cd code-server-enterprise
terraform -chdir=terraform apply -auto-approve
```

### Check Status
```bash
# From Windows
deploy.bat remote status

# From Linux/WSL
./deploy.sh remote status

# Or SSH
ssh akushnir@192.168.168.31
docker-compose ps
```

### View Logs
```bash
# From Windows
deploy.bat remote logs

# From Linux/WSL  
./deploy.sh remote logs

# Or SSH
ssh akushnir@192.168.168.31
docker-compose logs -f
```

### Connect to Host
```bash
# From Windows
deploy.bat remote shell

# From Linux/WSL
./deploy.sh remote shell

# Direct SSH
ssh akushnir@192.168.168.31
```

---

## 🔐 Security Checklist

Before deploying to production:

- [ ] All secrets are environment variables (not in code)
- [ ] HTTPS/TLS is enabled
- [ ] OAuth2 authentication is configured
- [ ] Network policies restrict access
- [ ] Monitoring and alerting are enabled
- [ ] Backup procedures are tested
- [ ] Incident runbooks are available
- [ ] Team has access to runbooks

See [Deployment Guide](./docs/production/deployment-guide.md) for full checklist.

---

## 📈 Monitoring & Alerts

### Key Dashboards
- **Overview:** http://192.168.168.31:3000/d/overview
- **Services:** http://192.168.168.31:3000/d/services
- **Infrastructure:** http://192.168.168.31:3000/d/infrastructure
- **Performance:** http://192.168.168.31:3000/d/performance

### Alert Thresholds
- **Error Rate:** >1% (critical)
- **P99 Latency:** >150ms (warning), >300ms (critical)
- **CPU Usage:** >80% (warning), >90% (critical)
- **Memory Usage:** >85% (warning), >95% (critical)
- **Disk Usage:** >80% (warning), >90% (critical)

See [Monitoring Setup](./docs/operations/monitoring.md) for detailed configuration.

---

## 🆘 Incident Response

### Service Down
1. Check health: `curl http://localhost:8080/health`
2. Check logs: `docker-compose logs -f`
3. Check containers: `docker-compose ps`
4. See [Service Recovery Runbook](./docs/runbooks/service-recovery.md)

### High Error Rate
1. Check logs for errors: `docker-compose logs -f code-server`
2. Check upstream services
3. Review recent changes
4. Rollback if necessary
5. See [Incident Response Runbook](./docs/runbooks/incident-response.md)

### Performance Issues
1. Check resource usage: `docker stats`
2. Check database queries
3. Check network connectivity
4. Scale up if needed
5. See [Performance Troubleshooting](./docs/runbooks/performance-issues.md)

---

## 🔄 Deployment Procedures

### Standard Deployment
```bash
# 1. Validate
./deploy.sh remote validate

# 2. Plan
./deploy.sh remote plan

# 3. Apply
./deploy.sh remote apply --auto-approve

# 4. Monitor
./deploy.sh remote logs
```

### Rollback
```bash
# If issues occur, rollback immediately
git revert <commit_sha>
git push origin main
# CI/CD deploys automatically

# Or manually restart services
ssh akushnir@192.168.168.31
cd code-server-enterprise
docker-compose restart
```

See [Deployment Guide](./docs/production/deployment-guide.md) for detailed procedures.

---

## 📋 Key Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definitions and configuration |
| `terraform/` | Infrastructure as Code (IaC) |
| `deploy.sh` / `deploy.bat` | Unified deployment entrypoint |
| `.env` | Environment variables (secrets) |
| `config/` | Configuration files for services |
| `docs/` | Complete documentation |

---

## 🔍 Verification Checklist

After deployment, verify:

```bash
# 1. All containers running
docker-compose ps

# 2. Health checks passing
curl http://localhost:8080/health
curl http://localhost:9090/-/healthy
curl http://localhost:3000/api/health

# 3. Logs clean (no errors)
docker-compose logs --tail=100 | grep -i error

# 4. Prometheus scraping targets
curl http://localhost:9090/api/v1/targets

# 5. Grafana dashboards loading
curl http://localhost:3000/api/search

# 6. Services responsive
curl -I http://code-server.192.168.168.31.nip.io/
```

---

## 🎯 SLOs & Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Availability | 99.99% | — |
| P99 Latency | <100ms | — |
| Error Rate | <0.1% | — |
| MTTR | <30 min | — |

See [SLOs](./docs/production/slos.md) for detailed definitions.

---

## 📚 Documentation

- **Getting Started:** [./docs/guides/getting-started.md](./docs/guides/getting-started.md)
- **Deployment:** [./docs/production/deployment-guide.md](./docs/production/deployment-guide.md)
- **Operations:** [./docs/operations/operations-guide.md](./docs/operations/operations-guide.md)
- **Runbooks:** [./docs/runbooks/](./docs/runbooks/)
- **Architecture:** [./docs/architecture/](./docs/architecture/)
- **Standards:** [./docs/standards/](./docs/standards/)

---

## 🤝 Support & Escalation

| Issue | First Step | Escalation |
|-------|-----------|-----------|
| Service down | Check runbook | Infrastructure Team |
| High errors | Check logs | On-call engineer |
| Performance | Scale if needed | Architecture review |
| Security | Isolate service | CISO + Infrastructure |

---

## 📞 Contact

- **Infrastructure Team:** infrastructure@company.internal
- **On-Call:** See PagerDuty
- **Escalation:** VP of Infrastructure
- **Emergency:** Security team

---

## 🔐 Important Reminders

⚠️ **Never:**
- Commit secrets to repository
- Deploy without validating
- Make manual changes without documenting
- Run commands as root unless necessary

✅ **Always:**
- Use deployment scripts (./deploy.sh or deploy.bat)
- Monitor after deployment (at least 1 hour)
- Document configuration changes
- Test rollback procedures
- Review runbooks before incidents

---

**Last Updated:** April 21, 2026  
**Next Review:** May 21, 2026  
**Owner:** Infrastructure Team

For detailed information, see [./docs/](./docs/)
