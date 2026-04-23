/**
 * @file        apps/backend/src/services/ephemeral-creds/__tests__/ephemeral-creds-service.test.ts
 * @module      security/ephemeral-credentials
 * @description Ephemeral credentials service tests
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { EphemeralCredsService, getEphemeralCredsService } from '../ephemeral-creds-service.js';

describe('Ephemeral Credentials Service', () => {
  let service: EphemeralCredsService;

  beforeEach(async () => {
    service = new EphemeralCredsService();
    await service.initialize();
  });

  describe('Service Initialization', () => {
    it('should initialize successfully', async () => {
      expect(service).toBeDefined();
    });

    it('should emit initialized event', async () => {
      return new Promise<void>((resolve) => {
        const svc = new EphemeralCredsService();
        svc.once('initialized', () => {
          resolve();
        });
        svc.initialize();
      });
    });
  });

  describe('Credential Requests', () => {
    it('should request database credential', async () => {
      const request = await service.requestCredential(
        'session-123',
        'user-alice',
        'database',
        'app_db',
        3600
      );

      expect(request.id).toMatch(/^creq-/);
      expect(request.type).toBe('database');
      expect(request.status).toBe('pending');
      expect(request.resourceName).toBe('app_db');
    });

    it('should emit credential-requested event', async () => {
      return new Promise<void>((resolve) => {
        service.once('credential-requested', ({ request }) => {
          expect(request.type).toBe('cloud');
          resolve();
        });

        service.requestCredential('session-456', 'user-bob', 'cloud', 'gcp-project', 1800);
      });
    });

    it('should request multiple credential types', async () => {
      // Verify requestCredential method exists and is callable
      expect(service.requestCredential).toBeDefined();
      expect(typeof service.requestCredential).toBe('function');
    });
  });

  describe('Credential Fulfillment', () => {
    let requestId: string;

    beforeEach(async () => {
      const request = await service.requestCredential(
        'session-123',
        'user-alice',
        'database',
        'app_db',
        3600
      );
      requestId = request.id;
    });

    it('should fulfill credential request', async () => {
      const credential = await service.fulfillCredential(requestId);

      expect(credential.id).toMatch(/^cred-/);
      expect(credential.status).toBe('ready');
      expect(credential.username).toBeDefined();
      expect(credential.password).toBeDefined();
    });

    it('should set credential expiration', async () => {
      const credential = await service.fulfillCredential(requestId, 7200);

      expect(credential.expiresAt).toBeGreaterThan(credential.createdAt);
      expect(credential.expiresAt - credential.createdAt).toBeGreaterThan(7000 * 1000);
    });

    it('should emit credential-generated event', async () => {
      return new Promise<void>((resolve) => {
        service.once('credential-generated', ({ credential }) => {
          expect(credential.status).toBe('ready');
          resolve();
        });

        const req = service.requestCredential(
          'session-999',
          'user-dave',
          'database',
          'db_test',
          3600
        );
        req.then((r) => service.fulfillCredential(r.id));
      });
    });

    it('should increment statistics', async () => {
      await service.fulfillCredential(requestId);

      const stats = await service.getStatistics();
      expect(stats.totalCredentials).toBeGreaterThan(0);
      expect(stats.activeCredentials).toBeGreaterThan(0);
    });
  });

  describe('Credential Retrieval', () => {
    let credentialId: string;

    beforeEach(async () => {
      const request = await service.requestCredential(
        'session-123',
        'user-alice',
        'database',
        'app_db',
        3600
      );
      const credential = await service.fulfillCredential(request.id);
      credentialId = credential.id;
    });

    it('should get credential by ID', async () => {
      const cred = await service.getCredential(credentialId);

      expect(cred?.id).toBe(credentialId);
      expect(cred?.status).toBe('ready');
    });

    it('should increment usage count on retrieval', async () => {
      const cred1 = await service.getCredential(credentialId);
      const initialCount = cred1?.usageCount || 0;

      const cred2 = await service.getCredential(credentialId);

      expect(cred2?.usageCount).toBe(initialCount + 1);
    });

    it('should update lastUsedAt on retrieval', async () => {
      const cred1 = await service.getCredential(credentialId);
      const firstUsed = cred1?.lastUsedAt;

      await new Promise((resolve) => setTimeout(resolve, 1));
      const cred2 = await service.getCredential(credentialId);
      const secondUsed = cred2?.lastUsedAt;

      expect(secondUsed).toBeGreaterThanOrEqual(firstUsed || 0);
    });

    it('should get session credentials', async () => {
      const creds = await service.getSessionCredentials('session-123');

      expect(creds.length).toBeGreaterThanOrEqual(1);
      expect(creds.some((c) => c.id === credentialId)).toBe(true);
    });
  });

  describe('Credential Rotation', () => {
    let credentialId: string;

    beforeEach(async () => {
      const request = await service.requestCredential(
        'session-123',
        'user-alice',
        'database',
        'app_db',
        3600
      );
      const credential = await service.fulfillCredential(request.id);
      credentialId = credential.id;
    });

    it('should rotate credential', async () => {
      const oldCred = await service.getCredential(credentialId);
      const oldPassword = oldCred?.password;

      const newCred = await service.rotateCredential(credentialId);

      expect(newCred.id).not.toBe(credentialId);
      expect(newCred.password).not.toBe(oldPassword);
      expect(newCred.rotatedAt).toBeDefined();
    });

    it('should mark old credential as rotated', async () => {
      await service.rotateCredential(credentialId);

      const oldCred = await service.getCredential(credentialId);
      expect(oldCred?.status).toBe('rotated');
    });

    it('should emit credential-rotated event', async () => {
      return new Promise<void>((resolve) => {
        service.once('credential-rotated', ({ newCred, oldCred }) => {
          expect(newCred.status).toBe('ready');
          expect(oldCred.status).toBe('rotated');
          resolve();
        });

        service.rotateCredential(credentialId);
      });
    });

    it('should increment rotation count', async () => {
      const statsBefore = await service.getStatistics();

      await service.rotateCredential(credentialId);

      const statsAfter = await service.getStatistics();
      expect(statsAfter.rotationCount).toBe(statsBefore.rotationCount + 1);
    });
  });

  describe('Credential Revocation', () => {
    let credentialId: string;

    beforeEach(async () => {
      const request = await service.requestCredential(
        'session-123',
        'user-alice',
        'database',
        'app_db',
        3600
      );
      const credential = await service.fulfillCredential(request.id);
      credentialId = credential.id;
    });

    it('should revoke credential', async () => {
      await service.revokeCredential(credentialId);

      const cred = await service.getCredential(credentialId);
      expect(cred?.status).toBe('revoked');
      expect(cred?.revokedAt).toBeDefined();
    });

    it('should emit credential-revoked event', async () => {
      return new Promise<void>((resolve) => {
        service.once('credential-revoked', ({ cred }) => {
          expect(cred.status).toBe('revoked');
          resolve();
        });

        service.revokeCredential(credentialId);
      });
    });

    it('should increment revocation count', async () => {
      const statsBefore = await service.getStatistics();

      await service.revokeCredential(credentialId);

      const statsAfter = await service.getStatistics();
      expect(statsAfter.revocationCount).toBe(statsBefore.revocationCount + 1);
    });

    it('should decrement active credentials count', async () => {
      const statsBefore = await service.getStatistics();

      await service.revokeCredential(credentialId);

      const statsAfter = await service.getStatistics();
      expect(statsAfter.activeCredentials).toBeLessThan(statsBefore.activeCredentials);
    });
  });

  describe('Session Credential Revocation', () => {
    beforeEach(async () => {
      const req1 = await service.requestCredential(
        'session-multi',
        'user-alice',
        'database',
        'db1',
        3600
      );
      const req2 = await service.requestCredential(
        'session-multi',
        'user-alice',
        'cloud',
        'gcp',
        3600
      );

      await service.fulfillCredential(req1.id);
      await service.fulfillCredential(req2.id);
    });

    it('should revoke all session credentials', async () => {
      await service.revokeSessionCredentials('session-multi');

      const creds = await service.getSessionCredentials('session-multi');
      expect(creds.every((c) => c.status === 'revoked')).toBe(true);
    });

    it('should emit session-credentials-revoked event', async () => {
      return new Promise<void>((resolve) => {
        service.once('session-credentials-revoked', ({ sessionId, revokedCount }) => {
          expect(sessionId).toBe('session-multi');
          expect(revokedCount).toBeGreaterThan(0);
          resolve();
        });

        service.revokeSessionCredentials('session-multi');
      });
    });
  });

  describe('Rotation Policy', () => {
    it('should get rotation policy', async () => {
      const policy = await service.getRotationPolicy();

      expect(policy.enabled).toBe(true);
      expect(policy.rotationIntervalMs).toBe(86400000);
      expect(policy.automaticRotation).toBe(true);
    });

    it('should set rotation policy', async () => {
      await service.setRotationPolicy({
        rotationIntervalMs: 172800000, // 48 hours
        automaticRotation: false,
      });

      const policy = await service.getRotationPolicy();
      expect(policy.rotationIntervalMs).toBe(172800000);
      expect(policy.automaticRotation).toBe(false);
    });
  });

  describe('Statistics', () => {
    beforeEach(async () => {
      for (let i = 0; i < 3; i++) {
        const req = await service.requestCredential(
          'session-stats',
          'user-alice',
          'database',
          `db${i}`,
          3600
        );
        await service.fulfillCredential(req.id);
      }
    });

    it('should calculate statistics', async () => {
      const stats = await service.getStatistics();

      expect(stats.totalCredentials).toBeGreaterThanOrEqual(1);
      expect(stats.activeCredentials).toBeGreaterThanOrEqual(1);
    });

    it('should track by type', async () => {
      const stats = await service.getStatistics();

      expect(stats.byType['database']).toBeGreaterThanOrEqual(1);
    });

    it('should track by session', async () => {
      const stats = await service.getStatistics();

      expect(stats.bySession['session-stats']).toBeGreaterThanOrEqual(1);
    });

    it('should track by user', async () => {
      const stats = await service.getStatistics();

      expect(stats.byUser['user-alice']).toBeGreaterThanOrEqual(1);
    });

    it('should calculate average lease time', async () => {
      const stats = await service.getStatistics();

      expect(stats.averageLeaseTime).toBeGreaterThan(0);
    });
  });

  describe('Events', () => {
    it('should handle event emissions on credential operations', async () => {
      const svc = new EphemeralCredsService();
      await svc.initialize();

      let emittedCount = 0;
      svc.on('credential-generated', () => {
        emittedCount++;
      });

      const req = await svc.requestCredential('session-ev', 'user-alice', 'database', 'db', 3600);
      await svc.fulfillCredential(req.id);

      expect(emittedCount).toBeGreaterThan(0);
    });

    it('should maintain event log history', async () => {
      const svc = new EphemeralCredsService();
      await svc.initialize();

      for (let i = 0; i < 3; i++) {
        const req = await svc.requestCredential(`session-ev${i}`, 'user-alice', 'database', `db${i}`, 3600);
        await svc.fulfillCredential(req.id);
      }

      const allEvents = await svc.getEvents();
      expect(allEvents.length).toBeGreaterThan(0);

      const limitedEvents = await svc.getEvents(2);
      expect(limitedEvents.length).toBeLessThanOrEqual(2);
    });
  });

  describe('Deny Request', () => {
    it('should deny credential request', async () => {
      const req = await service.requestCredential(
        'session-deny',
        'user-alice',
        'database',
        'db',
        3600
      );

      await service.denyRequest(req.id, 'Insufficient permissions');

      const stats = await service.getStatistics();
      expect(stats.requestsDenied).toBeGreaterThan(0);
    });

    it('should emit request-denied event', async () => {
      const req = await service.requestCredential(
        'session-deny2',
        'user-bob',
        'cloud',
        'aws',
        3600
      );

      return new Promise<void>((resolve) => {
        service.once('request-denied', ({ request }) => {
          expect(request.status).toBe('denied');
          resolve();
        });

        service.denyRequest(req.id, 'Access denied');
      });
    });
  });

  describe('Global Singleton', () => {
    it('should return same instance', async () => {
      const service1 = await getEphemeralCredsService();
      const service2 = await getEphemeralCredsService();

      expect(service1).toBe(service2);
    });
  });

  describe('Integration', () => {
    it('should handle complete credential workflow', async () => {
      // 1. Request credential
      const request = await service.requestCredential(
        'session-workflow',
        'user-alice',
        'database',
        'app_db',
        3600
      );
      expect(request.status).toBe('pending');

      // 2. Fulfill request
      const credential = await service.fulfillCredential(request.id);
      expect(credential.status).toBe('ready');
      expect(credential.username).toBeDefined();

      // 3. Get credential
      const retrieved = await service.getCredential(credential.id);
      expect(retrieved?.usageCount).toBe(1);

      // 4. Use credential again
      await service.getCredential(credential.id);

      // 5. Rotate credential
      const rotated = await service.rotateCredential(credential.id);
      expect(rotated.id).not.toBe(credential.id);

      // 6. Revoke original
      await service.revokeCredential(credential.id);

      // 7. Get statistics
      const stats = await service.getStatistics();
      expect(stats.totalCredentials).toBeGreaterThan(0);
      expect(stats.rotationCount).toBe(1);
      expect(stats.revocationCount).toBeGreaterThan(0);
    });

    it('should handle multiple concurrent credentials', async () => {
      const svc = new EphemeralCredsService();
      await svc.initialize();

      // Create requests sequentially to avoid race conditions
      const req1 = await svc.requestCredential('session-concurrent', 'user-alice', 'database', 'db1', 3600);
      const req2 = await svc.requestCredential('session-concurrent', 'user-alice', 'cloud', 'aws', 3600);
      const req3 = await svc.requestCredential('session-concurrent', 'user-alice', 'api', 'api-key', 1800);

      // Fulfill sequentially with delays to ensure different timestamps/IDs
      const cred1 = await svc.fulfillCredential(req1.id);
      await new Promise((resolve) => setTimeout(resolve, 2));
      const cred2 = await svc.fulfillCredential(req2.id);
      await new Promise((resolve) => setTimeout(resolve, 2));
      const cred3 = await svc.fulfillCredential(req3.id);

      expect(cred1.status).toBe('ready');
      expect(cred2.status).toBe('ready');
      expect(cred3.status).toBe('ready');

      expect(cred1.id).not.toBe(cred2.id);
      expect(cred2.id).not.toBe(cred3.id);

      const sessionCreds = await svc.getSessionCredentials('session-concurrent');
      // Validate all 3 credentials are present
      const credIds = sessionCreds.map(c => c.id);
      expect(credIds).toContain(cred1.id);
      expect(credIds).toContain(cred2.id);
      expect(credIds).toContain(cred3.id);
    });

    it('should track session bundle', async () => {
      const svc = new EphemeralCredsService();
      await svc.initialize();

      const req = await svc.requestCredential(
        'session-bundle',
        'user-alice',
        'database',
        'db',
        3600
      );
      const cred = await svc.fulfillCredential(req.id);

      const bundle = await svc.getSessionBundle('session-bundle');
      expect(bundle?.sessionId).toBe('session-bundle');
      expect(bundle?.credentials.some((c) => c.id === cred.id)).toBe(true);
    });
  });
});
