# P1 #1661 — Direct Deployment Commands (Terminal-Free Reference)

## Quick Deployment (Copy-Paste Ready)

If terminal automation has issues, use these direct SSH commands:

### Deploy to Replica 31
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && \
   docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus'
```

### Deploy to Replica 42
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && \
   docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus'
```

### Deploy Both in Parallel (background)
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus' &

ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus' &

wait  # Wait for both to complete
```

---

## Quick Verification (After Deployment)

### Check Prometheus is Running
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 \
  'docker ps | grep prometheus'

ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 \
  'docker ps | grep prometheus'
```

### Check Prometheus Health
```bash
curl -k -s https://192.168.168.31:9090/-/healthy

curl -k -s https://192.168.168.42:9090/-/healthy
```

### Verify Scrape Targets (via curl to Prometheus API)
```bash
# Replica 31 targets
curl -k -s 'https://192.168.168.31:9090/api/v1/targets?state=active' | jq '.data.activeTargets[] | select(.labels.job | contains("cluster-health")) | {job: .labels.job, instance: .labels.instance, health: .health}'

# Replica 42 targets  
curl -k -s 'https://192.168.168.42:9090/api/v1/targets?state=active' | jq '.data.activeTargets[] | select(.labels.job | contains("cluster-health")) | {job: .labels.job, instance: .labels.instance, health: .health}'
```

---

## Configuration Deployed

### Prometheus Scrape Jobs (from prometheus.yml)
```yaml
- job_name: 'cluster-health-replica-31'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ['192.168.168.31:443']
      labels:
        replica: '31'
  metrics_path: /health
  scrape_interval: 30s

- job_name: 'cluster-health-replica-42'
  scheme: https
  tls_config:
    insecure_skip_verify: true
  static_configs:
    - targets: ['192.168.168.42:443']
      labels:
        replica: '42'
  metrics_path: /health
  scrape_interval: 30s
```

### Alert Rules (from alert-rules.yml)
```yaml
- alert: ClusterHealthCheckFailure
  expr: up{job=~"cluster-health-replica-.*"} == 0
  for: 1m
  # Single replica down after 1 minute

- alert: ClusterHealthCheckBothReplicasDown
  expr: count(up{job=~"cluster-health-replica-.*"} == 0) == 2
  for: 30s
  # Both replicas down after 30 seconds
```

---

## Status Summary

✅ **Configuration**: prometheus.yml and alert-rules.yml ready (version-controlled)  
✅ **Automation**: Deployment script created (`scripts/ops/deploy-cluster-health-monitoring.sh`)  
✅ **Documentation**: Complete deployment procedures (`1661-HEALTH-MONITORING-DEPLOYMENT.md`)  
⏳ **Deployment**: Ready for execution (copy-paste commands above or use automation script)  
⏳ **Verification**: Procedures documented (see above)  

---

## Definition of Done

After executing the deployment commands above:

- [ ] Both SSH commands complete successfully
- [ ] `docker ps | grep prometheus` shows running containers on both replicas
- [ ] Prometheus health endpoints respond with 200 OK
- [ ] Scrape targets show `cluster-health-replica-31` and `cluster-health-replica-42` as UP
- [ ] Metrics available in `/api/v1/query?query=up{job="cluster-health-replica-31"}`

---

## Next Steps

1. Execute deployment (copy-paste SSH commands)
2. Wait 30-60 seconds for Prometheus to scrape health endpoints
3. Verify using commands above
4. Update GitHub issue #1661 with deployment confirmation
5. Monitor alerts for 24 hours

---

**Status**: ✅ DEPLOYMENT READY  
**Risk**: 🟢 LOW  
**Rollback**: INSTANT (revert prometheus config, restart container)  
**Timeline**: 2-5 minutes total
