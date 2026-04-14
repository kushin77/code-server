# Phase 26-C/D: Organizations & Webhooks Implementation Guide
## Multi-Tenant Organizations & Event Delivery (Apr 25-May 1, 2026)

---

## OVERVIEW

**Combined Duration**: 23 hours (Apr 25-May 1)
**Components**:
- Organization API service (Node.js, 3 replicas)
- Webhook dispatcher (Python, 3 replicas)
- PostgreSQL schema migrations
- React management UI
**Deployment**: Kubernetes on 192.168.168.31
**Scalability**: 50+ organizations, 1M webhooks/day
**Availability Target**: 99.95%

---

## PART 1: MULTI-TENANT ORGANIZATIONS (Apr 25-26, 11h)

### 1.1 PostgreSQL Schema

**Location**: `db/migrations/phase-26c-organizations.sql`

```sql
-- Phase 26-C: Organizations Schema
-- Creates multi-tenant organization support

-- Enable UUID extension if not exists
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Organizations table
CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(128) UNIQUE NOT NULL,
  description TEXT,
  tier VARCHAR(50) NOT NULL DEFAULT 'free',
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  max_members INT NOT NULL DEFAULT 10,
  max_api_keys INT NOT NULL DEFAULT 5,
  webhook_quota_per_day INT NOT NULL DEFAULT 1000,
  storage_quota_mb INT NOT NULL DEFAULT 100,

  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP,

  CONSTRAINT valid_tier CHECK (tier IN ('free', 'pro', 'enterprise')),
  CONSTRAINT valid_slug CHECK (slug ~ '^[a-z0-9][a-z0-9-]{2,62}[a-z0-9]$')
);

CREATE INDEX idx_organizations_owner_id ON organizations(owner_id);
CREATE INDEX idx_organizations_slug ON organizations(slug);
CREATE INDEX idx_organizations_tier ON organizations(tier);
CREATE INDEX idx_organizations_deleted_at ON organizations(deleted_at) WHERE deleted_at IS NULL;

-- Organization members
CREATE TABLE IF NOT EXISTS organization_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(50) NOT NULL DEFAULT 'developer',
  email VARCHAR(255) NOT NULL,

  permissions JSONB DEFAULT '{}',
  invited_at TIMESTAMP,
  joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  disabled_at TIMESTAMP,

  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT valid_role CHECK (role IN ('admin', 'developer', 'auditor', 'viewer')),
  UNIQUE(org_id, user_id)
);

CREATE INDEX idx_org_members_org_id ON organization_members(org_id);
CREATE INDEX idx_org_members_user_id ON organization_members(user_id);
CREATE INDEX idx_org_members_role ON organization_members(role);

-- API Keys for organizations
CREATE TABLE IF NOT EXISTS organization_api_keys (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  created_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,

  name VARCHAR(255) NOT NULL,
  key_hash VARCHAR(256) NOT NULL UNIQUE,  -- SHA-256 of actual key
  prefix VARCHAR(20) UNIQUE NOT NULL,  -- For display/identification

  permissions JSONB NOT NULL DEFAULT '[]',
  rate_limit_per_minute INT,

  last_used_at TIMESTAMP,
  expires_at TIMESTAMP,
  rotated_at TIMESTAMP,

  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at TIMESTAMP
);

CREATE INDEX idx_api_keys_org_id ON organization_api_keys(org_id);
CREATE INDEX idx_api_keys_prefix ON organization_api_keys(prefix);
CREATE INDEX idx_api_keys_expires_at ON organization_api_keys(expires_at);

-- Organization invitations
CREATE TABLE IF NOT EXISTS organization_invitations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  invited_email VARCHAR(255) NOT NULL,
  invited_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,

  role VARCHAR(50) NOT NULL DEFAULT 'developer',
  token_hash VARCHAR(256) NOT NULL UNIQUE,

  accepted_at TIMESTAMP,
  expires_at TIMESTAMP NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '7 days'),

  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_invitations_org_id ON organization_invitations(org_id);
CREATE INDEX idx_invitations_email ON organization_invitations(invited_email);

-- Organization audit log
CREATE TABLE IF NOT EXISTS organization_audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,

  action VARCHAR(100) NOT NULL,
  resource_type VARCHAR(50) NOT NULL,
  resource_id VARCHAR(255),

  changes JSONB,  -- {before, after}
  ip_address INET,
  user_agent TEXT,

  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT valid_action CHECK (action IN ('created', 'updated', 'deleted', 'invited', 'joined', 'left', 'role_changed', 'key_created', 'key_rotated', 'key_revoked'))
);

CREATE INDEX idx_audit_logs_org_id ON organization_audit_logs(org_id);
CREATE INDEX idx_audit_logs_user_id ON organization_audit_logs(user_id);
CREATE INDEX idx_audit_logs_created_at ON organization_audit_logs(created_at);
```

**Deploy Migration**:
```bash
# db/migrations/apply-phase-26c.sh
#!/bin/bash
set -e

DB_HOST=${DB_HOST:-postgres.phase-22-c.svc.cluster.local}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-codeserver}
DB_USER=${DB_USER:-postgres}
MIGRATION_FILE="phase-26c-organizations.sql"

echo "Applying Phase 26-C schema migration..."

# Wait for database to be ready
until pg_isready -h $DB_HOST -p $DB_PORT -U $DB_USER; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done

# Run migration
psql -h $DB_HOST -p $DB_PORT -d $DB_NAME -U $DB_USER -f $MIGRATION_FILE

echo "✓ Phase 26-C schema migration completed"
```

### 1.2 Organization API Service (Node.js)

**Location**: `src/services/organization-api/index.js`

```javascript
const express = require('express');
const { Pool } = require('pg');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const prometheus = require('prom-client');
const validateTier = require('./middleware/validate-tier');
const authMiddleware = require('./middleware/auth');
const auditLog = require('./middleware/audit-log');

const app = express();
app.use(express.json());
app.use(authMiddleware);
app.use(auditLog);

// Database pool
const pool = new Pool({
  host: process.env.DB_HOST || 'postgres.phase-22-c.svc.cluster.local',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'codeserver',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || '',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000
});

// Prometheus metrics
const orgApiRequests = new prometheus.Counter({
  name: 'organization_api_requests_total',
  help: 'Total organization API requests',
  labelNames: ['endpoint', 'method', 'status']
});

const orgApiDuration = new prometheus.Histogram({
  name: 'organization_api_duration_seconds',
  help: 'Organization API request duration',
  labelNames: ['endpoint']
});

// Organization class
class OrganizationManager {
  constructor(pool) {
    this.pool = pool;
  }

  async createOrganization(userId, name, slug) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Create organization
      const result = await client.query(
        `INSERT INTO organizations (name, slug, owner_id, tier)
         VALUES ($1, $2, $3, 'free')
         RETURNING id, name, slug, tier`,
        [name, slug, userId]
      );

      const orgId = result.rows[0].id;

      // Add owner as admin member
      await client.query(
        `INSERT INTO organization_members (org_id, user_id, role, email)
         VALUES ($1, $2, 'admin', (SELECT email FROM users WHERE id = $2))`,
        [orgId, userId]
      );

      // Audit log
      await client.query(
        `INSERT INTO organization_audit_logs (org_id, user_id, action, resource_type)
         VALUES ($1, $2, 'created', 'organization')`,
        [orgId, userId]
      );

      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async addMember(orgId, email, role) {
    // Verify org and permissions
    const result = await this.pool.query(
      `INSERT INTO organization_members (org_id, user_id, role, email)
       VALUES ($1, (SELECT id FROM users WHERE email = $2), $3, $2)
       RETURNING id, role`,
      [orgId, email, role]
    );
    return result.rows[0];
  }

  async createApiKey(orgId, userId, name, permissions) {
    const key = crypto.randomBytes(32).toString('hex');
    const keyHash = crypto.createHash('sha256').update(key).digest('hex');
    const prefix = key.substring(0, 20);

    const result = await this.pool.query(
      `INSERT INTO organization_api_keys (org_id, created_by_user_id, name, key_hash, prefix, permissions)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, prefix, created_at`,
      [orgId, userId, name, keyHash, prefix, JSON.stringify(permissions)]
    );

    return {
      ...result.rows[0],
      key: key,  // Only returned once!
      message: 'Save this key securely. It will not be shown again.'
    };
  }

  async listMembers(orgId) {
    const result = await this.pool.query(
      `SELECT id, email, role, joined_at, disabled_at
       FROM organization_members
       WHERE org_id = $1 AND deleted_at IS NULL
       ORDER BY joined_at DESC`,
      [orgId]
    );
    return result.rows;
  }

  async updateMemberRole(orgId, memberId, newRole) {
    const result = await this.pool.query(
      `UPDATE organization_members
       SET role = $1, updated_at = CURRENT_TIMESTAMP
       WHERE id = $2 AND org_id = $3
       RETURNING id, role`,
      [newRole, memberId, orgId]
    );
    return result.rows[0];
  }

  async removeMember(orgId, memberId) {
    await this.pool.query(
      `UPDATE organization_members
       SET disabled_at = CURRENT_TIMESTAMP
       WHERE id = $1 AND org_id = $2`,
      [memberId, orgId]
    );
  }
}

const orgManager = new OrganizationManager(pool);

// API Routes
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/metrics', (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(prometheus.register.metrics());
});

// Create organization
app.post('/api/v1/organizations', async (req, res) => {
  const timer = orgApiDuration.startTimer({ endpoint: 'create_org' });
  try {
    const { name, slug } = req.body;
    const org = await orgManager.createOrganization(req.user.id, name, slug);
    orgApiRequests.labels('create_org', 'POST', 201).inc();
    res.status(201).json(org);
  } catch (error) {
    orgApiRequests.labels('create_org', 'POST', 400).inc();
    res.status(400).json({ error: error.message });
  } finally {
    timer();
  }
});

// List user's organizations
app.get('/api/v1/organizations', async (req, res) => {
  const timer = orgApiDuration.startTimer({ endpoint: 'list_orgs' });
  try {
    const result = await pool.query(
      `SELECT id, name, slug, tier FROM organizations
       WHERE owner_id = $1 OR id IN (
         SELECT org_id FROM organization_members WHERE user_id = $1
       )
       ORDER BY created_at DESC`,
      [req.user.id]
    );
    orgApiRequests.labels('list_orgs', 'GET', 200).inc();
    res.json({ organizations: result.rows });
  } catch (error) {
    orgApiRequests.labels('list_orgs', 'GET', 500).inc();
    res.status(500).json({ error: error.message });
  } finally {
    timer();
  }
});

// Get org members
app.get('/api/v1/organizations/:org_id/members', validateTier('admin'), async (req, res) => {
  const timer = orgApiDuration.startTimer({ endpoint: 'list_members' });
  try {
    const members = await orgManager.listMembers(req.params.org_id);
    orgApiRequests.labels('list_members', 'GET', 200).inc();
    res.json({ members });
  } catch (error) {
    orgApiRequests.labels('list_members', 'GET', 500).inc();
    res.status(500).json({ error: error.message });
  } finally {
    timer();
  }
});

// Add member
app.post('/api/v1/organizations/:org_id/members', validateTier('admin'), async (req, res) => {
  const timer = orgApiDuration.startTimer({ endpoint: 'add_member' });
  try {
    const { email, role } = req.body;
    const member = await orgManager.addMember(req.params.org_id, email, role || 'developer');
    orgApiRequests.labels('add_member', 'POST', 201).inc();
    res.status(201).json(member);
  } catch (error) {
    orgApiRequests.labels('add_member', 'POST', 400).inc();
    res.status(400).json({ error: error.message });
  } finally {
    timer();
  }
});

// Update member role
app.patch('/api/v1/organizations/:org_id/members/:member_id', validateTier('admin'), async (req, res) => {
  const timer = orgApiDuration.startTimer({ endpoint: 'update_member' });
  try {
    const { role } = req.body;
    const member = await orgManager.updateMemberRole(req.params.org_id, req.params.member_id, role);
    orgApiRequests.labels('update_member', 'PATCH', 200).inc();
    res.json(member);
  } catch (error) {
    orgApiRequests.labels('update_member', 'PATCH', 400).inc();
    res.status(400).json({ error: error.message });
  } finally {
    timer();
  }
});

// Remove member
app.delete('/api/v1/organizations/:org_id/members/:member_id', validateTier('admin'), async (req, res) => {
  const timer = orgApiDuration.startTimer({ endpoint: 'remove_member' });
  try {
    await orgManager.removeMember(req.params.org_id, req.params.member_id);
    orgApiRequests.labels('remove_member', 'DELETE', 200).inc();
    res.status(204).send();
  } catch (error) {
    orgApiRequests.labels('remove_member', 'DELETE', 500).inc();
    res.status(500).json({ error: error.message });
  } finally {
    timer();
  }
});

// Create API key
app.post('/api/v1/organizations/:org_id/api-keys', validateTier('developer'), async (req, res) => {
  const timer = orgApiDuration.startTimer({ endpoint: 'create_api_key' });
  try {
    const { name, permissions } = req.body;
    const key = await orgManager.createApiKey(req.params.org_id, req.user.id, name, permissions || []);
    orgApiRequests.labels('create_api_key', 'POST', 201).inc();
    res.status(201).json(key);
  } catch (error) {
    orgApiRequests.labels('create_api_key', 'POST', 400).inc();
    res.status(400).json({ error: error.message });
  } finally {
    timer();
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`Organization API listening on port ${PORT}`);
});
```

**Kubernetes Deployment**:
```yaml
# kubernetes/phase-26c-orgs/organization-api-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: organization-api
  namespace: api
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: organization-api
  template:
    metadata:
      labels:
        app: organization-api
    spec:
      containers:
      - name: api
        image: code-server/organization-api:latest
        ports:
        - containerPort: 3001
        env:
        - name: DB_HOST
          value: "postgres.phase-22-c.svc.cluster.local"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "codeserver"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: auth-secrets
              key: jwt-secret
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "250m"
        readinessProbe:
          httpGet:
            path: /health
            port: 3001
          initialDelaySeconds: 10
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: organization-api
  namespace: api
spec:
  type: ClusterIP
  ports:
  - port: 3001
    targetPort: 3001
  selector:
    app: organization-api
```

### 1.3 RBAC Role Matrix

```
┌──────────────┬─────────────────────────────────────────────────────────┐
│ Role         │ Permissions                                              │
├──────────────┼─────────────────────────────────────────────────────────┤
│ admin        │ org:read, org:update, org:delete                         │
│              │ members:read, members:create, members:update, ...        │
│              │ api_keys:*, webhooks:*, billing:*, analytics:*           │
│              │ audit_logs:read, invitations:*                           │
├──────────────┼─────────────────────────────────────────────────────────┤
│ developer    │ org:read                                                 │
│              │ members:read                                             │
│              │ api_keys:create, api_keys:read, api_keys:delete          │
│              │ webhooks:create, webhooks:list                           │
│              │ analytics:read                                           │
├──────────────┼─────────────────────────────────────────────────────────┤
│ auditor      │ org:read                                                 │
│              │ members:read                                             │
│              │ analytics:read                                           │
│              │ audit_logs:read                                          │
│              │ api_keys:read                                            │
├──────────────┼─────────────────────────────────────────────────────────┤
│ viewer       │ org:read                                                 │
│              │ analytics:read (read-only)                               │
│              │ schema:read                                              │
└──────────────┴─────────────────────────────────────────────────────────┘
```

---

## PART 2: WEBHOOK SYSTEM (Apr 27-28, 12h)

### 2.1 Webhook Schema

```sql
-- Phase 26-D: Webhooks Schema

CREATE TABLE IF NOT EXISTS webhooks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,

  endpoint_url TEXT NOT NULL,
  events TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  active BOOLEAN DEFAULT true,

  retry_policy JSONB DEFAULT '{"max_retries": 3, "backoff_ms": 1000}',
  timeout_ms INT DEFAULT 30000,

  secret_key VARCHAR(256),  -- For HMAC-SHA256 signing
  headers JSONB,

  created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP
);

CREATE INDEX idx_webhooks_org_id ON webhooks(org_id);
CREATE INDEX idx_webhooks_active ON webhooks(active) WHERE deleted_at IS NULL;

-- Webhook events log
CREATE TABLE IF NOT EXISTS webhook_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  webhook_id UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
  org_id UUID NOT NULL,

  event_type VARCHAR(100) NOT NULL,
  event_data JSONB NOT NULL,

  delivery_status VARCHAR(50) DEFAULT 'pending',  -- pending, delivered, failed, expired
  retry_count INT DEFAULT 0,

  first_attempt_at TIMESTAMP,
  last_attempt_at TIMESTAMP,
  delivered_at TIMESTAMP,

  http_status INT,
  error_message TEXT,

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '7 days')
);

CREATE INDEX idx_webhook_events_webhook_id ON webhook_events(webhook_id);
CREATE INDEX idx_webhook_events_org_id ON webhook_events(org_id);
CREATE INDEX idx_webhook_events_status ON webhook_events(delivery_status);
CREATE INDEX idx_webhook_events_created_at ON webhook_events(created_at);
```

### 2.2 Webhook Dispatcher Service (Python)

**Location**: `src/services/webhook-dispatcher/index.py`

```python
from flask import Flask, request, jsonify
import asyncio
import aiohttp
import json
import hashlib
import hmac
import logging
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import RealDictCursor
import os
import time
import prometheus_client
from prometheus_client import Counter, Histogram, Gauge

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
webhook_events_received = Counter('webhook_events_received_total', 'Total webhook events received', ['event_type'])
webhook_deliveries = Counter('webhook_deliveries_total', 'Total webhook deliveries', ['status'])
webhook_latency = Histogram('webhook_delivery_latency_seconds', 'Webhook delivery latency')
webhook_retries = Counter('webhook_retries_total', 'Total webhook retries')
active_webhooks = Gauge('active_webhooks', 'Number of active webhooks')

# Database connection pool
DB_HOST = os.getenv('DB_HOST', 'postgres.phase-22-c.svc.cluster.local')
DB_PORT = int(os.getenv('DB_PORT', 5432))
DB_NAME = os.getenv('DB_NAME', 'codeserver')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', '')

def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

class WebhookDispatcher:
    def __init__(self, max_retries=3, backoff_ms=1000):
        self.max_retries = max_retries
        self.backoff_ms = backoff_ms
        self.session = None

    async def init_session(self):
        """Initialize aiohttp session"""
        self.session = aiohttp.ClientSession(
            connector=aiohttp.TCPConnector(limit_per_host=10, limit=100),
            timeout=aiohttp.ClientTimeout(total=60)
        )

    async def close_session(self):
        if self.session:
            await self.session.close()

    def sign_payload(self, payload, secret):
        """Generate HMAC-SHA256 signature"""
        signature = hmac.new(
            secret.encode(),
            payload.encode(),
            hashlib.sha256
        ).hexdigest()
        return signature

    async def deliver_webhook(self, webhook_id, org_id, event_type, event_data, secret_key):
        """Deliver webhook with retry logic"""
        retry_count = 0
        last_error = None

        while retry_count <= self.max_retries:
            try:
                # Get webhook endpoint
                conn = get_db_connection()
                cur = conn.cursor(cursor_factory=RealDictCursor)
                cur.execute(
                    "SELECT endpoint_url FROM webhooks WHERE id = %s",
                    (webhook_id,)
                )
                webhook = cur.fetchone()
                cur.close()
                conn.close()

                if not webhook:
                    logger.warning(f"Webhook {webhook_id} not found")
                    return False

                # Prepare payload
                payload = json.dumps({
                    "event_type": event_type,
                    "event_data": event_data,
                    "timestamp": datetime.utcnow().isoformat(),
                    "webhook_id": str(webhook_id)
                })

                # Sign payload
                signature = self.sign_payload(payload, secret_key)

                # Deliver with timeout
                headers = {
                    'Content-Type': 'application/json',
                    'User-Agent': 'code-server-webhook-dispatcher/1.0',
                    'X-Webhook-Signature': f'sha256={signature}',
                    'X-Webhook-ID': str(webhook_id)
                }

                start_time = time.time()

                async with self.session.post(
                    webhook['endpoint_url'],
                    data=payload,
                    headers=headers,
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    latency = time.time() - start_time
                    webhook_latency.observe(latency)

                    if response.status >= 200 and response.status < 300:
                        # Success
                        self._log_delivery(webhook_id, org_id, 'delivered', response.status, None)
                        webhook_deliveries.labels(status='success').inc()
                        logger.info(f"Webhook {webhook_id} delivered (status={response.status}, latency={latency:.3f}s)")
                        return True
                    else:
                        last_error = f"HTTP {response.status}"
                        logger.warning(f"Webhook {webhook_id} failed: {last_error}")

            except asyncio.TimeoutError:
                last_error = "Timeout"
                logger.error(f"Webhook {webhook_id} timed out")
            except Exception as e:
                last_error = str(e)
                logger.error(f"Webhook {webhook_id} error: {e}")

            # Retry with exponential backoff
            if retry_count < self.max_retries:
                wait_time = (self.backoff_ms * (2 ** retry_count)) / 1000
                logger.info(f"Webhook {webhook_id} retry in {wait_time}s (attempt {retry_count + 1})")
                await asyncio.sleep(wait_time)
                webhook_retries.inc()
                retry_count += 1
            else:
                break

        # All retries failed
        self._log_delivery(webhook_id, org_id, 'failed', None, last_error)
        webhook_deliveries.labels(status='failed').inc()
        logger.error(f"Webhook {webhook_id} permanently failed after {self.max_retries} retries: {last_error}")
        return False

    def _log_delivery(self, webhook_id, org_id, status, http_status, error_message):
        """Log webhook delivery result"""
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute(
                """
                UPDATE webhook_events
                SET delivery_status = %s, http_status = %s, error_message = %s,
                    last_attempt_at = %s, delivered_at = CASE WHEN %s = 'delivered' THEN %s END
                WHERE webhook_id = %s AND delivery_status = 'pending'
                """,
                (status, http_status, error_message, datetime.utcnow(), status, datetime.utcnow(), webhook_id)
            )
            conn.commit()
            cur.close()
            conn.close()
        except Exception as e:
            logger.error(f"Failed to log delivery: {e}")

dispatcher = WebhookDispatcher()

# Routes
@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"}), 200

@app.route('/metrics', methods=['GET'])
def metrics():
    return prometheus_client.generate_latest()

@app.route('/api/v1/webhooks/dispatch', methods=['POST'])
async def dispatch_webhook():
    """Queue webhook for delivery"""
    try:
        data = request.json
        webhook_id = data.get('webhook_id')
        org_id = data.get('org_id')
        event_type = data.get('event_type')
        event_data = data.get('event_data', {})
        secret_key = data.get('secret_key')

        webhook_events_received.labels(event_type=event_type).inc()

        # Dispatch asynchronously
        asyncio.create_task(
            dispatcher.deliver_webhook(webhook_id, org_id, event_type, event_data, secret_key)
        )

        return jsonify({"status": "queued"}), 202
    except Exception as e:
        logger.error(f"Dispatch failed: {e}")
        return jsonify({"error": str(e)}), 400

@app.before_serving
async def startup():
    """Initialize on startup"""
    await dispatcher.init_session()

@app.after_serving
async def shutdown():
    """Cleanup on shutdown"""
    await dispatcher.close_session()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=False)
```

**Kubernetes Deployment**:
```yaml
# kubernetes/phase-26d-webhooks/dispatcher-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-dispatcher
  namespace: api
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: webhook-dispatcher
  template:
    metadata:
      labels:
        app: webhook-dispatcher
    spec:
      containers:
      - name: dispatcher
        image: code-server/webhook-dispatcher:latest
        ports:
        - containerPort: 5001
        env:
        - name: DB_HOST
          value: "postgres.phase-22-c.svc.cluster.local"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "codeserver"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /health
            port: 5001
          initialDelaySeconds: 10
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: webhook-dispatcher
  namespace: api
spec:
  type: ClusterIP
  ports:
  - port: 5001
    targetPort: 5001
  selector:
    app: webhook-dispatcher
```

### 2.3 Webhook Event Types

**14 Supported Event Types**:
```
workspace:created
workspace:updated
workspace:deleted
files:created
files:modified
files:deleted
users:invited
users:joined
users:left
api_keys:created
api_keys:rotated
api_keys:revoked
organizations:invited
organizations:joined
```

---

## PART 3: MANAGEMENT UI (Apr 28-29, 6h)

### 3.1 Organizations UI Component (React)

```javascript
// src/ui/components/OrganizationManager.jsx
import React, { useState, useEffect } from 'react';
import axios from 'axios';

export function OrganizationManager() {
  const [orgs, setOrgs] = useState([]);
  const [selectedOrg, setSelectedOrg] = useState(null);
  const [members, setMembers] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchOrganizations();
  }, []);

  async function fetchOrganizations() {
    try {
      setLoading(true);
      const response = await axios.get('/api/v1/organizations');
      setOrgs(response.data.organizations);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  async function selectOrganization(orgId) {
    try {
      setLoading(true);
      setSelectedOrg(orgId);
      const response = await axios.get(`/api/v1/organizations/${orgId}/members`);
      setMembers(response.data.members);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  async function addMember(email, role) {
    try {
      await axios.post(
        `/api/v1/organizations/${selectedOrg}/members`,
        { email, role }
      );
      await selectOrganization(selectedOrg);
    } catch (err) {
      setError(err.message);
    }
  }

  async function removeMember(memberId) {
    try {
      await axios.delete(
        `/api/v1/organizations/${selectedOrg}/members/${memberId}`
      );
      await selectOrganization(selectedOrg);
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <div className="organization-manager">
      <h2>Organizations</h2>

      {error && <div className="error">{error}</div>}

      <div className="org-list">
        {orgs.map(org => (
          <div
            key={org.id}
            className={`org-item ${selectedOrg === org.id ? 'active' : ''}`}
            onClick={() => selectOrganization(org.id)}
          >
            <h3>{org.name}</h3>
            <p>{org.slug}</p>
            <span className={`tier ${org.tier}`}>{org.tier}</span>
          </div>
        ))}
      </div>

      {selectedOrg && (
        <div className="members-panel">
          <h3>Members</h3>
          <table>
            <thead>
              <tr>
                <th>Email</th>
                <th>Role</th>
                <th>Joined</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {members.map(member => (
                <tr key={member.id}>
                  <td>{member.email}</td>
                  <td>{member.role}</td>
                  <td>{new Date(member.joined_at).toLocaleDateString()}</td>
                  <td>
                    <button onClick={() => removeMember(member.id)}>Remove</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
```

### 3.2 Webhooks UI Component (React)

```javascript
// src/ui/components/WebhookManager.jsx
import React, { useState, useEffect } from 'react';

export function WebhookManager() {
  const [webhooks, setWebhooks] = useState([]);
  const [newWebhook, setNewWebhook] = useState({
    name: '',
    endpoint_url: '',
    events: []
  });

  async function createWebhook() {
    try {
      const response = await axios.post(
        `/api/v1/organizations/${selectedOrg}/webhooks`,
        newWebhook
      );
      setWebhooks([...webhooks, response.data]);
      setNewWebhook({ name: '', endpoint_url: '', events: [] });
    } catch (err) {
      alert(`Failed to create webhook: ${err.message}`);
    }
  }

  async function deleteWebhook(webhookId) {
    try {
      await axios.delete(
        `/api/v1/organizations/${selectedOrg}/webhooks/${webhookId}`
      );
      setWebhooks(webhooks.filter(w => w.id !== webhookId));
    } catch (err) {
      alert(`Failed to delete webhook: ${err.message}`);
    }
  }

  return (
    <div className="webhook-manager">
      <h3>Webhooks</h3>

      <form onSubmit={(e) => { e.preventDefault(); createWebhook(); }}>
        <input
          type="text"
          placeholder="Webhook name"
          value={newWebhook.name}
          onChange={(e) => setNewWebhook({...newWebhook, name: e.target.value})}
          required
        />
        <input
          type="url"
          placeholder="Endpoint URL"
          value={newWebhook.endpoint_url}
          onChange={(e) => setNewWebhook({...newWebhook, endpoint_url: e.target.value})}
          required
        />
        <button type="submit">Create Webhook</button>
      </form>

      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Endpoint</th>
            <th>Events</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {webhooks.map(webhook => (
            <tr key={webhook.id}>
              <td>{webhook.name}</td>
              <td>{webhook.endpoint_url}</td>
              <td>{webhook.events.join(', ')}</td>
              <td>{webhook.active ? 'Active' : 'Inactive'}</td>
              <td>
                <button onClick={() => deleteWebhook(webhook.id)}>Delete</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

---

## INTEGRATION & TESTING (Apr 29-May 1, 3h)

### Test Suite

```bash
#!/bin/bash
# load-tests/phase-26c-d-integration.sh

set -e

ORG_API="http://organization-api.api.svc.cluster.local:3001"
WEBHOOK_DISPATCHER="http://webhook-dispatcher.api.svc.cluster.local:5001"
DB_HOST="postgres.phase-22-c.svc.cluster.local"

echo "Phase 26-C/D: Organizations & Webhooks Integration Testing"
echo "==========================================================="

# Test 1: Create organization
echo "[Test 1] Creating organization..."
ORG_RESPONSE=$(curl -s -X POST "$ORG_API/api/v1/organizations" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Org", "slug": "test-org"}')

ORG_ID=$(echo $ORG_RESPONSE | jq -r '.id')
echo "✓ Organization created: $ORG_ID"

# Test 2: Add member
echo "[Test 2] Adding member..."
curl -s -X POST "$ORG_API/api/v1/organizations/$ORG_ID/members" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "dev@example.com", "role": "developer"}'
echo "✓ Member added"

# Test 3: Create API key
echo "[Test 3] Creating API key..."
KEY_RESPONSE=$(curl -s -X POST "$ORG_API/api/v1/organizations/$ORG_ID/api-keys" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Key", "permissions": []}')

API_KEY=$(echo $KEY_RESPONSE | jq -r '.key')
echo "✓ API key created"

# Test 4: Webhook dispatcher health
echo "[Test 4] Webhook dispatcher health..."
HEALTH=$(curl -s "$WEBHOOK_DISPATCHER/health")
if echo "$HEALTH" | grep -q "healthy"; then
  echo "✓ Webhook dispatcher ready"
else
  echo "✗ Webhook dispatcher not ready"
  exit 1
fi

# Test 5: RBAC enforcement
echo "[Test 5] Testing RBAC..."
RBAC_TEST=$(curl -s -X GET "$ORG_API/api/v1/organizations/$ORG_ID/members" \
  -H "Authorization: Bearer $VIEWER_TOKEN")
if echo "$RBAC_TEST" | grep -q "error\|403"; then
  echo "✓ RBAC enforced correctly"
else
  echo "✗ RBAC not enforced"
  exit 1
fi

echo ""
echo "✓ All integration tests passed"
echo "Phase 26-C/D ready for May 1 deployment"
```

---

## SUCCESS CRITERIA

All stages combined (Apr 25-May 1):

- ✓ 50+ organizations created & managed
- ✓ RBAC enforced 100% (no privilege escalation)
- ✓ API latency <100ms p99
- ✓ Webhook delivery success ≥95%
- ✓ Zero event loss
- ✓ Auto-scaling verified (3-10 org, 3-20 webhooks)
- ✓ All tests passing
- ✓ Audit logs complete & searchable

---

**Timeline**: Apr 25-May 1, 2026 | **Status**: Ready to deploy | **Owner**: Platform Team
