#!/bin/bash
################################################################################
# Q3 Phase 4: Phase 1 Infrastructure Preparation Report
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @purpose Comprehensive Phase 1 readiness report and deployment strategy
# @phase Q3 Phase 4 Preparation (Phase 1)
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Source environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"
. "${PROJECT_ROOT}/scripts/_common/_base-config.env"

# Configuration
OUTPUT_DIR="${PROJECT_ROOT}/artifacts/q3-phase4-preparation"
REPORT_FILE="${OUTPUT_DIR}/PHASE1-INFRASTRUCTURE-PREP.md"

mkdir -p "${OUTPUT_DIR}"

################################################################################
# Report Generation
################################################################################

cat > "${REPORT_FILE}" <<'EOF'
# Q3 Phase 4: Phase 1 Infrastructure Preparation Report

**Date**: $(date '+%Y-%m-%d %H:%M:%S')  
**Duration**: May 1-12, 2026 (40-60 hours)  
**Status**: ✅ READY FOR EXECUTION  
**Team**: 4-5 engineers (Infra, Platform, QA)  

---

## Executive Summary

Phase 1 of the Kubernetes migration is **infrastructure provisioning and validation**. This report provides comprehensive guidance for:

1. **Kubernetes Cluster Provisioning** (Primary Host  + Replica )
2. **Infrastructure Prerequisites** (Storage, Networking, Certificate Management)
3. **Monitoring & Observability** (Prometheus, Grafana, Loki)
4. **Helm Chart Deployment** (18 microservices to staging cluster)
5. **Performance Baseline** (Load testing, resource utilization monitoring)

---

## Phase 1 Objectives & Success Criteria

### Primary Objectives

| Objective | Success Criteria | Owner |
|-----------|------------------|-------|
| **Cluster Provisioning** | K8s 1.28+, 3 masters, 8 workers, all Ready | Infra Lead |
| **Storage Ready** | StorageClass created, PV provisioned | Infra Lead |
| **Network Ready** | Ingress controller live at  | Infra Lead |
| **Monitoring Deployed** | Prometheus, Grafana, Loki operational | Platform Eng |
| **Services Running** | All 18 microservices deployed to staging | Platform Eng |
| **Health Checks Passing** | 100% readiness/liveness probes Green | QA Lead |
| **Performance Baseline** | p99 latency < 100ms under light load | QA Lead |
| **Documentation Complete** | Phase 2 runbook ready for launch | All |

### Success Metrics

```
Availability:       99.95%+ during Phase 1
Response Time:      p99 < 100ms (5% tolerance for testing)
CPU Utilization:    20-30% baseline (room for traffic spikes)
Memory Utilization: 40-50% baseline
Pod Success Rate:   100% (zero CrashLoopBackOff)
Deployment Time:    < 5 minutes per Helm install
```

---

## Infrastructure Architecture for Phase 1

### Kubernetes Cluster Topology

```
┌─────────────────────────────────────────────┐
│     Kubernetes Cluster (Managed)            │
├─────────────────────────────────────────────┤
│                                             │
│  Control Plane (3 masters - HA)             │
│  ├── Master-1 ()             │
│  ├── Master-2 ()             │
│  └── Master-3 (floating)                    │
│                                             │
│  Worker Nodes (8 nodes)                    │
│  ├── Worker-1 to Worker-4 (16-core/64GB)  │
│  └── Worker-5 to Worker-8 (16-core/64GB)  │
│                                             │
│  Load Balancer:  (VRRP)    │
│  Ingress Controller: NGINX/Traefik          │
│  ServiceMesh: Istio 1.18+ (optional Phase2) │
│                                             │
│  Storage: NAS  (10Gbps)     │
│  ├── PostgreSQL WAL archiving               │
│  ├── Redis persistence                     │
│  └── Application data volumes              │
└─────────────────────────────────────────────┘
```

### Network Architecture

- **API Endpoint**: kubernetes.default.svc.cluster.local
- **Ingress VRRP**: ${ONPREM_VRRP_VIP}:443 (virtual IP)
- **Service Discovery**: CoreDNS (internal)
- **External DNS**: kushnir.cloud (managed via external provider)
- **Network Policies**: Enabled (enforce pod-to-pod communication rules)

### Storage Architecture

- **StorageClass**: fast-ssd (EBS gp3 in AWS or equivalent)
- **PV Size**: 100Gi (stateful services)
- **PVC Binding**: Dynamic provisioning
- **Backup**: Automated to NAS via rsync/snapshots

---

## Phase 1 Week-by-Week Timeline

### Week 1a: Cluster Provisioning & Validation (May 1-3)

#### Day 1: Infrastructure (May 1)
- **Time**: 4-6 hours
- **Lead**: Infrastructure Lead
- **Tasks**:
  - [ ] Provision K8s cluster (3 control, 8 worker nodes)
  - [ ] Configure kubectl authentication
  - [ ] Verify cluster health: `kubectl cluster-info` + `kubectl get nodes`
  - [ ] Install Helm 3.x on deployment machine
  - [ ] Install kubeval for manifest validation

**Validation Commands**:
```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl top nodes
# Expected: 11 nodes (3 control + 8 worker) in Ready state
```

#### Day 2: Storage & Networking (May 2)
- **Time**: 3-4 hours
- **Lead**: Infrastructure Lead
- **Tasks**:
  - [ ] Create StorageClass (fast-ssd, EBS gp3)
  - [ ] Provision PersistentVolumes (100Gi each)
  - [ ] Deploy Ingress Controller (NGINX at ${ONPREM_VRRP_VIP})
  - [ ] Install cert-manager for TLS
  - [ ] Configure network policies (default deny + allow same-namespace)

**Validation Commands**:
```bash
kubectl get storageclass
kubectl get pv
kubectl get svc -n ingress-nginx
# Expected: ingress-nginx LoadBalancer with EXTERNAL-IP = ${ONPREM_VRRP_VIP}
```

#### Day 3: Monitoring Setup (May 3)
- **Time**: 3-4 hours
- **Lead**: Platform Engineer
- **Tasks**:
  - [ ] Deploy Prometheus (30d retention, 100Gi storage)
  - [ ] Deploy Grafana (connected to Prometheus)
  - [ ] Deploy Loki (centralized logging, 50Gi storage)
  - [ ] Deploy Promtail (log collection on all nodes)
  - [ ] Create initial dashboards (cluster health, node metrics)

**Validation Commands**:
```bash
kubectl get pods -n monitoring
# Expected: prometheus-server, grafana, loki, promtail all Running

# Access dashboards
kubectl port-forward -n monitoring svc/grafana 3000:80
# URL: http://localhost:3000
```

### Week 1b: Service Deployment & Testing (May 4-9)

#### Day 4: Pre-Flight Validation (May 4)
- **Time**: 2-3 hours
- **Lead**: Platform Engineer
- **Tasks**:
  - [ ] Helm chart validation: `helm lint --strict`
  - [ ] Manifest validation: `helm template | kubeval`
  - [ ] Image registry credentials configured
  - [ ] ConfigMaps created for environment variables
  - [ ] Namespace & RBAC ready

#### Day 5: Staging Deployment (May 5)
- **Time**: 4-5 hours
- **Lead**: Platform Engineer + QA
- **Tasks**:
  - [ ] Deploy code-server-enterprise Helm chart to `staging` namespace
  - [ ] Verify all 18 microservices started
  - [ ] Check readiness probes (all Green)
  - [ ] Check liveness probes (all Green)
  - [ ] Test service-to-service communication

**Deployment Command**:
```bash
helm install code-server-enterprise helm/code-server-enterprise/ \
  -n staging \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  --wait --timeout 10m

kubectl get all -n staging
# Expected: All pods Running, all services with ClusterIP
```

#### Days 6-7: Performance Testing & Baseline (May 6-7)
- **Time**: 8-10 hours
- **Lead**: QA Lead
- **Tasks**:
  - [ ] Run k6 load tests (10→50 VUs, 9-minute ramp)
  - [ ] Record baseline metrics (latency, throughput, errors)
  - [ ] Monitor CPU/Memory under load
  - [ ] Document performance baseline report
  - [ ] Verify p99 latency < 100ms target

**Load Test Command**:
```bash
k6 run --vus 50 --duration 5m tests/load/api-tests.js \
  --out json=/tmp/k6-results.json

jq '.metrics' /tmp/k6-results.json
# Expected: http_req_duration p99 < 100ms
```

### Week 1c: Readiness & Handoff (May 8-12)

#### Day 8: Documentation (May 8)
- **Time**: 2-3 hours
- **Lead**: Platform Engineer + Technical Writer
- **Tasks**:
  - [ ] Generate cluster state documentation
  - [ ] Create troubleshooting guide
  - [ ] Document runbook for Phase 2
  - [ ] Create operational procedures
  - [ ] Record video walkthrough (optional)

#### Day 9: Phase 2 Preparation (May 9)
- **Time**: 2-3 hours
- **Lead**: All Team Leads
- **Tasks**:
  - [ ] Review Phase 2 runbook
  - [ ] Prepare deployment strategies (blue-green, canary)
  - [ ] Schedule Phase 2 team kickoff (May 13)
  - [ ] Address any Phase 1 blockers

#### Day 10: Go/No-Go Review (May 12)
- **Time**: 2-3 hours
- **Lead**: Director of Engineering
- **Tasks**:
  - [ ] Final metrics review
  - [ ] Stakeholder approval for Phase 2
  - [ ] Risk assessment
  - [ ] Go/No-Go decision
  - [ ] If GO: Proceed to Phase 2 (May 13)

---

## Resource Allocation

### Team Composition (40-60 hours total)

| Role | Hours | Responsibilities |
|------|-------|-----------------|
| Infrastructure Lead | 30-40 | Cluster provisioning, storage, networking |
| Platform Engineer (x2) | 30-40 | Monitoring, Helm deployment, testing |
| QA Lead | 20-30 | Performance testing, validation, metrics |
| Technical Writer | 10-15 | Documentation, runbooks, procedures |

**Total**: 310 hours across 5 engineers over 2 weeks

### Cluster Resource Allocation

```
Control Plane:
  - 3 master nodes
  - 6 vCPU each = 18 vCPU total
  - 16GB memory each = 48GB total

Worker Nodes:
  - 8 nodes × 16 vCPU = 128 vCPU
  - 8 nodes × 64GB = 512GB
  
System Pods (monitoring, networking):
  - Reserved: ~10% CPU, ~15% Memory

Available for Services:
  - ~115 vCPU, ~435GB RAM
  - 18 microservices with HA replicas (3 per service avg)
  - = ~6.4 vCPU per service, ~24GB per service
```

---

## Risk Assessment & Mitigation

### High-Risk Items

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|-----------|
| **K8s cluster provisioning delay** | Phase delayed by 3-5 days | Medium | Pre-validate infrastructure team capacity |
| **Storage performance insufficient** | High latency, SLA breach | Low | Benchmark NAS throughput before Phase 1 |
| **Network connectivity issues** | Services unreachable, rollback needed | Medium | Pre-validate 10Gbps connectivity to NAS |
| **Data loss during migration** | Critical data loss, recovery delay | Low | Backup procedure tested before Phase 1 |

### Mitigation Strategies

1. **Cluster Provisioning**
   - Pre-provision terraform scripts and validate
   - Have infrastructure team dry-run cluster creation beforehand
   - Scheduled contingency: 3-day buffer in timeline

2. **Storage Performance**
   - Run nas-benchmark-throughput.sh before Phase 1
   - Target: >500 MB/s sustained for PV provisioning
   - Fallback: Use local SSD on nodes if NAS < 300 MB/s

3. **Network Connectivity**
   - Pre-flight validation: `ping -c 10 ${ONPREM_NAS_IP}`
   - Verify 10Gbps link: `ethtool eth0 | grep Speed`
   - Test SMB mount: `mount -t cifs //${ONPREM_NAS_IP}/nas /mnt/nas -o credentials=/tmp/creds`

4. **Data Protection**
   - Backup all data before Phase 1: `kubectl exec postgres-0 -- pg_dump`
   - Store backup in S3: `aws s3 cp backup.sql s3://backups/`
   - Document rollback procedures (10-minute RTO)

---

## Prerequisites Checklist

### Infrastructure Team (Must Complete Before May 1)

- [ ] **Cluster Ready**
  - [ ] K8s cluster provisioned and accessible
  - [ ] 3 control plane nodes operational
  - [ ] 8 worker nodes operational (Ready status)
  - [ ] kubectl configured and authenticated

- [ ] **Network Ready**
  - [ ] ${ONPREM_VRRP_VIP} (VRRP) reserved and assigned
  - [ ] Network security groups configured
  - [ ] Ingress load balancer provisioned
  - [ ] 10Gbps NAS connectivity verified

- [ ] **Storage Ready**
  - [ ] StorageClass defined (fast-ssd or equivalent)
  - [ ] PV provisioning tested (create/destroy test PVC)
  - [ ] NAS accessible at ${ONPREM_NAS_IP}
  - [ ] Backup target prepared (S3 or equivalent)

- [ ] **Tools & Access**
  - [ ] kubectl installed and configured
  - [ ] Helm 3.x installed
  - [ ] kubeval installed
  - [ ] k6 (load testing) installed
  - [ ] ssh access to both hosts (${ONPREM_PRIMARY_IP}, ${ONPREM_REPLICA_IP})

### Platform Team (Must Complete Before May 1)

- [ ] **Images Ready**
  - [ ] All 18 microservice images built
  - [ ] Images pushed to container registry
  - [ ] Image pull secrets created in K8s

- [ ] **Configuration Ready**
  - [ ] Environment variables defined (.env file)
  - [ ] Secrets manager configured (Vault, AWS Secrets Manager)
  - [ ] values.phase4-k8s.yaml updated for target cluster
  - [ ] Helm dependencies resolved

- [ ] **Code Ready**
  - [ ] All microservices ready for K8s deployment
  - [ ] Helm charts syntax validated
  - [ ] Database migrations prepared
  - [ ] Configuration drift checks passed

### QA Team (Must Complete Before May 1)

- [ ] **Test Plans Ready**
  - [ ] Integration test suite prepared
  - [ ] Load test scenarios defined (k6 scripts)
  - [ ] Performance baseline targets documented
  - [ ] Rollback test cases prepared

- [ ] **Monitoring Ready**
  - [ ] Alert rules defined
  - [ ] Dashboard templates prepared
  - [ ] Log search queries documented
  - [ ] SLA metrics defined

---

## Phase 1 Readiness Checklist

### Infrastructure Validation (Before Phase 1 Deployment)

```bash
# 1. Cluster connectivity
kubectl cluster-info

# 2. Node readiness
kubectl get nodes -o wide
# Expected: All nodes Ready, Conditions OK

# 3. Storage availability
kubectl get storageclass
kubectl get pv
# Expected: fast-ssd StorageClass, PVs available

# 4. Network access
ping -c 5 
# Expected: All packets received, no loss

# 5. NAS mount test
mount -t cifs //${ONPREM_NAS_IP}/nas /mnt/nas
# Expected: Successful mount
```

### Pre-Deployment Validation

```bash
# 1. Helm chart validity
helm lint helm/code-server-enterprise/ --strict
# Expected: 0 errors, warnings acceptable

# 2. Manifest correctness
helm template code-server-enterprise helm/code-server-enterprise/ \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml | kubeval
# Expected: All manifests valid

# 3. Image availability
kubectl auth can-i pull images
# Expected: true (proper registry credentials)

# 4. Namespace ready
kubectl create namespace staging
# Expected: Namespace created or already exists
```

---

## Phase 1 Success Metrics

### Infrastructure Metrics

| Metric | Target | Threshold |
|--------|--------|-----------|
| Cluster uptime | 99.95% | > 99.90% |
| Node ready time | < 5 min | < 10 min |
| API server latency | < 100ms | < 200ms |
| etcd latency | < 50ms | < 100ms |

### Service Metrics

| Metric | Target | Threshold |
|--------|--------|-----------|
| Pod startup time | < 30s | < 60s |
| Service ready rate | 100% | > 95% |
| Health probe success | 100% | > 95% |
| Network latency | < 10ms | < 50ms |

### Application Metrics

| Metric | Target | Threshold |
|--------|--------|-----------|
| API p99 latency | < 100ms | < 150ms |
| Error rate | < 0.1% | < 1% |
| Throughput (VUs=50) | 500 req/s | > 250 req/s |
| CPU utilization | 20-30% | < 50% |
| Memory utilization | 40-50% | < 60% |

---

## Communication & Escalation

### Daily Standup
- **Time**: 9:00 AM UTC
- **Duration**: 15 minutes
- **Attendees**: Infra Lead, Platform Lead, QA Lead
- **Agenda**: Blockers, progress, next day plan

### Weekly Review
- **Time**: Friday 4:00 PM UTC
- **Duration**: 30 minutes
- **Attendees**: Full team + stakeholders
- **Agenda**: Status, metrics, risk assessment

### Critical Issues (Escalation)
1. **Issue reported** → Infrastructure Lead (30 min response)
2. **Unresolved after 1 hour** → Platform Lead (1 hour response)
3. **Unresolved after 3 hours** → Director of Engineering (immediate)

---

## Rollback Procedures

### Scenario 1: Failed Helm Deployment
```bash
# Rollback to previous release
helm rollback code-server-enterprise -n staging

# Verify
helm status code-server-enterprise -n staging
kubectl get pods -n staging
```

### Scenario 2: Cluster Issues (Complete Rollback)
```bash
# 1. Delete staging namespace (removes all resources)
kubectl delete namespace staging

# 2. Destroy and recreate cluster
terraform -chdir=terraform/kubernetes destroy
terraform -chdir=terraform/kubernetes apply

# 3. Redeploy from scratch
helm install code-server-enterprise ...
```

### Scenario 3: Data Recovery
```bash
# Restore from backup
aws s3 cp s3://backups/phase1-backup.sql /tmp/

# Restore to database
kubectl exec -it postgres-0 -n staging -- \
  psql -U postgres -d code_server_enterprise -f /tmp/backup.sql
```

---

## Phase 1 → Phase 2 Transition

### Approval Criteria for Phase 2 Launch (May 13)

- ✅ All Phase 1 success metrics met
- ✅ Zero unplanned downtime in Phase 1
- ✅ Performance baseline established and documented
- ✅ Monitoring stack fully operational
- ✅ Phase 2 runbook approved by all leads
- ✅ Team trained on procedures
- ✅ Infrastructure team commits to Phase 2 dates
- ✅ Stakeholder sign-off obtained

### Phase 2 Overview (May 13-26)

**Focus**: Migrate stateless services from Docker Compose to K8s
- Deployment strategies (blue-green, canary)
- Zero-downtime deployment procedures
- Monitoring and alerting for stateless services
- Estimated: 30-40 hours, 2 engineers

---

## Phase 1 Deliverables

### Documentation
- ✅ This Phase 1 Infrastructure Preparation Report
- ✅ Helm Chart Validation Report
- ✅ Phase 1 Deployment Runbook (day-by-day procedures)
- ✅ Troubleshooting Guide
- ✅ Phase 2 Runbook (ready for May 13 kickoff)

### Infrastructure
- ✅ Kubernetes cluster (3 control, 8 worker nodes)
- ✅ Ingress controller at 
- ✅ Storage classes and PersistentVolumes
- ✅ Monitoring stack (Prometheus, Grafana, Loki)
- ✅ Network policies for pod communication

### Services
- ✅ All 18 microservices running in staging K8s
- ✅ Health checks passing (readiness + liveness)
- ✅ Service discovery operational
- ✅ Metrics flowing to Prometheus
- ✅ Logs aggregated in Loki

### Validation
- ✅ Performance baseline established (p99 < 100ms)
- ✅ Load testing completed (50 VU sustained)
- ✅ Resource utilization within acceptable ranges
- ✅ Rollback procedures tested
- ✅ Disaster recovery validated

---

## Next Steps (Action Items for Next Week)

### Infrastructure Team (Before May 1)
1. [ ] Schedule cluster provisioning kickoff (April 26)
2. [ ] Validate Terraform IaC for K8s provisioning
3. [ ] Pre-provision test cluster (non-prod environment)
4. [ ] Validate kubectl configuration
5. [ ] Confirm NAS connectivity (10Gbps, 500+ MB/s throughput)

### Platform Team (Before May 1)
1. [ ] Finalize container images (all 18 services)
2. [ ] Update Helm values for phase4-k8s.yaml
3. [ ] Validate Helm charts (helm lint --strict)
4. [ ] Prepare load test scenarios (k6 scripts)
5. [ ] Create ConfigMaps for environment variables

### QA Team (Before May 1)
1. [ ] Prepare integration test suite
2. [ ] Document performance baselines
3. [ ] Set up monitoring dashboards template
4. [ ] Create issue tracking for Phase 1 blockers
5. [ ] Define alerting thresholds

### All Teams (Before May 1)
1. [ ] Team training on Kubernetes concepts (4 hours)
2. [ ] Review Phase 1 runbook (2 hours)
3. [ ] Schedule daily standup (9:00 AM UTC starting May 1)
4. [ ] Confirm availability for May 1-12

---

## Conclusion

Phase 1 is **infrastructure and validation**. This 2-week sprint (40-60 hours) will:

1. **Provision** production-grade Kubernetes cluster
2. **Validate** all infrastructure prerequisites
3. **Deploy** 18 microservices for staging testing
4. **Establish** performance baseline
5. **Prepare** team for Phase 2 stateless migration

**Status**: ✅ **READY FOR TEAM EXECUTION (May 1)**  
**Next Review**: May 12 (Go/No-Go for Phase 2)  

---

**Report Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Phase 1 Owner**: Infrastructure & Platform Teams  
**Phase 1 Timeline**: May 1-12, 2026  
**Total Effort**: 40-60 hours, 4-5 engineers  

EOF

    echo ""
    echo "✓ Phase 1 Infrastructure Preparation Report generated"
    echo "  Location: ${REPORT_FILE}"
    echo "  Lines: $(wc -l < "${REPORT_FILE}")"
}

cat > "${REPORT_FILE}" <<'EOF'
# Q3 Phase 4: Phase 1 Infrastructure Preparation Report

**Date**: $(date '+%Y-%m-%d %H:%M:%S')  
**Duration**: May 1-12, 2026 (40-60 hours)  
**Status**: ✅ READY FOR EXECUTION  
**Team**: 4-5 engineers (Infra, Platform, QA)  

---

## Executive Summary

Phase 1 of the Kubernetes migration is **infrastructure provisioning and validation**. This report provides comprehensive guidance for:

1. **Kubernetes Cluster Provisioning** (Primary Host  + Replica )
2. **Infrastructure Prerequisites** (Storage, Networking, Certificate Management)
3. **Monitoring & Observability** (Prometheus, Grafana, Loki)
4. **Helm Chart Deployment** (18 microservices to staging cluster)
5. **Performance Baseline** (Load testing, resource utilization monitoring)

---

## Phase 1 Objectives & Success Criteria

### Primary Objectives

| Objective | Success Criteria | Owner |
|-----------|------------------|-------|
| **Cluster Provisioning** | K8s 1.28+, 3 masters, 8 workers, all Ready | Infra Lead |
| **Storage Ready** | StorageClass created, PV provisioned | Infra Lead |
| **Network Ready** | Ingress controller live at  | Infra Lead |
| **Monitoring Deployed** | Prometheus, Grafana, Loki operational | Platform Eng |
| **Services Running** | All 18 microservices deployed to staging | Platform Eng |
| **Health Checks Passing** | 100% readiness/liveness probes Green | QA Lead |
| **Performance Baseline** | p99 latency < 100ms under light load | QA Lead |
| **Documentation Complete** | Phase 2 runbook ready for launch | All |

### Success Metrics

```
Availability:       99.95%+ during Phase 1
Response Time:      p99 < 100ms (5% tolerance for testing)
CPU Utilization:    20-30% baseline (room for traffic spikes)
Memory Utilization: 40-50% baseline
Pod Success Rate:   100% (zero CrashLoopBackOff)
Deployment Time:    < 5 minutes per Helm install
```

---

## Infrastructure Architecture for Phase 1

### Kubernetes Cluster Topology

```
┌─────────────────────────────────────────────┐
│     Kubernetes Cluster (Managed)            │
├─────────────────────────────────────────────┤
│                                             │
│  Control Plane (3 masters - HA)             │
│  ├── Master-1 ()             │
│  ├── Master-2 ()             │
│  └── Master-3 (floating)                    │
│                                             │
│  Worker Nodes (8 nodes)                    │
│  ├── Worker-1 to Worker-4 (16-core/64GB)  │
│  └── Worker-5 to Worker-8 (16-core/64GB)  │
│                                             │
│  Load Balancer:  (VRRP)    │
│  Ingress Controller: NGINX/Traefik          │
│  ServiceMesh: Istio 1.18+ (optional Phase2) │
│                                             │
│  Storage: NAS  (10Gbps)     │
│  ├── PostgreSQL WAL archiving               │
│  ├── Redis persistence                     │
│  └── Application data volumes              │
└─────────────────────────────────────────────┘
```

---

## Phase 1 Week-by-Week Timeline

### Week 1a: Cluster Provisioning & Validation (May 1-3)

**Day 1 (May 1)**: Infrastructure Provisioning (4-6 hours)
- Cluster creation (3 control, 8 worker nodes)
- kubectl configuration and authentication
- Node health verification

**Day 2 (May 2)**: Storage & Networking (3-4 hours)
- StorageClass configuration (fast-ssd)
- Ingress controller deployment (${ONPREM_VRRP_VIP})
- Certificate manager installation

**Day 3 (May 3)**: Monitoring Setup (3-4 hours)
- Prometheus deployment (30d retention, 100Gi)
- Grafana dashboards
- Loki centralized logging

### Week 1b: Service Deployment & Testing (May 4-9)

**Day 4 (May 4)**: Pre-Flight Validation (2-3 hours)
- Helm chart validation and templating
- Image registry credentials
- Namespace and RBAC setup

**Day 5 (May 5)**: Staging Deployment (4-5 hours)
- Deploy 18 microservices to staging K8s
- Verify all services running
- Health checks validation

**Days 6-7 (May 6-7)**: Performance Testing (8-10 hours)
- Load testing with k6 (10→50 VUs)
- Performance baseline establishment
- Resource utilization monitoring

### Week 1c: Readiness & Handoff (May 8-12)

**Day 8 (May 8)**: Documentation (2-3 hours)
- Generate cluster state documentation
- Create troubleshooting guide
- Phase 2 runbook finalization

**Day 9 (May 9)**: Phase 2 Preparation (2-3 hours)
- Review Phase 2 runbook
- Prepare deployment strategies
- Schedule Phase 2 kickoff (May 13)

**Day 10 (May 12)**: Go/No-Go Review (2-3 hours)
- Final metrics review
- Stakeholder approval
- Phase 2 launch decision

---

## Resource Allocation

### Team Composition (40-60 hours total)

| Role | Hours | Responsibilities |
|------|-------|-----------------|
| Infrastructure Lead | 30-40 | Cluster, storage, networking |
| Platform Engineer (x2) | 30-40 | Monitoring, Helm, testing |
| QA Lead | 20-30 | Performance, validation |
| Technical Writer | 10-15 | Documentation |

**Total**: 310 hours across 5 engineers over 2 weeks

---

## Prerequisites Checklist

### Infrastructure Team (Before May 1)

- [ ] Kubernetes cluster provisioned and accessible
- [ ] 3 control plane nodes operational
- [ ] 8 worker nodes operational (Ready status)
- [ ] kubectl configured and authenticated
- [ ] Network security groups configured
- [ ] Ingress load balancer provisioned (${ONPREM_VRRP_VIP})
- [ ] 10Gbps NAS connectivity verified
- [ ] StorageClass defined
- [ ] Helm 3.x, kubeval, k6 installed

### Platform Team (Before May 1)

- [ ] All 18 microservice images built and pushed
- [ ] Image pull secrets created in K8s
- [ ] Environment variables defined (.env file)
- [ ] values.phase4-k8s.yaml updated
- [ ] Helm charts syntax validated
- [ ] Database migrations prepared

### QA Team (Before May 1)

- [ ] Integration test suite prepared
- [ ] Load test scenarios defined (k6 scripts)
- [ ] Performance baseline targets documented
- [ ] Alert rules defined
- [ ] Dashboard templates prepared

---

## Phase 1 Success Metrics

### Infrastructure Metrics

| Metric | Target | Threshold |
|--------|--------|-----------|
| Cluster uptime | 99.95% | > 99.90% |
| Node ready time | < 5 min | < 10 min |
| API server latency | < 100ms | < 200ms |

### Service Metrics

| Metric | Target | Threshold |
|--------|--------|-----------|
| Pod startup time | < 30s | < 60s |
| Service ready rate | 100% | > 95% |
| Health probe success | 100% | > 95% |

### Application Metrics

| Metric | Target | Threshold |
|--------|--------|-----------|
| API p99 latency | < 100ms | < 150ms |
| Error rate | < 0.1% | < 1% |
| Throughput (VUs=50) | 500 req/s | > 250 req/s |
| CPU utilization | 20-30% | < 50% |
| Memory utilization | 40-50% | < 60% |

---

## Risk Assessment & Mitigation

### High-Risk Items

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|-----------|
| **Cluster provisioning delay** | Phase delayed 3-5 days | Medium | Pre-validate capacity |
| **Storage performance insufficient** | High latency, SLA breach | Low | Benchmark NAS before Phase 1 |
| **Network connectivity issues** | Services unreachable | Medium | Pre-validate 10Gbps link |
| **Data loss during migration** | Critical data loss | Low | Backup before Phase 1 |

---

## Rollback Procedures

### Scenario 1: Helm Deployment Failure
```bash
helm rollback code-server-enterprise -n staging
```

### Scenario 2: Complete Cluster Rollback
```bash
kubectl delete namespace staging
terraform destroy && terraform apply
helm install code-server-enterprise ...
```

### Scenario 3: Data Recovery
```bash
aws s3 cp s3://backups/phase1-backup.sql /tmp/
kubectl exec postgres-0 -- psql -f /tmp/backup.sql
```

---

## Phase 1 Deliverables

### Documentation
- ✅ Phase 1 Infrastructure Preparation Report (this document)
- ✅ Helm Chart Validation Report
- ✅ Phase 1 Deployment Runbook (day-by-day procedures)
- ✅ Troubleshooting Guide
- ✅ Phase 2 Runbook (ready for May 13 kickoff)

### Infrastructure
- ✅ Kubernetes cluster (3 control, 8 worker nodes)
- ✅ Ingress controller at 
- ✅ Storage classes and PersistentVolumes
- ✅ Monitoring stack (Prometheus, Grafana, Loki)
- ✅ Network policies for pod communication

### Services
- ✅ All 18 microservices running in staging K8s
- ✅ Health checks passing
- ✅ Service discovery operational
- ✅ Metrics flowing to Prometheus
- ✅ Logs aggregated in Loki

### Validation
- ✅ Performance baseline established
- ✅ Load testing completed
- ✅ Resource utilization acceptable
- ✅ Rollback procedures tested
- ✅ Disaster recovery validated

---

## Next Steps (Action Items for Next Week)

### Infrastructure Team (Before May 1)
1. [ ] Schedule cluster provisioning kickoff
2. [ ] Validate Terraform IaC for K8s
3. [ ] Pre-provision test cluster
4. [ ] Validate kubectl configuration
5. [ ] Confirm NAS connectivity

### Platform Team (Before May 1)
1. [ ] Finalize container images (all 18)
2. [ ] Update Helm values for phase4-k8s.yaml
3. [ ] Validate Helm charts
4. [ ] Prepare load test scenarios
5. [ ] Create ConfigMaps for environment variables

### QA Team (Before May 1)
1. [ ] Prepare integration test suite
2. [ ] Document performance baselines
3. [ ] Set up monitoring dashboards
4. [ ] Create issue tracking
5. [ ] Define alerting thresholds

### All Teams (Before May 1)
1. [ ] Team training on Kubernetes (4 hours)
2. [ ] Review Phase 1 runbook (2 hours)
3. [ ] Schedule daily standup (9:00 AM UTC)
4. [ ] Confirm availability for May 1-12

---

## Conclusion

Phase 1 is **infrastructure provisioning and validation** for the Kubernetes migration. This 2-week sprint (40-60 hours) will:

1. **Provision** production-grade Kubernetes cluster
2. **Validate** all infrastructure prerequisites
3. **Deploy** 18 microservices for staging testing
4. **Establish** performance baseline
5. **Prepare** team for Phase 2 stateless migration

**Status**: ✅ **READY FOR TEAM EXECUTION (May 1)**  
**Next Review**: May 12 (Go/No-Go for Phase 2)  
**Phase 1 Owner**: Infrastructure & Platform Teams  
**Total Effort**: 40-60 hours, 4-5 engineers  

---

**Report Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Last Updated**: April 25, 2026  

EOF

echo "✓ Phase 1 Infrastructure Preparation Report generated"
