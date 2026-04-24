import { describe, it, expect, beforeEach, vi } from 'vitest';
import { FunnelAnalyticsService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn()
  })
}));

describe('FunnelAnalyticsService', () => {
  let service: FunnelAnalyticsService;
  let mockPool: any;
  let mockClient: any;

  beforeEach(() => {
    mockClient = {
      query: vi.fn(),
      release: vi.fn()
    };

    mockPool = {
      connect: vi.fn().mockResolvedValue(mockClient)
    };

    service = new FunnelAnalyticsService(mockPool);
  });

  it('should initialize service and create tables', async () => {
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});

    await service.initialize();

    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('funnel_events'));
    expect(mockClient.release).toHaveBeenCalled();
  });

  it('should record a funnel event', async () => {
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});

    await service.recordFunnelEvent('user-1', 'invite', 'User Invited', { source: 'email' });

    expect(mockClient.query).toHaveBeenCalled();
  });

  it('should get user journey', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        user_id: 'user-1',
        current_step: 'session_join',
        completed_steps: ['invite', 'link_click', 'account_create']
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [
        { event_type: 'invite', occurred_at: new Date('2025-04-20T10:00:00') },
        { event_type: 'link_click', occurred_at: new Date('2025-04-20T11:00:00') },
        { event_type: 'account_create', occurred_at: new Date('2025-04-20T12:00:00') }
      ]
    });

    const journey = await service.getUserJourney('user-1');

    expect(journey).not.toBeNull();
    expect(journey?.completedSteps.length).toBe(3);
  });

  it('should normalize string-shaped completed steps', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        user_id: 'user-1',
        current_step: 'session_join',
        completed_steps: '["invite","link_click","account_create"]'
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [
        { event_type: 'invite', occurred_at: new Date('2025-04-20T10:00:00') },
        { event_type: 'link_click', occurred_at: new Date('2025-04-20T11:00:00') },
        { event_type: 'account_create', occurred_at: new Date('2025-04-20T12:00:00') }
      ]
    });

    const journey = await service.getUserJourney('user-1');

    expect(journey).not.toBeNull();
    expect(journey?.completedSteps).toEqual(['invite', 'link_click', 'account_create']);
  });

  it('should get funnel metrics', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ count: 1000 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [
        { step_number: 0, step_name: 'invite', completed_count: 1000 },
        { step_number: 1, step_name: 'link_click', completed_count: 800 },
        { step_number: 2, step_name: 'account_create', completed_count: 600 },
        { step_number: 3, step_name: 'session_join', completed_count: 500 },
        { step_number: 4, step_name: 'first_edit', completed_count: 400 },
        { step_number: 5, step_name: 'seven_day_streak', completed_count: 300 }
      ]
    });

    const metrics = await service.getFunnelMetrics();

    expect(metrics.totalUsers).toBe(1000);
    expect(metrics.totalConversions).toBe(300);
    expect(metrics.funnel.length).toBe(6);
  });

  it('should calculate conversion rate by step', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 600 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 800 }]
    });

    const rate = await service.getConversionRateByStep('onboarding', 2);

    expect(rate).toBeCloseTo(75, 1);
  });

  it('should track conversion by segment', async () => {
    let emittedEvent: any;

    service.on('conversion-tracked', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        user_id: 'user-1',
        current_step: 'first_edit',
        completed_steps: ['invite', 'link_click', 'account_create', 'session_join']
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    await service.trackConversionBySegment('user-1', 'enterprise');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.segment).toBe('enterprise');
  });

  it('should get dropoff rate between steps', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 1000 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 600 }]
    });

    const dropoff = await service.getDropoffRate('onboarding', 0, 2);

    expect(dropoff).toBeCloseTo(40, 1);
  });

  it('should return null for non-existent user journey', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const journey = await service.getUserJourney('non-existent');

    expect(journey).toBeNull();
  });

  it('should cleanup old funnel data', async () => {
    mockClient.query.mockResolvedValueOnce({
      rowCount: 5000
    });

    const count = await service.cleanupOldFunnelData(90);

    expect(count).toBe(5000);
  });

  it('should emit funnel-event-recorded event', async () => {
    let emittedEvent: any;

    service.on('funnel-event-recorded', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});

    await service.recordFunnelEvent('user-1', 'invite', 'User Invited');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.eventType).toBe('invite');
  });

  it('should handle funnel metrics with zero users', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ count: 0 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const metrics = await service.getFunnelMetrics();

    expect(metrics.totalUsers).toBe(0);
    expect(metrics.overallConversionRate).toBe(0);
  });

  it('should track conversion with correct completion rate', async () => {
    let emittedEvent: any;

    service.on('conversion-tracked', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        user_id: 'user-1',
        current_step: 'seven_day_streak',
        completed_steps: ['invite', 'link_click', 'account_create', 'session_join', 'first_edit', 'seven_day_streak']
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    await service.trackConversionBySegment('user-1', 'premium');

    expect(emittedEvent.completionRate).toBe(1);
  });

  it('should emit funnel-data-cleaned event', async () => {
    let emittedEvent: any;

    service.on('funnel-data-cleaned', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rowCount: 2000
    });

    await service.cleanupOldFunnelData(90);

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.count).toBe(2000);
  });

  it('should get conversion rate for first step', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 1000 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 1000 }]
    });

    const rate = await service.getConversionRateByStep('onboarding', 0);

    expect(rate).toBe(100);
  });

  it('should handle funnel with partial completion', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        user_id: 'user-1',
        current_step: 'first_edit',
        completed_steps: ['invite', 'link_click', 'account_create', 'session_join']
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [
        { event_type: 'invite', occurred_at: new Date('2025-04-20T10:00:00') },
        { event_type: 'link_click', occurred_at: new Date('2025-04-20T11:00:00') }
      ]
    });

    const journey = await service.getUserJourney('user-1');

    expect(journey?.currentStep).toBe('first_edit');
    expect(journey?.completedSteps.length).toBe(4);
  });

  it('should calculate conversion rate with previous step', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 500 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 800 }]
    });

    const rate = await service.getConversionRateByStep('onboarding', 3);

    expect(rate).toBeCloseTo(62.5, 1);
  });

  it('should handle dropoff when step count is zero', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 0 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ completed_count: 0 }]
    });

    const dropoff = await service.getDropoffRate('onboarding', 5, 6);

    expect(dropoff).toBe(0);
  });

  it('should record event with metadata', async () => {
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});

    const metadata = { referrer: 'google', campaign: 'summer2025' };
    await service.recordFunnelEvent('user-1', 'invite', 'User Invited', metadata);

    expect(mockClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO funnel_events'),
      expect.arrayContaining([expect.any(String), expect.any(String), expect.any(String), expect.any(Date), expect.stringContaining('referrer')])
    );
  });

  it('should handle funnel metrics calculation with decreasing counts', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ count: 500 }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [
        { step_number: 0, step_name: 'invite', completed_count: 500 },
        { step_number: 1, step_name: 'link_click', completed_count: 350 },
        { step_number: 2, step_name: 'account_create', completed_count: 200 }
      ]
    });

    const metrics = await service.getFunnelMetrics();

    expect(metrics.totalUsers).toBe(500);
    expect(metrics.overallConversionRate).toBeCloseTo(40, 1);
  });
});
