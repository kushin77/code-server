#!/usr/bin/env bash
# @governance: Q3 Phase 4 epic generation — create GitHub issue templates at scale
# Purpose: Generate Q3 Phase 4 GitHub Epic #1537 template and related issues
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1539 (Q3 Phase 4)

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly EPIC_TEMPLATE="${EPIC_TEMPLATE:-${REPO_ROOT}/artifacts/EPIC-1537-KUBERNETES-MIGRATION-TEMPLATE.md}"

cat > "${EPIC_TEMPLATE}" << 'EOF'
# Epic #1537: Kubernetes Migration - Q3 2026 Phase 4

**Status**: OPEN (Ready to Launch)  
**Assigned To**: Infrastructure Team  
**Priority**: P0 (High)  
**Estimated Effort**: 310 hours (4-5 engineers, 8 weeks)  
**Start Date**: May 1, 2026  
**Target Completion**: July 31, 2026  

---

## Overview

Migrate kushnir.cloud infrastructure from Docker Compose production deployment to managed Kubernetes cluster (EKS/GKE/AKS) for improved scalability, reliability, and operational efficiency.

### Current State
- ✅ Docker Compose: 20/20 services operational, production-ready
- ✅ Infrastructure as Code: Mature (47+ automation scripts, 100% GOV-002 compliant)
- ✅ Kubernetes Preparation: Complete (Helm charts, Istio templates, HPA policies)
- 🟡 Cluster Provisioning: Awaiting infrastructure team

### Target State
- ✅ Managed Kubernetes cluster: EKS/GKE/AKS
- ✅ All 18 microservices: Running on K8s with HA/failover
- ✅ 99.95% uptime SLA: Achieved with automated deployment
- ✅ Zero-downtime deployment: GitOps-driven via ArgoCD/Flux
- ✅ Backup/restore: Velero for cluster snapshots + PostgreSQL WAL archiving

---

## Sub-Tasks & Timeline

### Phase 1: Kubernetes Cluster Provisioning (Week 1-2, 40-60 hours)

**Dependencies**: Infrastructure team resource allocation

**Tasks**:
- [ ] Provision managed K8s cluster (EKS/GKE/AKS)
  - 3 control-plane nodes, 6 worker nodes (t3.xlarge minimum)
  - 100GB+ free storage per node
  - 3 availability zones for HA
  
- [ ] Configure networking
  - VPC: CIDR 10.0.0.0/16
  - Subnets: 3 AZs
  - Security groups: Ingress 443/80, egress all
  - NAS access: NFS mount persistence
  
- [ ] Set up ingress controller
  - Deploy Nginx or Istio ingress
  - TLS termination with certificates
  - DNS routing to ingress endpoints
  
- [ ] Deploy monitoring stack
  - Prometheus for metrics collection
  - Grafana for visualization
  - Loki for log aggregation

- [ ] Establish GitOps
  - Deploy ArgoCD or Flux
  - Connect kubernetes branch for auto-sync
  - Slack notifications for deployments

**Success Criteria**:
- kubectl get nodes: All nodes ready
- Storage provisioning: Working via CSI
- Ingress routing: Verified for health checks

---

### Phase 2: Stateless Services Migration (Week 3-4, 30-40 hours)

**Dependencies**: Phase 1 complete

**Microservices** (8 stateless services):
- auth-server, control-plane, event-bus
- reputation-engine, activity-feed, memory-engine
- (3 additional stateless services)

**Tasks**:
- [ ] Deploy 8 stateless microservices via Helm
  ```bash
  helm install auth-server helm/auth-server/ -n production
  helm install control-plane helm/control-plane/ -n production
  # ... (repeat for all 8)
  ```

- [ ] Deploy Istio service mesh
  - VirtualServices for traffic routing
  - DestinationRules for circuit breakers
  - PeerAuthentication for mTLS

- [ ] Validate inter-service communication
  - Health checks passing
  - Metrics collection working
  - Logs aggregating to Loki

- [ ] Implement blue-green deployment
  - Run Docker Compose + K8s in parallel
  - Traffic migration: 10% → 50% → 100% to K8s
  - Monitoring for errors and latency

- [ ] Test rollback procedures
  - Revert traffic to Docker Compose
  - Verify zero data loss
  - Document rollback procedures

**Success Criteria**:
- All 8 services: Running with 2+ replicas
- Health checks: 100% passing
- Latency: < 100ms p99 (baseline comparison)
- Error rate: < 0.1%

---

### Phase 3: Stateful Services Migration (Week 5-6, 40-50 hours)

**Dependencies**: Phase 2 complete

**Stateful Services** (10 data services):
- PostgreSQL (primary database)
- Redis (cache + session store)
- Kafka/Redpanda (event streaming)
- (7 additional stateful services)

**Tasks**:
- [ ] Create StatefulSets for data services
  ```bash
  helm install postgresql helm/postgresql/ -n production --values postgresql-values.yaml
  helm install redis helm/redis/ -n production
  helm install kafka helm/kafka/ -n production
  ```

- [ ] Migrate data from Docker volumes
  - PostgreSQL: pg_dump → K8s PostgreSQL operator
  - Redis: AOF dump → K8s Redis StatefulSet
  - Kafka: Topic replication across clusters
  
- [ ] Configure persistent volume management
  - StorageClass: EBS/GCP persistent disks
  - PersistentVolumeClaims: One per data service
  - Backup snapshots: Daily via Velero

- [ ] Establish replication and failover
  - PostgreSQL streaming replication
  - Redis Sentinel for failover
  - Kafka cluster replication factor: 3

- [ ] Test disaster recovery
  - Simulate pod failures: Services auto-recover
  - Simulate node failures: Workloads reschedule
  - Full cluster failure: Restore from Velero backup

**Success Criteria**:
- All 10 services: Running with high availability
- Data consistency: Verified across all services
- RTO (Recovery Time Objective): < 5 minutes
- RPO (Recovery Point Objective): < 1 minute
- Backup: Daily snapshots retained 30 days

---

### Phase 4: Production Cutover & Optimization (Week 7-8, 20-30 hours)

**Dependencies**: Phase 3 complete and validated

**Tasks**:
- [ ] Switch production DNS to K8s ingress
  - Update APEX_DOMAIN routing
  - Verify all domains resolving
  - Monitor for connectivity issues

- [ ] Retire Docker Compose services
  - Backup final Docker volumes
  - Document legacy configuration
  - Archive docker-compose files

- [ ] Decommission old infrastructure
  - Release Docker host resources
  - Archive monitoring data
  - Update documentation

- [ ] Performance validation
  - Baseline metrics vs Docker Compose
  - Latency: Should match or improve
  - Throughput: Should match or improve
  - Availability: Monitor 99.95% SLA

- [ ] Team training completion
  - Operations team: K8s cluster operations
  - Development team: Deployment procedures
  - Infrastructure team: Disaster recovery

**Success Criteria**:
- 99.95% uptime maintained
- All 18 services: Fully migrated
- Zero data loss: Verified
- Team trained: Ready for independent operations

---

## Resource Allocation

### Team Composition (4-5 Engineers)

**SRE/Ops Lead** (60 hours)
- Cluster provisioning and networking
- GitOps setup (ArgoCD/Flux)
- Backup/restore automation
- On-call support during migration

**Platform Engineer** (80 hours)
- Helm chart deployment
- Service mesh (Istio) configuration
- Performance optimization
- Documentation

**Backend Engineer** (70 hours)
- Service migration coordination
- Data migration validation
- Health check procedures
- Integration testing

**QA/Test Engineer** (60 hours)
- Load testing (k6)
- Chaos engineering (network partition, pod failure)
- Recovery testing
- SLA validation

**DevOps Support** (40 hours)
- Runbook preparation
- Team training
- Monitoring setup
- Documentation

**Total**: 310 hours across 4-5 engineers

---

## Risk Assessment

### High-Risk Areas

**1. Data Persistence (HIGH)**
- **Risk**: Data loss during migration
- **Mitigation**: Full backup before each phase, checksum validation
- **Rollback**: Restore from Docker Compose backup

**2. Service Interdependencies (HIGH)**
- **Risk**: Startup order issues, cascading failures
- **Mitigation**: Pre-flight dependency checks, gradual traffic migration
- **Rollback**: Blue-green deployment for immediate revert

**3. Network Latency (MEDIUM)**
- **Risk**: Service mesh adds 5-10ms latency
- **Mitigation**: Performance baseline established, SLA monitoring
- **Rollback**: Bypass Istio for performance-critical paths

**4. Configuration Drift (MEDIUM)**
- **Risk**: Manual changes break reproducibility
- **Mitigation**: GitOps enforcement, automated reconciliation
- **Rollback**: Redeploy from version control

### Testing Strategy

**Pre-Cutover** (all phases):
```bash
# Load testing
bash scripts/ops/load-test-kubernetes.sh --replicas 5 --duration 300s

# Chaos engineering
bash scripts/ops/chaos-test-kubernetes.sh --scenarios network-partition,pod-failure,node-drain

# Recovery validation
bash scripts/ops/disaster-recovery-test.sh --type full-cluster-failure
```

**Production** (Phase 2-4):
- Canary deployments: 5% → 25% → 50% → 100%
- Automated rollback if error rate > 0.1%
- Gradual traffic migration with continuous monitoring

---

## Success Metrics

### Performance KPIs
- **Latency (p99)**: < 100ms (vs Docker Compose baseline)
- **Throughput**: 5,000+ requests/second
- **Availability**: 99.95% uptime
- **Recovery Time**: RTO < 5 minutes, RPO < 1 minute

### Operational KPIs
- **Deployment frequency**: On-demand (GitOps)
- **Lead time for changes**: < 5 minutes
- **Mean time to recovery**: < 10 minutes
- **Change failure rate**: < 5%

### Cost KPIs
- **Infrastructure cost**: 30-40% reduction vs Docker Compose
- **Operational overhead**: 50% reduction (automation)
- **Developer productivity**: 60% faster deployments

---

## Pre-Requisites

### Infrastructure Team
- [ ] Allocate 60 hours for cluster provisioning
- [ ] Provision K8s cluster (EKS/GKE/AKS)
- [ ] Configure networking (VPC, subnets, security groups)
- [ ] Set up GitOps (ArgoCD or Flux)

### Development Team
- [ ] Validate all Helm charts locally (20 hours)
- [ ] Prepare migration procedures (10 hours)
- [ ] Create rollback procedures (10 hours)
- [ ] Test recovery from failures (10 hours)

### Operations Team
- [ ] Set up monitoring stack (15 hours)
- [ ] Configure backup/restore (15 hours)
- [ ] Document runbooks (10 hours)
- [ ] Train team on new procedures (10 hours)

---

## Blocking Issues

None identified. Epic is ready to launch upon infrastructure team confirmation.

---

## Documentation References

- **Q2 Completion Audit**: `artifacts/Q2-COMPLETION-AUDIT.md`
- **Q3 Phase 4 Init Report**: `artifacts/q3-phase4-kubernetes-init/Q3-PHASE4-KUBERNETES-INIT-2026-04-25.md`
- **Kubernetes Migration Plan**: `docs/architecture/kubernetes-migration.md`
- **Helm Charts**: `helm/*/README.md` (20+ services)
- **Istio Configuration**: `istio/` (VirtualServices, DestinationRules, PeerAuthentication)
- **Operations Scripts**: `scripts/operations/kubernetes-*.sh`

---

## Approval & Sign-Off

**Prepared By**: Autonomous Infrastructure Agent  
**Date**: April 26, 2026  
**Status**: ✅ READY FOR LAUNCH  

**Requires Approval From**:
- [ ] Infrastructure Team Lead: Cluster provisioning commitment
- [ ] Development Team Lead: Resource allocation (3 engineers, 170 hours)
- [ ] Operations Team Lead: Operational readiness confirmation

---

**Next Epic**: #1538 (Service Mesh Enhancement - Post-migration optimization)  
**Expected Completion**: July 31, 2026  
**Team Capacity After**: 40% (120 hours) for concurrent work on P3 features and operational support

EOF

echo "✅ GitHub Epic #1537 Template Generated"
echo "📋 File: ${EPIC_TEMPLATE}"
echo ""
echo "Next Steps:"
echo "1. Review template in artifacts/"
echo "2. Create GitHub issue #1537 with this content"
echo "3. Assign to Infrastructure Team Lead"
echo "4. Schedule project kickoff meeting"
echo "5. Allocate team resources"
