import { describe, it, expect, beforeEach, vi } from 'vitest';
import { SessionReplayTimelineService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn()
  })
}));

describe('SessionReplayTimelineService', () => {
  let service: SessionReplayTimelineService;
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

    service = new SessionReplayTimelineService(mockPool);
  });

  it('should initialize service and create tables', async () => {
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});

    await service.initialize();

    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('session_replay_timeline'));
    expect(mockClient.release).toHaveBeenCalled();
  });

  it('should record an event', async () => {
    const eventId = '123e4567-e89b-12d3-a456-426614174000';
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: eventId,
        session_id: 'session-1',
        event_type: 'click',
        timestamp: 1234567890,
        event_data: { x: 100, y: 200 },
        user_action: 'button_click',
        ip_address: '192.168.1.1',
        user_agent: 'Mozilla/5.0'
      }]
    });

    const event = await service.recordEvent('session-1', 'user-1', 'click', { x: 100, y: 200 }, 'button_click', '192.168.1.1', 'Mozilla/5.0');

    expect(event.eventType).toBe('click');
    expect(event.eventData).toEqual({ x: 100, y: 200 });
    expect(event.userAction).toBe('button_click');
  });

  it('should get session replay with events', async () => {
    const sessionId = '123e4567-e89b-12d3-a456-426614174000';
    
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: sessionId,
        user_id: 'user-1',
        start_time: new Date('2025-04-21T10:00:00'),
        end_time: new Date('2025-04-21T10:30:00'),
        duration_seconds: 1800,
        event_count: 5
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: 'event-1',
        session_id: sessionId,
        event_type: 'click',
        timestamp: 1234567890,
        event_data: { target: 'button' },
        user_action: 'click',
        ip_address: '192.168.1.1',
        user_agent: 'Mozilla/5.0'
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: 'deploy-1',
        deployment_time: new Date('2025-04-21T10:15:00'),
        version: '1.0.0',
        environment: 'prod',
        changes_summary: 'Fixed bug'
      }]
    });

    const replay = await service.getSessionReplay(sessionId);

    expect(replay).not.toBeNull();
    expect(replay?.sessionId).toBe(sessionId);
    expect(replay?.events.length).toBe(1);
    expect(replay?.deployments.length).toBe(1);
  });

  it('should create a session', async () => {
    const sessionId = '123e4567-e89b-12d3-a456-426614174000';
    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: sessionId }]
    });

    const result = await service.createSession('user-1', new Date());

    expect(result).toBe(sessionId);
  });

  it('should end a session with duration calculation', async () => {
    const sessionId = '123e4567-e89b-12d3-a456-426614174000';
    const startTime = new Date('2025-04-21T10:00:00');

    mockClient.query.mockResolvedValueOnce({
      rows: [{ start_time: startTime }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ count: 5 }]
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.endSession(sessionId);

    expect(mockClient.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE session_replay_sessions'),
      expect.any(Array)
    );
  });

  it('should record a deployment overlay', async () => {
    const deploymentId = '123e4567-e89b-12d3-a456-426614174000';
    const deploymentTime = new Date('2025-04-21T10:15:00');

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: deploymentId,
        deployment_time: deploymentTime,
        version: '1.0.0',
        environment: 'prod',
        changes_summary: 'Fixed bug'
      }]
    });

    const deployment = await service.recordDeployment(deploymentTime, '1.0.0', 'prod', 'Fixed bug');

    expect(deployment.version).toBe('1.0.0');
    expect(deployment.environment).toBe('prod');
  });

  it('should get event detail by ID', async () => {
    const eventId = '123e4567-e89b-12d3-a456-426614174000';

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: eventId,
        session_id: 'session-1',
        event_type: 'click',
        timestamp: 1234567890,
        event_data: { x: 100, y: 200 },
        user_action: 'button_click',
        ip_address: '192.168.1.1',
        user_agent: 'Mozilla/5.0'
      }]
    });

    const event = await service.getEventDetail(eventId);

    expect(event?.eventData).toEqual({ x: 100, y: 200 });
  });

  it('should cleanup old sessions', async () => {
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: 'session-1' }, { id: 'session-2' }]
    });

    const count = await service.cleanupOldSessions(30);

    expect(count).toBe(2);
  });

  it('should return null for non-existent session', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const replay = await service.getSessionReplay('non-existent');

    expect(replay).toBeNull();
  });

  it('should emit event-recorded event', async () => {
    const eventId = '123e4567-e89b-12d3-a456-426614174000';
    let emittedEvent: any;

    service.on('event-recorded', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: eventId,
        session_id: 'session-1',
        event_type: 'click',
        timestamp: 1234567890,
        event_data: {},
        user_action: null,
        ip_address: null,
        user_agent: null
      }]
    });

    await service.recordEvent('session-1', 'user-1', 'click', {});

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.eventType).toBe('click');
  });

  it('should emit deployment-recorded event', async () => {
    const deploymentId = '123e4567-e89b-12d3-a456-426614174000';
    let emittedEvent: any;

    service.on('deployment-recorded', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: deploymentId,
        deployment_time: new Date('2025-04-21T10:15:00'),
        version: '1.0.0',
        environment: 'prod',
        changes_summary: null
      }]
    });

    await service.recordDeployment(new Date(), '1.0.0', 'prod');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.version).toBe('1.0.0');
  });

  it('should handle session replay with event type filter', async () => {
    const sessionId = '123e4567-e89b-12d3-a456-426614174000';

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: sessionId,
        user_id: 'user-1',
        start_time: new Date('2025-04-21T10:00:00'),
        end_time: new Date('2025-04-21T10:30:00'),
        duration_seconds: 1800,
        event_count: 5
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: 'event-1',
        session_id: sessionId,
        event_type: 'click',
        timestamp: 1234567890,
        event_data: {},
        user_action: 'click',
        ip_address: '192.168.1.1',
        user_agent: 'Mozilla/5.0'
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const replay = await service.getSessionReplay(sessionId, { eventTypes: ['click'] });

    expect(replay?.events).toBeDefined();
  });

  it('should handle session creation with user id', async () => {
    const sessionId = '123e4567-e89b-12d3-a456-426614174000';
    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: sessionId }]
    });

    const result = await service.createSession('user-1', new Date('2025-04-21T10:00:00'));

    expect(result).toBe(sessionId);
    expect(mockClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO session_replay_sessions'),
      expect.any(Array)
    );
  });

  it('should return null for non-existent event', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const event = await service.getEventDetail('non-existent');

    expect(event).toBeNull();
  });

  it('should handle event query with time filters', async () => {
    const sessionId = '123e4567-e89b-12d3-a456-426614174000';
    const startTime = new Date('2025-04-21T10:00:00');
    const endTime = new Date('2025-04-21T10:30:00');

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: sessionId,
        user_id: 'user-1',
        start_time: startTime,
        end_time: endTime,
        duration_seconds: 1800,
        event_count: 5
      }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const replay = await service.getSessionReplay(sessionId, {
      startTime: new Date('2025-04-21T10:05:00'),
      endTime: new Date('2025-04-21T10:25:00')
    });

    expect(replay).not.toBeNull();
  });

  it('should emit session-created event', async () => {
    const sessionId = '123e4567-e89b-12d3-a456-426614174000';
    let emittedEvent: any;

    service.on('session-created', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ id: sessionId }]
    });

    await service.createSession('user-1', new Date());

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.sessionId).toBe(sessionId);
  });

  it('should emit session-ended event', async () => {
    const sessionId = '123e4567-e89b-12d3-a456-426614174000';
    let emittedEvent: any;

    service.on('session-ended', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ start_time: new Date('2025-04-21T10:00:00') }]
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{ count: 5 }]
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.endSession(sessionId);

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.duration).toBeDefined();
  });
});
