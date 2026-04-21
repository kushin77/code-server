// @file        apps/session-broker/src/services/kubernetes-oidc/__tests__/kubernetes-oidc.test.ts
// @module      identity/kubernetes
// @description Test suite for Kubernetes OIDC service and workload identity

import { describe, it, expect, beforeEach } from 'vitest';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { KubernetesOIDCService } from '../kubernetes-oidc';

describe('KubernetesOIDCService', () => {
  let service: KubernetesOIDCService;
  let publicKeyPEM: string;
  let privateKeyPEM: string;

  beforeEach(() => {
    // Generate test key pair
    const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
      modulusLength: 2048,
    });

    publicKeyPEM = publicKey.export({ type: 'spki', format: 'pem' }) as string;
    privateKeyPEM = privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;

    service = new KubernetesOIDCService({
      enabled: true,
      issuerURL: 'https://ide.kushnir.cloud/oidc',
      keyID: 'test-key-id',
      publicKeyPEM,
      privateKeyPEM,
      jwsAlgorithm: 'RS256',
      tokenExpiration: 3600,
      supportedAudiences: ['kubernetes', 'api', 'github-actions'],
    });
  });

  describe('Discovery Endpoint', () => {
    it('should return OpenID Connect discovery document', () => {
      const doc = service.getDiscoveryDocument();

      expect(doc).toMatchObject({
        issuer: 'https://ide.kushnir.cloud/oidc',
        authorization_endpoint: expect.any(String),
        token_endpoint: expect.any(String),
        jwks_uri: expect.any(String),
      });

      expect(doc.id_token_signing_alg_values_supported).toContain('RS256');
      expect(doc.claims_supported).toContain('kubernetes.io/namespace');
      expect(doc.claims_supported).toContain('kubernetes.io/serviceaccount/name');
    });

    it('should include Kubernetes-specific claims in supported claims', () => {
      const doc = service.getDiscoveryDocument();

      const k8sClaimsRequired = [
        'kubernetes.io/namespace',
        'kubernetes.io/serviceaccount/name',
        'kubernetes.io/serviceaccount/uid',
      ];

      k8sClaimsRequired.forEach(claim => {
        expect(doc.claims_supported).toContain(claim);
      });
    });
  });

  describe('JWKS Endpoint', () => {
    it('should return JWKS with public key', () => {
      const jwks = service.getJWKSEndpoint();

      expect(jwks).toHaveProperty('keys');
      expect(jwks.keys).toHaveLength(1);
      expect(jwks.keys[0]).toMatchObject({
        kty: 'RSA',
        use: 'sig',
        kid: 'test-key-id',
        alg: 'RS256',
      });
    });

    it('should mark key for signature verification', () => {
      const jwks = service.getJWKSEndpoint();
      expect(jwks.keys[0].use).toBe('sig');
    });
  });

  describe('ServiceAccount Token Generation', () => {
    it('should generate valid JWT token for ServiceAccount', async () => {
      const token = await service.generateServiceAccountToken(
        'default',
        'my-app-sa',
        'uid-123',
        'kubernetes',
      );

      expect(token).toHaveProperty('token');
      expect(token).toHaveProperty('expiresIn', 3600);
      expect(token.audience).toBe('kubernetes');

      // Verify token structure
      const parts = token.token.split('.');
      expect(parts).toHaveLength(3); // header.payload.signature
    });

    it('should include Kubernetes claims in token payload', async () => {
      const token = await service.generateServiceAccountToken(
        'production',
        'billing-service',
        'uid-456',
        'api',
      );

      // Decode without verification to inspect claims
      const decoded = jwt.decode(token.token) as any;

      expect(decoded).toMatchObject({
        'kubernetes.io/namespace': 'production',
        'kubernetes.io/serviceaccount/name': 'billing-service',
        'kubernetes.io/serviceaccount/uid': 'uid-456',
      });
    });

    it('should include pod identity when provided', async () => {
      const token = await service.generateServiceAccountToken(
        'default',
        'app-sa',
        'uid-789',
        'kubernetes',
        'app-pod-1',
        'pod-uid-001',
      );

      const decoded = jwt.decode(token.token) as any;

      expect(decoded['kubernetes.io/pod/name']).toBe('app-pod-1');
      expect(decoded['kubernetes.io/pod/uid']).toBe('pod-uid-001');
    });

    it('should set correct token expiration', async () => {
      const now = Math.floor(Date.now() / 1000);
      const token = await service.generateServiceAccountToken(
        'default',
        'test-sa',
        'uid-000',
        'kubernetes',
      );

      const decoded = jwt.decode(token.token) as any;

      expect(decoded.exp).toBeGreaterThanOrEqual(now + 3600);
      expect(decoded.exp).toBeLessThanOrEqual(now + 3601);
    });

    it('should reject unsupported audience', async () => {
      await expect(
        service.generateServiceAccountToken(
          'default',
          'test-sa',
          'uid-000',
          'unsupported-audience',
        ),
      ).rejects.toThrow(/not supported/);
    });

    it('should generate unique tokens on each call', async () => {
      const token1 = await service.generateServiceAccountToken(
        'default',
        'test-sa',
        'uid-000',
        'kubernetes',
      );

      const token2 = await service.generateServiceAccountToken(
        'default',
        'test-sa',
        'uid-000',
        'kubernetes',
      );

      // Tokens should be different (different iat timestamps)
      expect(token1.token).not.toBe(token2.token);
    });
  });

  describe('Token Verification', () => {
    it('should verify valid token', async () => {
      const generated = await service.generateServiceAccountToken(
        'default',
        'test-sa',
        'uid-123',
        'kubernetes',
      );

      const verified = await service.verifyToken(generated.token);

      expect(verified).toMatchObject({
        'kubernetes.io/namespace': 'default',
        'kubernetes.io/serviceaccount/name': 'test-sa',
        'kubernetes.io/serviceaccount/uid': 'uid-123',
      });
    });

    it('should reject invalid token', async () => {
      const invalidToken = 'invalid.token.here';

      await expect(service.verifyToken(invalidToken)).rejects.toThrow();
    });

    it('should reject malformed token', async () => {
      const malformed = jwt.sign({ test: 'claim' }, privateKeyPEM, {
        algorithm: 'RS256',
        key: privateKeyPEM,
      });

      await expect(service.verifyToken(malformed)).rejects.toThrow();
    });

    it('should enforce token expiration', async () => {
      const expiredService = new KubernetesOIDCService({
        enabled: true,
        issuerURL: 'https://ide.kushnir.cloud/oidc',
        keyID: 'test-key-id',
        publicKeyPEM,
        privateKeyPEM,
        jwsAlgorithm: 'RS256',
        tokenExpiration: -1, // Expired
        supportedAudiences: ['kubernetes'],
      });

      const expiredToken = await expiredService.generateServiceAccountToken(
        'default',
        'test-sa',
        'uid-000',
        'kubernetes',
      );

      await expect(service.verifyToken(expiredToken.token)).rejects.toThrow();
    });
  });

  describe('Namespace Isolation', () => {
    it('should generate different tokens for different namespaces', async () => {
      const token1 = await service.generateServiceAccountToken(
        'default',
        'test-sa',
        'uid-000',
        'kubernetes',
      );

      const token2 = await service.generateServiceAccountToken(
        'production',
        'test-sa',
        'uid-000',
        'kubernetes',
      );

      const decoded1 = jwt.decode(token1.token) as any;
      const decoded2 = jwt.decode(token2.token) as any;

      expect(decoded1['kubernetes.io/namespace']).toBe('default');
      expect(decoded2['kubernetes.io/namespace']).toBe('production');
    });

    it('should enforce namespace in verification', async () => {
      const token = await service.generateServiceAccountToken(
        'default',
        'test-sa',
        'uid-123',
        'kubernetes',
      );

      const verified = await service.verifyToken(token.token);
      expect(verified['kubernetes.io/namespace']).toBe('default');
    });
  });

  describe('Multi-Audience Support', () => {
    it('should generate tokens for different audiences', async () => {
      const audiences = ['kubernetes', 'api', 'github-actions'];

      for (const audience of audiences) {
        const token = await service.generateServiceAccountToken(
          'default',
          'test-sa',
          'uid-000',
          audience,
        );

        const decoded = jwt.decode(token.token) as any;
        expect(decoded.aud).toBe(audience);
      }
    });

    it('should include issuer in token', async () => {
      const token = await service.generateServiceAccountToken(
        'default',
        'test-sa',
        'uid-000',
        'kubernetes',
      );

      const decoded = jwt.decode(token.token) as any;
      expect(decoded.iss).toBe('https://ide.kushnir.cloud/oidc');
    });
  });

  describe('Service Account Subject', () => {
    it('should use Kubernetes standard subject format', async () => {
      const token = await service.generateServiceAccountToken(
        'production',
        'my-service',
        'uid-999',
        'kubernetes',
      );

      const decoded = jwt.decode(token.token) as any;
      expect(decoded.sub).toBe('system:serviceaccount:production:my-service');
    });
  });
});
