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

app.use(authenticateUser);

// ════════════════════════════════════════════════════════════════════════════
// Health Check
// ════════════════════════════════════════════════════════════════════════════
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'saas-api' });
});

// ════════════════════════════════════════════════════════════════════════════
// Org Management Endpoints
// ════════════════════════════════════════════════════════════════════════════

// GET /api/orgs - List organizations (admin only)
app.get('/api/orgs', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, name, logo_url, description, is_active, created_at FROM organizations WHERE is_active = true ORDER BY created_at DESC'
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching orgs:', err);
    res.status(500).json({ error: 'Failed to fetch organizations' });
  }
});

// POST /api/orgs - Create organization (admin only)
app.post('/api/orgs', async (req, res) => {
  const { name, description, logo_url } = req.body;

  if (!name) {
    return res.status(400).json({ error: 'Organization name is required' });
  }

  try {
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

// GET /api/users - List users (org members)
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

// POST /api/users - Create user (admin only)
app.post('/api/users', async (req, res) => {
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

// GET /api/audit-logs - List audit logs (admin only)
app.get('/api/audit-logs', async (req, res) => {
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
