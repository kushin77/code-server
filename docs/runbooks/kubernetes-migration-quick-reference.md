# Q3 Phase 4 Kubernetes Migration - Quick Reference Checklist

**Execution Period**: May 1-24, 2026  
**Audience**: SRE, Platform Engineering, Operations  
**Print and Post**: On war room wall during migration week  

---

## PRE-MIGRATION (April 30)

### Prerequisites Validation
- [ ] AWS account credentials verified (`aws sts get-caller-identity`)
- [ ] Tools installed: aws, eksctl, kubectl, helm, jq
- [ ] AWS budget approved (~$600/month for 4 weeks)
- [ ] Team members on-call assigned (4 weeks)
- [ ] Incident commander and escalation paths defined
- [ ] Backup of Docker Compose environment completed
- [ ] Communication channels set up (Slack, PagerDuty)
- [ ] Run-through of rollback procedures completed

---

## WEEK 1: INFRASTRUCTURE SETUP (May 1-3)

### Day 1: Cluster Provisioning
```bash
export AWS_REGION=us-east-1
export CLUSTER_NAME=kushnir-k8s-prod
./scripts/k8s/provision-kubernetes-cluster.sh
```
- [ ] Cluster creation initiated
- [ ] 3 nodes provisioning in progress
- [ ] kubeconfig updated
- [ ] Status: `kubectl get nodes` shows 3 nodes

### Day 2: Verify Infrastructure
```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get storageclass
kubectl get ns
```
- [ ] Cluster API server responsive
- [ ] 3 worker nodes in READY state
- [ ] Storage classes: fast-ssd, standard, efs present
- [ ] Namespaces: production, monitoring, istio-system created

### Day 3: Service Mesh & Monitoring
```bash
kubectl get deployments -n istio-system
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n monitoring svc/grafana 3000:3000
```
- [ ] Istio pods running (istio-ingressgateway, istiod, etc.)
- [ ] Prometheus scraping metrics (targets page)
- [ ] Grafana dashboard accessible (http://localhost:3000)
- [ ] AlertManager configured for PagerDuty/Slack

**EOW1 Validation**: Cluster ready, network verified, monitoring operational

---

## WEEK 2: HELM DEPLOYMENT (May 6-10)

### Day 1-2: Stateless Services
```bash
helm install code-server ./helm/code-server-enterprise \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  -f helm/code-server-enterprise/values.prod.yaml \
  -n production --create-namespace
```
- [ ] Helm release created
- [ ] frontend pods running (2-3 replicas)
- [ ] API pods running (3-5 replicas)
- [ ] reputation-engine, activity-feed, agents running
- [ ] `kubectl get deployments -n production` shows all services

### Day 3: Data Services
```bash
kubectl get statefulsets -n production
kubectl get pvc -n production
```
- [ ] PostgreSQL StatefulSet running (3 replicas)
- [ ] Redis StatefulSet running (1 replica)
- [ ] Redpanda StatefulSet running (3 replicas)
- [ ] All PVCs bound (showing 100Gi, 50Gi sizes)

### Day 4-5: Verification
```bash
kubectl exec -it postgres-0 -n production -- psql -U postgres
redis-cli ping  # (via port-forward)
```
- [ ] PostgreSQL accepting connections
- [ ] Redis responding to PING
- [ ] Database migrations completed
- [ ] Inter-service communication verified

**EOW2 Validation**: All 26 services deployed, health checks passing

---

## WEEK 3: DATA MIGRATION (May 13-17)

### Pre-Migration Backup
```bash
# On Docker Compose host (192.168.168.31)
docker-compose exec postgres-db pg_dump -U $DB_USER $DB_NAME | gzip > backup.sql.gz
docker exec redis-cache redis-cli BGSAVE
# ... complete all service backups
```
- [ ] PostgreSQL backup created and verified
- [ ] Redis snapshot backed up
- [ ] Redpanda topics backed up
- [ ] Qdrant collections exported
- [ ] All backups stored in S3/NAS

### PostgreSQL Migration
```bash
# Restore to K8s
kubectl exec -it postgres-0 -n production -- psql -U postgres < backup.sql
# Verify
kubectl exec -it postgres-0 -n production -- psql -U postgres -c "SELECT COUNT(*) FROM information_schema.tables;"
```
- [ ] Data restored (row count matches)
- [ ] Checksums verified (no corruption)
- [ ] Replication working (3 replicas in sync)
- [ ] Queries responding normally

### Redis & Redpanda Migration
- [ ] Redis keys and TTLs transferred
- [ ] Redpanda topics replicated
- [ ] Consumer groups offsets restored
- [ ] Message ordering verified

### Qdrant Migration
- [ ] Vector collections restored
- [ ] Collection count matches original
- [ ] Vector search accuracy tested (<100ms P95)

### Parallel Deployment Test
- [ ] Docker Compose and K8s running simultaneously
- [ ] Traffic split 50/50 between both
- [ ] Metrics comparison: response times, errors, throughput
- [ ] No data divergence observed

**EOW3 Validation**: Data verified, parallel deployment stable

---

## WEEK 4: TRAFFIC CUTOVER (May 20-24)

### Phase 1: 10% Traffic to K8s (May 20-21)
```bash
# Update Istio VirtualService traffic weight
kubectl patch vs api -p '{"spec":{"http":[{"route":[{"destination":{"host":"api","weight":10}},{"destination":{"host":"docker-compose-api","weight":90}}]}]}}'
```
- [ ] Istio traffic split configured (10/90)
- [ ] Error rate monitored (<1%)
- [ ] Response times within SLA (<100ms P95)
- [ ] Alerts configured for auto-rollback (error rate >5%)
- [ ] Documentation updated with traffic shift

### Phase 2: 50% Traffic to K8s (May 22)
```bash
# Increase K8s weight to 50%
kubectl patch vs api -p '{"spec":{"http":[{"route":[{"destination":{"host":"api","weight":50}},{"destination":{"host":"docker-compose-api","weight":50}}]}]}}'
```
- [ ] Traffic split 50/50 verified
- [ ] Load balanced between both systems
- [ ] Latency distribution similar (P50, P95, P99)
- [ ] Database connection pools healthy
- [ ] Cache hit ratios maintained

### Phase 3: 100% Traffic to K8s (May 23)
```bash
# Complete cutover to K8s
kubectl patch vs api -p '{"spec":{"http":[{"route":[{"destination":{"host":"api","weight":100}}]}]}}'
```
- [ ] All traffic routed to K8s
- [ ] Docker Compose still running (backup, 48h)
- [ ] DNS updated if needed
- [ ] SLA metrics maintained (99.99%)
- [ ] All services responding normally

### Phase 4: Stabilization & Decommission (May 24)
```bash
# After 48 hours of successful operation
docker-compose -f primary_compose_full.yml down
```
- [ ] Continuous monitoring (24-48 hours)
- [ ] No production issues observed
- [ ] All alerts working (test if needed)
- [ ] Docker Compose containers stopped
- [ ] Helm release stability confirmed

**EOW4 Validation**: 100% on K8s, 48h stable, Docker Compose decommissioned

---

## Critical Metrics to Monitor (All Weeks)

| Metric | Threshold | Check Frequency |
|--------|-----------|-----------------|
| API Error Rate | < 0.5% | Every 5 min |
| P95 Latency | < 100ms | Every 5 min |
| Database Connections | < 80% pool | Every 15 min |
| Memory Usage | < 80% | Every 15 min |
| CPU Utilization | < 70% | Every 15 min |
| Pod Restart Count | 0 | Every 15 min |
| PVC Usage | < 80% | Every hour |

## Incident Response Flow

**If error rate >5%**:
```bash
# Automatic rollback trigger
kubectl patch vs api -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-compose-api","weight":100}}]}]}}'
# Escalate to incident commander
# Investigate root cause
# Plan re-attempt after fix
```

**If database connection fails**:
```bash
# Check PostgreSQL StatefulSet
kubectl logs postgres-0 -n production --tail=50
kubectl describe pod postgres-0 -n production
# Verify network policies
kubectl get networkpolicies -n production
```

**If Istio mTLS issues**:
```bash
# Check peer authentication
kubectl get peerauthentication -n production
# Fallback to PERMISSIVE mode temporarily
kubectl patch pa default -n production --type merge -p '{"spec":{"mtls":{"mode":"PERMISSIVE"}}}'
```

---

## Rollback Procedure (Emergency)

```bash
# Step 1: Route traffic back to Docker
kubectl patch vs api -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-compose-api","weight":100}}]}]}}'

# Step 2: Verify Docker services are healthy
docker-compose ps

# Step 3: Stop K8s services (keep for debugging)
kubectl scale deployment api -n production --replicas=0

# Step 4: Restore database to last known good state (if needed)
./scripts/k8s/restore-database-snapshot.sh latest

# Step 5: Notify stakeholders and incident commander
echo "ROLLBACK COMPLETE - Docker Compose restored" | post-to-slack
```

---

## Contacts & Escalation

- **Incident Commander**: [NAME] ([PHONE])
- **Database Team Lead**: [NAME] ([PHONE])
- **SRE On-Call**: PagerDuty (configured)
- **AWS Support**: Enterprise plan (phone/chat)
- **Team Slack**: #kushnir-k8s-migration (pinned checklist)

---

## Documentation References

- Full execution plan: `docs/architecture/Q3-PHASE-4-KUBERNETES-MIGRATION-EXECUTION-PLAN.md`
- Helm values: `helm/code-server-enterprise/values.prod.yaml`
- Provisioning script: `scripts/k8s/provision-kubernetes-cluster.sh`
- Kubernetes runbooks: `docs/runbooks/kubernetes-operations.md`

---

## Post-Migration Checklist (After May 24)

- [ ] All 26 services stable on K8s
- [ ] Prometheus metrics showing 48h+ baseline
- [ ] SLA targets maintained (99.99% uptime)
- [ ] Zero data loss confirmed
- [ ] Team trained on K8s operations
- [ ] Runbooks updated with lessons learned
- [ ] Cost optimization review completed
- [ ] Next phase (Phase 5) planning kickoff

---

**Status**: Ready for May 1 execution  
**Print Date**: April 26, 2026  
**Last Updated**: April 26, 2026  
**Version**: 1.0

```
GOOD LUCK! 🚀
Timeline: 4 weeks | Target: Zero downtime | Goal: 99.99% uptime
```
