# Incident Response Policy - Code-Server Enterprise
**Version:** 1.0  
**Status:** ✅ DRAFT - Phase 7.1 Implementation  
**Created:** April 26, 2026  
**Governance:** GOV-002 Compliant (Immutable procedures, idempotent recovery)  

---

## 1. Incident Response Framework

### 1.1 Incident Classification

**Severity Levels (IaC-Enforced Response):**

```yaml
# scripts/ci/incident-classification.sh (immutable logic)
SEVERITY_LEVELS:
  CRITICAL:
    Description: "Service completely unavailable, data at risk, active attack"
    Response_Time: "5 minutes"
    Escalation: "Immediate to all stakeholders"
    Example: "Complete cluster failure, ransomware detected"
    
  HIGH:
    Description: "Partial service degradation, potential data exposure"
    Response_Time: "15 minutes"
    Escalation: "Manager + Security Lead"
    Example: "Authentication system offline, suspicious activity detected"
    
  MEDIUM:
    Description: "Minor service impact, no data at risk, resolved easily"
    Response_Time: "1 hour"
    Escalation: "Team Lead"
    Example: "Memory leak causing periodic restarts, CVE in optional dependency"
    
  LOW:
    Description: "No immediate impact, can be resolved in planned maintenance"
    Response_Time: "24 hours"
    Escalation: "Ticket only"
    Example: "Documentation error, unused service update available"
```

### 1.2 Detection & Alerting (Automated, Immutable)

**Alert Sources (IaC-Configured):**

```yaml
# helm/values.alerting.yaml (immutable configuration)
alerting:
  prometheus:
    rules:
      - name: PodCrashLoop
        severity: CRITICAL
        condition: |
          increase(kubernetes_pod_container_status_restarts_total[5m]) > 5
        action: 
          - trigger_incident(CRITICAL)
          - notify(#critical-alerts)
          - page_oncall()
      
      - name: HighErrorRate
        severity: HIGH
        condition: |
          (sum(rate(http_requests_total{status=~"5.."}[5m])) / 
           sum(rate(http_requests_total[5m]))) > 0.05
        action:
          - trigger_incident(HIGH)
          - notify(#high-alerts)
          
      - name: UnauthorizedAccess
        severity: HIGH
        condition: |
          increase(oauth2_unauthorized_requests_total[1m]) > 10
        action:
          - trigger_incident(HIGH)
          - enable_extra_logging()
          - notify(#security-alerts)
      
      - name: DataExfiltration
        severity: CRITICAL
        condition: |
          increase(database_export_queries_total[1m]) > 0
        action:
          - trigger_incident(CRITICAL)
          - isolate_database_network()
          - notify(#security-incidents)
          - enable_audit_logging()
```

---

## 2. Incident Response Procedures (IaC-Automated)

### 2.1 Preparation Phase

**Pre-Incident Readiness (Immutable Checklist):**

```bash
#!/bin/bash
# scripts/ops/incident-response-prepare.sh (idempotent pre-flight check)
set -euo pipefail

echo "=== Incident Response Readiness Check ==="

# 1. Verify on-call schedule
echo "✓ On-call schedule:"
kubectl get configmap on-call-schedule -o yaml | grep "current:"

# 2. Verify backup integrity
echo "✓ Backup validation:"
bash scripts/phase7/backup-and-restore-automation.sh --verify
[ $? -eq 0 ] && echo "  Backups healthy" || exit 1

# 3. Verify incident response tools
echo "✓ Tools available:"
command -v kubectl > /dev/null && echo "  kubectl: ✓"
command -v docker > /dev/null && echo "  docker: ✓"
command -v git > /dev/null && echo "  git: ✓"

# 4. Verify vault access
echo "✓ Vault access:"
vault status > /dev/null 2>&1 && echo "  Vault: ✓" || exit 1

# 5. Verify communication channels
echo "✓ Communication:"
curl -s https://hooks.slack.com/services/... -X POST \
  -d '{"text":"Incident Response Test"}' && echo "  Slack: ✓" || exit 1

echo ""
echo "✅ All systems ready for incident response"
```

### 2.2 Detection & Triage Phase

**Automated Incident Creation (Idempotent):**

```bash
#!/bin/bash
# scripts/ops/incident-response-triage.sh (immutable workflow)
set -euo pipefail

ALERT_LEVEL="${1:-MEDIUM}"  # From alerting system
INCIDENT_ID="INC-$(date +%Y%m%d-%H%M%S)"
INCIDENT_DIR="/var/log/incidents/${INCIDENT_ID}"

# Create immutable incident record
mkdir -p "${INCIDENT_DIR}"
cat > "${INCIDENT_DIR}/metadata.json" << EOF
{
  "incident_id": "${INCIDENT_ID}",
  "severity": "${ALERT_LEVEL}",
  "detected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "detector": "$(hostname)",
  "status": "TRIAGING"
}
EOF

# Capture immutable snapshot
echo "Capturing system state snapshot..."
kubectl get all -o yaml > "${INCIDENT_DIR}/k8s-snapshot.yaml"
docker ps -a > "${INCIDENT_DIR}/docker-snapshot.txt"
git log --oneline -20 > "${INCIDENT_DIR}/git-snapshot.txt"
dmesg | tail -100 > "${INCIDENT_DIR}/kernel-snapshot.txt"

# Determine incident type (rules engine)
INCIDENT_TYPE=$(determine_incident_type "${ALERT_LEVEL}")
echo "${INCIDENT_TYPE}" > "${INCIDENT_DIR}/type.txt"

# Notify team (immutable audit trail)
notify_incident_team "${INCIDENT_ID}" "${INCIDENT_TYPE}" "${ALERT_LEVEL}"

# Escalate if CRITICAL
if [[ "${ALERT_LEVEL}" == "CRITICAL" ]]; then
  # Activate incident commander
  page_incident_commander "${INCIDENT_ID}"
  
  # Enable enhanced logging (immutable audit)
  kubectl set env deployment/auth-server \
    AUDIT_LOG_LEVEL=TRACE \
    --record
  
  # Begin incident war room
  create_incident_channel "${INCIDENT_ID}"
fi

echo "✅ Incident ${INCIDENT_ID} created and triaged"
```

### 2.3 Investigation Phase (Non-Destructive, Immutable)

**Log Collection & Analysis:**

```bash
#!/bin/bash
# scripts/ops/incident-response-investigate.sh (immutable data collection)
set -euo pipefail

INCIDENT_ID="${1}"
INCIDENT_DIR="/var/log/incidents/${INCIDENT_ID}"

echo "=== Investigation Phase ==="

# 1. Collect application logs (non-destructive)
echo "Collecting application logs..."
kubectl logs --namespace code-server \
  --selector app=auth-server \
  --all-containers \
  --tail=10000 \
  --timestamps=true > "${INCIDENT_DIR}/app-logs.txt"

# 2. Collect audit logs (immutable record)
echo "Collecting audit logs..."
kubectl get events --namespace code-server \
  --sort-by='.lastTimestamp' > "${INCIDENT_DIR}/k8s-events.txt"

# 3. Collect security logs (immutable)
echo "Collecting security logs..."
curl -s -H "Authorization: Bearer ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/sys/audit" > "${INCIDENT_DIR}/vault-audit.json"

# 4. Analyze for indicators of compromise (IOC)
echo "Analyzing for indicators of compromise..."
grep -i "unauthorized\|denied\|failed\|error" \
  "${INCIDENT_DIR}/app-logs.txt" > "${INCIDENT_DIR}/error-analysis.txt" || true

# 5. Check for data exfiltration
echo "Checking for exfiltration attempts..."
grep -E "SELECT.*FROM.*users|export.*database|dump.*data" \
  "${INCIDENT_DIR}/app-logs.txt" > "${INCIDENT_DIR}/exfil-check.txt" || true

# 6. Timeline reconstruction (immutable)
echo "Building incident timeline..."
cat > "${INCIDENT_DIR}/timeline.md" << 'EOF'
# Incident Timeline

## Events (Ordered by Timestamp)
EOF

# Parse logs in chronological order
sort -t' ' -k1 "${INCIDENT_DIR}/app-logs.txt" | \
  awk '{print "- " $0}' >> "${INCIDENT_DIR}/timeline.md"

echo "✅ Investigation complete - results in ${INCIDENT_DIR}"
```

### 2.4 Containment & Isolation Phase (Idempotent)

**Network Isolation (Immutable, Can Revert):**

```bash
#!/bin/bash
# scripts/ops/incident-response-isolate.sh (idempotent isolation)
set -euo pipefail

INCIDENT_ID="${1}"
INCIDENT_DIR="/var/log/incidents/${INCIDENT_ID}"
AFFECTED_DEPLOYMENT="${2:-affected-service}"

echo "=== Containment Phase ==="

# 1. Isolate compromised pod (idempotent - safe to run multiple times)
echo "Isolating compromised deployment..."
kubectl patch netpol default \
  --type merge \
  -p '{"spec":{"podSelector":{"matchLabels":{"deployment":"'"${AFFECTED_DEPLOYMENT}"'"}},"policyTypes":["Ingress","Egress"],"ingress":[],"egress":[]}}' \
  --record

# Record isolation action
echo "isolation_action: kubectl netpol patch $(date)" >> "${INCIDENT_DIR}/metadata.json"

# 2. Enable traffic logging (immutable configuration)
echo "Enabling enhanced traffic logging..."
kubectl set env deployment/"${AFFECTED_DEPLOYMENT}" \
  TRAFFIC_LOG_LEVEL=DEBUG \
  --record

# 3. Revoke service account tokens (idempotent)
echo "Revoking compromised tokens..."
for token in $(kubectl get secret -o jsonpath='{.items[*].metadata.name}' \
  -l deployment="${AFFECTED_DEPLOYMENT}"); do
  kubectl delete secret "${token}" || true
done
# New tokens auto-generated on pod restart

# 4. Rotate credentials (immutable Vault operation)
echo "Rotating credentials..."
vault write -f auth/approle/role/incident-response/secret-id

# 5. Create immutable snapshot of isolated state
kubectl get all -o yaml > "${INCIDENT_DIR}/isolated-state.yaml"

echo "✅ Containment complete"
echo "Note: Isolation is immutable but reversible via rollback"
```

### 2.5 Remediation Phase (Idempotent Recovery)

**Automatic Remediation (Immutable State):**

```bash
#!/bin/bash
# scripts/ops/incident-response-remediate.sh (idempotent fix)
set -euo unpipefail

INCIDENT_ID="${1}"
INCIDENT_DIR="/var/log/incidents/${INCIDENT_ID}"

echo "=== Remediation Phase ==="

# Determine remediation strategy
STRATEGY=$(cat "${INCIDENT_DIR}/type.txt")

case "${STRATEGY}" in
  POD_CRASH_LOOP)
    remediate_pod_crash_loop
    ;;
  DATABASE_CORRUPTION)
    remediate_database_corruption
    ;;
  UNAUTHORIZED_ACCESS)
    remediate_unauthorized_access
    ;;
  DATA_EXFILTRATION)
    remediate_data_exfiltration
    ;;
  *)
    echo "Unknown incident type: ${STRATEGY}"
    exit 1
    ;;
esac

echo "✅ Remediation strategy applied"
```

**Remediation Workflows (Immutable, Idempotent):**

```bash
remediate_pod_crash_loop() {
  echo "Remediating pod crash loop..."
  
  # Roll back to previous stable version (idempotent - checks current first)
  CURRENT_IMAGE=$(kubectl get deployment affected-service \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
  
  if [[ "${CURRENT_IMAGE}" != "image:v1.2.3" ]]; then
    # Only rollback if not already on stable version
    kubectl set image deployment/affected-service \
      app=image:v1.2.3 \
      --record
  fi
  
  # Wait for rollout (idempotent - fails silently if already done)
  kubectl rollout status deployment/affected-service --timeout=5m || true
  
  # Verify health
  kubectl get deployment affected-service -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
}

remediate_database_corruption() {
  echo "Remediating database corruption..."
  
  # Restore from immutable backup
  bash scripts/phase7/backup-and-restore-automation.sh \
    --mode=restore \
    --backup-date="${BACKUP_DATE}" \
    --database-only \
    --verify-checksum
  
  # Verify data integrity (immutable checksum)
  psql -c "SELECT md5(string_agg(row_number()::text, ',')) FROM pg_tables" \
    > "${INCIDENT_DIR}/restored-checksum.txt"
  
  # Compare with pre-corruption checksum
  diff "${INCIDENT_DIR}/checksum-before.txt" \
       "${INCIDENT_DIR}/restored-checksum.txt" || \
    echo "Warning: checksums differ"
}

remediate_unauthorized_access() {
  echo "Remediating unauthorized access..."
  
  # Rotate all credentials (immutable Vault operation)
  vault write -f auth/kubernetes/rotate
  
  # Revoke all existing sessions (idempotent - Kubernetes auto-refreshes)
  kubectl delete secret --all --selector session=true || true
  
  # Force re-authentication (immutable policy)
  kubectl patch clusterrolebinding system:auth-delegator \
    -p '{"roleRef":{"apiGroup":"rbac.authorization.k8s.io","kind":"ClusterRole","name":"system:auth-delegator"}}'
}

remediate_data_exfiltration() {
  echo "Remediating data exfiltration..."
  
  # 1. Suspend all external network access (immutable NetworkPolicy)
  kubectl patch networkpolicy default \
    --type merge \
    -p '{"spec":{"egress":[{"to":[{"ipBlock":{"cidr":"10.0.0.0/8"}}]}]}}'
  
  # 2. Begin forensic analysis (immutable log collection)
  echo "Analyzing exfiltration channels..."
  grep -E "SELECT|export|dump" /var/log/postgresql/* > \
    "${INCIDENT_DIR}/exfil-queries.txt" || true
  
  # 3. Identify affected data (immutable audit)
  psql -c "SELECT datname,usename,query FROM pg_stat_statements \
    WHERE query LIKE '%SELECT%' ORDER BY calls DESC LIMIT 20" > \
    "${INCIDENT_DIR}/top-queries.txt"
  
  # 4. Rotate encryption keys (immutable Vault)
  vault write -f secret/data/rotate-keys
  
  # 5. Notify customers (immutable template)
  cat > "${INCIDENT_DIR}/customer-notification.txt" << 'EOF'
Subject: Security Incident Notification

[Standard template - fill in details]
Affected Data: [determined from audit logs]
Timeline: [from incident timeline]
Actions Taken: [remediation steps]
EOF
}
```

### 2.6 Recovery Phase (Idempotent Restoration)

**Service Restoration (Immutable Rollout):**

```bash
#!/bin/bash
# scripts/ops/incident-response-recover.sh (idempotent recovery)
set -euo pipefail

INCIDENT_ID="${1}"
INCIDENT_DIR="/var/log/incidents/${INCIDENT_ID}"

echo "=== Recovery Phase ==="

# 1. Restore normal network access (idempotent - safe re-run)
kubectl delete networkpolicy default \
  --ignore-not-found=true

# 2. Re-enable external traffic (idempotent ingress)
kubectl patch ingress --all \
  -p '{"metadata":{"annotations":{"incident.response":"false"}}}'

# 3. Verify service health (idempotent health check)
kubectl rollout status deployment/auth-server --timeout=5m
kubectl rollout status deployment/api-server --timeout=5m

# 4. Verify data integrity (immutable checksums)
echo "Verifying data integrity..."
RESTORED_CHECKSUM=$(psql -c "SELECT md5(string_agg(row_number()::text, ',')) FROM pg_tables")
EXPECTED_CHECKSUM=$(cat "${INCIDENT_DIR}/expected-checksum.txt")

if [[ "${RESTORED_CHECKSUM}" != "${EXPECTED_CHECKSUM}" ]]; then
  echo "⚠️  Checksum mismatch - data integrity questionable"
  exit 1
fi

# 5. Run smoke tests (idempotent validation)
echo "Running smoke tests..."
kubectl run smoke-test --image=curlimages/curl \
  -- sh -c 'curl -f http://api-server:8080/health' || exit 1

# 6. Monitor for 15 minutes (immutable watchdog)
echo "Monitoring service..."
for i in {1..15}; do
  kubectl get deployment --all-namespaces -o jsonpath='{.items[*].status}' \
    >> "${INCIDENT_DIR}/recovery-monitor-${i}.txt"
  sleep 60
done

echo "✅ Recovery complete"
```

### 2.7 Post-Incident Review (Immutable Documentation)

**Lessons Learned (Non-Destructive Analysis):**

```bash
#!/bin/bash
# scripts/ops/incident-response-retrospective.sh (immutable report)
set -euo pipefail

INCIDENT_ID="${1}"
INCIDENT_DIR="/var/log/incidents/${INCIDENT_ID}"

echo "=== Post-Incident Review ==="

# Generate immutable incident report
cat > "${INCIDENT_DIR}/incident-report.md" << 'EOF'
# Incident Report

## Summary
[Auto-populated from metadata]

## Timeline
[From timeline.md - auto-populated]

## Root Cause Analysis

### Technical Root Cause
[Determined from investigation logs]

### Process Root Cause
[Missing controls, monitoring gaps]

### Contributing Factors
[System interactions that enabled incident]

## Remediation Actions Taken

### Immediate (Completed)
- [Action 1 + timestamp]
- [Action 2 + timestamp]

### Short-term (Next 30 days)
- [Planned fix + owner + date]

### Long-term (3-6 months)
- [Architectural change + owner + date]

## Prevention: What We'll Do Differently

### Monitoring
- [New alert + threshold]
- [New dashboard]

### Automation
- [New automated response]

### Process
- [Updated runbook]
- [New training item]

### Architecture
- [Resilience improvement]
- [Security hardening]

## Follow-up Actions

- [ ] Code review for fixes (owner: [name], due: [date])
- [ ] Control testing (owner: [name], due: [date])
- [ ] Security training (owner: [name], due: [date])
- [ ] Policy update (owner: [name], due: [date])
- [ ] Incident review meeting (date, attendees)

## Impact Summary

- **Total Duration**: [start to all-clear]
- **Service Downtime**: [minutes]
- **Users Impacted**: [number]
- **Data at Risk**: [yes/no + details]
- **Severity**: [CRITICAL/HIGH/MEDIUM/LOW]

## Appendix: Raw Logs
[All collected logs + analysis available in incident directory]
EOF

# Archive immutable incident record (no modification allowed)
tar -czf "${INCIDENT_DIR}-archive.tar.gz" "${INCIDENT_DIR}"
chmod 444 "${INCIDENT_DIR}-archive.tar.gz"  # Read-only

# Send to S3 (immutable versioning enabled)
aws s3 cp "${INCIDENT_DIR}-archive.tar.gz" \
  s3://code-server-backups/incidents/ \
  --sse=AES256

echo "✅ Post-incident review complete"
echo "Report: ${INCIDENT_DIR}/incident-report.md"
echo "Archive: ${INCIDENT_DIR}-archive.tar.gz"
```

---

## 3. Incident Response Team Roles

**On-Call Schedule (Immutable Configuration):**

```yaml
# helm/values.oncall.yaml (idempotent schedule)
oncall:
  roles:
    - title: "Incident Commander"
      rotation: "1-week"
      contact: "Slack @incident-commander"
      responsibilities:
        - Declare incident severity
        - Activate war room
        - Coordinate response
        - Communicate with stakeholders
    
    - title: "Technical Lead"
      rotation: "1-week"
      contact: "Slack @technical-lead"
      responsibilities:
        - Investigate root cause
        - Execute remediation
        - Verify recovery
        - Post-incident analysis
    
    - title: "Security Lead"
      rotation: "1-week"
      contact: "Slack @security-lead"
      responsibilities:
        - Assess security impact
        - Investigate breaches
        - Coordinate legal/PR if needed
        - Update policies
    
    - title: "Communications"
      rotation: "1-week"
      contact: "Slack @communications"
      responsibilities:
        - Update status page
        - Notify customers
        - Update internal channels
        - Send post-incident summary
```

---

## 4. Communication Templates (Immutable)

**Internal Notification:**
```
🚨 INCIDENT: [INC-YYYYMMDD-HHMM]
Severity: [CRITICAL/HIGH/MEDIUM]
Service: [affected service]
Status: [INVESTIGATING/REMEDIATING/RECOVERED]

War room: #incident-[id]
Updates: Every 15 minutes
Timeline: See incident channel
```

**Customer Notification:**
```
Subject: [Service] - Incident Notification

We detected and have resolved an incident affecting [service].
- Incident Duration: [time]
- Root Cause: [brief explanation]
- Your Data: [impact assessment]
- Our Response: [actions taken]
- Prevention: [improvements made]

Full post-incident report: [link]
```

---

**Status:** ✅ DRAFT - Ready for Security Review  
**Related:** SECURITY-POLICY.md, ACCESS-CONTROL-MATRIX.md  
**Last Updated:** April 26, 2026
