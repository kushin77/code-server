# P1 #388 Phase 4: Compliance, Audit Reporting & Break-Glass Access
# Final phase: regulatory compliance, log retention, emergency procedures

**Status**: PLANNED (follows Phase 3)  
**Estimated Effort**: 4-6 hours  
**Dependencies**: Phase 1 + Phase 2 + Phase 3 complete  

---

## Phase 4 Scope

Phase 4 completes P1 #388 by implementing compliance features, audit reporting, and emergency access procedures:

### 1. Audit Log Retention Policies
- Implement 2-7 year retention by event type
- Automatic archival to S3 after 90 days
- Immutability verification (SHA256 chain)
- Compliance labeling (GDPR, SOC2, ISO27001)

### 2. Compliance Reporting
- Automated GDPR reports (data subject access requests)
- SOC2 audit readiness reports
- ISO27001 compliance validation
- Executive dashboards (Grafana)

### 3. Break-Glass Emergency Access
- Emergency token issuance procedure
- Session recording for break-glass usage
- Automatic expiration and cleanup
- Post-incident review process

### 4. User Lifecycle Management
- Automated revocation on offboarding
- Role expiration (contractors, trainees)
- Access review and recertification
- Orphaned account cleanup

### 5. Incident Response
- Playbooks for auth failures
- User compromise response
- Token/certificate revocation procedures
- Forensic audit log analysis

---

## Implementation Details

### Retention Policy Configuration

```yaml
# config/iam/retention-policies.yaml

retention:
  
  # Default: 1 year
  default_retention_days: 365
  
  # By event type
  policies:
    
    # Infrastructure changes (7 years - long-term decisions)
    infrastructure:
      event_types:
        - "terraform:apply"
        - "terraform:destroy"
        - "iam:policy:*"
        - "kubernetes:rbac:*"
      retention_days: 2555  # 7 years
      archive: true
      immutability: verified
      compliance: ["SOC2", "ISO27001"]
    
    # User authentication (2 years)
    authentication:
      event_types:
        - "authentication:*"
        - "iam:user:*"
      retention_days: 730  # 2 years
      archive: true
      compliance: ["GDPR"]
    
    # Access decisions (1 year)
    authorization:
      event_types:
        - "authorization:*"
        - "iam:role:*"
      retention_days: 365  # 1 year
      archive: false
      compliance: ["SOC2"]
    
    # Break-glass usage (3 years - critical incidents)
    emergency_access:
      event_types:
        - "break-glass:*"
      retention_days: 1095  # 3 years
      archive: true
      immutability: verified
      compliance: ["SOC2", "ISO27001"]

  # Archive configuration
  archive:
    destination: "s3://kushin-audit-archive/"
    encryption: "AES256 + KMS"
    retention_years: 7
    storage_class: "GLACIER"
    
    # Lifecycle transitions
    transitions:
      - days: 90
        storage_class: "STANDARD_IA"
      - days: 365
        storage_class: "GLACIER"
      - days: 2555
        action: "delete"  # After 7 years
```

### GDPR Data Subject Access Request

```python
# scripts/gdpr-data-subject-access.py

class GDPRDataSubjectAccess:
    """
    Automated GDPR Data Subject Access Request (DSAR) handling
    """
    
    def request_report(self, user_email, request_id):
        """Generate GDPR report for data subject"""
        
        # 1. Query all personal data
        personal_data = {
            'user_identity': self._get_user_identity(user_email),
            'authentication_events': self._get_auth_events(user_email),
            'authorization_events': self._get_authz_events(user_email),
            'session_data': self._get_sessions(user_email),
            'preferences': self._get_preferences(user_email),
        }
        
        # 2. Generate report
        report = {
            'request_id': request_id,
            'data_subject_email': user_email,
            'request_date': datetime.utcnow(),
            'response_deadline': datetime.utcnow() + timedelta(days=30),
            'personal_data': personal_data,
            'data_sources': ['Loki', 'PostgreSQL', 'K8s', 'GitHub'],
        }
        
        # 3. Encrypt and return
        return self._encrypt_report(report)
    
    def delete_on_request(self, user_email):
        """
        Right to be forgotten: delete personal data (GDPR Article 17)
        """
        
        # Delete non-essential personal data
        # Retain only: audit logs (immutable), incident records
        
        self._delete_user_preferences(user_email)
        self._anonymize_session_data(user_email)
        self._delete_auth_tokens(user_email)
        
        # Audit the deletion
        self._log_deletion(user_email)
```

### SOC2 Audit Readiness

```python
# scripts/soc2-audit-readiness.py

class SOC2AuditReadiness:
    """
    SOC2 compliance validation and reporting
    """
    
    def access_control_report(self):
        """SOC2 CC6-9: Access control implementation"""
        
        return {
            'cc6': {
                'title': 'Access Control',
                'controls': {
                    'cc6.1': {
                        'name': 'Logical access rights',
                        'verified': self._verify_role_definitions(),
                        'evidence': ['config/iam/rbac-policies.yaml'],
                    },
                    'cc6.2': {
                        'name': 'Access removal',
                        'verified': self._verify_offboarding_process(),
                        'evidence': ['scripts/revoke-access-on-offboarding.sh'],
                    },
                },
            },
            'cc7': {
                'title': 'System Monitoring',
                'controls': {
                    'cc7.2': {
                        'name': 'Authorization & activities monitoring',
                        'verified': self._verify_audit_logging(),
                        'evidence': ['config/iam/audit-logging-config.yaml'],
                    },
                },
            },
        }
    
    def generate_evidence_package(self):
        """Create evidence for SOC2 auditors"""
        
        evidence = {
            'audit_logs_sample': self._export_recent_logs(),
            'user_access_matrix': self._generate_access_matrix(),
            'policy_documents': self._collect_policies(),
            'testing_results': self._load_penetration_test_results(),
        }
        
        return self._create_evidence_package(evidence)
```

### Break-Glass Emergency Access Workflow

```bash
#!/usr/bin/env bash
# scripts/emergency-break-glass-access.sh

# P1 #388 - Break-Glass Emergency Token Issuance
# High-privilege access for emergency scenarios

set -euo pipefail

BREAK_GLASS_TTL=3600  # 1 hour max
BREAK_GLASS_ROLE="break-glass-admin"

issue_break_glass_token() {
    local requester=$1
    local reason=$2
    local ticket_number=$3
    
    # 1. Validate requester authorization
    if ! has_break_glass_authority "$requester"; then
        echo "ERROR: $requester not authorized for break-glass tokens"
        exit 1
    fi
    
    # 2. Require approval ticket
    if [ -z "$ticket_number" ]; then
        echo "ERROR: Ticket number required (incident, security alert)"
        exit 1
    fi
    
    # 3. Generate high-privilege token
    local token=$(openssl rand -base64 32)
    local expires_at=$(date -u +%s --date="+1 hour")
    
    # 4. Create token record
    kubectl create secret generic "break-glass-${ticket_number}" \
        --from-literal=token="$token" \
        --from-literal=expires_at="$expires_at" \
        --from-literal=requester="$requester" \
        --from-literal=reason="$reason" \
        --from-literal=ticket_number="$ticket_number" \
        -n code-server-iam
    
    # 5. Audit the issuance
    log_break_glass_event "break-glass:token:issued" \
        --actor="$requester" \
        --reason="$reason" \
        --ticket="$ticket_number" \
        --token_id="break-glass-${ticket_number}"
    
    # 6. Alert security team
    send_alert "BREAK-GLASS TOKEN ISSUED" \
        "User: $requester\nReason: $reason\nTicket: $ticket_number\nExpires: $(date -d @$expires_at)"
    
    # 7. Enable session recording
    start_session_recording "$requester" "$token"
    
    echo "Break-glass token issued: $token"
    echo "Expires in 1 hour"
    echo "Session recording enabled"
}

# Automatic cleanup after expiration
cleanup_expired_tokens() {
    local now=$(date +%s)
    
    kubectl get secrets -n code-server-iam -l type=break-glass \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.data.expires_at}{"\n"}{end}' |
    while read secret expires_b64; do
        local expires=$(echo "$expires_b64" | base64 -d)
        
        if [ "$now" -gt "$expires" ]; then
            kubectl delete secret "$secret" -n code-server-iam
            log_break_glass_event "break-glass:token:expired" \
                --token_id="$secret"
        fi
    done
}

main() {
    issue_break_glass_token "$@"
}

main "$@"
```

### Incident Response Playbooks

```markdown
## Incident: User Account Compromised

### Immediate Actions (< 5 minutes)

1. **Revoke all tokens**
   ```bash
   revoke_all_user_tokens user@example.com
   ```

2. **Disable user account**
   ```bash
   kubectl patch user user@example.com --type merge -p '{"spec":{"disabled":true}}'
   ```

3. **Kill active sessions**
   ```bash
   pkill -u user@example.com
   ```

4. **Alert security team**
   - Send to #security Slack channel
   - Create incident ticket
   - Page on-call security engineer

### Investigation (5-30 minutes)

1. **Collect forensic evidence**
   ```bash
   export_audit_logs --user=user@example.com --since="-7d" > /tmp/incident.json
   ```

2. **Analyze unauthorized actions**
   - Review authentication.login.failure events (brute force?)
   - Check authorization.access_denied for attempted privilege escalation
   - Identify what resources were accessed

3. **Check data exfiltration**
   - Logs downloaded?
   - Secrets accessed?
   - Code repositories cloned?

### Remediation (30+ minutes)

1. **Reset credentials**
   ```bash
   reset_mfa user@example.com
   force_password_reset user@example.com
   ```

2. **Review permissions**
   ```bash
   review_user_roles user@example.com
   review_user_group_memberships user@example.com
   ```

3. **Enable additional monitoring**
   ```bash
   enable_session_recording user@example.com
   enable_geolocation_alerts user@example.com
   ```

4. **Post-incident review**
   - Schedule retrospective (next day)
   - Document timeline
   - Identify prevention measures
```

---

## Success Criteria

- [ ] Audit logs retained for 2-7 years per policy
- [ ] Automated archival to S3 working (no manual intervention)
- [ ] GDPR DSAR can be generated in < 24 hours
- [ ] SOC2 evidence package ready for auditors
- [ ] Break-glass tokens issued with approval workflow
- [ ] Session recording for all break-glass access
- [ ] Automatic token expiration working
- [ ] User offboarding revokes all access
- [ ] Incident response playbooks tested
- [ ] Executive dashboards show compliance status

---

## Effort Estimate

- GDPR compliance: 1-2 hours
- SOC2 evidence collection: 1 hour
- Break-glass workflow: 1 hour
- User lifecycle management: 1-1.5 hours
- Incident response docs: 0.5-1 hour

**Total**: 4-6 hours (half day)

---

## Timeline

- **Phase 1** (8-10h): OIDC + RBAC + Audit Schema ✅ COMPLETE
- **Phase 2** (21-30h): Workload Federation + mTLS
- **Phase 3** (8-10h): RBAC Enforcement + Service Integration
- **Phase 4** (4-6h): Compliance + Break-Glass (this phase)

**Total P1 #388**: 41-56 hours (5-7 days)

---

## Next Steps

After Phase 4:

1. **Integration Testing** (2-3 days)
   - Full end-to-end user flow
   - Service-to-service authentication
   - Audit logging validation
   - Emergency access procedures

2. **Staging Deployment** (1 day)
   - Deploy to staging environment
   - Run compliance audit
   - Collect performance metrics

3. **Production Rollout** (1 day)
   - Phase rollout by service
   - Monitoring and alerting
   - Support escalation procedures

4. **Unblock Downstream Work**
   - P1 #385: Dual-Portal Architecture
   - P2 #418: Phase 3+ Terraform modules
   - All identity-dependent features

---

## Files to be Created (Phase 4)

```
config/iam/
├── retention-policies.yaml
├── break-glass-policy.yaml
└── incident-response-playbooks.md

scripts/
├── gdpr-data-subject-access.py
├── soc2-compliance-report.py
├── emergency-break-glass-access.sh
└── incident-response-automation.sh

docs/
└── P1-388-PHASE4-COMPLIANCE-FINAL.md
```

**Total Phase 4 Effort**: 4-6 hours (half day)  
**Unblocks**: P1 #385, P2 #418 Phase 3+, all downstream work  
**Related**: P1 #388 (main issue)
