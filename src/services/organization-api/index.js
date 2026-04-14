/**
 * Phase 26-C: Organization API
 * Multi-tenant organizations with RBAC (4 roles)
 * 
 * Roles:
 * - admin: Full access to organization
 * - developer: Can create/manage resources
 * - auditor: Read-only access to logs
 * - viewer: Read-only access to basic data
 */

const express = require('express');
const { Pool } = require('pg');
const crypto = require('crypto');
const prometheus = require('prom-client');

// ════════════════════════════════════════════════════════════════════════
// Prometheus Metrics
// ════════════════════════════════════════════════════════════════════════

const orgMetrics = {
  requests: new prometheus.Counter({
    name: 'org_api_requests_total',
    help: 'Total organization API requests',
    labelNames: ['method', 'path', 'role', 'status'],
  }),
  duration: new prometheus.Histogram({
    name: 'org_api_request_duration_seconds',
    help: 'Request duration',
    labelNames: ['method', 'path'],
    buckets: [0.01, 0.05, 0.1, 0.5, 1],
  }),
  rbacChecks: new prometheus.Counter({
    name: 'rbac_checks_total',
    help: 'RBAC permission checks',
    labelNames: ['action', 'allowed'],
  }),
  organizations: new prometheus.Gauge({
    name: 'organizations_total',
    help: 'Total organizations',
  }),
  organizationMembers: new prometheus.Gauge({
    name: 'organization_members_total',
    help: 'Total organization members',
    labelNames: ['organization_id'],
  }),
};

// ════════════════════════════════════════════════════════════════════════
// PostgreSQL Configuration
// ════════════════════════════════════════════════════════════════════════

const pool = new Pool({
  user: process.env.POSTGRES_USER || 'code_server_user',
  password: process.env.POSTGRES_PASSWORD,
  host: process.env.POSTGRES_HOST || 'localhost',
  port: process.env.POSTGRES_PORT || 5432,
  database: process.env.POSTGRES_DB || 'code_server',
});

// ════════════════════════════════════════════════════════════════════════
// Database Initialization
// ════════════════════════════════════════════════════════════════════════

async function initializeDatabase() {
  const client = await pool.connect();

  try {
    // Create organizations table
    await client.query(`
      CREATE TABLE IF NOT EXISTS organizations (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(255) NOT NULL,
        slug VARCHAR(255) UNIQUE NOT NULL,
        tier VARCHAR(50) DEFAULT 'free',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        deleted_at TIMESTAMP,
        metadata JSONB
      )
    `);

    // Create organization_members table
    await client.query(`
      CREATE TABLE IF NOT EXISTS organization_members (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
        user_id UUID NOT NULL,
        role VARCHAR(50) NOT NULL DEFAULT 'viewer',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(organization_id, user_id)
      )
    `);

    // Create organization_api_keys table
    await client.query(`
      CREATE TABLE IF NOT EXISTS organization_api_keys (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
        name VARCHAR(255) NOT NULL,
        key_hash VARCHAR(255) NOT NULL,
        last_used_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        revoked_at TIMESTAMP,
        metadata JSONB
      )
    `);

    // Create organization_audit_logs table
    await client.query(`
      CREATE TABLE IF NOT EXISTS organization_audit_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
        actor_id UUID NOT NULL,
        action VARCHAR(255) NOT NULL,
        resource_type VARCHAR(100) NOT NULL,
        resource_id VARCHAR(255),
        changes JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        ip_address INET,
        user_agent TEXT
      )
    `);

    console.log('Organization tables initialized');
  } finally {
    client.release();
  }
}

// ════════════════════════════════════════════════════════════════════════
// RBAC Authorization
// ════════════════════════════════════════════════════════════════════════

const RBAC_RULES = {
  admin: {
    'organizations:create': true,
    'organizations:read': true,
    'organizations:update': true,
    'organizations:delete': true,
    'members:create': true,
    'members:read': true,
    'members:update': true,
    'members:delete': true,
    'api_keys:create': true,
    'api_keys:read': true,
    'api_keys:delete': true,
    'audit_logs:read': true,
  },
  developer: {
    'organizations:read': true,
    'members:read': true,
    'api_keys:create': true,
    'api_keys:read': true,
    'audit_logs:read': true,
  },
  auditor: {
    'organizations:read': true,
    'members:read': true,
    'audit_logs:read': true,
  },
  viewer: {
    'organizations:read': true,
    'members:read': true,
  },
};

async function checkPermission(userId, orgId, action) {
  try {
    // Get user's role in organization
    const result = await pool.query(
      'SELECT role FROM organization_members WHERE organization_id = $1 AND user_id = $2',
      [orgId, userId]
    );

    if (result.rows.length === 0) {
      orgMetrics.rbacChecks.inc({ action, allowed: 'false' });
      return false;
    }

    const { role } = result.rows[0];
    const allowed = RBAC_RULES[role]?.[action] || false;

    orgMetrics.rbacChecks.inc({ action, allowed: allowed ? 'true' : 'false' });

    return allowed;
  } catch (error) {
    console.error('RBAC check failed:', error);
    return false;
  }
}

// ════════════════════════════════════════════════════════════════════════
// Express API
// ════════════════════════════════════════════════════════════════════════

const app = express();
app.use(express.json());

// Middleware for request tracking
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    orgMetrics.duration.observe({ method: req.method, path: req.path }, duration);
    orgMetrics.requests.inc({
      method: req.method,
      path: req.path,
      role: req.user?.role || 'unknown',
      status: res.statusCode,
    });
  });
  next();
});

// Mock authentication middleware (in production, use JWT/OAuth)
app.use((req, res, next) => {
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    req.user = {
      id: token,
      role: req.headers['x-user-role'] || 'viewer',
    };
  }
  next();
});

// ════════════════════════════════════════════════════════════════════════
// API Endpoints
// ════════════════════════════════════════════════════════════════════════

// Create organization
app.post('/organizations', async (req, res) => {
  try {
    const { name, slug, tier } = req.body;
    const userId = req.user?.id;

    if (!name || !slug) {
      return res.status(400).json({ error: 'name and slug required' });
    }

    const result = await pool.query(
      `INSERT INTO organizations (name, slug, tier) 
       VALUES ($1, $2, $3) 
       RETURNING id, name, slug, tier, created_at`,
      [name, slug, tier || 'free']
    );

    const org = result.rows[0];

    // Add creator as admin
    await pool.query(
      'INSERT INTO organization_members (organization_id, user_id, role) VALUES ($1, $2, $3)',
      [org.id, userId, 'admin']
    );

    // Audit log
    await pool.query(
      `INSERT INTO organization_audit_logs 
       (organization_id, actor_id, action, resource_type, resource_id) 
       VALUES ($1, $2, $3, $4, $5)`,
      [org.id, userId, 'created', 'organization', org.id]
    );

    res.json(org);
  } catch (error) {
    console.error('Create organization error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get organization
app.get('/organizations/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const allowed = await checkPermission(req.user?.id, id, 'organizations:read');

    if (!allowed) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const result = await pool.query(
      'SELECT id, name, slug, tier, created_at FROM organizations WHERE id = $1',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Organization not found' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Get organization error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Add member to organization
app.post('/organizations/:id/members', async (req, res) => {
  try {
    const { id } = req.params;
    const { userId, role } = req.body;
    const actorId = req.user?.id;

    const allowed = await checkPermission(actorId, id, 'members:create');
    if (!allowed) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const result = await pool.query(
      `INSERT INTO organization_members 
       (organization_id, user_id, role) 
       VALUES ($1, $2, $3) 
       RETURNING id, role, created_at`,
      [id, userId, role || 'viewer']
    );

    // Audit log
    await pool.query(
      `INSERT INTO organization_audit_logs 
       (organization_id, actor_id, action, resource_type, resource_id) 
       VALUES ($1, $2, $3, $4, $5)`,
      [id, actorId, 'member_added', 'member', userId]
    );

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Add member error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Create API key
app.post('/organizations/:id/api-keys', async (req, res) => {
  try {
    const { id } = req.params;
    const { name } = req.body;
    const actorId = req.user?.id;

    const allowed = await checkPermission(actorId, id, 'api_keys:create');
    if (!allowed) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    // Generate API key
    const apiKey = crypto.randomBytes(32).toString('hex');
    const keyHash = crypto.createHash('sha256').update(apiKey).digest('hex');

    const result = await pool.query(
      `INSERT INTO organization_api_keys 
       (organization_id, name, key_hash) 
       VALUES ($1, $2, $3) 
       RETURNING id, name, created_at`,
      [id, name || 'default', keyHash]
    );

    // Audit log
    await pool.query(
      `INSERT INTO organization_audit_logs 
       (organization_id, actor_id, action, resource_type) 
       VALUES ($1, $2, $3, $4)`,
      [id, actorId, 'api_key_created', 'api_key']
    );

    res.json({ ...result.rows[0], apiKey });
  } catch (error) {
    console.error('Create API key error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get audit logs
app.get('/organizations/:id/audit-logs', async (req, res) => {
  try {
    const { id } = req.params;
    const allowed = await checkPermission(req.user?.id, id, 'audit_logs:read');

    if (!allowed) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const result = await pool.query(
      `SELECT id, actor_id, action, resource_type, resource_id, created_at 
       FROM organization_audit_logs 
       WHERE organization_id = $1 
       ORDER BY created_at DESC 
       LIMIT 100`,
      [id]
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Get audit logs error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/healthz', (req, res) => {
  res.json({ status: 'healthy' });
});

// Readiness check
app.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not_ready', error: error.message });
  }
});

// Prometheus metrics
app.get('/metrics', (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(prometheus.register.metrics());
});

// Startup
const PORT = process.env.PORT || 3002;

async function start() {
  try {
    await initializeDatabase();
    app.listen(PORT, () => {
      console.log(`Phase 26-C Organization API listening on port ${PORT}`);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

start();

module.exports = app;
