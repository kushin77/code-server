// @file        apps/backend/src/services/screen-share/index.ts
// @module      collaboration/screen-share
// @description CRDT-backed screen sharing with live cursor tracking and drawing annotations

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import Redis from 'ioredis';
import { AuditService } from '../audit/audit-service.js';
import {
  ScreenShareSession,
  ScreenShareAnnotation,
  CursorPosition,
  ScreenShareConfig,
  ScreenShareEvent,
} from './types.js';

/**
 * Screen share service managing real-time screen sharing with CRDT-backed annotations
 * - Creates/manages screen share sessions per workspace
 * - Tracks participant presence and cursor positions
 * - Manages drawing annotations synced via CRDT
 * - Emits events for real-time synchronization
 */
export class ScreenShareService extends EventEmitter {
  private config: ScreenShareConfig;
  private pool: Pool;
  private redis: Redis;
  private auditService?: AuditService;
  private activeSessions: Map<string, ScreenShareSession> = new Map();
  private sessionAnnotations: Map<string, ScreenShareAnnotation[]> = new Map();
  private cursorPositions: Map<string, CursorPosition[]> = new Map();

  constructor(config: ScreenShareConfig, pool: Pool, redis: Redis, auditService?: AuditService) {
    super();
    this.config = config;
    this.pool = pool;
    this.redis = redis;
    this.auditService = auditService;

    if (!config.workspaceId) {
      throw new Error('Workspace ID required for screen share');
    }
  }

  /**
   * Start a new screen share session
   */
  async startSession(presenterId: string): Promise<ScreenShareSession> {
    const sessionId = `screen-share-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    const session: ScreenShareSession = {
      id: sessionId,
      workspaceId: this.config.workspaceId,
      presenterId,
      participantIds: [presenterId],
      startedAt: new Date(),
      isActive: true,
    };

    this.activeSessions.set(sessionId, session);
    this.sessionAnnotations.set(sessionId, []);
    this.cursorPositions.set(sessionId, []);

    // SOC2: Audit screen share session start
    this.auditService?.emit({
      userId: presenterId,
      action: 'CREATE',
      resource: 'ScreenShareSession',
      resourceId: sessionId,
      metadata: {
        workspaceId: this.config.workspaceId,
        presenterId,
        crdtBackend: this.config.crdtBackend || 'yjs',
      },
    });

    this.emit('session_started', session);
    return session;
  }

  /**
   * Join an active screen share session
   */
  async joinSession(sessionId: string, userId: string): Promise<ScreenShareSession> {
    const session = this.activeSessions.get(sessionId);
    if (!session || !session.isActive) {
      throw new Error(`Session ${sessionId} not found or inactive`);
    }

    if (!session.participantIds.includes(userId)) {
      session.participantIds.push(userId);

      // SOC2: Audit participant join
      this.auditService?.emit({
        userId,
        action: 'UPDATE',
        resource: 'ScreenShareSession',
        resourceId: sessionId,
        metadata: {
          event: 'participant_joined',
          participantCount: session.participantIds.length,
        },
      });
    }

    this.emit('participant_joined', { sessionId, userId });
    return session;
  }

  /**
   * Leave screen share session
   */
  async leaveSession(sessionId: string, userId: string): Promise<void> {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    const index = session.participantIds.indexOf(userId);
    if (index > -1) {
      session.participantIds.splice(index, 1);

      // SOC2: Audit participant leave
      this.auditService?.emit({
        userId,
        action: 'UPDATE',
        resource: 'ScreenShareSession',
        resourceId: sessionId,
        metadata: {
          event: 'participant_left',
          participantCount: session.participantIds.length,
        },
      });
    }

    // End session if presenter leaves or no participants
    if (userId === session.presenterId || session.participantIds.length === 0) {
      await this.endSession(sessionId);
    }

    this.emit('participant_left', { sessionId, userId });
  }

  /**
   * End a screen share session
   */
  async endSession(sessionId: string): Promise<void> {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      return;
    }

    session.isActive = false;
    session.endedAt = new Date();

    // SOC2: Audit session end
    this.auditService?.emit({
      userId: session.presenterId,
      action: 'DELETE',
      resource: 'ScreenShareSession',
      resourceId: sessionId,
      metadata: {
        durationSeconds: Math.round(
          (session.endedAt.getTime() - session.startedAt.getTime()) / 1000
        ),
        participantCount: session.participantIds.length,
      },
    });

    this.emit('session_ended', session);
  }

  /**
   * Add annotation (drawing/pointer)
   */
  async addAnnotation(
    sessionId: string,
    userId: string,
    type: 'pointer' | 'drawing' | 'highlight',
    x: number,
    y: number,
    color?: string
  ): Promise<ScreenShareAnnotation> {
    const session = this.activeSessions.get(sessionId);
    if (!session || !session.isActive) {
      throw new Error(`Session ${sessionId} not found or inactive`);
    }

    const annotation: ScreenShareAnnotation = {
      id: `ann-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      sessionId,
      userId,
      type,
      x,
      y,
      color,
      timestamp: new Date(),
    };

    const annotations = this.sessionAnnotations.get(sessionId) || [];
    annotations.push(annotation);
    this.sessionAnnotations.set(sessionId, annotations);

    // SOC2: Audit annotation
    this.auditService?.emit({
      userId,
      action: 'CREATE',
      resource: 'ScreenShareAnnotation',
      resourceId: annotation.id,
      metadata: {
        sessionId,
        annotationType: type,
        x,
        y,
      },
    });

    this.emit('annotation_added', annotation);
    return annotation;
  }

  /**
   * Update cursor position
   */
  async updateCursorPosition(sessionId: string, userId: string, x: number, y: number): Promise<void> {
    const session = this.activeSessions.get(sessionId);
    if (!session || !session.isActive) {
      return;
    }

    const cursor: CursorPosition = { userId, x, y, timestamp: new Date() };
    const positions = this.cursorPositions.get(sessionId) || [];

    // Keep only latest cursor per user
    const filtered = positions.filter(p => p.userId !== userId);
    filtered.push(cursor);
    this.cursorPositions.set(sessionId, filtered);

    // Emit for real-time broadcast
    this.emit('cursor_moved', cursor);
  }

  /**
   * Get session details
   */
  getSession(sessionId: string): ScreenShareSession | undefined {
    return this.activeSessions.get(sessionId);
  }

  /**
   * Get all sessions in workspace
   */
  getWorkspaceSessions(): ScreenShareSession[] {
    return Array.from(this.activeSessions.values()).filter(
      s => s.workspaceId === this.config.workspaceId && s.isActive
    );
  }

  /**
   * Get annotations for session
   */
  getSessionAnnotations(sessionId: string): ScreenShareAnnotation[] {
    return this.sessionAnnotations.get(sessionId) || [];
  }
}

export { ScreenShareSession, ScreenShareAnnotation, CursorPosition, ScreenShareConfig };
