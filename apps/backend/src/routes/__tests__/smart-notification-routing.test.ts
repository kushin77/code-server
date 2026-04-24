#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/smart-notification-routing.test.ts
// @module      routes/smart-notification-routing/tests
// @description Tests for smart notification routing routes

import express from 'express';
import request from 'supertest';
import { describe, expect, it, beforeEach } from 'vitest';

import { initializeSmartNotificationRoutingRoutes } from '../smart-notification-routing';

describe('Smart Notification Routing Routes', () => {
  let app: express.Express;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/api', initializeSmartNotificationRoutingRoutes({} as any));
  });

  it('normalizes calendar in-meeting presence to dnd status', async () => {
    const postResponse = await request(app).post('/api/status').send({
      userId: 'user-1',
      calendarStatus: 'in-meeting',
    });

    expect(postResponse.status).toBe(200);
    expect(postResponse.body.status.currentStatus).toBe('dnd');
    expect(postResponse.body.status.meetingModeActive).toBe(true);

    const getResponse = await request(app).get('/api/status/user-1');

    expect(getResponse.status).toBe(200);
    expect(getResponse.body.status.currentStatus).toBe('dnd');
    expect(getResponse.body.status.calendarStatus).toBe('in-meeting');
  });

  it('accepts explicit status updates without calendar presence', async () => {
    const response = await request(app).post('/api/status').send({
      userId: 'user-2',
      status: 'away',
    });

    expect(response.status).toBe(200);
    expect(response.body.status.currentStatus).toBe('away');
    expect(response.body.status.meetingModeActive).toBe(false);
  });
});