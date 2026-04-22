// @file        apps/backend/src/services/standup-summaries/integration-example.ts
// @module      standup-summaries/integration
// @description Example of how to integrate the standup summaries service into an Express application
// @owner       collab-2.9

import * as express from 'express';
import { Pool } from 'pg';
import { AIRouter } from '../ai/router';
import standupSummariesRouter, { initializeStandupRoutes } from '../../routes/standup-summaries';
import { getLogger } from '../../lib/logger';
import { AuditService } from '../audit/audit-service';

/**
 * Example of how to integrate the standup summaries service into an Express application
 */
export function setupStandupSummariesIntegration(app: express.Express, db: Pool, aiRouter: AIRouter) {
  const logger = getLogger('StandupIntegration');
  const auditService = new AuditService(db);

  // Initialize the standup summaries service with configuration
  const standupConfig = {
    githubToken: process.env.GITHUB_TOKEN, // Required for GitHub API access
    githubRepo: 'code-server',
    githubOwner: 'kushin77',
    matrixRoomId: process.env.MATRIX_ROOM_ID, // Optional: for Matrix posting
    postingTime: '09:00', // Daily posting time
    timezone: 'America/New_York',
    enabled: true,
  };

  try {
    // Initialize the service and routes
    initializeStandupRoutes(db, auditService, aiRouter, standupConfig);

    // Mount the routes under /api/standup-summaries
    app.use('/api/standup-summaries', standupSummariesRouter);

    logger.info('Standup summaries service integrated successfully', {
      postingTime: standupConfig.postingTime,
      timezone: standupConfig.timezone,
      hasGithubToken: !!standupConfig.githubToken,
      hasMatrixRoom: !!standupConfig.matrixRoomId,
    });

  } catch (error) {
    logger.error('Failed to integrate standup summaries service', { error });
    throw error;
  }
}

/**
 * Complete Express application example with standup summaries
 */
export function createExampleApp(): express.Express {
  const app = express();

  // Basic middleware
  app.use(express.json());

  // Mock database connection (replace with real connection)
  const db = new Pool({
    connectionString: process.env.DATABASE_URL || 'postgresql://localhost:5432/code-server',
  });

  // Mock AI router (replace with real AI router)
  const aiRouter = {
    route: async (request: any) => ({
      result: 'Mock AI response',
      usage: { tokens: 100 },
    }),
  } as unknown as AIRouter;

  // Integrate standup summaries
  setupStandupSummariesIntegration(app, db, aiRouter);

  // Health check endpoint
  app.get('/health', (req, res) => {
    res.json({ status: 'ok', services: ['standup-summaries'] });
  });

  return app;
}

/**
 * Example usage:
 *
 * import { createExampleApp } from './integration-example';
 *
 * const app = createExampleApp();
 * app.listen(3000, () => {
 *   console.log('Server running on port 3000');
 * });
 *
 * // Available endpoints:
 * // GET /api/standup-summaries/2024-01-01 - Get summary for specific date
 * // POST /api/standup-summaries/2024-01-01/approve - Approve draft summary
 * // POST /api/standup-summaries/2024-01-01/generate - Generate summary manually
 * // POST /api/standup-summaries/2024-01-01/post - Post approved summary to Matrix
 * // GET /api/standup-summaries - List recent summaries
 */