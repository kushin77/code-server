/**
 * @file        apps/backend/src/services/team-rich-presence/integration-example.ts
 * @module      collaboration/presence
 * @description Example Express app integration for Rich Presence service
 */
import express from 'express';
import { TeamRichPresenceService, PresenceState } from './index';
/**
 * Set up Rich Presence routes on an Express router
 */
export function initializeTeamRichPresenceRoutes(router, presence) {
    /**
     * Update user presence
     * POST /api/presence/users/:userId/update
     */
    router.post('/users/:userId/update', (req, res) => {
        try {
            const { userId } = req.params;
            const { teamId, state, currentFile, currentLine, statusMessage, statusEmoji } = req.body;
            if (!teamId) {
                return res.status(400).json({ error: 'teamId required' });
            }
            const updated = presence.upsertPresence(userId, teamId, {
                state: state || PresenceState.ONLINE,
                currentFile,
                currentLine,
                statusMessage,
                statusEmoji,
            });
            res.json(updated);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Get user presence
     * GET /api/presence/users/:userId?teamId=...
     */
    router.get('/users/:userId', (req, res) => {
        try {
            const { userId } = req.params;
            const { teamId } = req.query;
            if (!teamId) {
                return res.status(400).json({ error: 'teamId required' });
            }
            const userPresence = presence.getPresence(userId, teamId);
            if (!userPresence) {
                return res.status(404).json({ error: 'User presence not found' });
            }
            res.json(userPresence);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Get team presence
     * GET /api/presence/teams/:teamId/members
     */
    router.get('/teams/:teamId/members', (req, res) => {
        try {
            const { teamId } = req.params;
            const teamPresence = presence.listTeamPresence(teamId);
            res.json({ presence: teamPresence });
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Get team activity summary
     * GET /api/presence/teams/:teamId/summary
     */
    router.get('/teams/:teamId/summary', (req, res) => {
        try {
            const { teamId } = req.params;
            const summary = presence.getTeamActivitySummary(teamId);
            res.json(summary);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Set user in meeting
     * POST /api/presence/users/:userId/meeting
     */
    router.post('/users/:userId/meeting', (req, res) => {
        try {
            const { userId } = req.params;
            const { teamId, inMeeting } = req.body;
            if (!teamId || inMeeting === undefined) {
                return res.status(400).json({ error: 'teamId and inMeeting required' });
            }
            const updated = presence.setUserInMeeting(userId, teamId, inMeeting);
            res.json(updated);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Update editor position
     * POST /api/presence/users/:userId/editor
     */
    router.post('/users/:userId/editor', (req, res) => {
        try {
            const { userId } = req.params;
            const { teamId, filePath, lineNumber } = req.body;
            if (!teamId || !filePath) {
                return res.status(400).json({ error: 'teamId and filePath required' });
            }
            const updated = presence.updateEditorPosition(userId, teamId, filePath, lineNumber);
            res.json(updated);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Set custom status
     * POST /api/presence/users/:userId/status
     */
    router.post('/users/:userId/status', (req, res) => {
        try {
            const { userId } = req.params;
            const { teamId, message, emoji } = req.body;
            if (!teamId || !message) {
                return res.status(400).json({ error: 'teamId and message required' });
            }
            const updated = presence.setUserStatus(userId, teamId, message, emoji);
            res.json(updated);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Remove user presence (go offline)
     * DELETE /api/presence/users/:userId?teamId=...
     */
    router.delete('/users/:userId', (req, res) => {
        try {
            const { userId } = req.params;
            const { teamId } = req.query;
            if (!teamId) {
                return res.status(400).json({ error: 'teamId required' });
            }
            presence.removePresence(userId, teamId);
            res.json({ success: true });
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Get presence snapshot
     * GET /api/presence/teams/:teamId/snapshot
     */
    router.get('/teams/:teamId/snapshot', (req, res) => {
        try {
            const { teamId } = req.params;
            const snapshot = presence.getPresenceSnapshot(teamId);
            res.json(snapshot);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    return router;
}
/**
 * Set up Rich Presence integration in an Express app
 */
export function setupTeamRichPresenceIntegration(app) {
    const presence = new TeamRichPresenceService();
    // Mount routes under /api/presence
    const router = express.Router();
    initializeTeamRichPresenceRoutes(router, presence);
    app.use('/api/presence', router);
    // Log initialization
    console.log('[TeamRichPresence] Rich Presence service initialized');
    return presence;
}
/**
 * Create an example Express app with Rich Presence support
 */
export async function createTeamRichPresenceExampleApp() {
    const app = express();
    // Middleware
    app.use(express.json());
    // Setup Rich Presence
    setupTeamRichPresenceIntegration(app);
    // Health check
    app.get('/health', (req, res) => {
        res.json({ status: 'ok', service: 'team-rich-presence-example' });
    });
    return app;
}
//# sourceMappingURL=integration-example.js.map