// @file        apps/backend/src/services/debug-session-collaboration/integration-example.ts
// @module      backend/services/debug-session-collaboration
// @description Example Express integration for collaborative debugging routes
// @owner       backend

import express from 'express'

import { getLogger } from '../../lib/logger.js'
import { DebugSessionCollaborationService, initializeDebugSessionCollaborationRoutes } from './index.js'

const logger = getLogger('DebugSessionCollaborationIntegration')

/**
 * Example of how to integrate collaborative debugging into an Express application.
 */
export async function setupDebugSessionCollaborationIntegration(app: express.Express): Promise<DebugSessionCollaborationService> {
  const service = new DebugSessionCollaborationService()
  const router = await initializeDebugSessionCollaborationRoutes(service)

  app.use(router)

  logger.info('Debug session collaboration service integrated successfully')

  return service
}

/**
 * Complete Express application example with collaborative debugging routes.
 */
export async function createDebugSessionCollaborationExampleApp(): Promise<express.Express> {
  const app = express()

  app.use(express.json())

  await setupDebugSessionCollaborationIntegration(app)

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', services: ['debug-session-collaboration'] })
  })

  return app
}

/**
 * Example usage:
 *
 * import { createDebugSessionCollaborationExampleApp } from './integration-example';
 *
 * const app = await createDebugSessionCollaborationExampleApp();
 * app.listen(3000, () => {
 *   console.log('Server running on port 3000');
 * });
 *
 * // Available endpoints:
 * // GET /api/debug-sessions - List sessions
 * // POST /api/debug-sessions - Create session
 * // GET /api/debug-sessions/:sessionId - Get session details
 * // POST /api/debug-sessions/:sessionId/join - Join session
 * // POST /api/debug-sessions/:sessionId/leave - Leave session
 * // PUT /api/debug-sessions/:sessionId/breakpoints - Share breakpoints
 * // PUT /api/debug-sessions/:sessionId/variables - Share variable snapshots
 * // POST /api/debug-sessions/:sessionId/step - Record step action
 * // POST /api/debug-sessions/:sessionId/relay - Relay DAP message
 */