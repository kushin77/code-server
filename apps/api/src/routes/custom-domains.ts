/**
 * @file        apps/api/src/routes/custom-domains.ts
 * @module      api/routes
 * @description Custom domain management API endpoints for whitelabel support
 * 
 * Endpoints for organizations to add custom domains, verify DNS ownership,
 * and manage TLS certificates. All endpoints are org-scoped with RBAC enforcement.
 */

import { Router, Request, Response, NextFunction } from 'express';
import { getRepository } from 'typeorm';
import { CustomDomain, Organization } from '../entities';
import { validateDomain, generateTxtRecord, verifyDnsRecord, getCaddyClient } from '../services/custom-domain.service';
import { requireAuth, requireOrgAdmin } from '../middleware/auth';
import { validateRequestBody } from '../middleware/validation';

const router = Router();

// ════════════════════════════════════════════════════════════════════════════
// Middleware
// ════════════════════════════════════════════════════════════════════════════

// Require authentication for all routes
router.use(requireAuth);

// ════════════════════════════════════════════════════════════════════════════
// Routes
// ════════════════════════════════════════════════════════════════════════════

/**
 * POST /api/orgs/:orgId/custom-domains
 * 
 * Add a custom domain to an organization.
 * Generates verification TXT record (DNS ownership challenge).
 * 
 * @requires OrgAdmin role
 * @param orgId Organization ID
 * @body domain Domain name (e.g., mycompany.com)
 * @returns 201 { id, domain, txt_record_value, is_verified: false }
 */
router.post(
  '/orgs/:orgId/custom-domains',
  requireOrgAdmin,
  validateRequestBody(['domain']),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { orgId } = req.params;
      const { domain } = req.body;

      // Validate domain format
      if (!validateDomain(domain)) {
        return res.status(400).json({
          error: 'invalid_domain',
          message: 'Invalid domain format (must be valid FQDN)',
        });
      }

      // Check organization exists and user has access
      const org = await getRepository(Organization).findOne({
        where: { id: parseInt(orgId) },
      });
      if (!org) {
        return res.status(404).json({ error: 'org_not_found' });
      }

      // Check domain not already registered
      const existing = await getRepository(CustomDomain).findOne({
        where: { domain, deleted_at: null },
      });
      if (existing) {
        return res.status(409).json({
          error: 'domain_already_registered',
          message: `Domain ${domain} is already registered`,
        });
      }

      // Generate verification TXT record
      const txtRecord = generateTxtRecord();

      // Create custom domain record
      const customDomain = getRepository(CustomDomain).create({
        org_id: parseInt(orgId),
        domain,
        txt_record_value: txtRecord,
        is_verified: false,
        tls_certificate_status: 'pending',
      });

      const saved = await getRepository(CustomDomain).save(customDomain);

      res.status(201).json({
        id: saved.id,
        domain: saved.domain,
        txt_record_value: saved.txt_record_value,
        is_verified: false,
        instructions: `Add the following TXT record to your DNS provider:\nHost: ${domain}\nType: TXT\nValue: ${txtRecord}`,
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * GET /api/orgs/:orgId/custom-domains/:domainId/dns-verification
 * 
 * Check DNS verification status for a custom domain.
 * Queries public DNS to verify TXT record exists.
 * 
 * @param orgId Organization ID
 * @param domainId Custom domain ID
 * @returns 200 { is_verified, dns_found, error }
 */
router.get(
  '/orgs/:orgId/custom-domains/:domainId/dns-verification',
  requireOrgAdmin,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { orgId, domainId } = req.params;

      const customDomain = await getRepository(CustomDomain).findOne({
        where: {
          id: parseInt(domainId),
          org_id: parseInt(orgId),
        },
      });

      if (!customDomain) {
        return res.status(404).json({ error: 'domain_not_found' });
      }

      // Skip verification if already verified
      if (customDomain.is_verified) {
        return res.status(200).json({
          is_verified: true,
          dns_found: true,
          message: 'Domain already verified',
          tls_status: customDomain.tls_certificate_status,
        });
      }

      // Query DNS for TXT record
      const dnsResult = await verifyDnsRecord(
        customDomain.domain,
        customDomain.txt_record_value
      );

      if (dnsResult.found) {
        // Mark as verified and trigger Caddy config update
        customDomain.is_verified = true;
        customDomain.tls_certificate_status = 'provisioning';
        await getRepository(CustomDomain).save(customDomain);

        // Update Caddy with new domain
        try {
          await getCaddyClient().addCustomDomain({
            domain: customDomain.domain,
            org_id: customDomain.org_id,
          });
        } catch (error) {
          console.error('Failed to update Caddy config:', error);
          // Don't fail the response, but mark status as error
          customDomain.tls_certificate_status = 'error';
          await getRepository(CustomDomain).save(customDomain);
        }
      }

      res.status(200).json({
        is_verified: customDomain.is_verified,
        dns_found: dnsResult.found,
        error: dnsResult.error || null,
        tls_status: customDomain.tls_certificate_status,
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * GET /api/orgs/:orgId/custom-domains
 * 
 * List all custom domains for an organization.
 * 
 * @param orgId Organization ID
 * @returns 200 Array of custom domain objects
 */
router.get(
  '/orgs/:orgId/custom-domains',
  requireOrgAdmin,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { orgId } = req.params;

      const domains = await getRepository(CustomDomain).find({
        where: {
          org_id: parseInt(orgId),
          deleted_at: null,
        },
        order: { created_at: 'DESC' },
      });

      res.status(200).json({
        domains: domains.map((d) => ({
          id: d.id,
          domain: d.domain,
          is_verified: d.is_verified,
          tls_status: d.tls_certificate_status,
          tls_expires_at: d.tls_expires_at,
          created_at: d.created_at,
        })),
      });
    } catch (error) {
      next(error);
    }
  }
);

/**
 * DELETE /api/orgs/:orgId/custom-domains/:domainId
 * 
 * Deactivate a custom domain (soft delete).
 * Removes from Caddy routing.
 * 
 * @param orgId Organization ID
 * @param domainId Custom domain ID
 * @returns 204 No content
 */
router.delete(
  '/orgs/:orgId/custom-domains/:domainId',
  requireOrgAdmin,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { orgId, domainId } = req.params;

      const customDomain = await getRepository(CustomDomain).findOne({
        where: {
          id: parseInt(domainId),
          org_id: parseInt(orgId),
        },
      });

      if (!customDomain) {
        return res.status(404).json({ error: 'domain_not_found' });
      }

      // Remove from Caddy
      try {
        await getCaddyClient().removeCustomDomain({
          domain: customDomain.domain,
          org_id: customDomain.org_id,
        });
      } catch (error) {
        console.error('Failed to remove from Caddy:', error);
        // Continue with soft delete even if Caddy fails
      }

      // Soft delete
      customDomain.deleted_at = new Date();
      await getRepository(CustomDomain).save(customDomain);

      res.status(204).send();
    } catch (error) {
      next(error);
    }
  }
);

export default router;
