/**
 * @file        apps/backend/src/services/guest-session-quotas/__tests__/integration-example.test.ts
 * @module      collaboration/sessions
 * @description Integration tests for Guest Session Quotas service
 */

import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { createGuestSessionQuotasExampleApp } from '../integration-example';
import { QuotaTier, QUOTA_LIMITS } from '../index';
import type { Express } from 'express';

describe('Guest Session Quotas Integration Example', () => {
  let app: Express;

  beforeEach(async () => {
    app = await createGuestSessionQuotasExampleApp();
  });

  describe('Guest Session Lifecycle', () => {
    it('creates a guest session with free tier', async () => {
      const res = await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-1',
        tier: QuotaTier.FREE,
      });

      expect(res.status).toBe(201);
      expect(res.body).toMatchObject({
        guestId: 'guest-1',
        tier: QuotaTier.FREE,
        currentConcurrentSessions: 1,
      });
    });

    it('defaults to free tier if not specified', async () => {
      const res = await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-1',
        // no tier specified
      });

      expect(res.status).toBe(201);
      expect(res.body.tier).toBe(QuotaTier.FREE);
    });

    it('ends a guest session', async () => {
      // Create session
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-1',
        tier: QuotaTier.FREE,
      });

      // End session
      const res = await request(app).delete('/api/quotas/guest-sessions/guest-1');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);

      // Verify gone
      const checkRes = await request(app).get('/api/quotas/guest-sessions/guest-1');
      expect(checkRes.status).toBe(404);
    });
  });

  describe('Concurrent Session Limits', () => {
    beforeEach(async () => {
      // Create free tier guest (max 1 concurrent)
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-free',
        tier: QuotaTier.FREE,
      });

      // Create basic tier guest (max 5 concurrent)
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-basic',
        tier: QuotaTier.BASIC,
      });
    });

    it('free tier cannot start second concurrent session', async () => {
      const canStart = await request(app).post('/api/quotas/guest-sessions/guest-free/can-start-concurrent').send();

      expect(canStart.status).toBe(200);
      expect(canStart.body.canStart).toBe(false);
    });

    it('basic tier can start multiple concurrent sessions', async () => {
      // Should be able to start 4 more (already has 1)
      for (let i = 0; i < 4; i++) {
        const canStart = await request(app)
          .post('/api/quotas/guest-sessions/guest-basic/can-start-concurrent')
          .send();

        expect(canStart.body.canStart).toBe(true);

        const res = await request(app)
          .post('/api/quotas/guest-sessions/guest-basic/start-concurrent')
          .send();

        expect(res.status).toBe(200);
        expect(res.body.currentConcurrentSessions).toBe(i + 2);
      }

      // 5th concurrent should fail
      const canStart = await request(app)
        .post('/api/quotas/guest-sessions/guest-basic/can-start-concurrent')
        .send();

      expect(canStart.body.canStart).toBe(false);
    });

    it('enforces concurrent session limit on start', async () => {
      // Free tier should have max 1
      const res = await request(app).post('/api/quotas/guest-sessions/guest-free/start-concurrent').send();

      expect(res.status).toBe(429);
      expect(res.body.error).toContain('limit');
    });

    it('decrements concurrent sessions on end', async () => {
      // End one concurrent session
      const res = await request(app).post('/api/quotas/guest-sessions/guest-basic/end-concurrent').send();

      expect(res.status).toBe(200);
      expect(res.body.currentConcurrentSessions).toBe(0);
    });
  });

  describe('Session Duration Limits', () => {
    beforeEach(async () => {
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-duration',
        tier: QuotaTier.FREE, // 30 min limit
      });
    });

    it('reports remaining session duration', async () => {
      const res = await request(app).get('/api/quotas/guest-sessions/guest-duration/remaining-time');

      expect(res.status).toBe(200);
      expect(res.body.remainingMs).toBeLessThanOrEqual(30 * 60 * 1000); // <= 30 minutes
      expect(res.body.remainingMs).toBeGreaterThan(29 * 60 * 1000); // > 29 minutes
      expect(res.body.isExceeded).toBe(false);
    });

    it('tracks session duration per tier', async () => {
      const freeRes = await request(app)
        .get('/api/quotas/guest-sessions/guest-duration/remaining-time')
        .send();

      // Create premium tier for comparison
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-premium',
        tier: QuotaTier.PREMIUM, // 8 hour limit
      });

      const premiumRes = await request(app)
        .get('/api/quotas/guest-sessions/guest-premium/remaining-time')
        .send();

      // Premium should have much more remaining time
      expect(premiumRes.body.remainingMs).toBeGreaterThan(freeRes.body.remainingMs);
    });
  });

  describe('Storage Usage', () => {
    beforeEach(async () => {
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-storage',
        tier: QuotaTier.BASIC, // 1 GB limit
      });
    });

    it('tracks storage usage', async () => {
      const oneHundredMB = 100 * 1024 * 1024;

      const res = await request(app)
        .post('/api/quotas/guest-sessions/guest-storage/storage')
        .send({
          bytes: oneHundredMB,
        });

      expect(res.status).toBe(200);
      expect(res.body.currentStorageBytes).toBe(oneHundredMB);
    });

    it('enforces storage limit', async () => {
      const basicLimit = QUOTA_LIMITS[QuotaTier.BASIC].maxStorageBytes;

      // Try to exceed limit
      const res = await request(app)
        .post('/api/quotas/guest-sessions/guest-storage/storage')
        .send({
          bytes: basicLimit + 1,
        });

      expect(res.status).toBe(429);
      expect(res.body.error).toContain('Storage quota exceeded');
    });

    it('allows multiple storage additions up to limit', async () => {
      const basicLimit = QUOTA_LIMITS[QuotaTier.BASIC].maxStorageBytes;
      const halfLimit = basicLimit / 2;

      // Add first half
      let res = await request(app)
        .post('/api/quotas/guest-sessions/guest-storage/storage')
        .send({
          bytes: halfLimit,
        });

      expect(res.status).toBe(200);

      // Add second half
      res = await request(app)
        .post('/api/quotas/guest-sessions/guest-storage/storage')
        .send({
          bytes: halfLimit,
        });

      expect(res.status).toBe(200);
      expect(res.body.currentStorageBytes).toBe(basicLimit);
    });
  });

  describe('Quota Information Retrieval', () => {
    it('gets guest quota usage', async () => {
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-info',
        tier: QuotaTier.PREMIUM,
      });

      const res = await request(app).get('/api/quotas/guest-sessions/guest-info');

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        guestId: 'guest-info',
        tier: QuotaTier.PREMIUM,
        currentConcurrentSessions: 1,
      });
    });

    it('lists all active quotas', async () => {
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-list-1',
      });

      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-list-2',
      });

      const res = await request(app).get('/api/quotas/guest-sessions');

      expect(res.status).toBe(200);
      expect(res.body.quotas.length).toBeGreaterThanOrEqual(2);
      expect(res.body.quotas.some((q: any) => q.guestId === 'guest-list-1')).toBe(true);
      expect(res.body.quotas.some((q: any) => q.guestId === 'guest-list-2')).toBe(true);
    });

    it('returns 404 for unknown guest', async () => {
      const res = await request(app).get('/api/quotas/guest-sessions/unknown-guest');

      expect(res.status).toBe(404);
    });
  });

  describe('Error Handling', () => {
    it('validates guestId on creation', async () => {
      const res = await request(app).post('/api/quotas/guest-sessions').send({
        tier: QuotaTier.FREE,
        // missing guestId
      });

      expect(res.status).toBe(400);
    });

    it('validates bytes on storage add', async () => {
      await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-error',
      });

      const res = await request(app)
        .post('/api/quotas/guest-sessions/guest-error/storage')
        .send({
          bytes: -100, // negative
        });

      expect(res.status).toBe(400);
    });
  });

  describe('Quota Tier Comparison', () => {
    it('free tier is more restrictive than basic', async () => {
      const freeRes = await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-free-compare',
        tier: QuotaTier.FREE,
      });

      const basicRes = await request(app).post('/api/quotas/guest-sessions').send({
        guestId: 'guest-basic-compare',
        tier: QuotaTier.BASIC,
      });

      const freeLimits = QUOTA_LIMITS[QuotaTier.FREE];
      const basicLimits = QUOTA_LIMITS[QuotaTier.BASIC];

      expect(freeLimits.maxConcurrentSessions).toBeLessThan(basicLimits.maxConcurrentSessions);
      expect(freeLimits.maxSessionDurationMs).toBeLessThan(basicLimits.maxSessionDurationMs);
      expect(freeLimits.maxStorageBytes).toBeLessThan(basicLimits.maxStorageBytes);
    });
  });
});
