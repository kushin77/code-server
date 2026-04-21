// @file        apps/session-broker/src/services/kubernetes-oidc/kubernetes-oidc.ts
// @module      identity/kubernetes
// @description Kubernetes ServiceAccount OIDC federation and workload identity integration

import { Router, Request, Response } from 'express';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { logger } from '../../lib/logger';

export interface KubernetesOIDCConfig {
  enabled: boolean;
  issuerURL: string;
  keyID: string;
  publicKeyPEM: string;
  privateKeyPEM: string;
  jwsAlgorithm: 'RS256' | 'ES256';
  tokenExpiration: number; // seconds
  supportedAudiences: string[];
}

export interface KubernetesServiceAccountClaim {
  // Kubernetes-specific claims in JWT
  'kubernetes.io/namespace': string;
  'kubernetes.io/serviceaccount/name': string;
  'kubernetes.io/serviceaccount/uid': string;
  'kubernetes.io/pod/name'?: string;
  'kubernetes.io/pod/uid'?: string;
}

export interface KubernetesOIDCToken {
  token: string;
  expiresIn: number;
  expiresAt: number;
  audience: string;
}

/**
 * Kubernetes OIDC Service
 *
 * Provides OIDC token generation for Kubernetes workloads.
 * Enables ServiceAccounts to acquire JWT tokens for pod-to-API authentication.
 *
 * Features:
 * - Discovery endpoint (.well-known/openid-configuration)
 * - JWKS endpoint for public key distribution
 * - Token endpoint for ServiceAccount token acquisition
 * - Support for pod identity and namespace isolation
 */
export class KubernetesOIDCService {
  private config: KubernetesOIDCConfig;
  private privateKey: crypto.KeyObject;

  constructor(config: KubernetesOIDCConfig) {
    this.config = config;

    // Parse private key for JWT signing
    if (!config.privateKeyPEM) {
      throw new Error('KUBERNETES_OIDC_PRIVATE_KEY_PEM required for JWT signing');
    }

    this.privateKey = crypto.createPrivateKey({
      key: config.privateKeyPEM,
      format: 'pem',
    });

    logger.info('KubernetesOIDCService initialized', {
      issuer: config.issuerURL,
      algorithm: config.jwsAlgorithm,
      audiences: config.supportedAudiences.join(', '),
    });
  }

  /**
   * OpenID Connect Discovery Endpoint
   * Returns metadata about the OIDC provider
   * https://openid.net/specs/openid-connect-discovery-1_0.html
   */
  getDiscoveryDocument() {
    return {
      issuer: this.config.issuerURL,
      authorization_endpoint: `${this.config.issuerURL}/auth`,
      token_endpoint: `${this.config.issuerURL}/token`,
      userinfo_endpoint: `${this.config.issuerURL}/userinfo`,
      jwks_uri: `${this.config.issuerURL}/.well-known/jwks.json`,
      response_types_supported: ['code', 'token'],
      subject_types_supported: ['public'],
      id_token_signing_alg_values_supported: [this.config.jwsAlgorithm],
      token_endpoint_auth_methods_supported: ['client_secret_basic'],
      claims_supported: [
        'sub',
        'iss',
        'aud',
        'exp',
        'iat',
        'kubernetes.io/namespace',
        'kubernetes.io/serviceaccount/name',
        'kubernetes.io/serviceaccount/uid',
        'kubernetes.io/pod/name',
        'kubernetes.io/pod/uid',
      ],
      scopes_supported: ['openid', 'profile', 'email'],
    };
  }

  /**
   * JWKS (JSON Web Key Set) Endpoint
   * Returns public keys for token verification
   */
  getJWKSEndpoint() {
    const publicKey = crypto.createPublicKey({
      key: this.config.publicKeyPEM,
      format: 'pem',
    });

    const keyDetails = publicKey.asymmetricKeyDetails;

    return {
      keys: [
        {
          kty: 'RSA',
          use: 'sig',
          kid: this.config.keyID,
          n: this.extractModulus(publicKey),
          e: 'AQAB', // Standard RSA public exponent
          alg: this.config.jwsAlgorithm,
        },
      ],
    };
  }

  /**
   * Generate JWT token for Kubernetes ServiceAccount
   *
   * @param namespace Kubernetes namespace
   * @param serviceAccountName ServiceAccount name
   * @param serviceAccountUID ServiceAccount UID
   * @param audience Token audience (e.g., 'kubernetes', 'api')
   * @param podName Optional: Pod name (for pod-specific tokens)
   * @param podUID Optional: Pod UID
   */
  async generateServiceAccountToken(
    namespace: string,
    serviceAccountName: string,
    serviceAccountUID: string,
    audience: string,
    podName?: string,
    podUID?: string,
  ): Promise<KubernetesOIDCToken> {
    // Validate audience
    if (!this.config.supportedAudiences.includes(audience)) {
      throw new Error(
        `Audience '${audience}' not supported. Supported: ${this.config.supportedAudiences.join(', ')}`,
      );
    }

    const now = Math.floor(Date.now() / 1000);
    const expiresIn = this.config.tokenExpiration;
    const expiresAt = now + expiresIn;

    const k8sClaims: KubernetesServiceAccountClaim = {
      'kubernetes.io/namespace': namespace,
      'kubernetes.io/serviceaccount/name': serviceAccountName,
      'kubernetes.io/serviceaccount/uid': serviceAccountUID,
    };

    // Include pod identity if provided
    if (podName) {
      k8sClaims['kubernetes.io/pod/name'] = podName;
    }
    if (podUID) {
      k8sClaims['kubernetes.io/pod/uid'] = podUID;
    }

    const payload = {
      iss: this.config.issuerURL,
      sub: `system:serviceaccount:${namespace}:${serviceAccountName}`,
      aud: audience,
      iat: now,
      exp: expiresAt,
      ...k8sClaims,
    };

    const token = jwt.sign(payload, this.privateKey, {
      algorithm: this.config.jwsAlgorithm,
      keyid: this.config.keyID,
    });

    logger.debug('Generated Kubernetes ServiceAccount token', {
      namespace,
      serviceAccountName,
      audience,
      expiresIn,
    });

    return {
      token,
      expiresIn,
      expiresAt,
      audience,
    };
  }

  /**
   * Verify and validate a JWT token
   * Used by API servers to authenticate pod requests
   */
  async verifyToken(token: string): Promise<any> {
    const publicKey = crypto.createPublicKey({
      key: this.config.publicKeyPEM,
      format: 'pem',
    });

    try {
      const decoded = jwt.verify(token, publicKey, {
        algorithms: [this.config.jwsAlgorithm],
      });

      // Validate kubernetes claims exist
      if (!decoded['kubernetes.io/namespace']) {
        throw new Error('Missing kubernetes.io/namespace claim');
      }

      return decoded;
    } catch (error) {
      logger.warn('Token verification failed', {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  /**
   * Extract RSA modulus for JWKS endpoint
   * (used for public key distribution to Kubernetes API servers)
   */
  private extractModulus(publicKey: crypto.KeyObject): string {
    // In production, implement proper JWKS export
    // For now, return placeholder - actual implementation would use
    // publicKey.export({ format: 'jwk' })
    return 'AQAB';
  }
}

/**
 * Create Express router for Kubernetes OIDC endpoints
 */
export function createKubernetesOIDCRouter(service: KubernetesOIDCService): Router {
  const router = Router();

  // Discovery endpoint
  router.get('/.well-known/openid-configuration', (req: Request, res: Response) => {
    res.json(service.getDiscoveryDocument());
  });

  // JWKS endpoint (for public key distribution)
  router.get('/.well-known/jwks.json', (req: Request, res: Response) => {
    res.json(service.getJWKSEndpoint());
  });

  // Token endpoint for ServiceAccount token acquisition
  router.post('/token', async (req: Request, res: Response) => {
    try {
      const {
        grant_type,
        namespace,
        service_account_name,
        service_account_uid,
        audience,
        pod_name,
        pod_uid,
      } = req.body;

      // Validate grant type
      if (grant_type !== 'urn:ietf:params:oauth:grant-type:token-exchange') {
        return res.status(400).json({
          error: 'unsupported_grant_type',
          error_description: 'Only token exchange grant is supported',
        });
      }

      // Validate required fields
      if (!namespace || !service_account_name || !service_account_uid || !audience) {
        return res.status(400).json({
          error: 'invalid_request',
          error_description: 'Missing required parameters',
        });
      }

      const tokenResponse = await service.generateServiceAccountToken(
        namespace,
        service_account_name,
        service_account_uid,
        audience,
        pod_name,
        pod_uid,
      );

      res.json({
        access_token: tokenResponse.token,
        expires_in: tokenResponse.expiresIn,
        token_type: 'Bearer',
      });
    } catch (error) {
      logger.error('Token endpoint error', { error });
      res.status(500).json({
        error: 'server_error',
        error_description: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  });

  return router;
}
