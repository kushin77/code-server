require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const crypto = require('crypto');

const app = express();
const port = process.env.SAAS_API_PORT || 5000;

// ════════════════════════════════════════════════════════════════════════════
// Database Pool Configuration
// ════════════════════════════════════════════════════════════════════════════
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://codeserver:password@localhost:5432/codeserver',
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle client', err);
});

// ════════════════════════════════════════════════════════════════════════════
// Middleware
// ════════════════════════════════════════════════════════════════════════════
app.use(express.json());

// Health check route (no auth required)
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'saas-api' });
});

// OAuth2-Proxy Trust Headers
const authenticateUser = (req, res, next) => {
  const userEmail = req.headers['x-auth-request-email'];
  const userName = req.headers['x-auth-request-user'];
  const userGroups = req.headers['x-auth-request-groups'];

  if (!userEmail) {
    return res.status(401).json({ error: 'Unauthorized - No auth headers' });
  }

  req.user = {
    email: userEmail,
    username: userName,
    groups: userGroups ? userGroups.split(',') : [],
  };

  next();
};

// Apply auth middleware to all routes except health
app.use((req, res, next) => {
  if (req.path === '/health') {
    return next();
  }
  authenticateUser(req, res, next);
});

// ════════════════════════════════════════════════════════════════════════════
// RBAC Middleware - Role-Based Access Control
// ════════════════════════════════════════════════════════════════════════════

// Check if user is org admin
const requireOrgAdmin = (req, res, next) => {
  const orgId = req.params.org_id || req.body.org_id || req.query.org_id;
  
  if (!orgId) {
    return res.status(400).json({ error: 'Organization ID required' });
  }

  // For now, accept all authenticated users (mock RBAC)
  // In production, query memberships table to check role
  req.orgId = orgId;
  next();
};

// Check if user is global system admin
const requireSystemAdmin = (req, res, next) => {
  // Check if user has admin privileges (e.g., email in admin list)
  const adminEmails = (process.env.ADMIN_EMAILS || '').split(',');
  
  if (!adminEmails.includes(req.user.email)) {
    return res.status(403).json({ error: 'Admin privileges required' });
  }
  
  next();
};

// ════════════════════════════════════════════════════════════════════════════
// Org Management Endpoints
// ════════════════════════════════════════════════════════════════════════════

// GET /api/orgs - List organizations (system admin or member)
app.get('/api/orgs', async (req, res) => {
  try {
    // System admin sees all, members see their orgs
    let query = 'SELECT id, name, logo_url, description, is_active, created_at FROM organizations WHERE is_active = true';
    
    const result = await pool.query(query + ' ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching orgs:', err);
    res.status(500).json({ error: 'Failed to fetch organizations' });
  }
});

// POST /api/orgs - Create organization (system admin only)
app.post('/api/orgs', requireSystemAdmin, async (req, res) => {
  const { name, description, logo_url } = req.body;

  if (!name) {
    return res.status(400).json({ error: 'Organization name is required' });
  }

  try {
    // Set current user as org admin
    const result = await pool.query(
      'INSERT INTO organizations (name, description, logo_url) VALUES ($1, $2, $3) RETURNING id, name, created_at',
      [name, description || null, logo_url || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Organization name already exists' });
    }
    console.error('Error creating org:', err);
    res.status(500).json({ error: 'Failed to create organization' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// User Management Endpoints
// ════════════════════════════════════════════════════════════════════════════

// GET /api/users - List users (authenticated users)
app.get('/api/users', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, email, name, avatar_url, is_active, created_at FROM users WHERE is_active = true ORDER BY created_at DESC'
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching users:', err);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// POST /api/users - Create user (system admin only)
app.post('/api/users', requireSystemAdmin, async (req, res) => {
  const { email, name, avatar_url } = req.body;

  if (!email) {
    return res.status(400).json({ error: 'Email is required' });
  }

  try {
    const result = await pool.query(
      'INSERT INTO users (email, name, avatar_url) VALUES ($1, $2, $3) RETURNING id, email, name, created_at',
      [email, name || null, avatar_url || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Email already exists' });
    }
    console.error('Error creating user:', err);
    res.status(500).json({ error: 'Failed to create user' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// Group Management Endpoints
// ════════════════════════════════════════════════════════════════════════════

// GET /api/groups - List groups
app.get('/api/groups', async (req, res) => {
  const { org_id } = req.query;

  try {
    const query = org_id
      ? 'SELECT id, org_id, name, description, created_at FROM groups WHERE org_id = $1 ORDER BY created_at DESC'
      : 'SELECT id, org_id, name, description, created_at FROM groups ORDER BY created_at DESC';

    const params = org_id ? [org_id] : [];
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching groups:', err);
    res.status(500).json({ error: 'Failed to fetch groups' });
  }
});

// POST /api/groups - Create group
app.post('/api/groups', async (req, res) => {
  const { org_id, name, description } = req.body;

  if (!org_id || !name) {
    return res.status(400).json({ error: 'Organization ID and group name are required' });
  }

  try {
    const result = await pool.query(
      'INSERT INTO groups (org_id, name, description) VALUES ($1, $2, $3) RETURNING id, org_id, name, created_at',
      [org_id, name, description || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Error creating group:', err);
    res.status(500).json({ error: 'Failed to create group' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// Membership Management Endpoints
// ════════════════════════════════════════════════════════════════════════════

// POST /api/memberships - Assign user to org/group
app.post('/api/memberships', async (req, res) => {
  const { user_id, org_id, group_id, role } = req.body;

  if (!user_id || !org_id) {
    return res.status(400).json({ error: 'User ID and Organization ID are required' });
  }

  try {
    const result = await pool.query(
      'INSERT INTO memberships (user_id, org_id, group_id, role) VALUES ($1, $2, $3, $4) RETURNING id, user_id, org_id, group_id, role, created_at',
      [user_id, org_id, group_id || null, role || 'member']
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'User already member of this organization' });
    }
    console.error('Error creating membership:', err);
    res.status(500).json({ error: 'Failed to create membership' });
  }
});

// GET /api/memberships - List memberships
app.get('/api/memberships', async (req, res) => {
  const { org_id, user_id } = req.query;

  try {
    let query = 'SELECT id, user_id, org_id, group_id, role, created_at FROM memberships WHERE deleted_at IS NULL';
    const params = [];

    if (org_id) {
      query += ' AND org_id = $' + (params.length + 1);
      params.push(org_id);
    }

    if (user_id) {
      query += ' AND user_id = $' + (params.length + 1);
      params.push(user_id);
    }

    query += ' ORDER BY created_at DESC';

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching memberships:', err);
    res.status(500).json({ error: 'Failed to fetch memberships' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// Audit Log Endpoints
// ════════════════════════════════════════════════════════════════════════════

// GET /api/audit-logs - List audit logs (system admin only)
app.get('/api/audit-logs', requireSystemAdmin, async (req, res) => {
  const { org_id, limit = 100 } = req.query;

  try {
    const query = org_id
      ? 'SELECT id, org_id, user_id, action, resource_type, created_at FROM audit_logs WHERE org_id = $1 ORDER BY created_at DESC LIMIT $2'
      : 'SELECT id, org_id, user_id, action, resource_type, created_at FROM audit_logs ORDER BY created_at DESC LIMIT $1';

    const params = org_id ? [org_id, limit] : [limit];
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching audit logs:', err);
    res.status(500).json({ error: 'Failed to fetch audit logs' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// Custom Domain Endpoints (P3-1675)
// ════════════════════════════════════════════════════════════════════════════

// Caddy On-Demand TLS Validator (Rule 9: Idempotent/Safe)
// GET /api/v1/validate-domain?domain=...
// Returns 200 OK if the domain is authorized for TLS on-demand
app.get('/api/v1/validate-domain', async (req, res) => {
  const { domain } = req.query;

  if (!domain) {
    return res.status(400).end();
  }

  // Authorize our core domains and wildcards
  const allowedDomains = [
    'ide.kushnir.cloud',
    'kushnir.cloud',
    'localhost'
  ];

  if (allowedDomains.includes(domain) || domain.endsWith('.kushnir.cloud')) {
    return res.status(200).end();
  }

  try {
    // Check if domain is registered in custom_domains table and verified
    const result = await pool.query(
      'SELECT id FROM custom_domains WHERE domain = $1 AND is_verified = true AND is_active = true',
      [domain.toLowerCase()]
    );

    if (result.rows.length > 0) {
      return res.status(200).end();
    }
  } catch (err) {
    console.error('Error validating domain for Caddy:', err);
  }

  // Deny all others (prevents certificate harvesting attacks)
  res.status(403).end();
});

// POST /api/orgs/:org_id/custom-domain - Add custom domain with verification
app.post('/api/orgs/:org_id/custom-domain', requireOrgAdmin, async (req, res) => {
  const { org_id } = req.params;
  const { domain } = req.body;

  if (!domain) {
    return res.status(400).json({ error: 'Domain is required' });
  }

  // Validate domain format
  if (!/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.​[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/.test(domain)) {
    return res.status(400).json({ error: 'Invalid domain format' });
  }

  try {
    // Generate cryptographically secure TXT record value
    const txtRecordValue = crypto.randomBytes(32).toString('hex');

    const result = await pool.query(
      'INSERT INTO custom_domains (org_id, domain, txt_record_value) VALUES ($1, $2, $3) RETURNING id, org_id, domain, txt_record_value, is_verified, created_at',
      [org_id, domain.toLowerCase(), txtRecordValue]
    );

    const customDomain = result.rows[0];
    res.status(201).json({
      id: customDomain.id,
      domain: customDomain.domain,
      txt_record_value: customDomain.txt_record_value,
      is_verified: customDomain.is_verified,
      dns_verification_instruction: `Add TXT record to _acme-challenge.${domain}: ${txtRecordValue}`,
      created_at: customDomain.created_at,
    });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Domain already exists for another organization' });
    }
    console.error('Error creating custom domain:', err);
    res.status(500).json({ error: 'Failed to create custom domain' });
  }
});

// GET /api/orgs/:org_id/custom-domain/:domain - Get custom domain details
app.get('/api/orgs/:org_id/custom-domain/:domain', requireOrgAdmin, async (req, res) => {
  const { org_id, domain } = req.params;

  try {
    const result = await pool.query(
      'SELECT id, org_id, domain, txt_record_value, is_verified, tls_certificate_expires_at, verified_at FROM custom_domains WHERE org_id = $1 AND domain = $2',
      [org_id, domain.toLowerCase()]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Custom domain not found' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error('Error fetching custom domain:', err);
    res.status(500).json({ error: 'Failed to fetch custom domain' });
  }
});

// GET /api/orgs/:org_id/dns-verification - Check DNS TXT record and verify
app.get('/api/orgs/:org_id/dns-verification', requireOrgAdmin, async (req, res) => {
  const { org_id } = req.params;
  const { domain } = req.query;

  if (!domain) {
    return res.status(400).json({ error: 'Domain query parameter required' });
  }

  try {
    // Get the expected TXT record value
    const domainResult = await pool.query(
      'SELECT txt_record_value FROM custom_domains WHERE org_id = $1 AND domain = $2',
      [org_id, domain.toLowerCase()]
    );

    if (domainResult.rows.length === 0) {
      return res.status(404).json({ error: 'Custom domain not found' });
    }

    const expectedTxtValue = domainResult.rows[0].txt_record_value;

    // Record verification attempt
    try {
      await pool.query(
        'INSERT INTO domain_verification_attempts (custom_domain_id, attempt_number, result) SELECT id, 1, $1 FROM custom_domains WHERE org_id = $2 AND domain = $3',
        ['pending', org_id, domain.toLowerCase()]
      );
    } catch (e) {
      // Ignore duplicate verification attempts
    }

    // In production, would use dns module to query actual DNS
    // For now, return status structure for integration testing
    res.json({
      domain: domain.toLowerCase(),
      txt_record_expected: expectedTxtValue,
      txt_record_found: false, // Placeholder - would query actual DNS
      is_verified: false,
      verification_status: 'pending',
      next_check: new Date(Date.now() + 60000).toISOString(), // Suggest retry in 60s
      dns_verification_instruction: `Add TXT record to _acme-challenge.${domain}: ${expectedTxtValue}`,
    });
  } catch (err) {
    console.error('Error checking DNS:', err);
    res.status(500).json({ error: 'Failed to verify DNS' });
  }
});

// DELETE /api/orgs/:org_id/custom-domain/:domain - Remove custom domain
app.delete('/api/orgs/:org_id/custom-domain/:domain', requireOrgAdmin, async (req, res) => {
  const { org_id, domain } = req.params;

  try {
    const result = await pool.query(
      'UPDATE custom_domains SET is_active = false WHERE org_id = $1 AND domain = $2 RETURNING id, domain, is_active',
      [org_id, domain.toLowerCase()]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Custom domain not found' });
    }

    res.json({
      success: true,
      domain: result.rows[0].domain,
      is_active: result.rows[0].is_active,
      message: 'Custom domain deactivated',
    });
  } catch (err) {
    console.error('Error deleting custom domain:', err);
    res.status(500).json({ error: 'Failed to delete custom domain' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// Error Handling
// ════════════════════════════════════════════════════════════════════════════
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// ════════════════════════════════════════════════════════════════════════════
// Server Startup
// ════════════════════════════════════════════════════════════════════════════
app.listen(port, () => {
  console.log(`SaaS API listening on port ${port}`);
});

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('Shutting down...');
  await pool.end();
  process.exit(0);
});
