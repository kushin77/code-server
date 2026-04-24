import { describe, it, expect, beforeEach, vi } from 'vitest';
import { CalendarIntegrationService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn()
  })
}));

describe('CalendarIntegrationService', () => {
  let service: CalendarIntegrationService;
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

    service = new CalendarIntegrationService(mockPool);
  });

  it('initializes calendar tables', async () => {
    for (let i = 0; i < 8; i++) {
      mockClient.query.mockResolvedValueOnce({});
    }

    await service.initialize();

    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('calendar_integrations'));
    expect(mockClient.release).toHaveBeenCalled();
  });

  it('connects a calendar integration', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        user_id: 'user-1',
        provider: 'google',
        email: 'user@example.com',
        status: 'active',
        scopes: ['calendar.readonly'],
        last_synced_at: new Date(),
        created_at: new Date()
      }]
    });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    const integration = await service.connectIntegration(
      'user-1',
      'google',
      'user@example.com',
      'access-token',
      'refresh-token',
      ['calendar.readonly']
    );

    expect(integration.userId).toBe('user-1');
    expect(integration.provider).toBe('google');
  });

  it('lists integrations for a user', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          user_id: 'user-1',
          provider: 'google',
          email: 'user@example.com',
          status: 'active',
          scopes: ['calendar.readonly'],
          last_synced_at: new Date(),
          created_at: new Date()
        }
      ]
    });

    const integrations = await service.listIntegrations('user-1');

    expect(integrations).toHaveLength(1);
    expect(integrations[0].provider).toBe('google');
  });

  it('records a free busy window', async () => {
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    const window = await service.recordFreeBusyWindow(
      'user-1',
      'outlook',
      new Date('2026-04-22T13:00:00Z'),
      new Date('2026-04-22T14:00:00Z'),
      'Design review',
      true
    );

    expect(window.isBusy).toBe(true);
    expect(window.provider).toBe('outlook');
  });

  it('gets free busy windows', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          user_id: 'user-1',
          provider: 'google',
          start_time: new Date('2026-04-22T13:00:00Z'),
          end_time: new Date('2026-04-22T14:00:00Z'),
          is_busy: true,
          summary: 'Planning'
        }
      ]
    });

    const windows = await service.getFreeBusyWindows(
      'user-1',
      new Date('2026-04-22T00:00:00Z'),
      new Date('2026-04-23T00:00:00Z')
    );

    expect(windows).toHaveLength(1);
    expect(windows[0].summary).toBe('Planning');
  });

  it('syncs a presence card when busy', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          start_time: new Date('2026-04-22T13:00:00Z'),
          end_time: new Date('2026-04-22T14:00:00Z'),
          summary: 'Design review',
          provider: 'google'
        }
      ]
    });
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          user_id: 'user-1',
          state: 'in-meeting',
          message: 'In meeting until 2:00 PM',
          busy_until: new Date('2026-04-22T14:00:00Z'),
          updated_at: new Date()
        }
      ]
    });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    const card = await service.syncPresenceCard('user-1');

    expect(card.state).toBe('in-meeting');
    expect(card.message).toContain('In meeting until');
  });

  it('syncs a presence card when available', async () => {
    mockClient.query.mockResolvedValueOnce({ rows: [] });
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          user_id: 'user-1',
          state: 'available',
          message: 'Available',
          busy_until: null,
          updated_at: new Date()
        }
      ]
    });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    const card = await service.syncPresenceCard('user-1');

    expect(card.state).toBe('available');
    expect(card.message).toBe('Available');
  });

  it('gets presence card', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          user_id: 'user-1',
          state: 'busy',
          message: 'Busy in a meeting',
          busy_until: new Date('2026-04-22T14:00:00Z'),
          updated_at: new Date()
        }
      ]
    });

    const card = await service.getPresenceCard('user-1');

    expect(card?.state).toBe('busy');
  });

  it('disconnects integration', async () => {
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.disconnectIntegration('user-1', 'google');

    expect(mockClient.query).toHaveBeenCalledTimes(2);
  });

  it('emits calendar-connected event', async () => {
    let emittedEvent: any;
    service.on('calendar-connected', event => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        user_id: 'user-1',
        provider: 'google',
        email: 'user@example.com',
        status: 'active',
        scopes: [],
        last_synced_at: new Date(),
        created_at: new Date()
      }]
    });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.connectIntegration('user-1', 'google', 'user@example.com', 'a', 'b', []);

    expect(emittedEvent.userId).toBe('user-1');
  });

  it('emits free-busy-recorded event', async () => {
    let emittedEvent: any;
    service.on('free-busy-recorded', event => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.recordFreeBusyWindow('user-1', 'google', new Date(), new Date(), 'Planning', true);

    expect(emittedEvent.userId).toBe('user-1');
  });

  it('returns null for missing presence card', async () => {
    mockClient.query.mockResolvedValueOnce({ rows: [] });

    const card = await service.getPresenceCard('missing');

    expect(card).toBeNull();
  });

  it('emits presence-synced event', async () => {
    let emittedEvent: any;
    service.on('presence-synced', event => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({ rows: [] });
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        user_id: 'user-1',
        state: 'available',
        message: 'Available',
        busy_until: null,
        updated_at: new Date()
      }]
    });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.syncPresenceCard('user-1');

    expect(emittedEvent.userId).toBe('user-1');
  });

  it('emits calendar-disconnected event', async () => {
    let emittedEvent: any;
    service.on('calendar-disconnected', event => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.disconnectIntegration('user-1', 'outlook');

    expect(emittedEvent.provider).toBe('outlook');
  });
});
