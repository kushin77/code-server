#!/usr/bin/env node
// @file        scripts/k8s/workload-identity-token-client.ts
// @module      kubernetes/workload-identity
// @description Client library for Kubernetes workloads to acquire JWT tokens from OIDC issuer

import https from 'https';
import fs from 'fs';
import path from 'path';

/**
 * Kubernetes workload identity token request configuration
 * Reads from projected volumes mounted by Kubernetes
 */
interface WorkloadIdentityConfig {
  tokenPath: string;
  caPath: string;
  namespace: string;
  serviceAccount: string;
  issuerURL: string;
  audience: string;
}

/**
 * JWT token response from OIDC issuer
 */
interface TokenResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
  issued_at: number;
}

/**
 * WorkloadIdentityClient acquires JWT tokens for service-to-service authentication
 */
export class WorkloadIdentityClient {
  private config: WorkloadIdentityConfig;
  private tokenCache: { token: string; expiresAt: number } | null = null;

  constructor(config?: Partial<WorkloadIdentityConfig>) {
    // Read from projected volumes (standard Kubernetes ServiceAccount mounting)
    this.config = {
      tokenPath: config?.tokenPath || '/var/run/secrets/kubernetes.io/serviceaccount/token',
      caPath: config?.caPath || '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
      namespace: config?.namespace || this.readProjectedValue('/var/run/secrets/kubernetes.io/serviceaccount/namespace'),
      serviceAccount: config?.serviceAccount || this.readProjectedValue('/var/run/secrets/kubernetes.io/serviceaccount/namespace').split('/')[1] || 'default',
      issuerURL: config?.issuerURL || process.env.OIDC_ISSUER_URL || 'https://oidc.kushnir.cloud',
      audience: config?.audience || process.env.OIDC_AUDIENCE || 'code-server,api,kubernetes',
    };

    // Validate required files exist
    if (!fs.existsSync(this.config.tokenPath)) {
      throw new Error(`ServiceAccount token not found at ${this.config.tokenPath}`);
    }
    if (!fs.existsSync(this.config.caPath)) {
      throw new Error(`CA certificate not found at ${this.config.caPath}`);
    }
  }

  /**
   * Read projected volume value (e.g., namespace from mounted file)
   */
  private readProjectedValue(filePath: string): string {
    try {
      return fs.readFileSync(filePath, 'utf-8').trim();
    } catch (error) {
      console.warn(`Failed to read projected value from ${filePath}:`, error);
      return '';
    }
  }

  /**
   * Read Kubernetes ServiceAccount token from projected volume
   */
  private getServiceAccountToken(): string {
    return fs.readFileSync(this.config.tokenPath, 'utf-8').trim();
  }

  /**
   * Request JWT token from OIDC issuer
   * Token is requested using Kubernetes ServiceAccount identity
   */
  async requestToken(): Promise<string> {
    // Return cached token if still valid
    if (this.tokenCache && this.tokenCache.expiresAt > Date.now() + 60000) {
      return this.tokenCache.token;
    }

    const serviceAccountToken = this.getServiceAccountToken();
    const url = new URL(`${this.config.issuerURL}/oauth2/token`);

    const params = new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange',
      subject_token: serviceAccountToken,
      subject_token_type: 'urn:ietf:params:oauth:token-type:kubernetes-sa',
      audience: this.config.audience,
      requested_token_use: 'access',
    });

    return new Promise((resolve, reject) => {
      const options = {
        hostname: url.hostname,
        port: url.port || 443,
        path: url.pathname + url.search,
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(params.toString()),
          Authorization: `Bearer ${serviceAccountToken}`,
        },
        ca: fs.readFileSync(this.config.caPath),
      };

      const req = https.request(options, (res) => {
        let data = '';

        res.on('data', (chunk) => {
          data += chunk;
        });

        res.on('end', () => {
          if (res.statusCode !== 200) {
            reject(new Error(`Token request failed: ${res.statusCode} ${data}`));
            return;
          }

          try {
            const response: TokenResponse = JSON.parse(data);
            const expiresAt = Date.now() + response.expires_in * 1000;

            // Cache token for reuse (with 1-minute safety margin)
            this.tokenCache = {
              token: response.access_token,
              expiresAt: expiresAt - 60000,
            };

            resolve(response.access_token);
          } catch (error) {
            reject(new Error(`Failed to parse token response: ${error}`));
          }
        });
      });

      req.on('error', (error) => {
        reject(new Error(`Token request error: ${error.message}`));
      });

      req.write(params.toString());
      req.end();
    });
  }

  /**
   * Get authorization header with JWT token for API requests
   */
  async getAuthorizationHeader(): Promise<string> {
    const token = await this.requestToken();
    return `Bearer ${token}`;
  }

  /**
   * Decode JWT token (without verification - use in trusted environment only)
   */
  decodeToken(token: string): { header: Record<string, any>; payload: Record<string, any> } {
    const parts = token.split('.');
    if (parts.length !== 3) {
      throw new Error('Invalid token format');
    }

    const header = JSON.parse(Buffer.from(parts[0], 'base64').toString());
    const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString());

    return { header, payload };
  }

  /**
   * Check if token is expired
   */
  isTokenExpired(token: string): boolean {
    try {
      const { payload } = this.decodeToken(token);
      const expiresAt = payload.exp * 1000;
      return Date.now() >= expiresAt;
    } catch (error) {
      return true;
    }
  }
}

/**
 * Global singleton instance for convenience
 */
let globalClient: WorkloadIdentityClient | null = null;

/**
 * Get or create global WorkloadIdentityClient instance
 */
export function getWorkloadIdentityClient(config?: Partial<WorkloadIdentityConfig>): WorkloadIdentityClient {
  if (!globalClient) {
    globalClient = new WorkloadIdentityClient(config);
  }
  return globalClient;
}

/**
 * Request JWT token using global client
 */
export async function requestWorkloadToken(): Promise<string> {
  return getWorkloadIdentityClient().requestToken();
}

/**
 * Example usage
 */
if (require.main === module) {
  (async () => {
    try {
      const client = new WorkloadIdentityClient();
      console.log('Requesting workload identity token...');
      const token = await client.requestToken();
      console.log('Token received:', token.substring(0, 50) + '...');

      const decoded = client.decodeToken(token);
      console.log('Token claims:', JSON.stringify(decoded.payload, null, 2));
    } catch (error) {
      console.error('Error:', error);
      process.exit(1);
    }
  })();
}
