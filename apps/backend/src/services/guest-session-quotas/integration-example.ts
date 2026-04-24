/**
 * @file        apps/backend/src/services/guest-session-quotas/integration-example.ts
 * @module      collaboration/sessions
 * @description Example Express app integration for Guest Session Quotas service
 */

import express, { Express, Request, Response } from 'express';
import { GuestSessionQuotasService, QuotaTier } from './index';

/**
 * Set up Guest Session Quotas routes on an Express router
 */
export function initializeGuestSessionQuotasRoutes(
  router: express.Router,
  quotas: GuestSessionQuotasService,
): express.Router {
  /**
   * Create new guest session
   * POST /api/quotas/guest-sessions
   */
  router.post('/guest-sessions', (req: Request, res: Response) => {
    try {
      const { guestId, tier } = req.body;

      if (!guestId) {
        return res.status(400).json({ error: 'guestId required' });
      }

      const validTier = (Object.values(QuotaTier) as string[]).includes(tier)
        ? (tier as QuotaTier)
        : QuotaTier.FREE;

      const quota = quotas.createGuestSession(guestId, validTier);
      res.status(201).json(quota);
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  /**
   * Get guest quota usage
   * GET /api/quotas/guest-sessions/:guestId
   */
  router.get('/guest-sessions/:guestId', (req: Request, res: Response) => {
    try {
      const { guestId } = req.params;
      const quota = quotas.getQuotaUsage(guestId);

      if (!quota) {
        return res.status(404).json({ error: 'Guest session not found' });
      }

      res.json(quota);
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  /**
   * Check if can start new concurrent session
   * POST /api/quotas/guest-sessions/:guestId/can-start-concurrent
   */
  router.post('/guest-sessions/:guestId/can-start-concurrent', (req: Request, res: Response) => {
    try {
      const { guestId } = req.params;
      const canStart = quotas.canStartConcurrentSession(guestId);

      res.json({ canStart });
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  /**
   * Start new concurrent session
   * POST /api/quotas/guest-sessions/:guestId/start-concurrent
   */
  router.post('/guest-sessions/:guestId/start-concurrent', (req: Request, res: Response) => {
    try {
      const { guestId } = req.params;

      if (!quotas.canStartConcurrentSession(guestId)) {
        return res.status(429).json({ error: 'Concurrent session limit reached' });
      }

      quotas.incrementConcurrentSessions(guestId);
      const updated = quotas.getQuotaUsage(guestId);

      res.json(updated);
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  /**
   * End concurrent session
   * POST /api/quotas/guest-sessions/:guestId/end-concurrent
   */
  router.post('/guest-sessions/:guestId/end-concurrent', (req: Request, res: Response) => {
    try {
      const { guestId } = req.params;
      quotas.decrementConcurrentSessions(guestId);
      const updated = quotas.getQuotaUsage(guestId);

      res.json(updated);
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  /**
   * Check remaining session duration
   * GET /api/quotas/guest-sessions/:guestId/remaining-time
   */
  router.get('/guest-sessions/:guestId/remaining-time', (req: Request, res: Response) => {
    try {
      const { guestId } = req.params;
      const remainingMs = quotas.getRemainingSessionDuration(guestId);
      const isExceeded = quotas.isSessionDurationExceeded(guestId);

      res.json({ remainingMs, isExceeded, remainingMinutes: Math.floor(remainingMs / 60000) });
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  /**
   * Add storage usage
   * POST /api/quotas/guest-sessions/:guestId/storage
   */
  router.post('/guest-sessions/:guestId/storage', (req: Request, res: Response) => {
    try {
      const { guestId } = req.params;
      const { bytes } = req.body;

      if (bytes === undefined || bytes < 0) {
        return res.status(400).json({ error: 'bytes required and must be >= 0' });
      }

      const allowed = quotas.addStorageUsage(guestId, bytes);

      if (!allowed) {
        return res.status(429).json({ error: 'Storage quota exceeded' });
      }

      const updated = quotas.getQuotaUsage(guestId);
      res.json(updated);
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  /**
   * End guest session
   * DELETE /api/quotas/guest-sessions/:guestId
   */
  router.delete('/guest-sessions/:guestId', (req: Request, res: Response) => {
    try {
      const { guestId } = req.params;
      quotas.endGuestSession(guestId);

      res.json({ success: true });
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  /**
   * List all active quotas
   * GET /api/quotas/guest-sessions
   */
  router.get('/guest-sessions', (req: Request, res: Response) => {
    try {
      const activeQuotas = quotas.listActiveQuotas();
      res.json({ quotas: activeQuotas });
    } catch (err) {
      const error = err instanceof Error ? err.message : 'Unknown error';
      res.status(500).json({ error });
    }
  });

  return router;
}

/**
 * Set up Guest Session Quotas integration in an Express app
 */
export function setupGuestSessionQuotasIntegration(app: Express): GuestSessionQuotasService {
  const quotas = new GuestSessionQuotasService();

  // Mount routes under /api/quotas
  const router = express.Router();
  initializeGuestSessionQuotasRoutes(router, quotas);
  app.use('/api/quotas', router);

  // Log initialization
  console.log('[GuestSessionQuotas] Guest Session Quotas service initialized');

  return quotas;
}

/**
 * Create an example Express app with Guest Session Quotas support
 */
export async function createGuestSessionQuotasExampleApp(): Promise<Express> {
  const app = express();

  // Middleware
  app.use(express.json());

  // Setup Guest Session Quotas
  setupGuestSessionQuotasIntegration(app);

  // Health check
  app.get('/health', (req: Request, res: Response) => {
    res.json({ status: 'ok', service: 'guest-session-quotas-example' });
  });

  return app;
}
