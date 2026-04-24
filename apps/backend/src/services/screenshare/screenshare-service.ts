/**
 * @file        apps/backend/src/services/screenshare/screenshare-service.ts
 * @module      services/screenshare
 * @description Screen share service with CRDT-based drawing/pointer annotations synchronized across participants
 *
 */

import { EventEmitter } from 'events';
import type {
  DrawingStroke,
  Cursor,
  ScreenShareSession,
  StartScreenShareRequest,
  StartScreenShareResult,
  JoinScreenShareRequest,
  JoinScreenShareResult,
  AddDrawingRequest,
  AddDrawingResult,
  ClearAnnotationRequest,
  ClearAnnotationResult,
  UpdateCursorRequest,
  UpdateCursorResult,
  GetAnnotationsRequest,
  GetAnnotationsResult,
  GetCursorsRequest,
  GetCursorsResult,
  LeaveScreenShareRequest,
  LeaveScreenShareResult,
  StartRecordingRequest,
  StartRecordingResult,
  StopRecordingRequest,
  StopRecordingResult,
  PauseShareRequest,
  PauseShareResult,
  ResumeShareRequest,
  ResumeShareResult,
  ScreenShareAuditEntry,
  ScreenShareStatistics,
  ScreenShareServiceConfig,
  CRDTOperation,
} from './types.js';

/**
 * Screen Share Service
 * Manages screen sharing with CRDT-based drawing and pointer annotations
 */
export class ScreenShareService extends EventEmitter {
  private static instance: ScreenShareService;
  private config: Required<ScreenShareServiceConfig>;
  private sessions: Map<string, ScreenShareSession> = new Map();
  private auditLogs: Map<string, ScreenShareAuditEntry[]> = new Map();
  private recordings: Map<string, { sessionId: string; startedAt: number; recordingId: string }> = new Map();
  private crdtClocks: Map<string, number> = new Map();
  private cursorTracking: Map<string, number> = new Map();

  static getInstance(config?: Partial<ScreenShareServiceConfig>): ScreenShareService {
    if (!this.instance) {
      this.instance = new ScreenShareService(config);
    }
    return this.instance;
  }

  static reset(): void {
    this.instance = (undefined as any);
  }

  private constructor(config?: Partial<ScreenShareServiceConfig>) {
    super();
    this.config = {
      maxConcurrentSessions: 50,
      maxParticipantsPerSession: 100,
      maxAnnotationsPerSession: 5000,
      maxAuditLogSize: 1000,
      defaultQuality: 'high',
      enableRecording: true,
      enableAnnotations: true,
      crdtSyncInterval: 100,
      cursorUpdateInterval: 50,
      annotationTimeout: 3600000, // 1 hour
      cursorTimeout: 30000, // 30 seconds
      ...config,
    };
    this.emit('initialized', { timestamp: Date.now() });
  }

  startScreenShare(request: StartScreenShareRequest, ipAddress: string, userAgent: string): StartScreenShareResult {
    try {
      const sessionId = `screen-${request.workspaceId}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const streamUrl = `wss://streaming.example.com/session/${sessionId}`;

      const session: ScreenShareSession = {
        id: sessionId,
        workspaceId: request.workspaceId,
        presenterId: request.userId,
        presenterName: request.userName,
        presenterEmail: request.userEmail,
        startedAt: Date.now(),
        state: 'capturing',
        quality: request.quality || this.config.defaultQuality,
        screenTitle: request.screenTitle || 'Screen Share',
        screenResolution: request.screenResolution || { width: 1920, height: 1080 },
        participants: new Map([[request.userId, 'presenter']]),
        viewers: 0,
        annotators: 0,
        annotations: new Map(),
        cursors: new Map(),
        recordingId: null,
        isRecording: false,
      };

      this.sessions.set(sessionId, session);
      this.crdtClocks.set(sessionId, 0);

      // Simulate streaming state change
      setTimeout(() => {
        session.state = 'streaming';
        this.emit('share-state-changed', {
          sessionId,
          state: 'streaming',
          timestamp: Date.now(),
        });
      }, Math.random() * 45 + 5);

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'start-screen-share',
        sessionId,
        status: 'success',
        details: { screenTitle: request.screenTitle },
      });

      this.emit('screen-share-started', {
        session,
        timestamp: Date.now(),
      });

      return {
        success: true,
        sessionId,
        session,
        streamUrl,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'start-screen-share',
        sessionId: '',
        status: 'failure',
        details: { error: errorMsg },
      });
      return { success: false, sessionId: '', session: null, streamUrl: '', error: errorMsg };
    }
  }

  joinScreenShare(request: JoinScreenShareRequest, ipAddress: string, userAgent: string): JoinScreenShareResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      if (session.participants.size >= session.participants.size + 1) {
        if (session.participants.size >= this.config.maxParticipantsPerSession) {
          throw new Error('Session is full');
        }
      }

      session.participants.set(request.userId, request.role);
      if (request.role === 'viewer') {
        session.viewers += 1;
      } else if (request.role === 'annotator') {
        session.annotators += 1;
      }

      const streamUrl = `wss://streaming.example.com/session/${request.sessionId}`;

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'join-screen-share',
        sessionId: request.sessionId,
        status: 'success',
        details: { role: request.role },
      });

      this.emit('participant-joined', {
        sessionId: request.sessionId,
        userId: request.userId,
        role: request.role,
        timestamp: Date.now(),
      });

      return {
        success: true,
        sessionId: request.sessionId,
        session,
        streamUrl,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'join-screen-share',
        sessionId: request.sessionId,
        status: 'failure',
        details: { error: errorMsg },
      });
      return { success: false, sessionId: '', session: null, streamUrl: '', error: errorMsg };
    }
  }

  addDrawing(request: AddDrawingRequest, ipAddress: string, userAgent: string): AddDrawingResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      if (!this.config.enableAnnotations) {
        throw new Error('Annotations are disabled');
      }

      const annotationId = `ann-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const clock = (this.crdtClocks.get(request.sessionId) || 0) + 1;
      this.crdtClocks.set(request.sessionId, clock);

      const stroke: DrawingStroke = {
        id: annotationId,
        annotationType: request.annotationType,
        userId: request.userId,
        userName: request.userEmail.split('@')[0],
        points: request.points,
        color: request.color,
        lineWidth: request.lineWidth,
        style: request.style,
        opacity: request.opacity,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        crdt: {
          clientId: request.userId,
          clock,
          version: 1,
        },
      };

      session.annotations.set(annotationId, stroke);

      // Enforce max annotations
      if (session.annotations.size > this.config.maxAnnotationsPerSession) {
        const firstKey = session.annotations.keys().next().value;
        session.annotations.delete(firstKey);
      }

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'add-drawing',
        sessionId: request.sessionId,
        status: 'success',
        details: { annotationType: request.annotationType, pointCount: request.points.length },
      });

      this.emit('drawing-added', {
        sessionId: request.sessionId,
        annotation: stroke,
        timestamp: Date.now(),
      });

      return {
        success: true,
        annotationId,
        annotation: stroke,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, annotationId: '', annotation: null, error: errorMsg };
    }
  }

  clearAnnotation(request: ClearAnnotationRequest, ipAddress: string, userAgent: string): ClearAnnotationResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      const annotation = session.annotations.get(request.annotationId);
      if (!annotation) {
        throw new Error(`Annotation ${request.annotationId} not found`);
      }

      session.annotations.delete(request.annotationId);

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'clear-annotation',
        sessionId: request.sessionId,
        status: 'success',
      });

      this.emit('annotation-cleared', {
        sessionId: request.sessionId,
        annotationId: request.annotationId,
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, error: errorMsg };
    }
  }

  updateCursor(request: UpdateCursorRequest, ipAddress: string, userAgent: string): UpdateCursorResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      const cursor: Cursor = {
        id: `cursor-${request.userId}`,
        userId: request.userId,
        userName: request.userName,
        position: request.position,
        isVisible: request.isVisible,
        color: request.color,
        label: request.label || request.userName,
        lastSeenAt: Date.now(),
      };

      session.cursors.set(request.userId, cursor);
      this.cursorTracking.set(request.userId, Date.now());

      this.emit('cursor-updated', {
        sessionId: request.sessionId,
        cursor,
        timestamp: Date.now(),
      });

      return {
        success: true,
        cursor,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, cursor: null, error: errorMsg };
    }
  }

  getAnnotations(request: GetAnnotationsRequest): GetAnnotationsResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      const annotations = Array.from(session.annotations.values());
      return {
        success: true,
        annotations,
        count: annotations.length,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, annotations: [], count: 0, error: errorMsg };
    }
  }

  getCursors(request: GetCursorsRequest): GetCursorsResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      const cursors = Array.from(session.cursors.values());
      return {
        success: true,
        cursors,
        count: cursors.length,
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, cursors: [], count: 0, error: errorMsg };
    }
  }

  leaveScreenShare(request: LeaveScreenShareRequest, ipAddress: string, userAgent: string): LeaveScreenShareResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      const role = session.participants.get(request.userId);
      if (role === 'viewer') {
        session.viewers = Math.max(0, session.viewers - 1);
      } else if (role === 'annotator') {
        session.annotators = Math.max(0, session.annotators - 1);
      }

      session.participants.delete(request.userId);
      session.cursors.delete(request.userId);

      if (session.participants.size === 0) {
        session.state = 'stopped';
      }

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'leave-screen-share',
        sessionId: request.sessionId,
        status: 'success',
      });

      this.emit('participant-left', {
        sessionId: request.sessionId,
        userId: request.userId,
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, error: errorMsg };
    }
  }

  startRecording(request: StartRecordingRequest, ipAddress: string, userAgent: string): StartRecordingResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      if (!this.config.enableRecording) {
        throw new Error('Recording is disabled');
      }

      const recordingId = `rec-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const startedAt = Date.now();

      this.recordings.set(recordingId, {
        sessionId: request.sessionId,
        startedAt,
        recordingId,
      });

      session.recordingId = recordingId;
      session.isRecording = true;

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'start-recording',
        sessionId: request.sessionId,
        status: 'success',
        details: { recordingId },
      });

      return { success: true, recordingId, startedAt };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, recordingId: '', startedAt: 0, error: errorMsg };
    }
  }

  stopRecording(request: StopRecordingRequest, ipAddress: string, userAgent: string): StopRecordingResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      if (!session.recordingId) {
        throw new Error('No active recording');
      }

      const recording = this.recordings.get(session.recordingId);
      if (!recording) {
        throw new Error('Recording not found');
      }

      const duration = Date.now() - recording.startedAt;
      const recordingId = session.recordingId;

      this.recordings.delete(recordingId);
      session.recordingId = null;
      session.isRecording = false;

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'stop-recording',
        sessionId: request.sessionId,
        status: 'success',
        details: { recordingId, duration },
      });

      return { success: true, recordingId, duration };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, recordingId: '', duration: 0, error: errorMsg };
    }
  }

  pauseShare(request: PauseShareRequest, ipAddress: string, userAgent: string): PauseShareResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      session.state = 'paused';

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'pause-share',
        sessionId: request.sessionId,
        status: 'success',
      });

      this.emit('share-paused', {
        sessionId: request.sessionId,
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, error: errorMsg };
    }
  }

  resumeShare(request: ResumeShareRequest, ipAddress: string, userAgent: string): ResumeShareResult {
    try {
      const session = this.sessions.get(request.sessionId);
      if (!session) {
        throw new Error(`Session ${request.sessionId} not found`);
      }

      session.state = 'streaming';

      this.recordAudit({
        timestamp: Date.now(),
        userId: request.userId,
        userEmail: request.userEmail,
        ipAddress,
        userAgent,
        operation: 'resume-share',
        sessionId: request.sessionId,
        status: 'success',
      });

      this.emit('share-resumed', {
        sessionId: request.sessionId,
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      return { success: false, error: errorMsg };
    }
  }

  getSession(sessionId: string): ScreenShareSession | null {
    return this.sessions.get(sessionId) || null;
  }

  getAuditLog(userId: string, limit: number = 100): ScreenShareAuditEntry[] {
    const logs = this.auditLogs.get(userId) || [];
    return logs.slice(-limit);
  }

  getStatistics(): ScreenShareStatistics {
    const activeSessions = Array.from(this.sessions.values()).filter(
      (s) => s.state === 'streaming' || s.state === 'paused',
    );
    let totalAnnotations = 0;
    let totalViewerHours = 0;
    let totalDuration = 0;

    this.sessions.forEach((session) => {
      totalAnnotations += session.annotations.size;
      totalViewerHours += (session.viewers * (Date.now() - session.startedAt)) / (1000 * 60 * 60);
      totalDuration += Date.now() - session.startedAt;
    });

    return {
      totalSessions: this.sessions.size,
      activeSessions: activeSessions.length,
      totalParticipants: Array.from(this.sessions.values()).reduce(
        (sum, s) => sum + s.participants.size,
        0,
      ),
      totalAnnotations,
      totalRecordings: this.recordings.size,
      activeRecordings: Array.from(this.sessions.values()).filter((s) => s.isRecording).length,
      averageSessionDuration:
        this.sessions.size > 0 ? totalDuration / this.sessions.size : 0,
      totalViewerHours,
      averageAnnotationsPerSession:
        this.sessions.size > 0 ? totalAnnotations / this.sessions.size : 0,
    };
  }

  updateConfig(config: Partial<ScreenShareServiceConfig>, userId: string, ipAddress: string, userAgent: string): void {
    Object.assign(this.config, config);

    this.recordAudit({
      timestamp: Date.now(),
      userId,
      userEmail: 'system@example.com',
      ipAddress,
      userAgent,
      operation: 'update-config',
      sessionId: '',
      status: 'success',
      details: { config },
    });

    this.emit('config-updated', { config: this.config, timestamp: Date.now() });
  }

  private recordAudit(entry: ScreenShareAuditEntry): void {
    if (!this.auditLogs.has(entry.userId)) {
      this.auditLogs.set(entry.userId, []);
    }

    const logs = this.auditLogs.get(entry.userId)!;
    logs.push(entry);

    if (logs.length > this.config.maxAuditLogSize) {
      logs.splice(0, logs.length - this.config.maxAuditLogSize);
    }

    this.emit('audit-logged', { entry, timestamp: Date.now() });
  }

  shutdown(): void {
    this.sessions.clear();
    this.auditLogs.clear();
    this.recordings.clear();
    this.crdtClocks.clear();
    this.cursorTracking.clear();
    this.emit('shutdown', { timestamp: Date.now() });
  }
}
