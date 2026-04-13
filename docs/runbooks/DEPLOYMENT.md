# Production Deployment Runbook

## Prerequisites
- `kubectl` configured with prod cluster access
- `kustomize` v5+
- Docker credentials in `~/.docker/config.json`
- GCP service account with appropriate roles
- Change control approval (CHANGE-XXXX)

## Pre-Deployment Checklist
- [ ] All PR reviews merged to main
- [ ] All CI checks passing (build, test, security, performance)
- [ ] Code review approvals from 2+ maintainers
- [ ] Deployment window approved (avoid 4pm-6pm EST)
- [ ] Runbook walkthrough completed
- [ ] On-call engineer standing by
- [ ] Rollback plan reviewed and tested
- [ ] Metrics dashboards validated

## Deployment Steps

### 1. Pre-flight validation

```bash
# Verify cluster connectivity
kubectl cluster-info

# Validate manifests (all 3 environments)
kustomize build kubernetes/overlays/production --enable-alpha-plugins
kustomize build kubernetes/overlays/staging --enable-alpha-plugins
kustomize build kubernetes/overlays/dev --enable-alpha-plugins

# Verify images are built and available in registry
kubectl get images image:code-server:$(git rev-parse --short HEAD)
```

### 2. Canary Deployment (to staging, then 10% prod)

```bash
# Deploy to staging
kustomize build kubernetes/overlays/staging | kubectl apply -f -

# Wait for readiness
kubectl rollout status deployment/code-server -n code-server --timeout=5m
kubectl rollout status deployment/agent-api -n agents --timeout=5m
kubectl rollout status deployment/embeddings -n agents --timeout=5m

# Run smoke tests
./scripts/smoke-tests.sh staging

# If green, proceed to prod canary
# Scale code-server to 1 replica initially
kubectl scale deployment/code-server --replicas=1 -n code-server

# Monitor metrics for 15 minutes
watch -n 5 'kubectl top pod -n code-server'
```

### 3. Full Production Rollout

```bash
# Deploy to production
kustomize build kubernetes/overlays/production | kubectl apply -f -

# Monitor rollout (phase by phase)
kubectl rollout status deployment/code-server -n code-server --timeout=10m
kubectl rollout status deployment/agent-api -n agents --timeout=10m
kubectl rollout status deployment/embeddings -n agents --timeout=10m

# Verify all replicas are running
kubectl get pods -n code-server -l app=code-server
kubectl get pods -n agents -l app=agent-api
kubectl get pods -n agents -l app=embeddings

# Run full test suite
./scripts/integration-tests.sh production
./scripts/performance-tests.sh production
```

### 4. Post-Deployment Validation

```bash
# Health checks
curl -f https://code-server.prod.example.com/health || exit 1
curl -f https://api.agents.prod.example.com/health || exit 1
curl -f https://embeddings.agents.prod.example.com/health || exit 1

# Metrics validation (query Prometheus)
# - Request latency P99 < 1s
# - Error rate < 0.1%
# - Redis latency < 100ms
# - Agent API throughput > 100 req/s

# Verify SLO compliance
curl -s "http://prometheus:9090/api/v1/query?query=slo_compliance_percent" | jq '.data.result[].value[1]'

# Check alert status
kubectl get managedalerts -n observability

echo "✅ Production deployment successful"
```

## Rollback Procedure

If any health checks fail:

```bash
# Immediate rollback
kubectl rollout undo deployment/code-server -n code-server
kubectl rollout undo deployment/agent-api -n agents
kubectl rollout undo deployment/embeddings -n agents

# Verify previous version is running
kubectl rollout status deployment/code-server -n code-server --timeout=5m

# Investigate root cause
kubectl logs -l app=code-server -n code-server --tail=100
kubectl logs -l app=agent-api -n agents --tail=100

# Post-deployment review (mandatory)
# Document in incident log: what failed, why, how we fixed it
```

## Rollback Eligibility

Rollback is only safe if:
- Previous version is still running (keep 2 revisions minimum)
- No Database migrations in this release
- State is identical between versions (no feature flag changes)
- No data loss from new features

## Communication

1. **Deployment Start**: Announce in #engineering-deployments
2. **Every 5 minutes**: Status updates to on-call channel
3. **Completion**: Final metrics summary and closure

## Metrics to Monitor (15 minutes post-deployment)

| Metric | Threshold | Action If Exceeded |
|--------|-----------|-------------------|
| P99 Latency | > 1s | Scale up code-server replicas |
| Error Rate | > 0.5% | Investigate logs, consider rollback |
| Pod Restarts | > 1 per pod | Check resource limits, debug |
| Memory Usage | > 85% | Trigger HPA scale-up |
| Disk Usage | > 80% | Clean old logs, check for leaks |

## Estimated Deployment Time

- Pre-flight checks: 5 min
- Staging deployment: 10 min
- Staging validation: 5 min
- Production canary: 5 min
- Full production rollout: 15 min
- Post-deployment validation: 10 min
- **Total: ~50 minutes**

## Escalation Path

1. **Issue detected**: Page on-call engineer
2. **5 min unresolved**: Escalate to engineering lead
3. **10 min unresolved**: Escalate to CTO
4. **Rollback decision**: Made by engineering lead + CTO

## Success Criteria

✅ All pods in Running state  
✅ All readiness/liveness probes passing  
✅ Error rate < 0.1%  
✅ P99 latency < 1s  
✅ All SLOs met  
✅ No pages/alerts firing  
✅ Integration tests passing  
