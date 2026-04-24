#!/usr/bin/env node
// @file        apps/backend/src/services/auth/routes.ts
// @module      services/auth
// @description Express routes for JWT diagnostics and cache inspection
// @owner       Infrastructure Team
// @status      ACTIVE

import { Router, Request, Response } from 'express';
import { JwtTokenClient } from './jwt-token-client';
import { metricsHandler, renderMetrics } from './jwt-metrics';

export interface JwtDiagnosticsRoutesOptions {
  tokenClient?: JwtTokenClient;
}

function countMetricFamilies(): number {
  return renderMetrics()
    .split('\n')
    .filter((line) => line.startsWith('# HELP ')).length;
}

export function initializeJwtDiagnosticsRoutes(options: JwtDiagnosticsRoutesOptions = {}): Router {
  const router = Router();

  router.get('/metrics', (req: Request, res: Response) => {
    metricsHandler(req, res);
  });

  router.get('/cache', (_req: Request, res: Response) => {
    if (!options.tokenClient) {
      return res.status(503).json({
        success: false,
        error: 'JWT token client is not configured',
      });
    }

    return res.status(200).json({
      success: true,
      data: options.tokenClient.getCacheStats(),
    });
  });

  router.get('/health', (_req: Request, res: Response) => {
    const tokenClientConfigured = Boolean(options.tokenClient);

    return res.status(200).json({
      success: true,
      data: {
        status: tokenClientConfigured ? 'healthy' : 'degraded',
        tokenClientConfigured,
        metricFamilies: countMetricFamilies(),
        cache: options.tokenClient ? options.tokenClient.getCacheStats() : null,
      },
    });
  });

  return router;
}

export default initializeJwtDiagnosticsRoutes;