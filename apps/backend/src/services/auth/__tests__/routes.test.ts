#!/usr/bin/env node
// @file        apps/backend/src/services/auth/__tests__/routes.test.ts
// @module      services/auth/__tests__
// @description Tests for JWT diagnostics routes
// @owner       Infrastructure Team
// @status      ACTIVE

import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { initializeJwtDiagnosticsRoutes } from '../routes';

describe('initializeJwtDiagnosticsRoutes', () => {
  it('serves Prometheus metrics text', async () => {
    const app = express();
    app.use('/diagnostics/jwt', initializeJwtDiagnosticsRoutes());

    const response = await request(app).get('/diagnostics/jwt/metrics');

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/text\/plain/);
    expect(response.text).toContain('# HELP jwt_validations_total');
  });

  it('returns token cache stats when a token client is provided', async () => {
    const tokenClient = {
      getCacheStats: () => ({
        cachedTokenCount: 2,
        schedules: [
          { cacheKey: 'session-broker|https://session-broker/api', expiresIn: 1200 },
          { cacheKey: 'workspace-service|https://workspace-service/api', expiresIn: 900 },
        ],
      }),
    };

    const app = express();
    app.use('/diagnostics/jwt', initializeJwtDiagnosticsRoutes({ tokenClient: tokenClient as never }));

    const response = await request(app).get('/diagnostics/jwt/cache');

    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      success: true,
      data: {
        cachedTokenCount: 2,
        schedules: [
          { cacheKey: 'session-broker|https://session-broker/api', expiresIn: 1200 },
          { cacheKey: 'workspace-service|https://workspace-service/api', expiresIn: 900 },
        ],
      },
    });
  });

  it('returns a clear error when no token client is configured', async () => {
    const app = express();
    app.use('/diagnostics/jwt', initializeJwtDiagnosticsRoutes());

    const response = await request(app).get('/diagnostics/jwt/cache');

    expect(response.status).toBe(503);
    expect(response.body).toEqual({
      success: false,
      error: 'JWT token client is not configured',
    });
  });

  it('reports a health summary for the diagnostics surface', async () => {
    const app = express();
    app.use('/diagnostics/jwt', initializeJwtDiagnosticsRoutes());

    const response = await request(app).get('/diagnostics/jwt/health');

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe('degraded');
    expect(response.body.data.metricFamilies).toBeGreaterThan(0);
    expect(response.body.data.cache).toBeNull();
  });
});