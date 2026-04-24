/**
 * @file        apps/backend/src/services/team-rich-presence/__tests__/integration-example.test.ts
 * @module      collaboration/presence
 * @description Integration tests for Rich Presence service
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import { createTeamRichPresenceExampleApp } from '../integration-example';
import { PresenceState } from '../index';
import type { Express } from 'express';

describe('Team Rich Presence Integration Example', () => {
  let app: Express;

  beforeEach(async () => {
    app = await createTeamRichPresenceExampleApp();
  });

  describe('User Presence Management', () => {
    it('updates user presence state', async () => {
      const res = await request(app).post('/api/presence/users/user-1/update').send({
        teamId: 'team-1',
        state: PresenceState.ONLINE,
        statusMessage: 'Coding',
      });

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        userId: 'user-1',
        teamId: 'team-1',
        state: PresenceState.ONLINE,
        statusMessage: 'Coding',
      });
    });

    it('retrieves user presence', async () => {
      await request(app).post('/api/presence/users/user-2/update').send({
        teamId: 'team-1',
        state: PresenceState.ONLINE,
      });

      const res = await request(app).get('/api/presence/users/user-2?teamId=team-1');

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        userId: 'user-2',
        state: PresenceState.ONLINE,
      });
    });

    it('returns 404 for unknown user', async () => {
      const res = await request(app).get('/api/presence/users/unknown?teamId=team-1');
      expect(res.status).toBe(404);
    });
  });

  describe('Meeting Mode', () => {
    it('marks user as in meeting', async () => {
      const res = await request(app).post('/api/presence/users/user-1/meeting').send({
        teamId: 'team-1',
        inMeeting: true,
      });

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        state: PresenceState.IN_MEETING,
        statusMessage: 'In a meeting',
        statusEmoji: '🎤',
      });
    });

    it('marks user as no longer in meeting', async () => {
      // First set to meeting
      await request(app).post('/api/presence/users/user-1/meeting').send({
        teamId: 'team-1',
        inMeeting: true,
      });

      // Then clear meeting status
      const res = await request(app).post('/api/presence/users/user-1/meeting').send({
        teamId: 'team-1',
        inMeeting: false,
      });

      expect(res.status).toBe(200);
      expect(res.body.state).toBe(PresenceState.ONLINE);
    });
  });

  describe('Editor Position Tracking', () => {
    it('updates user editor position', async () => {
      const res = await request(app).post('/api/presence/users/user-1/editor').send({
        teamId: 'team-1',
        filePath: 'src/main.ts',
        lineNumber: 42,
      });

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        currentFile: 'src/main.ts',
        currentLine: 42,
      });
    });

    it('tracks editor position without line number', async () => {
      const res = await request(app).post('/api/presence/users/user-1/editor').send({
        teamId: 'team-1',
        filePath: 'README.md',
      });

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        currentFile: 'README.md',
      });
    });
  });

  describe('Custom Status', () => {
    it('sets custom status with emoji', async () => {
      const res = await request(app).post('/api/presence/users/user-1/status').send({
        teamId: 'team-1',
        message: 'Debugging',
        emoji: '🐛',
      });

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        statusMessage: 'Debugging',
        statusEmoji: '🐛',
      });
    });

    it('requires teamId and message', async () => {
      const res = await request(app).post('/api/presence/users/user-1/status').send({
        teamId: 'team-1',
        // missing message
      });

      expect(res.status).toBe(400);
    });
  });

  describe('Team Presence', () => {
    beforeEach(async () => {
      // Add multiple users
      await request(app).post('/api/presence/users/user-1/update').send({
        teamId: 'team-1',
        state: PresenceState.ONLINE,
      });

      await request(app).post('/api/presence/users/user-2/update').send({
        teamId: 'team-1',
        state: PresenceState.ONLINE,
      });

      await request(app).post('/api/presence/users/user-3/update').send({
        teamId: 'team-1',
        state: PresenceState.IN_MEETING,
      });
    });

    it('lists all team members', async () => {
      const res = await request(app).get('/api/presence/teams/team-1/members');

      expect(res.status).toBe(200);
      expect(res.body.presence).toHaveLength(3);
    });

    it('gets team activity summary', async () => {
      const res = await request(app).get('/api/presence/teams/team-1/summary');

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        teamId: 'team-1',
        totalMembers: 3,
        activeMembers: 3,
        membersInMeeting: 1,
      });
    });

    it('gets presence snapshot for broadcasting', async () => {
      const res = await request(app).get('/api/presence/teams/team-1/snapshot');

      expect(res.status).toBe(200);
      expect(res.body.presence).toHaveLength(3);
      expect(res.body.timestamp).toBeDefined();
    });
  });

  describe('Presence Cleanup', () => {
    it('removes user presence (goes offline)', async () => {
      // Add user
      await request(app).post('/api/presence/users/user-1/update').send({
        teamId: 'team-1',
        state: PresenceState.ONLINE,
      });

      // Remove presence
      const res = await request(app).delete('/api/presence/users/user-1?teamId=team-1');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);

      // Verify user is offline
      const checkRes = await request(app).get('/api/presence/users/user-1?teamId=team-1');
      expect(checkRes.body.state).toBe(PresenceState.OFFLINE);
    });

    it('returns 400 when teamId missing for delete', async () => {
      const res = await request(app).delete('/api/presence/users/user-1');
      expect(res.status).toBe(400);
    });
  });

  describe('Idle State Detection', () => {
    it('preserves lastActive timestamp on updates', async () => {
      const before = Date.now();

      const res = await request(app).post('/api/presence/users/user-1/update').send({
        teamId: 'team-1',
        state: PresenceState.ONLINE,
      });

      const after = Date.now();

      expect(res.body.lastActive).toBeGreaterThanOrEqual(before);
      expect(res.body.lastActive).toBeLessThanOrEqual(after);
    });
  });

  describe('Multi-Team Presence', () => {
    it('isolates presence by team', async () => {
      // Add user to team-1
      await request(app).post('/api/presence/users/user-1/update').send({
        teamId: 'team-1',
        state: PresenceState.ONLINE,
        statusMessage: 'Team 1 work',
      });

      // Add same user to team-2
      await request(app).post('/api/presence/users/user-1/update').send({
        teamId: 'team-2',
        state: PresenceState.IDLE,
        statusMessage: 'Team 2 idle',
      });

      // Verify separate presence records
      const team1 = await request(app).get('/api/presence/users/user-1?teamId=team-1');
      const team2 = await request(app).get('/api/presence/users/user-1?teamId=team-2');

      expect(team1.body).toMatchObject({
        state: PresenceState.ONLINE,
        statusMessage: 'Team 1 work',
      });

      expect(team2.body).toMatchObject({
        state: PresenceState.IDLE,
        statusMessage: 'Team 2 idle',
      });
    });
  });

  describe('Error Handling', () => {
    it('validates required fields on update', async () => {
      const res = await request(app).post('/api/presence/users/user-1/update').send({
        // missing teamId
        state: PresenceState.ONLINE,
      });

      expect(res.status).toBe(400);
      expect(res.body.error).toBeDefined();
    });

    it('handles invalid teamId gracefully', async () => {
      const res = await request(app).get('/api/presence/teams/invalid-team/members');

      expect(res.status).toBe(200);
      expect(res.body.presence).toEqual([]);
    });
  });
});
