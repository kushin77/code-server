/**
 * Session Lifecycle Coordinator
 * Orchestrates Hibernation, Broker, and Snapshots for RAM/Latency optimization
 */

import { EventEmitter } from 'events';
import pino from 'pino';
import { HibernationService } from '../session-hibernation-service.js';
import { SessionSnapshotService } from '../session-snapshot-service.js';
import { SessionBrokerService } from '../../session-broker/session-broker-service.js';

export interface CoordinatorConfig {
  autoHibernationEnabled: boolean;
  idleTimeoutMs: number;
  snapshotBeforeHibernation: boolean;
}

/**
 * Coordinator that manages session state transitions across the cluster.
 */
export class SessionLifecycleCoordinator extends EventEmitter {
  private static instance: SessionLifecycleCoordinator;
  private logger: pino.Logger;
  
  private hibernation: HibernationService;
  private snapshots: SessionSnapshotService;
  private broker: SessionBrokerService;

  constructor(
    config: CoordinatorConfig,
    hibernation: HibernationService,
    snapshots: SessionSnapshotService,
    broker: SessionBrokerService,
    logger?: pino.Logger
  ) {
    super();
    this.hibernation = hibernation;
    this.snapshots = snapshots;
    this.broker = broker;
    this.logger = logger || pino({ name: 'session-lifecycle-coordinator' });

    this.logger.info('SessionLifecycleCoordinator initialized');
  }

  static getInstance(
    config: CoordinatorConfig,
    hibernation: HibernationService,
    snapshots: SessionSnapshotService,
    broker: SessionBrokerService
  ): SessionLifecycleCoordinator {
    if (!SessionLifecycleCoordinator.instance) {
      SessionLifecycleCoordinator.instance = new SessionLifecycleCoordinator(
        config,
        hibernation,
        snapshots,
        broker
      );
    }
    return SessionLifecycleCoordinator.instance;
  }

  /**
   * Handle session idle event from broker or monitor
   */
  async handleSessionIdle(sessionId: string, userId: string): Promise<void> {
    this.logger.info({ sessionId, userId }, 'Session idle detected, triggering hibernation protocol');

    try {
      // 1. Snapshot if enabled
      const userEmail = `${userId}@kushnir.cloud`; // Simplified for now
      const workspaceId = `ws-${sessionId}`; // Simplified
      
      await this.snapshots.createSnapshot(userId, userEmail, workspaceId, sessionId, {
        description: 'Automatic pre-hibernation snapshot',
        version: '1.0.0',
        metadata: { trigger: 'idle-hibernation' },
        files: [], // Captured by snapshot service internally
        layout: { editors: [] },
        terminals: [],
        debug: { sessions: [] },
        settings: {}
      });

      // 2. Hibernate
      await this.hibernation.hibernateSession(sessionId, userId, workspaceId);

      this.logger.info({ sessionId }, 'Session successfully hibernated and snapshotted');
      this.emit('session-hibernated', { sessionId, userId });
    } catch (error) {
      this.logger.error({ sessionId, error }, 'Failed to hibernate session');
      this.emit('hibernation-failed', { sessionId, userId, error });
    }
  }

  /**
   * Wake up a session
   */
  async handleSessionWakeup(sessionId: string, userId: string): Promise<void> {
    this.logger.info({ sessionId, userId }, 'Session wakeup requested');

    try {
      await this.hibernation.restoreSession(sessionId, userId);
      this.logger.info({ sessionId }, 'Session successfully restored from hibernation');
      this.emit('session-restored', { sessionId, userId });
    } catch (error) {
      this.logger.error({ sessionId, error }, 'Failed to restore session from hibernation');
      this.emit('restore-failed', { sessionId, userId, error });
    }
  }
}
