// @file        apps/backend/src/services/voice-channel/routes.ts
// @module      collaboration/voice-channel
// @description REST API routes for voice channel service

import { Router, Request, Response } from 'express';
import { VoiceChannelService } from './index.js';
import { AuditService } from '../audit/audit-service.js';

// Simple auth check (in production, would import from middleware)
const authenticate = (_req: Request, _res: Response, next: Function) => next();
const requireWorkspace = (_req: Request, _res: Response, next: Function) => next();

/**
 * Create voice channel routes
 */
export function initializeVoiceChannelRoutes(
  voiceService: VoiceChannelService,
  auditService: AuditService
): Router {
  const router = Router();

  /**
   * POST /api/voice/sessions - Create new voice session
   * Request: { workspaceId: string }
   * Response: { session: VoiceSession, token: string }
   */
  router.post(
    '/api/voice/sessions',
    authenticate,
    requireWorkspace,
    async (req: Request, res: Response) => {
      try {
        const { workspaceId } = req.body;
        const userId = (req as any).user?.id || 'user-' + Math.random().toString(36).slice(2, 9);
        const userName = (req as any).user?.username || 'Anonymous';

        if (!workspaceId) {
          return res.status(400).json({ error: 'workspaceId required' });
        }

        const session = await voiceService.createSession(
          workspaceId,
          userId,
          userName
        );

        // SOC2: Audit session creation
        auditService.emit({
          userId,
          role: 'developer',
          method: 'POST',
          path: '/api/voice/sessions',
          action: 'allow',
          reason: `Created voice session for workspace ${workspaceId}`,
          statusCode: 200,
          sessionId: session.sessionId,
        });

        res.json({
          session,
          token: session.liveKitToken,
          liveKitUrl: process.env.LIVEKIT_URL || 'wss://livekit.kushnir.cloud',
        });
      } catch (error) {
        // SOC2: Audit failure
        const userId = (req as any).user?.id || 'unknown';
        auditService.emit({
          userId,
          role: 'developer',
          method: 'POST',
          path: '/api/voice/sessions',
          action: 'deny',
          reason: error instanceof Error ? error.message : 'Unknown error during session creation',
          statusCode: 500,
        });

        console.error('[VoiceChannelRoutes] Session creation failed:', error);
        res.status(500).json({ error: 'Failed to create voice session' });
      }
    }
  );

  /**
   * POST /api/voice/sessions/:sessionId/join - Join existing session
   * Response: { token: string, session: VoiceSession }
   */
  router.post(
    '/api/voice/sessions/:sessionId/join',
    authenticate,
    async (req: Request, res: Response) => {
      try {
        const { sessionId } = req.params;
        const userId = (req as any).user?.id || 'user-' + Math.random().toString(36).slice(2, 9);
        const userName = (req as any).user?.username || 'Anonymous';

        const result = await voiceService.joinSession(sessionId, userId, userName);

        // SOC2: Audit session join
        auditService.emit({
          userId,
          role: 'developer',
          method: 'POST',
          path: `/api/voice/sessions/${sessionId}/join`,
          action: 'allow',
          reason: `Joined voice session ${sessionId}`,
          statusCode: 200,
          sessionId,
        });

        res.json({
          token: result.token,
          session: result.session,
          liveKitUrl: process.env.LIVEKIT_URL || 'wss://livekit.kushnir.cloud',
        });
      } catch (error) {
        // SOC2: Audit failure
        const userId = (req as any).user?.id || 'unknown';
        auditService.emit({
          userId,
          role: 'developer',
          method: 'POST',
          path: `/api/voice/sessions/${req.params.sessionId}/join`,
          action: 'deny',
          reason: error instanceof Error ? error.message : 'Unknown error during join',
          statusCode: 400,
          sessionId: req.params.sessionId,
        });

        console.error('[VoiceChannelRoutes] Join failed:', error);
        res.status(400).json({ error: 'Failed to join voice session' });
      }
    }
  );

  /**
   * POST /api/voice/sessions/:sessionId/leave - Leave session
   */
  router.post(
    '/api/voice/sessions/:sessionId/leave',
    authenticate,
    async (req: Request, res: Response) => {
      try {
        const { sessionId } = req.params;
        const userId = (req as any).user?.id || 'user-' + Math.random().toString(36).slice(2, 9);

        await voiceService.leaveSession(sessionId, userId);

        // SOC2: Audit session leave
        auditService.emit({
          userId,
          role: 'developer',
          method: 'POST',
          path: `/api/voice/sessions/${sessionId}/leave`,
          action: 'allow',
          reason: `Left voice session ${sessionId}`,
          statusCode: 200,
          sessionId,
        });

        res.json({ success: true });
      } catch (error) {
        // SOC2: Audit failure
        const userId = (req as any).user?.id || 'unknown';
        auditService.emit({
          userId,
          role: 'developer',
          method: 'POST',
          path: `/api/voice/sessions/${req.params.sessionId}/leave`,
          action: 'deny',
          reason: error instanceof Error ? error.message : 'Unknown error during leave',
          statusCode: 400,
          sessionId: req.params.sessionId,
        });

        console.error('[VoiceChannelRoutes] Leave failed:', error);
        res.status(400).json({ error: 'Failed to leave voice session' });
      }
    }
  );

  /**
   * GET /api/voice/sessions/:sessionId - Get session details
   */
  router.get(
    '/api/voice/sessions/:sessionId',
    authenticate,
    async (req: Request, res: Response) => {
      try {
        const { sessionId } = req.params;

        const session = voiceService.getSession(sessionId);
        if (!session) {
          return res.status(404).json({ error: 'Session not found' });
        }

        const participants = voiceService.getParticipants(sessionId);

        res.json({
          session,
          participants,
        });
      } catch (error) {
        console.error('[VoiceChannelRoutes] Get session failed:', error);
        res.status(500).json({ error: 'Failed to retrieve session' });
      }
    }
  );

  /**
   * GET /api/voice/workspaces/:workspaceId/sessions - List sessions for workspace
   */
  router.get(
    '/api/voice/workspaces/:workspaceId/sessions',
    authenticate,
    async (req: Request, res: Response) => {
      try {
        const { workspaceId } = req.params;

        const sessions = voiceService.getWorkspaceSessions(workspaceId);

        res.json({
          sessions,
          count: sessions.length,
        });
      } catch (error) {
        console.error('[VoiceChannelRoutes] List sessions failed:', error);
        res.status(500).json({ error: 'Failed to list sessions' });
      }
    }
  );

  /**
   * POST /api/voice/sessions/:sessionId/metrics - Update participant metrics
   * Request: { userId: string, latencyMs?: number, audioQualityScore?: number }
   */
  router.post(
    '/api/voice/sessions/:sessionId/metrics',
    authenticate,
    async (req: Request, res: Response) => {
      try {
        const { sessionId } = req.params;
        const { userId, latencyMs, audioQualityScore } = req.body;

        await voiceService.updateParticipantMetrics(sessionId, userId, {
          latencyMs,
          audioQualityScore,
        });

        res.json({ success: true });
      } catch (error) {
        console.error('[VoiceChannelRoutes] Metrics update failed:', error);
        res.status(500).json({ error: 'Failed to update metrics' });
      }
    }
  );

  /**
   * GET /api/voice/stats - Get voice channel statistics
   */
  router.get('/api/voice/stats', authenticate, async (req: Request, res: Response) => {
    try {
      const stats = await voiceService.getStats();
      res.json(stats);
    } catch (error) {
      console.error('[VoiceChannelRoutes] Stats retrieval failed:', error);
      res.status(500).json({ error: 'Failed to retrieve statistics' });
    }
  });

  return router;
}
