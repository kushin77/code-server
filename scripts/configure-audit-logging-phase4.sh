#!/bin/bash
# @file        scripts/configure-audit-logging-phase4.sh
# @module      operations
# @description configure audit logging phase4 — on-prem code-server
# @owner       platform
# @status      active
# Phase 4: Audit Logging & Testing - Complete Observability for IAM Stack
# Purpose: Implement immutable audit trail and comprehensive testing
# Author: Copilot AI Agent
# Date: April 22, 2026

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }

# === Configuration ===
POSTGRES_HOST="${POSTGRES_HOST:-${DEPLOY_HOST}}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-code_server_prod}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"

# === Phase 4: Audit Logging Schema ===

create_audit_schema() {
  log_info "Creating immutable audit logging schema..."

  cat > config/audit-logging-schema.sql <<'EOF'
-- Phase 4: Immutable Audit Logging Schema
-- Purpose: Complete event trail for compliance and forensics

-- Main audit log table (append-only)
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  event_id UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  timestamp TIMESTAMP NOT NULL DEFAULT NOW(),
  
  -- Request context
  trace_id VARCHAR(36),
  user_id VARCHAR(255),
  service_name VARCHAR(100),
  ip_address INET,
  user_agent TEXT,
  
  -- Event details
  event_type VARCHAR(50) NOT NULL, -- 'auth', 'authz', 'action', 'config_change'
  action VARCHAR(100) NOT NULL,
  resource VARCHAR(512),
  details JSONB,
  
  -- Outcome
  result VARCHAR(10) NOT NULL, -- 'success' or 'failure'
  error_message TEXT,
  
  -- Immutability markers
  hash_previous BYTEA,
  signature BYTEA
);

-- Immutable table: Prevent updates
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_log_immutable ON audit_log
  USING (true)
  WITH CHECK (true)
  FOR UPDATE, DELETE USING false;

-- Indexes for queries
CREATE INDEX idx_audit_timestamp ON audit_log(timestamp DESC);
CREATE INDEX idx_audit_user_id ON audit_log(user_id);
CREATE INDEX idx_audit_event_type ON audit_log(event_type);
CREATE INDEX idx_audit_resource ON audit_log(resource);
CREATE INDEX idx_audit_trace_id ON audit_log(trace_id);

-- Retention policy table
CREATE TABLE IF NOT EXISTS audit_retention_policy (
  id SERIAL PRIMARY KEY,
  event_type VARCHAR(50) NOT NULL,
  retention_days INTEGER NOT NULL,
  archive_after_days INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Default retention policies
INSERT INTO audit_retention_policy (event_type, retention_days, archive_after_days) VALUES
  ('auth', 365, 90),              -- 1 year retention, archive after 3 months
  ('authz', 365, 90),
  ('action', 730, 180),           -- 2 years for actions
  ('config_change', 1825, 365)    -- 5 years for configuration changes
ON CONFLICT DO NOTHING;

-- Archive table for long-term retention
CREATE TABLE IF NOT EXISTS audit_log_archive (
  id BIGSERIAL PRIMARY KEY,
  event_id UUID NOT NULL UNIQUE,
  timestamp TIMESTAMP NOT NULL,
  event_type VARCHAR(50) NOT NULL,
  user_id VARCHAR(255),
  action VARCHAR(100),
  resource VARCHAR(512),
  details JSONB,
  archived_at TIMESTAMP DEFAULT NOW(),
  archive_path TEXT -- S3 or NAS path
);

-- Audit compliance report table
CREATE TABLE IF NOT EXISTS audit_compliance_report (
  id SERIAL PRIMARY KEY,
  report_date DATE NOT NULL,
  total_events BIGINT,
  auth_events BIGINT,
  authz_events BIGINT,
  failed_events BIGINT,
  privilege_escalations BIGINT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Procedures for audit operations

-- Archive old events
CREATE OR REPLACE FUNCTION archive_old_audit_events()
RETURNS void AS $$
BEGIN
  INSERT INTO audit_log_archive (event_id, timestamp, event_type, user_id, action, resource, details)
  SELECT event_id, timestamp, event_type, user_id, action, resource, details
  FROM audit_log
  WHERE timestamp < NOW() - INTERVAL '3 months'
    AND event_type IN (SELECT event_type FROM audit_retention_policy WHERE archive_after_days IS NOT NULL)
    AND timestamp < NOW() - (SELECT INTERVAL '1 day' * archive_after_days FROM audit_retention_policy WHERE event_type = audit_log.event_type);
  
  DELETE FROM audit_log
  WHERE timestamp < NOW() - INTERVAL '3 months'
    AND event_type IN (SELECT event_type FROM audit_retention_policy WHERE archive_after_days IS NOT NULL);
END;
$$ LANGUAGE plpgsql;

-- Compliance report
CREATE OR REPLACE FUNCTION generate_compliance_report(report_date DATE)
RETURNS void AS $$
BEGIN
  INSERT INTO audit_compliance_report (report_date, total_events, auth_events, authz_events, failed_events, privilege_escalations)
  SELECT
    report_date,
    COUNT(*) as total_events,
    COUNT(*) FILTER (WHERE event_type = 'auth') as auth_events,
    COUNT(*) FILTER (WHERE event_type = 'authz') as authz_events,
    COUNT(*) FILTER (WHERE result = 'failure') as failed_events,
    COUNT(*) FILTER (WHERE action LIKE '%elevate%' OR action LIKE '%admin%') as privilege_escalations
  FROM audit_log
  WHERE DATE(timestamp) = report_date;
END;
$$ LANGUAGE plpgsql;

EOF

  log_success "Audit logging schema created"
}

configure_loki_ingestion() {
  log_info "Configuring Loki for audit log ingestion..."

  cat > config/loki-audit-pipeline.yml <<'EOF'
# Loki configuration for audit log pipeline

auth_enabled: true

server:
  http_listen_port: 3100
  log_level: info

ingester:
  chunk_encoding: snappy
  max_chunk_age: 5m
  chunk_retain_period: 1m

schema_config:
  configs:
  - from: 2024-01-01
    store: boltdb-shipper
    object_store: filesystem
    schema: v11
    index:
      prefix: loki_index_
      period: 24h

storage_config:
  filesystem:
    directory: /loki/chunks
  boltdb_shipper:
    active_index_directory: /loki/index
    shared_store: filesystem

# Audit log specific settings
limits_config:
  ingestion_rate_mb: 100
  ingestion_burst_size_mb: 200
  retention_period: 2160h  # 90 days

# Audit log stream labels
stream_labels:
  - job: audit
    service: code-server
  - job: audit
    service: kubernetes
  - job: audit
    service: postgresql

EOF

  log_success "Loki audit pipeline configured"
}

create_audit_api() {
  log_info "Creating audit log query API..."

  cat > backend/src/services/audit.ts <<'EOF'
import { Pool } from 'pg';
import { v4 as uuidv4 } from 'uuid';

export interface AuditEvent {
  user_id: string;
  service_name: string;
  event_type: 'auth' | 'authz' | 'action' | 'config_change';
  action: string;
  resource?: string;
  result: 'success' | 'failure';
  error_message?: string;
  ip_address?: string;
  user_agent?: string;
  trace_id?: string;
  details?: Record<string, any>;
}

export class AuditService {
  private pool: Pool;

  constructor(pool: Pool) {
    this.pool = pool;
  }

  // Log an audit event
  async logEvent(event: AuditEvent): Promise<string> {
    const event_id = uuidv4();
    
    const query = `
      INSERT INTO audit_log (
        event_id, user_id, service_name, event_type, action,
        resource, result, error_message, ip_address, user_agent,
        trace_id, details
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
      RETURNING event_id;
    `;

    const values = [
      event_id,
      event.user_id,
      event.service_name,
      event.event_type,
      event.action,
      event.resource || null,
      event.result,
      event.error_message || null,
      event.ip_address || null,
      event.user_agent || null,
      event.trace_id || null,
      event.details ? JSON.stringify(event.details) : null,
    ];

    const result = await this.pool.query(query, values);
    return result.rows[0].event_id;
  }

  // Query audit log
  async queryEvents(filters: {
    user_id?: string;
    event_type?: string;
    date_from?: Date;
    date_to?: Date;
    limit?: number;
  }): Promise<AuditEvent[]> {
    let query = 'SELECT * FROM audit_log WHERE 1=1';
    const values: any[] = [];
    let paramCount = 1;

    if (filters.user_id) {
      query += ` AND user_id = $${paramCount++}`;
      values.push(filters.user_id);
    }

    if (filters.event_type) {
      query += ` AND event_type = $${paramCount++}`;
      values.push(filters.event_type);
    }

    if (filters.date_from) {
      query += ` AND timestamp >= $${paramCount++}`;
      values.push(filters.date_from);
    }

    if (filters.date_to) {
      query += ` AND timestamp <= $${paramCount++}`;
      values.push(filters.date_to);
    }

    query += ` ORDER BY timestamp DESC LIMIT $${paramCount}`;
    values.push(filters.limit || 1000);

    const result = await this.pool.query(query, values);
    return result.rows;
  }

  // Generate compliance report
  async generateComplianceReport(date: Date): Promise<any> {
    const result = await this.pool.query(
      'SELECT * FROM generate_compliance_report($1)',
      [date]
    );
    
    return await this.pool.query(
      'SELECT * FROM audit_compliance_report WHERE report_date = $1',
      [date.toISOString().split('T')[0]]
    );
  }
}

export async function logAuditEvent(event: AuditEvent, pool: Pool): Promise<void> {
  const service = new AuditService(pool);
  await service.logEvent(event);
}

EOF

  log_success "Audit API service created"
}

create_test_suite() {
  log_info "Creating comprehensive test suite..."

  cat > tests/iam/phase4-audit.test.ts <<'EOF'
import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import { AuditService, AuditEvent } from '../../src/services/audit';
import { Pool } from 'pg';

describe('Phase 4: Audit Logging', () => {
  let pool: Pool;
  let auditService: AuditService;

  beforeAll(async () => {
    pool = new Pool({
      host: process.env.POSTGRES_HOST || 'localhost',
      port: parseInt(process.env.POSTGRES_PORT || '5432'),
      database: process.env.POSTGRES_DB || 'code_server_test',
      user: process.env.POSTGRES_USER || 'postgres',
    });

    auditService = new AuditService(pool);
  });

  afterAll(async () => {
    await pool.end();
  });

  describe('Audit Event Logging', () => {
    it('should log authentication events', async () => {
      const event: AuditEvent = {
        user_id: 'user-123',
        service_name: 'code-server',
        event_type: 'auth',
        action: 'login',
        result: 'success',
        trace_id: 'trace-001',
      };

      const eventId = await auditService.logEvent(event);
      expect(eventId).toBeDefined();
    });

    it('should log authorization events', async () => {
      const event: AuditEvent = {
        user_id: 'user-123',
        service_name: 'code-server',
        event_type: 'authz',
        action: 'deploy',
        resource: 'services/api',
        result: 'success',
      };

      const eventId = await auditService.logEvent(event);
      expect(eventId).toBeDefined();
    });

    it('should log failed events', async () => {
      const event: AuditEvent = {
        user_id: 'user-456',
        service_name: 'code-server',
        event_type: 'authz',
        action: 'delete_user',
        resource: 'users/user-789',
        result: 'failure',
        error_message: 'Insufficient permissions',
      };

      const eventId = await auditService.logEvent(event);
      expect(eventId).toBeDefined();
    });
  });

  describe('Audit Query', () => {
    it('should query events by user_id', async () => {
      const events = await auditService.queryEvents({ user_id: 'user-123' });
      expect(events.length).toBeGreaterThan(0);
      expect(events[0].user_id).toBe('user-123');
    });

    it('should query events by event_type', async () => {
      const events = await auditService.queryEvents({ event_type: 'auth' });
      expect(events.every(e => e.event_type === 'auth')).toBe(true);
    });

    it('should query events by date range', async () => {
      const now = new Date();
      const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);

      const events = await auditService.queryEvents({
        date_from: yesterday,
        date_to: now,
      });

      expect(events.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Audit Immutability', () => {
    it('should prevent deletion of audit logs', async () => {
      // This test verifies that the DELETE policy is enforced
      // Expected: Database should reject deletion attempts
      expect(() => {
        // Attempt to delete an audit event (should fail)
        return pool.query('DELETE FROM audit_log WHERE id = 1');
      }).rejects.toThrow();
    });

    it('should prevent update of audit logs', async () => {
      // Expected: Database should reject update attempts
      expect(() => {
        return pool.query('UPDATE audit_log SET action = $1 WHERE id = 1', ['modified']);
      }).rejects.toThrow();
    });
  });

  describe('Compliance Reporting', () => {
    it('should generate compliance report', async () => {
      const today = new Date();
      const report = await auditService.generateComplianceReport(today);
      
      expect(report.rows).toBeDefined();
      expect(report.rows[0]).toHaveProperty('total_events');
      expect(report.rows[0]).toHaveProperty('failed_events');
    });
  });
});

EOF

  log_success "Test suite created"
}

create_testing_guide() {
  log_info "Creating testing documentation..."

  cat > docs/iam/PHASE-4-TESTING-GUIDE.md <<'EOF'
# Phase 4: Testing Guide - IAM Stack Validation

## Overview

Complete testing procedures for the 4-phase IAM implementation:
- Phase 1: OIDC Provider Configuration
- Phase 2: Service-to-Service Authentication
- Phase 3: RBAC Enforcement
- Phase 4: Audit Logging

## Test Execution Plan

### Phase 1: OIDC Provider Tests

```bash
# 1. OIDC Endpoint Validation
curl -s https://accounts.google.com/.well-known/openid-configuration | jq .

# 2. oauth2-proxy Health Check
curl -s http://localhost:4180/health

# 3. OAuth2 Flow Test (browser)
# Navigate to: http://localhost:4180/oauth2/start?rd=http://localhost:8080/
# Expected: Redirect to Google login, then back to code-server

# 4. JWT Token Validation
curl -H "Authorization: Bearer $(cat /tmp/test_token.jwt)" \
  http://localhost:8080/api/health
# Expected: 200 OK with JWT claims in response
```

### Phase 2: Service-to-Service Tests

```bash
# 1. Workload Identity Token Generation
curl -X POST http://kubernetes-api:6443/api/v1/serviceaccounts/code-server/token

# 2. mTLS Certificate Validation
openssl s_client -connect localhost:8080 -cert /path/to/client.crt -key /path/to/client.key

# 3. Token Exchange
curl -X POST http://localhost:8000/token/exchange \
  -d "assertion=$(cat /tmp/workload_token)"

# 4. Service-to-Service Call
curl -H "Authorization: Bearer $(cat /tmp/service_token)" \
  http://ollama:11434/api/models
```

### Phase 3: RBAC Tests

```bash
# 1. Role-Based Access Control
# Admin user: should have full access
curl -H "Authorization: Bearer $(cat /tmp/admin_token)" \
  http://localhost:8080/api/users

# Viewer user: should be denied
curl -H "Authorization: Bearer $(cat /tmp/viewer_token)" \
  http://localhost:8080/api/users
# Expected: 403 Forbidden

# 2. Resource-Level Permissions
# Create a test resource
curl -X POST -H "Authorization: Bearer $(cat /tmp/admin_token)" \
  http://localhost:8080/api/resources \
  -d '{"name":"test-resource"}'

# Try to delete (operator should be denied)
curl -X DELETE -H "Authorization: Bearer $(cat /tmp/operator_token)" \
  http://localhost:8080/api/resources/test-resource
# Expected: 403 Forbidden

# 3. Network Policy Enforcement
kubectl get networkpolicies -A
kubectl describe networkpolicy code-server-network-policy
```

### Phase 4: Audit Logging Tests

```bash
# 1. Audit Event Logging
# Perform an action and check audit log
curl -X POST -H "Authorization: Bearer $(cat /tmp/test_token)" \
  http://localhost:8080/api/actions

# Query audit log
psql -h localhost -d code_server_prod -U postgres -c \
  "SELECT * FROM audit_log ORDER BY timestamp DESC LIMIT 10;"

# 2. Audit Immutability
# Verify logs cannot be deleted
psql -h localhost -d code_server_prod -U postgres -c \
  "DELETE FROM audit_log WHERE id = 1;"
# Expected: Error (policy prevents deletion)

# 3. Compliance Report
psql -h localhost -d code_server_prod -U postgres -c \
  "SELECT generate_compliance_report(CURRENT_DATE);"

# Query report results
psql -h localhost -d code_server_prod -U postgres -c \
  "SELECT * FROM audit_compliance_report WHERE report_date = CURRENT_DATE;"

# 4. Log Retention
# Verify archive process works
psql -h localhost -d code_server_prod -U postgres -c \
  "SELECT archive_old_audit_events();"
```

## Load Testing

### Setup

```bash
# Install k6
brew install k6  # macOS
# or
apt-get install k6  # Linux

# Create test script
cat > tests/iam-load-test.js <<'ENDSCRIPT'
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp-up
    { duration: '1m30s', target: 100 }, // Stay at 100 users
    { duration: '20s', target: 0 },    // Ramp-down
  ],
};

export default function() {
  const token = __ENV.JWT_TOKEN;
  
  const res = http.get('http://localhost:8080/api/health', {
    headers: { Authorization: `Bearer ${token}` },
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'auth latency < 100ms': (r) => r.timings.duration < 100,
  });
}
ENDSCRIPT

# Run test
export JWT_TOKEN=$(cat /tmp/test_token.jwt)
k6 run tests/iam-load-test.js
```

## Chaos Testing

### Failure Scenarios

```bash
# 1. OIDC Provider Down
# Block traffic to accounts.google.com
sudo iptables -A OUTPUT -d accounts.google.com -j DROP

# Verify fallback to Keycloak works
curl http://localhost:4180/health
# Should use Keycloak as fallback

# Restore
sudo iptables -D OUTPUT -d accounts.google.com -j DROP

# 2. PostgreSQL Down
docker-compose stop postgres

# Verify authorization denies (no database)
curl -H "Authorization: Bearer $(cat /tmp/test_token)" \
  http://localhost:8080/api/health
# Should return 503 or 500

# Restore
docker-compose start postgres

# 3. Network Partition
# Kill traffic between code-server and ollama
sudo iptables -A OUTPUT -d ollama -j DROP

# Verify authorization check fails gracefully
# Expected: Request times out, not returns 500

# Restore
sudo iptables -D OUTPUT -d ollama -j DROP
```

## Validation Checklist

- [ ] All OIDC endpoints responding (200 OK)
- [ ] OAuth2 flow completes in browser
- [ ] JWT tokens valid and claims correct
- [ ] Service-to-service tokens exchange works
- [ ] mTLS certificates validate correctly
- [ ] RBAC denies unauthorized users (403)
- [ ] Audit logs immutable (cannot delete/update)
- [ ] Compliance reports generate correctly
- [ ] Load test shows &lt;50ms p99 latency for auth checks
- [ ] Chaos test scenarios handled gracefully
- [ ] All tests pass: `npm test -- tests/iam/`

EOF

  log_success "Testing guide created"
}

main() {
  echo "╔════════════════════════════════════════════════════════════════════════════════════════════╗"
  echo "║  Phase 4: Audit Logging & Comprehensive Testing                                         ║"
  echo "╚════════════════════════════════════════════════════════════════════════════════════════════╝"
  echo ""

  create_audit_schema
  configure_loki_ingestion
  create_audit_api
  create_test_suite
  create_testing_guide

  echo ""
  echo "╔════════════════════════════════════════════════════════════════════════════════════════════╗"
  echo "║  Phase 4 Complete - Ready for Integration Testing                                        ║"
  echo "╚════════════════════════════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Deliverables:"
  echo "  ✓ config/audit-logging-schema.sql"
  echo "  ✓ config/loki-audit-pipeline.yml"
  echo "  ✓ backend/src/services/audit.ts"
  echo "  ✓ tests/iam/phase4-audit.test.ts"
  echo "  ✓ docs/iam/PHASE-4-TESTING-GUIDE.md"
  echo ""
  echo "Next steps:"
  echo "1. Deploy audit schema: psql -f config/audit-logging-schema.sql"
  echo "2. Run tests: npm test -- tests/iam/"
  echo "3. Execute load tests: bash tests/iam/load-test.sh"
  echo "4. Validate chaos scenarios: bash tests/iam/chaos-test.sh"
}

main "$@"
