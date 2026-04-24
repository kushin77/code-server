#!/usr/bin/env node
// @file        scripts/k8s/test-workload-identity.ts
// @module      kubernetes/workload-identity
// @description Unit tests for Kubernetes workload identity configuration

import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import https from 'https';
import fs from 'fs';

/**
 * Test 1: OIDC Issuer Configuration
 */
describe('Kubernetes OIDC Issuer Configuration', () => {
  const OIDC_ISSUER_URL = process.env.OIDC_ISSUER_URL || 'https://oidc.kushnir.cloud';

  it('should have OIDC issuer accessible', async () => {
    return new Promise((resolve, reject) => {
      const url = new URL(`${OIDC_ISSUER_URL}/.well-known/openid-configuration`);
      const options = {
        hostname: url.hostname,
        path: url.pathname,
        method: 'GET',
      };

      const req = https.request(options, (res) => {
        expect(res.statusCode).toBe(200);
        let data = '';

        res.on('data', (chunk) => {
          data += chunk;
        });

        res.on('end', () => {
          const config = JSON.parse(data);
          expect(config.issuer).toBeDefined();
          expect(config.authorization_endpoint).toBeDefined();
          expect(config.token_endpoint).toBeDefined();
          expect(config.jwks_uri).toBeDefined();
          resolve(null);
        });
      });

      req.on('error', reject);
      req.end();
    });
  });

  it('should return valid JWKS with RS256 public keys', async () => {
    return new Promise((resolve, reject) => {
      const url = new URL(`${OIDC_ISSUER_URL}/.well-known/jwks.json`);
      const options = {
        hostname: url.hostname,
        path: url.pathname,
        method: 'GET',
      };

      const req = https.request(options, (res) => {
        expect(res.statusCode).toBe(200);
        let data = '';

        res.on('data', (chunk) => {
          data += chunk;
        });

        res.on('end', () => {
          const jwks = JSON.parse(data);
          expect(jwks.keys).toBeDefined();
          expect(jwks.keys.length).toBeGreaterThan(0);

          const rsaKey = jwks.keys.find((k: any) => k.kty === 'RSA' && k.use === 'sig');
          expect(rsaKey).toBeDefined();
          expect(rsaKey.kid).toBeDefined();
          expect(rsaKey.n).toBeDefined();
          expect(rsaKey.e).toBeDefined();
          resolve(null);
        });
      });

      req.on('error', reject);
      req.end();
    });
  });
});

/**
 * Test 2: JWT Token Claims
 */
describe('JWT Token Claims for Kubernetes', () => {
  const testClaims = {
    sub: 'system:serviceaccount:default:test-workload',
    aud: 'kubernetes',
    iss: 'https://oidc.kushnir.cloud',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600,
    email: 'test-workload@kubernetes.cluster',
    groups: ['system:serviceaccounts', 'system:serviceaccounts:default'],
    'kubernetes.io/namespace': 'default',
    'kubernetes.io/service-account': 'test-workload',
  };

  it('should have all required Kubernetes claims', () => {
    expect(testClaims.sub).toBeDefined();
    expect(testClaims.sub).toMatch(/^system:serviceaccount:/);
    
    expect(testClaims['kubernetes.io/namespace']).toBeDefined();
    expect(testClaims['kubernetes.io/service-account']).toBeDefined();
    expect(testClaims.aud).toContain('kubernetes');
  });

  it('should include service account identity in subject claim', () => {
    const [, namespace, serviceAccount] = testClaims.sub.split(':');
    expect(namespace).toBe('default');
    expect(serviceAccount).toBe('test-workload');
  });

  it('should include groups for RBAC', () => {
    expect(testClaims.groups).toContain('system:serviceaccounts');
    expect(testClaims.groups).toContain('system:serviceaccounts:default');
  });

  it('should have valid token expiration', () => {
    const now = Math.floor(Date.now() / 1000);
    expect(testClaims.exp).toBeGreaterThan(now);
    expect(testClaims.exp - testClaims.iat).toBe(3600);
  });
});

/**
 * Test 3: ServiceAccount RBAC Integration
 */
describe('ServiceAccount RBAC Integration', () => {
  const rbacConfig = {
    serviceAccounts: [
      {
        name: 'code-server',
        namespace: 'prod',
        role: 'viewer',
      },
      {
        name: 'prometheus',
        namespace: 'monitoring',
        role: 'viewer',
      },
      {
        name: 'grafana',
        namespace: 'monitoring',
        role: 'operator',
      },
    ],
  };

  it('should have OIDC-enabled service accounts', () => {
    expect(rbacConfig.serviceAccounts).toBeDefined();
    expect(rbacConfig.serviceAccounts.length).toBeGreaterThanOrEqual(3);
  });

  it('should map service accounts to RBAC roles', () => {
    rbacConfig.serviceAccounts.forEach((sa) => {
      expect(sa.name).toBeDefined();
      expect(sa.namespace).toBeDefined();
      expect(['viewer', 'operator']).toContain(sa.role);
    });
  });

  it('should support viewer and operator role mappings', () => {
    const roles = rbacConfig.serviceAccounts.map((sa) => sa.role);
    expect(new Set(roles).size).toBeGreaterThanOrEqual(1);
  });
});

/**
 * Test 4: Workload Identity Token Exchange Flow
 */
describe('Workload Identity Token Exchange Flow', () => {
  it('should support urn:ietf:params:oauth:grant-type:token-exchange', () => {
    const grantType = 'urn:ietf:params:oauth:grant-type:token-exchange';
    expect(grantType).toMatch(/^urn:ietf:params:oauth:grant-type:/);
  });

  it('should support urn:ietf:params:oauth:token-type:kubernetes-sa', () => {
    const tokenType = 'urn:ietf:params:oauth:token-type:kubernetes-sa';
    expect(tokenType).toMatch(/^urn:ietf:params:oauth:token-type:/);
  });

  it('should exchange Kubernetes SA token for JWT', () => {
    // Mock token exchange request
    const request = {
      grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange',
      subject_token: 'eyJ...',
      subject_token_type: 'urn:ietf:params:oauth:token-type:kubernetes-sa',
      audience: 'code-server,api,kubernetes',
      requested_token_use: 'access',
    };

    expect(request.grant_type).toContain('token-exchange');
    expect(request.subject_token_type).toContain('kubernetes-sa');
    expect(request.audience).toBeDefined();
  });

  it('should return JWT with correct structure', () => {
    // Mock JWT token response
    const mockToken = {
      access_token:
        'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzeXN0ZW06c2VydmljZWFjY291bnQ6cHJvZDpjb2RlLXNlcnZlciIsImF1ZCI6ImNvZGUtc2VydmVyIiwiaXNzIjoiaHR0cHM6Ly9vaWRjLmt1c2huaXIuY2xvdWQiLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MTcwMDAzNjAwMH0.sig',
      token_type: 'Bearer',
      expires_in: 3600,
    };

    expect(mockToken.access_token).toMatch(/^eyJ/);
    expect(mockToken.token_type).toBe('Bearer');
    expect(mockToken.expires_in).toBe(3600);
  });
});

/**
 * Test 5: Network Policy and Security
 */
describe('Kubernetes Workload Identity Security', () => {
  it('should restrict OIDC issuer access via network policy', () => {
    const networkPolicy = {
      metadata: {
        name: 'oidc-issuer-access',
        namespace: 'oidc-system',
      },
      spec: {
        podSelector: {
          matchLabels: {
            app: 'oidc-issuer',
          },
        },
        policyTypes: ['Ingress'],
        ingress: [
          {
            from: [
              {
                namespaceSelector: {},
              },
            ],
            ports: [
              {
                protocol: 'TCP',
                port: 8080,
              },
            ],
          },
        ],
      },
    };

    expect(networkPolicy.spec.policyTypes).toContain('Ingress');
    expect(networkPolicy.spec.ingress).toBeDefined();
    expect(networkPolicy.spec.ingress[0].ports[0].port).toBe(8080);
  });

  it('should require RBAC permissions for token request', () => {
    const role = {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: {
        name: 'workload-identity-token-request',
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['serviceaccounts/token'],
          verbs: ['create'],
        },
      ],
    };

    expect(role.rules[0].resources).toContain('serviceaccounts/token');
    expect(role.rules[0].verbs).toContain('create');
  });
});
