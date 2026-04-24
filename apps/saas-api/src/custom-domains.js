// @file        apps/saas-api/src/custom-domains.js
// @module      saas/custom-domains
// @description Custom domain management API endpoints (Phase 4 #1674)
// IaC: Idempotent REST endpoints, stateless, database-backed

const express = require('express');
const crypto = require('crypto');
const dns = require('dns').promises;

const router = express.Router();

// ════════════════════════════════════════════════════════════════════════════
// Database Pool (injected from parent app)
// ════════════════════════════════════════════════════════════════════════════
let pool;
function setPool(dbPool) {
  pool = dbPool;
}

// ════════════════════════════════════════════════════════════════════════════
// Helper: Generate verification token (idempotent - same input = same token)
// ════════════════════════════════════════════════════════════════════════════
function generateVerificationToken(orgId, domainName) {
  return crypto
    .createHash('sha256')
    .update(`${orgId}:${domainName}:${process.env.DOMAIN_TOKEN_SECRET || 'default'}`)
    .digest('hex');
}

// ════════════════════════════════════════════════════════════════════════════
// Helper: Format DNS TXT record
// ════════════════════════════════════════════════════════════════════════════
function formatDnsTxtRecord(token) {
  return `kushnir-domain-verify=${token}`;
}

// ════════════════════════════════════════════════════════════════════════════
// Helper: Verify DNS TXT record (idempotent - read-only)
// ════════════════════════════════════════════════════════════════════════════
async function verifyDnsTxtRecord(domainName, expectedToken) {
  try {
    const records = await dns.resolveTxt(domainName);
    const flatRecords = records.flat().join('');
    return flatRecords.includes(`kushnir-domain-verify=${expectedToken}`);
  } catch (err) {
    console.error(`DNS verification failed for ${domainName}:`, err.message);
    return false;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Middleware: Require org admin access
// ════════════════════════════════════════════════════════════════════════════
async function requireOrgAdmin(req, res, next) {
  const orgId = req.params.org_id || req.body.org_id;
  const userEmail = req.user?.email;

  if (!orgId || !userEmail) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const result = await pool.query(
      'SELECT role FROM memberships WHERE org_id = $1 AND user_id = (SELECT id FROM users WHERE email = $2)',
      [orgId, userEmail]
    );

    const membership = result.rows[0];
    if (!membership || membership.role !== 'admin') {
      return res.status(403).json({ error: 'Forbidden - Admin access required' });
    }

    req.orgId = orgId;
    next();
  } catch (err) {
    console.error('Auth check failed:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
}

// ════════════════════════════════════════════════════════════════════════════
// POST /api/domains — Add custom domain (org admin)
// Idempotent: Returns same token for same org+domain
// ════════════════════════════════════════════════════════════════════════════
router.post('/domains', requireOrgAdmin, async (req, res) => {
  const { domain_name } = req.body;
  const orgId = req.orgId;

  if (!domain_name) {
    return res.status(400).json({ error: 'domain_name is required' });
  }

  // Validate domain format
  const domainRegex = /^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/i;
  if (!domainRegex.test(domain_name)) {
    return res.status(400).json({ error: 'Invalid domain format' });
  }

  try {
    // Generate verification token (idempotent)
    const token = generateVerificationToken(orgId, domain_name);
    const dnsTxt = formatDnsTxtRecord(token);

    // Check if domain already exists
    const existing = await pool.query(
      'SELECT id FROM custom_domains WHERE org_id = $1 AND domain_name = $2 AND deleted_at IS NULL',
      [orgId, domain_name]
    );

    if (existing.rows.length > 0) {
      return res.status(409).json({ 
        error: 'Domain already registered',
        id: existing.rows[0].id,
        message: 'Use GET /api/domains/{id} to check status'
      });
    }

    // Insert new domain (idempotent due to UNIQUE constraint)
    const result = await pool.query(
      `INSERT INTO custom_domains 
       (org_id, domain_name, verification_token, dns_txt_record, status)
       VALUES ($1, $2, $3, $4, 'pending')
       RETURNING id, domain_name, verification_token, dns_txt_record, status, created_at`,
      [orgId, domain_name, token, dnsTxt]
    );

    const domain = result.rows[0];
    res.status(201).json({
      id: domain.id,
      domain_name: domain.domain_name,
      status: domain.status,
      verification_required: {
        record_type: 'TXT',
        name: `_verification.${domain_name}`,
        value: domain.dns_txt_record,
        instructions: 'Add this TXT record to your domain registrar, then call POST /api/domains/{id}/verify'
      },
      created_at: domain.created_at
    });
  } catch (err) {
    console.error('Error creating domain:', err);
    res.status(500).json({ error: 'Failed to create domain' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// GET /api/domains/{org_id} — List org domains (idempotent read-only)
// ════════════════════════════════════════════════════════════════════════════
router.get('/domains/:org_id', requireOrgAdmin, async (req, res) => {
  const orgId = req.params.org_id;

  try {
    const result = await pool.query(
      `SELECT id, domain_name, status, is_verified, verified_at, tls_cert_expiry, created_at
       FROM custom_domains
       WHERE org_id = $1 AND deleted_at IS NULL
       ORDER BY created_at DESC`,
      [orgId]
    );

    res.json(result.rows);
  } catch (err) {
    console.error('Error listing domains:', err);
    res.status(500).json({ error: 'Failed to list domains' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// POST /api/domains/{id}/verify — Verify DNS TXT record (idempotent)
// Idempotent: Multiple calls return same result if DNS already verified
// ════════════════════════════════════════════════════════════════════════════
router.post('/domains/:domain_id/verify', async (req, res) => {
  const domainId = req.params.domain_id;

  try {
    // Fetch domain
    const domainResult = await pool.query(
      'SELECT * FROM custom_domains WHERE id = $1',
      [domainId]
    );

    if (!domainResult.rows.length) {
      return res.status(404).json({ error: 'Domain not found' });
    }

    const domain = domainResult.rows[0];

    // If already verified, return success (idempotent)
    if (domain.is_verified) {
      return res.json({
        status: 'already_verified',
        verified_at: domain.verified_at,
        message: 'Domain was previously verified'
      });
    }

    // Check DNS TXT record
    const isValid = await verifyDnsTxtRecord(domain.domain_name, domain.verification_token);

    if (!isValid) {
      // Log failed attempt but don't fail
      await pool.query(
        `INSERT INTO domain_verification_events (domain_id, event_type, event_data)
         VALUES ($1, 'verification_failed', jsonb_build_object('attempted_at', NOW()))`,
        [domainId]
      );

      return res.status(400).json({
        error: 'DNS verification failed',
        message: `TXT record not found: ${domain.dns_txt_record}`,
        instructions: 'Ensure DNS record is propagated and try again'
      });
    }

    // Update domain as verified (idempotent due to transaction)
    await pool.query(
      `UPDATE custom_domains
       SET is_verified = true, verified_at = NOW(), status = 'verified'
       WHERE id = $1`,
      [domainId]
    );

    res.json({
      status: 'verified',
      domain_name: domain.domain_name,
      message: 'DNS verification successful',
      next_step: 'Next: Wait for TLS provisioning (check status via GET /api/domains/{org_id})'
    });
  } catch (err) {
    console.error('Error verifying domain:', err);
    res.status(500).json({ error: 'Verification failed' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// DELETE /api/domains/{id} — Remove domain (idempotent soft delete)
// ════════════════════════════════════════════════════════════════════════════
router.delete('/domains/:domain_id', async (req, res) => {
  const domainId = req.params.domain_id;

  try {
    const result = await pool.query(
      `UPDATE custom_domains
       SET deleted_at = NOW(), status = 'revoked'
       WHERE id = $1 AND deleted_at IS NULL
       RETURNING id`,
      [domainId]
    );

    if (!result.rows.length) {
      return res.status(404).json({ error: 'Domain not found or already deleted' });
    }

    res.json({
      status: 'deleted',
      id: result.rows[0].id,
      message: 'Domain removed successfully'
    });
  } catch (err) {
    console.error('Error deleting domain:', err);
    res.status(500).json({ error: 'Failed to delete domain' });
  }
});

// ════════════════════════════════════════════════════════════════════════════
// GET /api/domains/{id}/status — Check domain status (idempotent read-only)
// ════════════════════════════════════════════════════════════════════════════
router.get('/domains/:domain_id/status', async (req, res) => {
  const domainId = req.params.domain_id;

  try {
    const result = await pool.query(
      `SELECT id, domain_name, status, is_verified, tls_cert_expiry, error_message, created_at, updated_at
       FROM custom_domains
       WHERE id = $1`,
      [domainId]
    );

    if (!result.rows.length) {
      return res.status(404).json({ error: 'Domain not found' });
    }

    const domain = result.rows[0];
    res.json({
      domain_id: domain.id,
      domain_name: domain.domain_name,
      status: domain.status,
      progress: {
        dns_verified: domain.is_verified,
        tls_provisioned: domain.tls_cert_expiry ? true : false,
        tls_expires: domain.tls_cert_expiry,
        error: domain.error_message
      },
      timestamps: {
        created_at: domain.created_at,
        updated_at: domain.updated_at
      }
    });
  } catch (err) {
    console.error('Error fetching domain status:', err);
    res.status(500).json({ error: 'Failed to fetch status' });
  }
});

module.exports = {
  router,
  setPool
};
