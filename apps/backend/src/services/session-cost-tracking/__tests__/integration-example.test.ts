/**
 * @file        apps/backend/src/services/session-cost-tracking/__tests__/integration-example.test.ts
 * @module      collaboration/sessions
 * @description Integration tests for session cost tracking service
 */

import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { createSessionCostTrackingExampleApp } from '../integration-example';
import { SessionCostTrackingService } from '../index';
import type { Express } from 'express';

describe('Session Cost Tracking Integration Example', () => {
  let app: Express;
  let service: SessionCostTrackingService;

  beforeEach(async () => {
    app = await createSessionCostTrackingExampleApp();
    service = SessionCostTrackingService.getInstance();
    service.reset();
  });

  describe('Session Lifecycle', () => {
    it('starts a new session', async () => {
      const res = await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      expect(res.status).toBe(201);
      expect(res.body).toMatchObject({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
        status: 'active',
      });
      expect(res.body.startTime).toBeDefined();
      expect(res.body.components).toEqual([]);
      expect(res.body.totalCost).toBe(0);
    });

    it('validates required fields on start', async () => {
      const res = await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        // missing projectId and teamId
      });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Missing required fields');
    });

    it('rejects duplicate session ids', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      const res = await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-2',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('already exists');
    });

    it('ends a session and calculates duration', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      // Wait a bit to ensure there's measurable duration
      await new Promise((resolve) => setTimeout(resolve, 100));

      const res = await request(app).post('/api/session-cost/session-1/end').send();

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        sessionId: 'session-1',
        status: 'completed',
      });
      expect(res.body.endTime).toBeDefined();
      expect(res.body.durationMinutes).toBeGreaterThanOrEqual(0);
      expect(res.body.totalCost).toBeGreaterThan(0); // Should have compute cost
    });
  });

  describe('Cost Components', () => {
    beforeEach(async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });
    });

    it('adds storage cost component', async () => {
      const res = await request(app)
        .post('/api/session-cost/session-1/add-component')
        .send({
          type: 'storage',
          unit: 'GB',
          unitPrice: 0.1,
          quantity: 5,
        });

      expect(res.status).toBe(200);
      expect(res.body.components.length).toBe(1);
      expect(res.body.components[0]).toMatchObject({
        type: 'storage',
        unit: 'GB',
        unitPrice: 0.1,
        quantity: 5,
        totalCost: 0.5,
      });
      expect(res.body.totalCost).toBe(0.5);
    });

    it('adds multiple cost components', async () => {
      await request(app)
        .post('/api/session-cost/session-1/add-component')
        .send({
          type: 'storage',
          unit: 'GB',
          unitPrice: 0.1,
          quantity: 5,
        });

      const res = await request(app)
        .post('/api/session-cost/session-1/add-component')
        .send({
          type: 'network',
          unit: 'GB',
          unitPrice: 0.01,
          quantity: 10,
        });

      expect(res.status).toBe(200);
      expect(res.body.components.length).toBe(2);
      expect(res.body.totalCost).toBe(0.5 + 0.1); // 0.5 + 0.1
    });

    it('validates component fields', async () => {
      const res = await request(app)
        .post('/api/session-cost/session-1/add-component')
        .send({
          type: 'storage',
          // missing unit, unitPrice, quantity
        });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Missing required fields');
    });
  });

  describe('Session Retrieval', () => {
    it('gets session cost details', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      const res = await request(app).get('/api/session-cost/session-1');

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
      });
    });

    it('returns 404 for unknown session', async () => {
      const res = await request(app).get('/api/session-cost/unknown-session');

      expect(res.status).toBe(404);
      expect(res.body.error).toContain('not found');
    });
  });

  describe('User Cost Summary', () => {
    beforeEach(async () => {
      // Create and end a session
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      await request(app)
        .post('/api/session-cost/session-1/add-component')
        .send({
          type: 'storage',
          unit: 'GB',
          unitPrice: 0.1,
          quantity: 5,
        });

      await request(app).post('/api/session-cost/session-1/end').send();
    });

    it('gets user cost summary', async () => {
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - 1);
      const endDate = new Date();

      const res = await request(app)
        .get('/api/session-cost/user/user-1/summary')
        .query({
          startDate: startDate.toISOString(),
          endDate: endDate.toISOString(),
          period: 'daily',
        });

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        userId: 'user-1',
        period: 'daily',
        sessionCount: 1,
      });
      expect(res.body.totalCost).toBeGreaterThan(0);
      expect(res.body.costByProject['project-1']).toBeGreaterThan(0);
      expect(res.body.costByComponent).toBeDefined();
    });

    it('calculates average cost per session', async () => {
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - 1);
      const endDate = new Date();

      const res = await request(app)
        .get('/api/session-cost/user/user-1/summary')
        .query({
          startDate: startDate.toISOString(),
          endDate: endDate.toISOString(),
        });

      expect(res.status).toBe(200);
      expect(res.body.averageCostPerSession).toBe(res.body.totalCost / res.body.sessionCount);
    });

    it('validates required date parameters', async () => {
      const res = await request(app)
        .get('/api/session-cost/user/user-1/summary')
        .query({
          period: 'monthly',
          // missing startDate and endDate
        });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Missing required query params');
    });
  });

  describe('Project Cost Summary', () => {
    beforeEach(async () => {
      // Create multiple sessions for same project
      for (let i = 1; i <= 2; i++) {
        await request(app).post('/api/session-cost/start').send({
          sessionId: `session-${i}`,
          userId: `user-${i}`,
          projectId: 'project-1',
          teamId: 'team-1',
        });

        await request(app)
          .post(`/api/session-cost/session-${i}/add-component`)
          .send({
            type: 'storage',
            unit: 'GB',
            unitPrice: 0.1,
            quantity: i * 5,
          });

        await request(app).post(`/api/session-cost/session-${i}/end`).send();
      }
    });

    it('gets project cost summary', async () => {
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - 1);
      const endDate = new Date();

      const res = await request(app)
        .get('/api/session-cost/project/project-1/summary')
        .query({
          startDate: startDate.toISOString(),
          endDate: endDate.toISOString(),
        });

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        projectId: 'project-1',
        sessionCount: 2,
      });
      expect(res.body.costByUser['user-1']).toBeGreaterThan(0);
      expect(res.body.costByUser['user-2']).toBeGreaterThan(0);
      expect(res.body.costByUser['user-2']).toBeGreaterThan(res.body.costByUser['user-1']);
    });
  });

  describe('Session Lists', () => {
    it('gets all sessions for a user', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      const res = await request(app).get('/api/session-cost/user/user-1/sessions');

      expect(res.status).toBe(200);
      expect(res.body.sessions.length).toBe(1);
      expect(res.body.sessions[0].sessionId).toBe('session-1');
    });

    it('gets all sessions for a project', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      const res = await request(app).get('/api/session-cost/project/project-1/sessions');

      expect(res.status).toBe(200);
      expect(res.body.sessions.length).toBe(1);
    });
  });

  describe('Cost Forecasting', () => {
    it('forecasts user cost', async () => {
      // Create a session and end it
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      await request(app).post('/api/session-cost/session-1/end').send();

      const res = await request(app)
        .get('/api/session-cost/user/user-1/forecast')
        .query({ days: 30 });

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('forecast');
      expect(res.body.forecast).toBeGreaterThan(0);
      expect(res.body.forecastDays).toBe('30');
    });

    it('forecasts project cost', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      await request(app).post('/api/session-cost/session-1/end').send();

      const res = await request(app)
        .get('/api/session-cost/project/project-1/forecast')
        .query({ days: 30 });

      expect(res.status).toBe(200);
      expect(res.body.forecast).toBeGreaterThan(0);
    });
  });

  describe('Active Sessions', () => {
    it('counts active sessions', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      const res = await request(app).get('/api/session-cost/active-sessions/count');

      expect(res.status).toBe(200);
      expect(res.body.activeSessionsCount).toBe(1);
    });

    it('excludes ended sessions from active count', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      await request(app).post('/api/session-cost/session-1/end').send();

      const res = await request(app).get('/api/session-cost/active-sessions/count');

      expect(res.status).toBe(200);
      expect(res.body.activeSessionsCount).toBe(0);
    });
  });

  describe('Session Archival', () => {
    it('archives old sessions', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      await request(app).post('/api/session-cost/session-1/end').send();

      const res = await request(app).post('/api/session-cost/archive-old').send({
        olderThanDays: 0, // Archive immediately
      });

      expect(res.status).toBe(200);
      expect(res.body.archivedCount).toBe(1);
    });

    it('does not archive recent sessions', async () => {
      await request(app).post('/api/session-cost/start').send({
        sessionId: 'session-1',
        userId: 'user-1',
        projectId: 'project-1',
        teamId: 'team-1',
      });

      await request(app).post('/api/session-cost/session-1/end').send();

      const res = await request(app).post('/api/session-cost/archive-old').send({
        olderThanDays: 7,
      });

      expect(res.status).toBe(200);
      expect(res.body.archivedCount).toBe(0);
    });
  });

  describe('Pricing Configuration', () => {
    it('updates pricing configuration', async () => {
      const res = await request(app).put('/api/session-cost/pricing').send({
        computeCostPerMinute: 0.01,
        storageCostPerGB: 0.2,
      });

      expect(res.status).toBe(200);
      expect(res.body.message).toContain('Pricing updated');
    });
  });
});
