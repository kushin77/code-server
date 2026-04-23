// @file        apps/backend/src/services/voice-channel/routes.ts
// @module      collaboration/voice-channel
// @description REST API routes for voice channel service

import { Router } from 'express';
import { AuditService } from '../audit/audit-service.js';

const authenticate = (_req, _res, next) => next();
const requireWorkspace = (_req, _res, next) => next();

export function initializeVoiceChannelRoutes(voiceService, auditService) {
  const router = Router();

  router.post('/api/voice/sessions', authenticate, requireWorkspace, async (req, res) => {
    try {
      const { workspaceId } = req.body;
      const userId = req.user?.id || `user-${Math.random().toString(36).slice(2, 9)}`;
      const userName = req.user?.username || 'Anonymous';

      if (!workspaceId) {
        return res.status(400).json({ error: 'workspaceId required' });
      }

      const session = await voiceService.createSession(workspaceId, userId, userName);

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
      const userId = req.user?.id || 'unknown';
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
  });

  router.post('/api/voice/sessions/:sessionId/join', authenticate, async (req, res) => {
    try {
      const { sessionId } = req.params;
      const userId = req.user?.id || `user-${Math.random().toString(36).slice(2, 9)}`;
      const userName = req.user?.username || 'Anonymous';

      const result = await voiceService.joinSession(sessionId, userId, userName);

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
      const userId = req.user?.id || 'unknown';
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
  });

  router.post('/api/voice/sessions/:sessionId/leave', authenticate, async (req, res) => {
    try {
      const { sessionId } = req.params;
      const userId = req.user?.id || `user-${Math.random().toString(36).slice(2, 9)}`;

      await voiceService.leaveSession(sessionId, userId);

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
      const userId = req.user?.id || 'unknown';
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
  });

  router.get('/api/voice/sessions/:sessionId', authenticate, async (req, res) => {
    try {
      const { sessionId } = req.params;

      const session = voiceService.getSession(sessionId);
      if (!session) {
        return res.status(404).json({ error: 'Session not found' });
      }

      const participants = voiceService.getParticipants(sessionId);
      res.json({ session, participants });
    } catch (error) {
      console.error('[VoiceChannelRoutes] Get session failed:', error);
      res.status(500).json({ error: 'Failed to retrieve session' });
    }
  });

  router.get('/api/voice/workspaces/:workspaceId/sessions', authenticate, async (req, res) => {
    try {
      const { workspaceId } = req.params;

      const sessions = voiceService.getWorkspaceSessions(workspaceId);
      res.json({ sessions });
    } catch (error) {
      console.error('[VoiceChannelRoutes] Workspace sessions failed:', error);
      res.status(500).json({ error: 'Failed to retrieve workspace sessions' });
    }
  });

  router.get('/api/voice/stats', authenticate, async (_req, res) => {
    try {
      const stats = await voiceService.getStats();
      res.json(stats);
    } catch (error) {
      console.error('[VoiceChannelRoutes] Stats failed:', error);
      res.status(500).json({ error: 'Failed to retrieve voice stats' });
    }
  });

  return router;
}

export { AuditService } from '../audit/audit-service.js';