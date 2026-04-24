/**
 * @file        apps/api/src/services/custom-domain.service.ts
 * @module      api/services
 * @description Service layer for custom domain management and DNS verification
 * 
 * Handles:
 * - Domain validation (FQDN format, DNS lookup)
 * - TXT record generation and verification
 * - DNS lookups via public resolvers (Cloudflare, Google)
 * - Caddy Admin API integration for dynamic routing
 * - Certificate status tracking
 */

import * as dns from 'dns';
import * as validator from 'validator';
import * as crypto from 'crypto';
import axios from 'axios';

// ════════════════════════════════════════════════════════════════════════════
// Configuration
// ════════════════════════════════════════════════════════════════════════════

const CADDY_ADMIN_URL = process.env.CADDY_ADMIN_URL || 'http://localhost:2019';
const DNS_RESOLVER_CLOUDFLARE = '1.1.1.1';
const DNS_RESOLVER_GOOGLE = '8.8.8.8';
const DNS_LOOKUP_TIMEOUT = 5000; // 5 seconds

// ════════════════════════════════════════════════════════════════════════════
// Types
// ════════════════════════════════════════════════════════════════════════════

interface DnsVerificationResult {
  found: boolean;
  error?: string;
  records?: string[];
}

interface CaddyConfigUpdate {
  domain: string;
  org_id: number;
}

// ════════════════════════════════════════════════════════════════════════════
// Domain Validation
// ════════════════════════════════════════════════════════════════════════════

/**
 * Validate domain format (basic FQDN validation)
 * 
 * @param domain Domain name to validate
 * @returns true if valid FQDN format
 */
export function validateDomain(domain: string): boolean {
  if (!domain || typeof domain !== 'string') {
    return false;
  }

  // Check FQDN format
  if (!validator.isFQDN(domain, { require_tld: true })) {
    return false;
  }

  // Reject certain reserved domains
  const reserved = [
    'localhost',
    'local',
    'example.com',
    'test.com',
    '127.0.0.1',
    'kushnir.cloud', // Cannot register our own domain
    'ide.kushnir.cloud',
  ];

  if (reserved.includes(domain.toLowerCase())) {
    return false;
  }

  // Length checks
  if (domain.length < 4 || domain.length > 255) {
    return false;
  }

  return true;
}

// ════════════════════════════════════════════════════════════════════════════
// TXT Record Generation
// ════════════════════════════════════════════════════════════════════════════

/**
 * Generate unique TXT record for DNS ownership verification
 * 
 * Format: p1675_<16 random hex chars>
 * Example: p1675_a7c9e2b4f1d3e6c8
 * 
 * @returns TXT record value
 */
export function generateTxtRecord(): string {
  const randomBytes = crypto.randomBytes(8).toString('hex');
  return `p1675_${randomBytes}`;
}

// ════════════════════════════════════════════════════════════════════════════
// DNS Verification
// ════════════════════════════════════════════════════════════════════════════

/**
 * Verify DNS TXT record exists (Cloudflare DNS API or direct lookup)
 * 
 * Tries multiple DNS resolvers (Cloudflare -> Google -> system resolver)
 * 
 * @param domain Domain to check
 * @param expectedTxtValue Expected TXT record value
 * @returns DnsVerificationResult with found status and error details
 */
export async function verifyDnsRecord(
  domain: string,
  expectedTxtValue: string
): Promise<DnsVerificationResult> {
  try {
    // Try Cloudflare DNS API first (fastest, most reliable)
    try {
      const cfResult = await verifyViaDnsApi(domain, expectedTxtValue);
      return cfResult;
    } catch (error) {
      console.warn('Cloudflare DNS API failed, trying direct lookup:', error);
    }

    // Fallback to direct DNS lookup
    const records = await queryTxtRecordsDirect(domain);
    const found = records.some((record) =>
      record.includes(expectedTxtValue)
    );

    if (found) {
      return { found: true, records };
    }

    return {
      found: false,
      error: `TXT record "${expectedTxtValue}" not found for domain "${domain}"`,
      records,
    };
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    return {
      found: false,
      error: `DNS lookup failed: ${errorMsg}`,
    };
  }
}

/**
 * Verify DNS via Cloudflare DNS API (preferred method)
 * 
 * @param domain Domain to check
 * @param expectedTxtValue TXT record to find
 * @returns Verification result
 */
async function verifyViaDnsApi(
  domain: string,
  expectedTxtValue: string
): Promise<DnsVerificationResult> {
  const response = await axios.get(
    `https://cloudflare-dns.com/dns-query?name=${domain}&type=TXT`,
    {
      headers: { Accept: 'application/dns-json' },
      timeout: DNS_LOOKUP_TIMEOUT,
    }
  );

  const answers = response.data.Answer || [];
  const txtRecords = answers
    .filter((a: any) => a.type === 16) // TXT record type
    .map((a: any) => a.data);

  const found = txtRecords.some((record: string) =>
    record.includes(expectedTxtValue)
  );

  return {
    found,
    records: txtRecords,
  };
}

/**
 * Query TXT records directly via system DNS resolver
 * 
 * @param domain Domain to query
 * @returns Array of TXT records
 */
async function queryTxtRecordsDirect(domain: string): Promise<string[]> {
  return new Promise((resolve, reject) => {
    const resolver = new dns.Resolver();
    resolver.setServers([DNS_RESOLVER_CLOUDFLARE, DNS_RESOLVER_GOOGLE]);

    resolver.resolveTxt(domain, (err, records) => {
      if (err) {
        reject(err);
      } else {
        resolve(records.map((r) => r.join('')));
      }
    });

    // Set timeout
    setTimeout(() => {
      reject(new Error(`DNS lookup timeout for ${domain}`));
    }, DNS_LOOKUP_TIMEOUT);
  });
}

// ════════════════════════════════════════════════════════════════════════════
// Caddy Integration
// ════════════════════════════════════════════════════════════════════════════

/**
 * Get Caddy Admin API client
 * 
 * @returns Caddy client with add/remove domain methods
 */
export function getCaddyClient() {
  return {
    /**
     * Add custom domain to Caddy configuration
     * 
     * Dynamically updates Caddyfile to route custom domain to org-scoped Appsmith instance
     * 
     * @param config Domain configuration
     */
    async addCustomDomain(config: CaddyConfigUpdate): Promise<void> {
      try {
        // Build Caddy config snippet for custom domain
        const caddyConfig = {
          [`${config.domain}`]: {
            route: [
              {
                // Add org context header
                handler: 'headers',
                request: {
                  set: {
                    'X-Org-ID': String(config.org_id),
                    'X-Custom-Domain': config.domain,
                  },
                },
              },
              {
                // Proxy to Appsmith (org-scoped)
                handler: 'reverse_proxy',
                upstreams: [
                  {
                    dial: 'appsmith:3000',
                  },
                ],
              },
            ],
          },
        };

        // Update Caddy config via Admin API
        const response = await axios.patch(
          `${CADDY_ADMIN_URL}/config/apps/http/servers/main/routes`,
          [
            {
              match: [{ host: [config.domain] }],
              handle: caddyConfig[config.domain].route,
              terminal: true,
            },
          ],
          { timeout: 10000 }
        );

        if (response.status !== 200) {
          throw new Error(`Caddy update failed: ${response.statusText}`);
        }

        console.log(`✅ Custom domain added to Caddy: ${config.domain}`);
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        throw new Error(`Failed to add custom domain to Caddy: ${msg}`);
      }
    },

    /**
     * Remove custom domain from Caddy configuration
     * 
     * @param config Domain configuration
     */
    async removeCustomDomain(config: CaddyConfigUpdate): Promise<void> {
      try {
        // Query current config
        const response = await axios.get(
          `${CADDY_ADMIN_URL}/config/apps/http/servers/main/routes`,
          { timeout: 10000 }
        );

        // Filter out the custom domain route
        const updatedRoutes = (response.data || []).filter(
          (route: any) =>
            !route.match?.[0]?.host?.includes(config.domain)
        );

        // Update Caddy config
        await axios.patch(
          `${CADDY_ADMIN_URL}/config/apps/http/servers/main/routes`,
          updatedRoutes,
          { timeout: 10000 }
        );

        console.log(`✅ Custom domain removed from Caddy: ${config.domain}`);
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        console.warn(`Failed to remove custom domain from Caddy: ${msg}`);
        // Don't throw - soft failure allowed during deletion
      }
    },
  };
}
