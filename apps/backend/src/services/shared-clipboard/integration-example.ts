// @file        apps/backend/src/services/shared-clipboard/integration-example.ts
// @module      collaboration/shared-clipboard
// @description Example Express integration for shared clipboard sessions

import express from 'express';
import type { Express } from 'express';
import { initializeSharedClipboardRoutes, SharedClipboardService } from './index.js';

export async function setupSharedClipboardIntegration(app: Express): Promise<SharedClipboardService> {
  const service = new SharedClipboardService({ historyLimit: 20 });
  const router = initializeSharedClipboardRoutes(service);

  app.use(router);

  return service;
}

export async function createSharedClipboardExampleApp(): Promise<Express> {
  const app = express();

  app.use(express.json());
  await setupSharedClipboardIntegration(app);

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', services: ['shared-clipboard'] });
  });

  return app;
}
