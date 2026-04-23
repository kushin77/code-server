/**
 * @file        apps/backend/src/services/presence-timezone/integration-example.ts
 * @module      collaboration/presence
 * @description REST API surface for presence timezone service
 */

import { Router, Request, Response, Express } from 'express';
import express from 'express';
import { PresenceTimezoneService } from './index';
import type { TimezoneInfo, PresenceWithTimezone, TeamTimezoneStats } from './index';

export function initializePresenceTimezoneRoutes(
  service: PresenceTimezoneService = PresenceTimezoneService.getInstance()
): Router {
  const router = Router();

  /**
   * POST /api/presence-timezone/register
   * Register a user's timezone and working hours
   */
  router.post('/register', (req: Request, res: Response) => {
    const { userId, teamId, timezone, workingHoursStart, workingHoursEnd } = req.body;

    if (!userId || !teamId || !timezone) {
      return res.status(400).json({ error: 'Missing required fields: userId, teamId, timezone' });
    }

    try {
      const tzInfo = service.registerUserTimezone(userId, teamId, timezone, workingHoursStart, workingHoursEnd);
      res.status(201).json(tzInfo);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  /**
   * GET /api/presence-timezone/user/:userId/team/:teamId/:timezone
   * Get timezone info for a user
   */
  router.get('/user/:userId/team/:teamId/:timezone', (req: Request, res: Response) => {
    const { userId, teamId, timezone } = req.params;
    const { workingHoursStart, workingHoursEnd } = req.query;

    try {
      const tzInfo = service.getTimezoneInfo(
        userId,
        teamId,
        timezone,
        workingHoursStart ? parseInt(workingHoursStart as string) : undefined,
        workingHoursEnd ? parseInt(workingHoursEnd as string) : undefined
      );
      res.json(tzInfo);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  /**
   * GET /api/presence-timezone/presence/:userId/team/:teamId/:timezone/:presence
   * Get presence with timezone information
   */
  router.get('/presence/:userId/team/:teamId/:timezone/:presence', (req: Request, res: Response) => {
    const { userId, teamId, timezone, presence } = req.params;
    const lastActive = req.query.lastActive ? new Date(req.query.lastActive as string) : new Date();

    try {
      const presenceWithTz = service.getPresenceWithTimezone(userId, teamId, presence, lastActive, timezone);
      res.json(presenceWithTz);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  /**
   * POST /api/presence-timezone/team-stats
   * Get team-wide timezone statistics
   */
  router.post('/team-stats', (req: Request, res: Response) => {
    const { teamId, memberTimezones } = req.body;

    if (!teamId || !memberTimezones) {
      return res.status(400).json({ error: 'Missing required fields: teamId, memberTimezones' });
    }

    try {
      const stats = service.getTeamTimezoneStats(teamId, memberTimezones);
      res.json(stats);
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  /**
   * GET /api/presence-timezone/timezones
   * List all available timezones
   */
  router.get('/timezones', (req: Request, res: Response) => {
    const timezones = service.listTimezones();
    res.json({ timezones });
  });

  /**
   * POST /api/presence-timezone/convert-time
   * Convert time from one timezone to another
   */
  router.post('/convert-time', (req: Request, res: Response) => {
    const { time, fromTimezone, toTimezone } = req.body;

    if (!time || !fromTimezone || !toTimezone) {
      return res.status(400).json({ error: 'Missing required fields: time, fromTimezone, toTimezone' });
    }

    try {
      const converted = service.convertTime(new Date(time), fromTimezone, toTimezone);
      res.json({ time: converted });
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  /**
   * POST /api/presence-timezone/meeting-suggestions
   * Get suggested meeting times that work for all team members
   */
  router.post('/meeting-suggestions', (req: Request, res: Response) => {
    const { teamId, memberTimezones, durationMinutes } = req.body;

    if (!teamId || !memberTimezones) {
      return res.status(400).json({ error: 'Missing required fields: teamId, memberTimezones' });
    }

    try {
      const suggestions = service.suggestMeetingTimes(teamId, memberTimezones, durationMinutes || 60);
      res.json({ suggestions });
    } catch (err: any) {
      res.status(400).json({ error: err.message });
    }
  });

  return router;
}

export function setupPresenceTimezoneIntegration(
  app: Express,
  service: PresenceTimezoneService = PresenceTimezoneService.getInstance()
): void {
  const router = initializePresenceTimezoneRoutes(service);
  app.use('/api/presence-timezone', router);
}

export async function createPresenceTimezoneExampleApp(): Promise<Express> {
  const app = express();
  app.use(express.json());

  const service = PresenceTimezoneService.getInstance();
  setupPresenceTimezoneIntegration(app, service);

  return app;
}

export { PresenceTimezoneService };
export type { TimezoneInfo, PresenceWithTimezone, TeamTimezoneStats };
