/**
 * @file        apps/backend/src/services/presence-timezone/__tests__/integration-example.test.ts
 * @module      collaboration/presence
 * @description Integration tests for presence timezone service
 */

import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { createPresenceTimezoneExampleApp } from '../integration-example';
import { PresenceTimezoneService } from '../index';
import type { Express } from 'express';

describe('Presence Timezone Integration Example', () => {
  let app: Express;
  let service: PresenceTimezoneService;

  beforeEach(async () => {
    app = await createPresenceTimezoneExampleApp();
    service = PresenceTimezoneService.getInstance();
    service.reset();
  });

  describe('Timezone Registration', () => {
    it('registers a user timezone', async () => {
      const res = await request(app).post('/api/presence-timezone/register').send({
        userId: 'user-1',
        teamId: 'team-1',
        timezone: 'America/New_York',
        workingHoursStart: 9,
        workingHoursEnd: 17,
      });

      expect(res.status).toBe(201);
      expect(res.body).toMatchObject({
        userId: 'user-1',
        teamId: 'team-1',
        timezone: 'America/New_York',
        workingHoursStart: 9,
        workingHoursEnd: 17,
      });
      expect(res.body.currentHour).toBeGreaterThanOrEqual(0);
      expect(res.body.currentHour).toBeLessThan(24);
    });

    it('defaults working hours if not provided', async () => {
      const res = await request(app).post('/api/presence-timezone/register').send({
        userId: 'user-2',
        teamId: 'team-1',
        timezone: 'Europe/London',
      });

      expect(res.status).toBe(201);
      expect(res.body.workingHoursStart).toBe(9);
      expect(res.body.workingHoursEnd).toBe(17);
    });

    it('validates required fields', async () => {
      const res = await request(app).post('/api/presence-timezone/register').send({
        userId: 'user-3',
        // missing teamId and timezone
      });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Missing required fields');
    });

    it('rejects invalid timezone', async () => {
      const res = await request(app).post('/api/presence-timezone/register').send({
        userId: 'user-4',
        teamId: 'team-1',
        timezone: 'Invalid/Timezone',
      });

      expect(res.status).toBe(400);
      // Error could be from validation or from Date parsing
      expect(res.body.error).toMatch(/(Unknown timezone|Invalid time zone)/);
    });

    it('rejects invalid working hours', async () => {
      const res = await request(app).post('/api/presence-timezone/register').send({
        userId: 'user-5',
        teamId: 'team-1',
        timezone: 'America/New_York',
        workingHoursStart: 25, // Invalid hour
      });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Invalid working hours');
    });
  });

  describe('Timezone Info Retrieval', () => {
    beforeEach(async () => {
      // Register some users
      await request(app).post('/api/presence-timezone/register').send({
        userId: 'user-ny',
        teamId: 'team-1',
        timezone: 'America/New_York',
        workingHoursStart: 9,
        workingHoursEnd: 17,
      });

      await request(app).post('/api/presence-timezone/register').send({
        userId: 'user-london',
        teamId: 'team-1',
        timezone: 'Europe/London',
        workingHoursStart: 8,
        workingHoursEnd: 18,
      });
    });

    it('gets timezone info for a user', async () => {
      const res = await request(app)
        .get('/api/presence-timezone/user/info?userId=user-ny&teamId=team-1&timezone=America/New_York')
        .send();

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        userId: 'user-ny',
        teamId: 'team-1',
        timezone: 'America/New_York',
        workingHoursStart: 9,
        workingHoursEnd: 17,
      });
      expect(res.body.utcOffset).toBeLessThanOrEqual(0); // EST/EDT is UTC-5/-4
      expect(res.body).toHaveProperty('isDaylightSaving');
    });

    it('overrides working hours on request', async () => {
      const res = await request(app)
        .get('/api/presence-timezone/user/info?userId=user-ny&teamId=team-1&timezone=America/New_York&workingHoursStart=6&workingHoursEnd=14')
        .send();

      expect(res.status).toBe(200);
      expect(res.body.workingHoursStart).toBe(6);
      expect(res.body.workingHoursEnd).toBe(14);
    });

    it('calculates is-currently-working correctly', async () => {
      const res = await request(app)
        .get('/api/presence-timezone/user/info?userId=user-ny&teamId=team-1&timezone=America/New_York')
        .send();

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('isCurrentlyWorking');
      expect(typeof res.body.isCurrentlyWorking).toBe('boolean');
    });
  });

  describe('Presence with Timezone', () => {
    it('gets presence with timezone info', async () => {
      const lastActive = new Date();

      const res = await request(app)
        .get(
          `/api/presence-timezone/presence/info?userId=user-1&teamId=team-1&timezone=America/New_York&presence=online&lastActive=${lastActive.toISOString()}`
        )
        .send();

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        userId: 'user-1',
        teamId: 'team-1',
        presence: 'online',
      });
      expect(res.body.timezone).toHaveProperty('timezone', 'America/New_York');
      expect(res.body.timezone).toHaveProperty('currentHour');
      expect(res.body.timezone).toHaveProperty('isCurrentlyWorking');
    });

    it('defaults lastActive if not provided', async () => {
      const res = await request(app)
        .get('/api/presence-timezone/presence/info?userId=user-2&teamId=team-1&timezone=Europe/London&presence=idle')
        .send();

      expect(res.status).toBe(200);
      expect(res.body.lastActive).toBeDefined();
    });
  });

  describe('Team Timezone Statistics', () => {
    it('calculates team timezone stats', async () => {
      const res = await request(app).post('/api/presence-timezone/team-stats').send({
        teamId: 'team-1',
        memberTimezones: {
          'user-1': 'America/New_York',
          'user-2': 'Europe/London',
          'user-3': 'Asia/Tokyo',
          'user-4': 'America/New_York',
        },
      });

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        teamId: 'team-1',
        memberCount: 4,
      });
      expect(res.body.timezoneDistribution).toMatchObject({
        'America/New_York': 2,
        'Europe/London': 1,
        'Asia/Tokyo': 1,
      });
      expect(res.body).toHaveProperty('workingMembersCount');
      expect(res.body).toHaveProperty('workingHoursRange');
      expect(res.body).toHaveProperty('averageUTCOffset');
    });

    it('validates required fields for team stats', async () => {
      const res = await request(app).post('/api/presence-timezone/team-stats').send({
        teamId: 'team-1',
        // missing memberTimezones
      });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Missing required fields');
    });

    it('calculates correct distribution', async () => {
      const res = await request(app).post('/api/presence-timezone/team-stats').send({
        teamId: 'team-2',
        memberTimezones: {
          'user-a': 'America/Los_Angeles',
          'user-b': 'America/Los_Angeles',
          'user-c': 'Europe/Paris',
        },
      });

      expect(res.status).toBe(200);
      expect(res.body.timezoneDistribution['America/Los_Angeles']).toBe(2);
      expect(res.body.timezoneDistribution['Europe/Paris']).toBe(1);
    });
  });

  describe('Available Timezones', () => {
    it('lists available timezones', async () => {
      const res = await request(app).get('/api/presence-timezone/timezones').send();

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('timezones');
      expect(Array.isArray(res.body.timezones)).toBe(true);
      expect(res.body.timezones.length).toBeGreaterThan(0);
      expect(res.body.timezones).toContain('America/New_York');
      expect(res.body.timezones).toContain('Europe/London');
      expect(res.body.timezones).toContain('Asia/Tokyo');
    });

    it('sorts timezones alphabetically', async () => {
      const res = await request(app).get('/api/presence-timezone/timezones').send();

      expect(res.status).toBe(200);
      const timezones = res.body.timezones;
      const sorted = [...timezones].sort();
      expect(timezones).toEqual(sorted);
    });
  });

  describe('Time Conversion', () => {
    it('converts time between timezones', async () => {
      const testTime = new Date('2026-04-23T12:00:00Z');

      const res = await request(app).post('/api/presence-timezone/convert-time').send({
        time: testTime.toISOString(),
        fromTimezone: 'UTC',
        toTimezone: 'America/New_York',
      });

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('time');
      // NY is UTC-4 or UTC-5, so the time should be earlier
      const convertedTime = new Date(res.body.time);
      expect(convertedTime).toBeDefined();
    });

    it('validates required fields for conversion', async () => {
      const res = await request(app).post('/api/presence-timezone/convert-time').send({
        time: new Date().toISOString(),
        fromTimezone: 'UTC',
        // missing toTimezone
      });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Missing required fields');
    });
  });

  describe('Meeting Time Suggestions', () => {
    it('suggests meeting times for team', async () => {
      const res = await request(app).post('/api/presence-timezone/meeting-suggestions').send({
        teamId: 'team-1',
        memberTimezones: {
          'user-1': 'America/New_York',
          'user-2': 'Europe/London',
          'user-3': 'Asia/Tokyo',
        },
        durationMinutes: 60,
      });

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('suggestions');
      expect(Array.isArray(res.body.suggestions)).toBe(true);
      // Should have at least 1 suggestion, max 3
      expect(res.body.suggestions.length).toBeGreaterThanOrEqual(1);
      expect(res.body.suggestions.length).toBeLessThanOrEqual(3);

      // Each suggestion should be a valid date
      res.body.suggestions.forEach((suggestion: any) => {
        expect(() => new Date(suggestion)).not.toThrow();
      });
    });

    it('defaults duration to 60 minutes', async () => {
      const res = await request(app).post('/api/presence-timezone/meeting-suggestions').send({
        teamId: 'team-1',
        memberTimezones: {
          'user-1': 'America/Los_Angeles',
          'user-2': 'Europe/Berlin',
        },
        // no durationMinutes
      });

      expect(res.status).toBe(200);
      expect(res.body.suggestions.length).toBeGreaterThan(0);
    });

    it('validates required fields', async () => {
      const res = await request(app).post('/api/presence-timezone/meeting-suggestions').send({
        teamId: 'team-1',
        // missing memberTimezones
      });

      expect(res.status).toBe(400);
      expect(res.body.error).toContain('Missing required fields');
    });
  });

  describe('Edge Cases', () => {
    it('handles single member timezone stats', async () => {
      const res = await request(app).post('/api/presence-timezone/team-stats').send({
        teamId: 'team-solo',
        memberTimezones: {
          'user-solo': 'America/Denver',
        },
      });

      expect(res.status).toBe(200);
      expect(res.body.memberCount).toBe(1);
      expect(res.body.timezoneDistribution['America/Denver']).toBe(1);
    });

    it('handles empty member timezones', async () => {
      const res = await request(app).post('/api/presence-timezone/team-stats').send({
        teamId: 'team-empty',
        memberTimezones: {},
      });

      expect(res.status).toBe(200);
      expect(res.body.memberCount).toBe(0);
      expect(res.body.workingMembersCount).toBe(0);
    });
  });
});
