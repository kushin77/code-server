#!/bin/bash
# @file scripts/k8s/TRAFFIC-MIGRATION-STRATEGY.md
# @description Traffic migration strategies from Docker Compose to Kubernetes
# @governance GOV-002: Zero-downtime deployment procedures

# Phase 4: Traffic Migration Strategy

## Overview

This document outlines three strategies for migrating traffic from Docker Compose (old environment) to Kubernetes (new environment) with minimal disruption.

**Choice Summary**:
- **Blue-Green**: Safest, requires 2x infrastructure temporarily
- **Canary**: Risk-managed, gradual rollout, uses Istio
- **DNS Switchover**: Fastest, least control, external traffic only

## Strategy 1: Blue-Green Deployment (Recommended)

### Best For
- Critical production services
- When maximum safety is priority
- Full rollback capability needed
- Team prefers immediate all-or-nothing switch

### Timeline
- Phase 1: Setup (1 day) - Prepare new K8s environment
- Phase 2: Deploy Green (1 day) - Deploy to K8s alongside Docker
- Phase 3: Validate (1-2 days) - Full testing and monitoring
- Phase 4: Switchover (1 hour) - Update ingress/load balancer
- Phase 5: Monitor (1 week) - Validate stability before decommission

### Implementation

#### Step 1: Label Environments
```bash
# Docker Compose environment (BLUE)
export ENVIRONMENT=blue
export DEPLOYMENT_ID=docker-compose-$(date +%Y%m%d)

# Kubernetes environment (GREEN)
export ENVIRONMENT=green
export DEPLOYMENT_ID=k8s-$(date +%Y%m%d)
```

#### Step 2: Deploy to Kubernetes (GREEN)
```bash
# Create separate ingress for K8s testing
kubectl create namespace code-server-enterprise-green

helm install code-server-enterprise-green ./helm/code-server-enterprise \
  --namespace code-server-enterprise-green \
  --values helm/code-server-enterprise/values-green.yaml \
  --wait

# Assign different domain for testing
# api-green.example.com -> K8s ingress
# api-blue.example.com  -> Docker Compose ingress (via Nginx proxy)
```

#### Step 3: Run Full Validation
```bash
# Health checks
curl -s https://api-green.example.com/health | jq .

# Smoke tests
./scripts/k8s/validate-deployment.sh code-server-enterprise-green

# Load testing
ab -n 10000 -c 100 https://api-green.example.com/api/tasks

# Chaos testing
kubectl patch vs api-green -n code-server-enterprise-green \
  -p '{"spec":{"http":[{"fault":{"abort":{"percentage":10}}}]}}'
# Monitor error rate - should spike then recover
```

#### Step 4: Switchover (The Critical Moment)

**Option A: DNS Switchover (Fastest)**
```bash
# Update DNS to point to K8s ingress
aws route53 change-resource-record-sets \
  --hosted-zone-id Z... \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "TTL": 60,
        "AliasTarget": {
          "HostedZoneId": "K8S_INGRESS_ZONE_ID",
          "DNSName": "k8s-ingress.elb.amazonaws.com",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'

# Monitor traffic shift
# Expected: DNS TTL (60s) → all traffic to K8s within 2-3 minutes
```

**Option B: Load Balancer Switchover (More control)**
```bash
# Update AWS NLB/ALB target group
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn arn:aws:elasticloadbalancing:... \
  --attributes Key=stickiness.type,Value=source_ip

# Change target group to K8s ingress (via service endpoint)
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --targets Id=k8s-nlb-endpoint

# Drain connections from Docker Compose
aws elbv2 deregister-targets \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --targets Id=docker-nlb-endpoint
```

#### Step 5: Monitor (Critical - First 24 hours)
```bash
# Continuous monitoring dashboard
kubectl port-forward -n monitoring svc/grafana 3000:80
# Dashboard: "Kubernetes Cluster" + "Istio Mesh"

# Watch error rates
watch 'kubectl top pods -n code-server-enterprise-green'

# Check application metrics
curl https://api.example.com/metrics | grep "request_total"

# Check for unusual patterns
kubectl logs -f -n code-server-enterprise-green deploy/api | jq '.level'

# If issues detected: instant rollback
# Update DNS back to api-blue.example.com or reverse load balancer change
```

#### Step 6: Cleanup
```bash
# After 1 week of stable operation:
# 1. Verify no traffic to Docker Compose
curl -v https://api-blue.example.com/health  # Should show no traffic

# 2. Backup Docker Compose data
docker-compose -f docker-compose.yml exec postgres pg_dump app > backup.sql

# 3. Stop Docker services
docker-compose down -v

# 4. Delete BLUE infrastructure
docker system prune -a --volumes

# 5. Remove green namespace suffix
kubectl delete namespace code-server-enterprise-green
```

---

## Strategy 2: Canary Deployment (Gradual)

### Best For
- Incremental risk reduction
- Monitoring new environment behavior first
- A/B testing capability
- Team comfort with advanced traffic management

### Timeline
- Phase 1: Deploy K8s (1 day) - Deploy alongside Docker, 5% traffic
- Phase 2: Monitor (2-3 days) - Validate health metrics
- Phase 3: Gradual Increase (2-3 days) - 5% → 25% → 50% → 100%
- Phase 4: Stabilization (1 week) - Monitor for anomalies
- Phase 5: Decommission (1 day) - Remove Docker Compose

### Implementation

#### Step 1: Deploy to Kubernetes (Initial 0% Traffic)
```bash
kubectl create namespace code-server-enterprise-canary

helm install code-server-enterprise-canary ./helm/code-server-enterprise \
  --namespace code-server-enterprise-canary \
  --set replicas.api=1 \
  --values helm/code-server-enterprise/values-canary.yaml \
  --wait
```

#### Step 2: Setup Istio Traffic Splitting
```bash
# Create VirtualService with canary routing
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-canary
  namespace: code-server-enterprise
spec:
  hosts:
  - api.example.com
  http:
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: api-docker.default.svc.cluster.local
        port:
          number: 3100
      weight: 95
    - destination:
        host: api.code-server-enterprise-canary.svc.cluster.local
        port:
          number: 3100
      weight: 5  # Start with 5% to K8s
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
EOF
```

#### Step 3: Monitor Initial Traffic (5%)
```bash
# Watch Istio metrics
kubectl port-forward -n monitoring svc/grafana 3000:80

# Dashboard: "Istio" → "Mesh" → Monitor error rates

# Specific metrics:
# - request_total{destination_service="api-canary"}
# - request_duration_milliseconds_bucket{destination_service="api-canary"}
# - request_total{response_code=~"5.."}

# Set alert thresholds
# If error rate > 1% for 5 minutes → rollback to 0%
# If latency p99 > 500ms → investigate
```

#### Step 4: Gradual Traffic Increase

**Day 1: 5% → 25%**
```bash
kubectl patch vs api-canary -n code-server-enterprise --type merge \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"api-docker"},"weight":75},{"destination":{"host":"api-canary"},"weight":25}]}]}}'

# Monitor for 24 hours
# Metrics look good? Continue to next step
```

**Day 2: 25% → 50%**
```bash
kubectl patch vs api-canary -n code-server-enterprise --type merge \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"api-docker"},"weight":50},{"destination":{"host":"api-canary"},"weight":50}]}]}}'

# Monitor for 24 hours
```

**Day 3: 50% → 100%**
```bash
kubectl patch vs api-canary -n code-server-enterprise --type merge \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"api-canary"},"weight":100}]}]}}'

# Monitor for 48 hours (weekend safety window)
```

#### Step 5: Cleanup
```bash
# After 1 week stable at 100% traffic:

# 1. Remove canary label
kubectl delete virtualservice api-canary -n code-server-enterprise

# 2. Stop Docker services
docker-compose down -v

# 3. Delete canary namespace
kubectl delete namespace code-server-enterprise-canary
```

### Rollback (If Issues Detected)
```bash
# Instant rollback to Docker Compose
kubectl patch vs api-canary -n code-server-enterprise --type merge \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"api-docker"},"weight":100}]}]}}'

# Alternative: Scale down K8s pods
kubectl scale deployment/api -n code-server-enterprise-canary --replicas=0

# Investigate issue, then retry canary process
```

---

## Strategy 3: DNS Switchover (Fastest)

### Best For
- External traffic only (public-facing services)
- Parallel environment validation already complete
- Need fastest cutover time
- Internal services can use blue-green/canary

### Timeline
- Phase 1: Deploy & Validate (1-2 days) - K8s fully operational
- Phase 2: Execute Switchover (15 minutes) - Update DNS TTL, then DNS record
- Phase 3: Monitor (1-7 days) - Validate all users switched

### Implementation

#### Step 1: Pre-Switchover Validation
```bash
# Ensure both environments fully operational
# BLUE (Docker): api-blue.example.com → working
# GREEN (K8s):   api-green.example.com → working

curl -s https://api-blue.example.com/health | jq .
curl -s https://api-green.example.com/health | jq .

# Load testing both
ab -n 1000 -c 50 https://api-blue.example.com/api/tasks
ab -n 1000 -c 50 https://api-green.example.com/api/tasks

# Performance must be equivalent
```

#### Step 2: Lower DNS TTL (Pre-switchover, 1 hour before)
```bash
# Set TTL to 60 seconds for fast propagation
aws route53 change-resource-record-sets \
  --hosted-zone-id Z... \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{"Value": "BLUE_IP_ADDRESS"}]
      }
    }]
  }'

# Wait 1 hour for TTL to propagate globally
```

#### Step 3: Execute Switchover
```bash
# Update DNS to point to K8s
aws route53 change-resource-record-sets \
  --hosted-zone-id Z... \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "TTL": 60,
        "AliasTarget": {
          "HostedZoneId": "K8S_INGRESS_ZONE",
          "DNSName": "k8s-ingress-abc.elb.amazonaws.com",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'

# Expected traffic shift timeline:
# - DNS recursive resolvers: 0-60 seconds
# - ISP caches: 1-5 minutes
# - Client DNS caches: 1-10 minutes
# - 99% traffic switched: ~5-10 minutes
```

#### Step 4: Monitor Traffic Shift
```bash
# Watch real-time logs
# Query: destination_service=api-green (should increase to 100%)

# Metrics to watch:
# 1. Request rate: sum(rate(request_total{destination_service=~"api.*"}[1m]))
# 2. Error rate: sum(rate(request_total{destination_service="api-green",status=~"5.."}[1m]))
# 3. Latency: histogram_quantile(0.99, request_duration)

# If issues: instant rollback
aws route53 change-resource-record-sets \
  --hosted-zone-id Z... \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{"Value": "BLUE_IP_ADDRESS"}]
      }
    }]
  }'
```

#### Step 5: Stabilization & Cleanup
```bash
# After 24 hours with no issues:

# 1. Keep DNS TTL at 60s for 1 more week
# 2. Monitor daily metrics

# After 1 week:
# 1. Restore DNS TTL to 300s
# 2. Decommission Docker Compose
# 3. Archive backup data
```

---

## Decision Matrix

| Factor | Blue-Green | Canary | DNS |
|--------|-----------|--------|-----|
| Safety | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| Speed | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Cost | ⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Complexity | ⭐⭐ | ⭐⭐⭐⭐ | ⭐ |
| Rollback time | < 5 min | < 1 min | < 5 min |
| Infrastructure overhead | 2x during migration | 1.3x | None |
| External traffic only | ❌ | ✅ | ✅ |
| Internal service migration | ✅ | ✅ | ❌ |

## Recommended Sequence

**For mixed internal + external services:**

1. **Week 1-2**: Use Blue-Green for critical internal services
   - Paperclip Control Plane, Reputation Engine, Scheduler
   
2. **Week 2-3**: Use Canary for less critical services
   - Frontend, Activity Feed, Knowledge Graph
   
3. **Week 3-4**: Use DNS Switchover for public-facing API
   - External API Gateway, IDE service

---

## Monitoring During Migration

### Key Metrics to Watch
```
- Request rate by destination service
- Error rate by destination service (alert if > 0.1%)
- Latency p99 by destination service (alert if > 200ms)
- Pod restart count (alert if > 0)
- PVC usage (alert if > 80%)
- Network I/O saturation (alert if > 70%)
```

### Grafana Dashboard
Create dashboard with:
- Traffic distribution (Docker vs K8s)
- Error rates (trending, alerting)
- Latency comparison
- Resource utilization

### Rollback Decision Criteria
- Error rate > 1% sustained for 5 minutes
- Latency p99 > 500ms sustained for 5 minutes
- Data corruption or loss detected
- Security incident detected
- Customer complaints > baseline
- Pod crashes or persistent failures

---

## Success Criteria

✅ Migration successful if:
- 100% traffic on K8s for 7 days
- Error rate < 0.1% (same as baseline)
- Latency p99 within 5% of baseline
- Zero data loss or corruption
- All team members trained
- Runbooks updated and validated
- Disaster recovery tested

---

**Document Status**: Ready for Production  
**Last Updated**: April 2026  
**Governance**: GOV-002: Enterprise Standards
