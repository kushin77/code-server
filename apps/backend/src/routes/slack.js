#!/usr/bin/env typescript
// @file        apps/backend/src/routes/slack.ts
// @module      routes/slack
// @description Slack integration API endpoints
import { Router } from 'express';
import { handleShareIdeCommand, getSessionInfo, getChannelSessions, revokeSession, verifySlackRequest, } from '../integrations/slack/handler.js';
const router = Router();
/**
 * Middleware: Verify Slack signature
 */
function verifySlackMiddleware(req, res, next) {
    if (!verifySlackRequest(req)) {
        res.status(401).json({ error: 'Invalid Slack signature' });
        return;
    }
    next();
}
/**
 * POST /api/slack/commands/share-ide
 * Handle /share-ide slash command
 */
router.post('/commands/share-ide', verifySlackMiddleware, async (req, res) => {
    await handleShareIdeCommand(req, res);
});
/**
 * GET /api/slack/sessions/:sessionId
 * Get session info by ID
 */
router.get('/sessions/:sessionId', async (req, res) => {
    try {
        const { sessionId } = req.params;
        const session = await getSessionInfo(sessionId);
        if (!session) {
            res.status(404).json({ error: 'Session not found or expired' });
            return;
        }
        res.json(session);
    }
    catch (error) {
        console.error('[Slack] Error getting session info:', error);
        res.status(500).json({ error: 'Failed to retrieve session' });
    }
});
/**
 * GET /api/slack/channels/:channelId/sessions
 * List active sessions for a channel
 */
router.get('/channels/:channelId/sessions', async (req, res) => {
    try {
        const { channelId } = req.params;
        const sessions = await getChannelSessions(channelId);
        res.json({
            channelId,
            sessions,
            count: sessions.length,
        });
    }
    catch (error) {
        console.error('[Slack] Error listing channel sessions:', error);
        res.status(500).json({ error: 'Failed to list sessions' });
    }
});
/**
 * DELETE /api/slack/sessions/:sessionId
 * Revoke a session (admin only)
 */
router.delete('/sessions/:sessionId', async (req, res) => {
    try {
        const { sessionId } = req.params;
        const adminSecret = req.headers['x-admin-secret'];
        // Verify admin secret
        if (adminSecret !== process.env.SLACK_ADMIN_SECRET) {
            res.status(401).json({ error: 'Unauthorized' });
            return;
        }
        const revoked = await revokeSession(sessionId);
        if (revoked) {
            res.json({ success: true, message: 'Session revoked' });
        }
        else {
            res.status(404).json({ error: 'Session not found' });
        }
    }
    catch (error) {
        console.error('[Slack] Error revoking session:', error);
        res.status(500).json({ error: 'Failed to revoke session' });
    }
});
/**
 * POST /api/slack/oauth/callback
 * OAuth2 callback handler
 */
router.post('/oauth/callback', async (req, res) => {
    try {
        const { code } = req.body;
        if (!code) {
            res.status(400).json({ error: 'Missing authorization code' });
            return;
        }
        // Exchange code for token (simplified - in production, use oauth2-proxy or direct Slack API)
        // This would typically authenticate with Slack's OAuth endpoint
        res.json({ success: true, message: 'Authorization successful' });
    }
    catch (error) {
        console.error('[Slack] Error in OAuth callback:', error);
        res.status(500).json({ error: 'OAuth callback failed' });
    }
});
/**
 * GET /api/slack/health
 * Health check endpoint
 */
router.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        service: 'slack-integration',
        timestamp: new Date().toISOString(),
    });
});
export default router;
//# sourceMappingURL=slack.js.map