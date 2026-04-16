# Phase 4: Compliance & Audit Automation

**Issue**: #391 (P1 High) — Compliance Automation  
**Phase**: 4 (of 4 for complete IAM)  
**Status**: DESIGNING  
**Effort**: 4-6 hours  
**Dependencies**: Phase 3 RBAC Enforcement (#390) — Prerequisite  
**Blocked By**: Phase 3 completion  

---

## Executive Summary

Phase 4 implements compliance automation and audit trail immutability. Building on Phases 1-3's identity, service-to-service auth, and RBAC enforcement, Phase 4 ensures all security-relevant events are immutably logged, accessible for compliance audits (GDPR, SOC2, ISO27001), and enables automated break-glass access for emergencies.

**Key Deliverables**:
1. Immutable audit log infrastructure (append-only, cryptographically signed)
2. Break-glass access (emergency escalation with full audit)
3. Compliance report automation (GDPR, SOC2, ISO27001)
4. Data retention and archival policies
5. Automated compliance notifications and alerts

---

## Architecture

### Audit Trail Flow

```
Security Events (All Sources)
  ├─ Authentication events (Phase 1)
  ├─ Service-to-service calls (Phase 2)
  ├─ RBAC policy decisions (Phase 3)
  ├─ Data access logs
  └─ Configuration changes
    ↓
Audit Aggregation (Loki + PostgreSQL)
  ├─ Loki: Real-time logs (7-day hot storage)
  └─ PostgreSQL: Immutable audit table (append-only)
    ↓
Signature & Sealing (Merkle tree + HMAC)
  ├─ Each audit entry signed with private key
  ├─ Merkle tree of all entries (tamper detection)
  └─ Daily seal uploaded to immutable storage
    ↓
Immutable Storage (Google Cloud Storage + on-prem backup)
  ├─ GCS: encrypted, versioned, no-delete retention
  └─ On-prem: tape archive on 192.168.168.42
    ↓
Compliance Export & Reporting
  ├─ GDPR: data export on demand
  ├─ SOC2: access logs for auditors
  └─ ISO27001: control evidence gathering
```

### Break-Glass Access Model

```
Emergency Situation
  ├─ P0 incident requiring urgent access
  └─ Normal RBAC doesn't permit required action
    ↓
Break-Glass Request
  ├─ Requester: engineer with "security:escalate" permission
  ├─ Reason: required for incident response (required field)
  ├─ Duration: requested (max 1 hour)
  └─ Pair: optional pair programmer for oversight
    ↓
Immediate Grant (No approval wait)
  ├─ Access granted immediately (< 1 sec)
  ├─ Full audit trail: who, when, why, what
  └─ Real-time alerts to security team
    ↓
Automatic Revocation
  ├─ Timer: access expires automatically (1 hour max)
  ├─ Cleanup: logs retained permanently
  └─ Post-incident: review logged for audit
```

---

## Implementation Roadmap

### Phase 4.1: Immutable Audit Infrastructure (Hours 1-2)

**Objective**: Guarantee audit logs cannot be deleted or modified.

**Tasks**:
1. [ ] Create PostgreSQL immutable audit table
   ```sql
   CREATE TABLE audit_log (
     id BIGSERIAL PRIMARY KEY,
     timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
     event_type VARCHAR(50) NOT NULL,
     subject VARCHAR(255) NOT NULL,
     action VARCHAR(100) NOT NULL,
     resource VARCHAR(255),
     result BOOLEAN,
     details JSONB,
     ip_address INET,
     tls_cert_subject VARCHAR(255),
     trace_id UUID,
     
     -- Immutability: prevent updates/deletes
     CONSTRAINT audit_immutable CHECK (false)  -- Never allow updates/deletes
   );
   
   -- Insert-only via function (no update/delete permissions)
   CREATE FUNCTION audit_log_insert(
     p_event_type VARCHAR,
     p_subject VARCHAR,
     p_action VARCHAR,
     p_resource VARCHAR,
     p_result BOOLEAN,
     p_details JSONB,
     p_ip_address INET,
     p_tls_cert_subject VARCHAR,
     p_trace_id UUID
   ) RETURNS BIGINT AS $$
   BEGIN
     INSERT INTO audit_log (...)
     VALUES (DEFAULT, NOW(), p_event_type, p_subject, ...);
     RETURN LASTVAL();
   END;
   $$ LANGUAGE plpgsql;
   
   -- Grant only EXECUTE permission (not SELECT, UPDATE, DELETE)
   GRANT EXECUTE ON FUNCTION audit_log_insert TO app_user;
   REVOKE SELECT, UPDATE, DELETE ON audit_log FROM app_user;
   ```

2. [ ] Set up append-only log stream
   - PostgreSQL: UNLOGGED table with append-only trigger
   - Alternative: WAL (Write-Ahead Log) export for immutability proof

3. [ ] Implement log signing
   - Each entry: HMAC-SHA256(entry || previous_hash)
   - Chain: entry N depends on entry N-1 (integrity chain)
   - Detection: any modification breaks chain

4. [ ] Daily audit seal
   - Merkle tree of all entries from past 24 hours
   - Sign with master key
   - Upload to immutable storage
   - Create attestation certificate

**Files to Create**:
- `terraform/audit.tf` - Audit infrastructure IaC
- `config/audit/audit-schema.sql` - Immutable table schema
- `scripts/audit-log-seal.sh` - Daily audit sealing
- `config/audit/log-signing-key.kms` - KMS key for signing

**Success Criteria**:
- Audit table truly append-only
- All entries signed and chained
- No ability to modify/delete audit logs
- Daily seals immutably stored

---

### Phase 4.2: Break-Glass Access (Hours 2-3)

**Objective**: Emergency escalation with full audit trail.

**Tasks**:
1. [ ] Design break-glass policy
   ```yaml
   break_glass:
     max_duration: 1h
     max_escalation_level: 4  # Out of 1-5
     requires_reason: true
     requires_pair: optional
     auto_revocation: true
     alert_to:
       - slack: #security-incidents
       - email: security-team@kushnir.cloud
       - pagerduty: security-on-call
   ```

2. [ ] Implement break-glass grant mechanism
   - Endpoint: /api/v1/break-glass/request
   - Input: reason, duration (max 1h), optional pair
   - Output: temporary token with escalated permissions
   - Effect: immediate (no approval queue)

3. [ ] Set up automatic revocation
   - Timer: revokes token after requested duration
   - Alert: 5 minutes before expiry
   - Cleanup: logs incident for audit

4. [ ] Create break-glass audit trail
   - Every break-glass grant logged
   - Every action during break-glass tracked
   - Post-incident: reviewable by security team

**Files to Create**:
- `config/break-glass/policy.yaml` - Break-glass policy
- `scripts/break-glass-grant.sh` - Grant mechanism
- `scripts/break-glass-revoke.sh` - Automatic revocation
- `docs/BREAK-GLASS-PROCEDURES.md` - Operator guide

**Success Criteria**:
- Break-glass access granted < 1 second
- Full audit trail of emergency access
- Automatic revocation working
- Security team alerted immediately

---

### Phase 4.3: Compliance Reporting (Hours 3-4)

**Objective**: Automated reports for GDPR, SOC2, ISO27001.

**Tasks**:
1. [ ] GDPR Data Subject Access Requests (DSAR)
   ```bash
   # Query: Get all data related to subject "user@example.com"
   SELECT * FROM audit_log 
   WHERE subject LIKE 'user@example.com%'
   OR details @> '{"email": "user@example.com"}';
   
   # Export: CSV + metadata
   # Delivery: encrypted to requested email (30 days from request)
   ```

2. [ ] SOC2 Compliance Reports
   - CC6.1 (Logical Access Control): RBAC policies audit
   - CC7.2 (System Monitoring): audit log retention proof
   - CC7.5 (Incident Preparation): incident logs available
   - Reports: monthly automated generation

3. [ ] ISO27001 Control Evidence
   - A.9.2.1 (User registration): user creation logs
   - A.9.2.2 (User password management): password change logs
   - A.12.4.1 (Event logging): comprehensive audit trail
   - A.18.1.4 (Data protection compliance): GDPR DSAR handling

4. [ ] Data Retention Policy
   - Logs: retained for 7 years (compliance requirement)
   - Hot storage (Loki): 90 days
   - Warm storage (PostgreSQL): 1 year
   - Cold storage (S3 Glacier): 7 years

**Files to Create**:
- `scripts/gdpr-dsar-handler.sh` - GDPR DSAR automation
- `scripts/soc2-report-generator.sh` - SOC2 report generation
- `scripts/iso27001-evidence-gather.sh` - ISO27001 evidence
- `config/compliance/retention-policy.yaml` - Data retention

**Success Criteria**:
- GDPR DSARs processed automatically
- SOC2 reports generated monthly
- ISO27001 evidence collected and organized
- Data retention policy enforced

---

### Phase 4.4: Notifications & Alerting (Hours 4-5)

**Objective**: Real-time alerts for security-relevant events.

**Tasks**:
1. [ ] Set up alerting infrastructure
   - Slack: #security-incidents
   - PagerDuty: on-call escalation
   - Email: security-team@kushnir.cloud
   - SMS: critical incidents only

2. [ ] Define alert rules
   - High severity: break-glass access granted
   - Medium: multiple failed access attempts
   - Low: policy changes, new roles created
   - Info: daily summary (audit metrics)

3. [ ] Implement alerting pipeline
   - Event source: audit logs
   - Filter: alert-worthy events
   - Enrich: additional context
   - Route: appropriate channel

4. [ ] Create alert runbooks
   - "Break-glass access granted" → check reason and scope
   - "Multiple denied RBAC requests" → possible attack?
   - "Audit log tampering detected" → immediate incident

**Files to Create**:
- `config/alerting/security-alerts.yaml` - Alert rules
- `scripts/security-alert-handler.sh` - Alert processor
- `docs/SECURITY-ALERTS-RUNBOOK.md` - Alert runbook

**Success Criteria**:
- All security events generate appropriate alerts
- Alerts reach right people immediately
- Runbooks available for on-call response
- Alert fatigue minimized

---

### Phase 4.5: Audit & Forensics Tools (Hours 5-6)

**Objective**: Tools for incident investigation and forensics.

**Tasks**:
1. [ ] Create audit query library
   ```bash
   # Who accessed resource X?
   audit-query --resource prometheus --action "read-metrics"
   
   # What did principal Y do?
   audit-query --subject "code-server:default"
   
   # Show timeline of events
   audit-query --timerange "2026-04-16T00:00:00Z to 2026-04-16T12:00:00Z"
   
   # Detect anomalies
   audit-query --detect-anomalies --threshold 3-sigma
   ```

2. [ ] Implement forensics capabilities
   - Timeline reconstruction: events in chronological order
   - Causal analysis: which event caused which outcome
   - Impact analysis: what was affected by this event
   - Root cause analysis: why did incident occur

3. [ ] Create visualization tools
   - Grafana dashboards: audit metrics
   - Timeline visualization: events over time
   - Access maps: service A ↔ service B interactions

4. [ ] Document investigation procedures
   - How to investigate unauthorized access
   - How to detect policy bypass
   - How to recover from audit tampering
   - How to preserve evidence

**Files to Create**:
- `scripts/audit-query.sh` - Audit query tool
- `scripts/forensics-timeline.sh` - Timeline reconstruction
- `docs/INCIDENT-INVESTIGATION-GUIDE.md` - Investigation guide
- `config/grafana/audit-forensics-dashboard.json` - Grafana dashboard

**Success Criteria**:
- Quick query of audit logs possible
- Forensics tools available for investigation
- Visualization helps understand events
- Investigation procedures documented

---

## Testing Strategy

### Unit Tests
- Audit logging: all events captured correctly
- Signing: cryptographic signatures valid
- Break-glass: access granted and revoked correctly

### Integration Tests
- Full event flow: event → audit log → seal → compliance report
- Break-glass: request → grant → automatic revocation
- Compliance: GDPR DSAR handled correctly

### Security Tests
- Audit tampering: detect modifications
- Break-glass abuse: log and alert
- Compliance bypass: prevent data retention deletion

---

## Rollback Plan

If Phase 4 fails:
1. **Audit logging down**: services continue (logs queued, replayed later)
2. **Break-glass broken**: fall back to normal RBAC (no emergency escalation)
3. **Compliance broken**: manual reports generated by security team

**Recovery Time**: < 30 minutes

---

## Success Criteria

✅ **Implementation Complete**:
- Immutable audit infrastructure deployed
- Break-glass access working with full audit
- Compliance reports auto-generating
- Alerting and notifications operational
- Forensics tools available

✅ **Testing Complete**:
- All audit events logged and signed
- Break-glass requests processed correctly
- Compliance reports accurate
- Forensics tools functional

✅ **Production Ready**:
- 7-year audit retention enforced
- GDPR/SOC2/ISO27001 compliance proven
- Emergency access available with full audit
- Incident investigation possible

---

## Timeline

| Task | Effort | Owner |
|------|--------|-------|
| Immutable Infrastructure | 2h | @infra-team |
| Break-Glass Access | 1h | @security-team |
| Compliance Reports | 1h | @compliance-team |
| Alerting | 1h | @platform-team |
| Forensics Tools | 1h | @kushin77 |
| **Total Phase 4** | **6h** | **Full team** |

---

## Compliance References

**GDPR (General Data Protection Regulation)**:
- Article 15: Data Subject Access Requests (implemented)
- Article 17: Right to erasure (with audit trail)
- Article 33: Breach notification (via alerts)

**SOC2 Type II (Service Organization Control)**:
- CC6: Logical Access Control (implemented via RBAC + audit)
- CC7: System Monitoring (implemented via audit logs)
- CC8: Change Management (via audit trail of all changes)

**ISO27001 (Information Security Management)**:
- A.9.2: User Access Management (implemented)
- A.12.4: Event Logging (immutable audit logs)
- A.18: Compliance Monitoring (compliance reports)

---

## Notes

- **Immutability**: Append-only, cryptographically signed, tamper-evident
- **Break-glass**: Emergency escalation, but with full audit trail
- **Compliance**: Automated, continuous evidence gathering
- **Retention**: 7 years for regulatory compliance

---

**Status**: Ready for implementation after Phase 3 completes  
**Next Phase**: None (complete IAM system after Phase 4)  
**Owner**: @kushin77 (can distribute to team)  

---

Last Updated: April 16, 2026  
Session: #3 (Execution Phase)
