import { describe, it, expect, vi, beforeEach } from 'vitest';
import { SessionLifecycleCoordinator } from '../session-lifecycle-coordinator';
import { HibernationService } from '../../session-hibernation-service';
import { SessionSnapshotService } from '../../session-snapshot-service';
import { SessionBrokerService } from '../../../session-broker/session-broker-service';
import pino from 'pino';

const logger = pino({ level: 'silent' });

describe('SessionLifecycleCoordinator', () => {
  let coordinator: SessionLifecycleCoordinator;
  let hibernation: HibernationService;
  let snapshots: SessionSnapshotService;
  let broker: SessionBrokerService;

  beforeEach(() => {
    hibernation = {
      hibernateSession: vi.fn().mockResolvedValue({ status: 'success' }),
      restoreSession: vi.fn().mockResolvedValue({ status: 'success' }),
      on: vi.fn(),
      emit: vi.fn(),
    } as unknown as HibernationService;

    snapshots = {
      createSnapshot: vi.fn().mockResolvedValue({ id: 'snap-123' }),
    } as unknown as SessionSnapshotService;

    broker = {
      routeSession: vi.fn(),
    } as unknown as SessionBrokerService;

    coordinator = new SessionLifecycleCoordinator(
      {
        autoHibernationEnabled: true,
        idleTimeoutMs: 300000,
        snapshotBeforeHibernation: true,
      },
      hibernation,
      snapshots,
      broker,
      logger
    );
  });

  it('should successfully hibernate and snapshot an idle session', async () => {
    await coordinator.handleSessionIdle('sess-1', 'user-1');

    expect(snapshots.createSnapshot).toHaveBeenCalledWith(
      'user-1',
      'user-1@kushnir.cloud',
      'ws-sess-1',
      'sess-1',
      expect.any(Object)
    );

    expect(hibernation.hibernateSession).toHaveBeenCalledWith(
      'sess-1',
      'user-1',
      'ws-sess-1'
    );
  });

  it('should successfully wake up a hibernated session', async () => {
    await coordinator.handleSessionWakeup('sess-1', 'user-1');
    expect(hibernation.restoreSession).toHaveBeenCalledWith('sess-1', 'user-1');
  });

  it('should emit failure event if hibernation fails', async () => {
    const error = new Error('CRIU failure');
    (hibernation.hibernateSession as any).mockRejectedValue(error);

    const failListener = vi.fn();
    coordinator.on('hibernation-failed', failListener);

    await coordinator.handleSessionIdle('sess-1', 'user-1');

    expect(failListener).toHaveBeenCalledWith({
      sessionId: 'sess-1',
      userId: 'user-1',
      error: error,
    });
  });
});
