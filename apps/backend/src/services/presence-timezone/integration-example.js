/**
 * @file        apps/backend/src/services/presence-timezone/integration-example.ts
 * @module      collaboration/presence
 * @description REST API surface for presence timezone service
 */
import { Router } from 'express';
import express from 'express';
import { PresenceTimezoneService } from './index';
export function initializePresenceTimezoneRoutes(service = PresenceTimezoneService.getInstance()) {
    const router = Router();
    /**
     * POST /api/presence-timezone/register
     * Register a user's timezone and working hours
     */
    router.post('/register', (req, res) => {
        const { userId, teamId, timezone, workingHoursStart, workingHoursEnd } = req.body;
        if (!userId || !teamId || !timezone) {
            return res.status(400).json({ error: 'Missing required fields: userId, teamId, timezone' });
        }
        try {
            const tzInfo = service.registerUserTimezone(userId, teamId, timezone, workingHoursStart, workingHoursEnd);
            res.status(201).json(tzInfo);
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/presence-timezone/user/info
     * Get timezone info for a user (timezone provided as query param to handle slashes)
     */
    router.get('/user/info', (req, res) => {
        const { userId, teamId, timezone, workingHoursStart, workingHoursEnd } = req.query;
        if (!userId || !teamId || !timezone) {
            return res.status(400).json({ error: 'Missing required query params: userId, teamId, timezone' });
        }
        try {
            const tzInfo = service.getTimezoneInfo(userId, teamId, timezone, workingHoursStart ? parseInt(workingHoursStart) : undefined, workingHoursEnd ? parseInt(workingHoursEnd) : undefined);
            res.json(tzInfo);
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/presence-timezone/presence/info
     * Get presence with timezone information (timezone provided as query param to handle slashes)
     */
    router.get('/presence/info', (req, res) => {
        const { userId, teamId, timezone, presence, lastActive } = req.query;
        if (!userId || !teamId || !timezone || !presence) {
            return res.status(400).json({ error: 'Missing required query params: userId, teamId, timezone, presence' });
        }
        const lastActiveDate = lastActive ? new Date(lastActive) : new Date();
        try {
            const presenceWithTz = service.getPresenceWithTimezone(userId, teamId, presence, lastActiveDate, timezone);
            res.json(presenceWithTz);
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * POST /api/presence-timezone/team-stats
     * Get team-wide timezone statistics
     */
    router.post('/team-stats', (req, res) => {
        const { teamId, memberTimezones } = req.body;
        if (!teamId || !memberTimezones) {
            return res.status(400).json({ error: 'Missing required fields: teamId, memberTimezones' });
        }
        try {
            const stats = service.getTeamTimezoneStats(teamId, memberTimezones);
            res.json(stats);
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/presence-timezone/timezones
     * List all available timezones
     */
    router.get('/timezones', (req, res) => {
        const timezones = service.listTimezones();
        res.json({ timezones });
    });
    /**
     * POST /api/presence-timezone/convert-time
     * Convert time from one timezone to another
     */
    router.post('/convert-time', (req, res) => {
        const { time, fromTimezone, toTimezone } = req.body;
        if (!time || !fromTimezone || !toTimezone) {
            return res.status(400).json({ error: 'Missing required fields: time, fromTimezone, toTimezone' });
        }
        try {
            const converted = service.convertTime(new Date(time), fromTimezone, toTimezone);
            res.json({ time: converted });
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * POST /api/presence-timezone/meeting-suggestions
     * Get suggested meeting times that work for all team members
     */
    router.post('/meeting-suggestions', (req, res) => {
        const { teamId, memberTimezones, durationMinutes } = req.body;
        if (!teamId || !memberTimezones) {
            return res.status(400).json({ error: 'Missing required fields: teamId, memberTimezones' });
        }
        try {
            const suggestions = service.suggestMeetingTimes(teamId, memberTimezones, durationMinutes || 60);
            res.json({ suggestions });
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    return router;
}
export function setupPresenceTimezoneIntegration(app, service = PresenceTimezoneService.getInstance()) {
    const router = initializePresenceTimezoneRoutes(service);
    app.use('/api/presence-timezone', router);
}
export async function createPresenceTimezoneExampleApp() {
    const app = express();
    app.use(express.json());
    const service = PresenceTimezoneService.getInstance();
    setupPresenceTimezoneIntegration(app, service);
    return app;
}
export { PresenceTimezoneService };
//# sourceMappingURL=integration-example.js.map