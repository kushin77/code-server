/**
 * Session Recording Service
 * Full-fidelity recording with multi-speed playback and video export
 */

import { EventEmitter } from 'events';
import {
  RecordingSession,
  RecordedEvent,
  RecordableEventType,
  PlaybackRequest,
  PlaybackState,
  PlaybackResult,
  VideoExportRequest,
  VideoExportResult,
  RecordingMetadata,
  ShareableLink,
  RecordingStatistics,
  RecordingQuery,
  RecordingQueryResult,
  RecordingAuditEntry,
  RecordingServiceConfig,
} from './types.js';

/**
 * Session Recording Service
 * Capture, playback, and export session recordings
 */
export class RecordingService extends EventEmitter {
  private isInitialized = false;
  private recordings: Map<string, RecordingSession> = new Map();
  private events: Map<string, RecordedEvent[]> = new Map(); // Per-recording events
  private metadata: Map<string, RecordingMetadata[]> = new Map(); // Per-user metadata
  private playbackStates: Map<string, PlaybackState> = new Map();
  private shareableLinks: Map<string, ShareableLink> = new Map();
  private auditLog: Map<string, RecordingAuditEntry[]> = new Map(); // Per-user
  private stats: RecordingStatistics = {
    totalRecordings: 0,
    recordingsByUser: {},
    recordingsByWorkspace: {},
    totalEvents: 0,
    averageEventsPerRecording: 0,
    totalStorage: 0,
    averageStoragePerRecording: 0,
    playbackSessions: 0,
    videoExports: 0,
    shareableLinksCreated: 0,
  };
  private config: RecordingServiceConfig;

  constructor(config?: Partial<RecordingServiceConfig>) {
    super();
    this.config = {
      enabled: true,
      auditLoggingEnabled: true,
      maxRecordingsPerUser: 100,
      maxEventCaptureRate: 1000,
      videoExportEnabled: true,
      shareableLinksEnabled: true,
      retentionDays: 90,
      compressionEnabled: true,
      encryptionEnabled: false,
      maxAuditLogSize: 10000,
      storageBackend: 'memory',
      videoStorageBackend: 's3',
      ...config,
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;
    this.emit('initialized');
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    this.emit('shutdown');
  }

  /**
   * Start recording session
   */
  async startRecording(
    userId: string,
    userEmail: string,
    workspaceId: string,
    sessionId: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<RecordingSession> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const now = Date.now();
    const recordingId = `rec-${userId}-${now}-${Math.random().toString(36).slice(2, 9)}`;
    const expiresAt = now + this.config.retentionDays * 24 * 60 * 60 * 1000;

    const recording: RecordingSession = {
      id: recordingId,
      userId,
      workspaceId,
      sessionId,
      startTime: now,
      duration: 0,
      isActive: true,
      eventCount: 0,
      fileChanges: 0,
      terminalOutput: 0,
      chatMessages: 0,
      debugEvents: 0,
      size: 0,
      tags: [],
      description: '',
      visibility: 'private',
      expiresAt,
    };

    this.recordings.set(recordingId, recording);
    this.events.set(recordingId, []);

    // Update metadata
    const userMeta = this.metadata.get(userId) || [];
    userMeta.push({
      recordingId,
      userId,
      workspaceId,
      startTime: now,
      duration: 0,
      eventCount: 0,
      size: 0,
      visibility: 'private',
      tags: [],
      expiresAt,
    });
    if (userMeta.length > this.config.maxRecordingsPerUser) {
      const oldest = userMeta.shift()!;
      this.recordings.delete(oldest.recordingId);
      this.events.delete(oldest.recordingId);
    }
    this.metadata.set(userId, userMeta);

    // Log audit
    const auditEntry: RecordingAuditEntry = {
      id: `audit-${recordingId}`,
      userId,
      userEmail,
      operation: 'started',
      status: 'success',
      recordingId,
      ipAddress,
      userAgent,
      timestamp: now,
    };

    await this.logAudit(userId, auditEntry);
    this.updateStats();
    this.emit('recording-started', { recordingId, userId });

    return recording;
  }

  /**
   * Stop recording session
   */
  async stopRecording(
    userId: string,
    userEmail: string,
    recordingId: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<RecordingSession> {
    const recording = this.recordings.get(recordingId);
    if (!recording) throw new Error('Recording not found');

    const now = Date.now();
    recording.isActive = false;
    recording.endTime = now;
    recording.duration = now - recording.startTime;

    // Update metadata
    const userMeta = this.metadata.get(userId);
    if (userMeta) {
      const meta = userMeta.find((m) => m.recordingId === recordingId);
      if (meta) {
        meta.endTime = now;
        meta.duration = recording.duration;
      }
    }

    // Log audit
    const auditEntry: RecordingAuditEntry = {
      id: `audit-stop-${recordingId}`,
      userId,
      userEmail,
      operation: 'stopped',
      status: 'success',
      recordingId,
      ipAddress,
      userAgent,
      timestamp: now,
      details: { duration: recording.duration, eventCount: recording.eventCount },
    };

    await this.logAudit(userId, auditEntry);
    this.emit('recording-stopped', { recordingId, duration: recording.duration });

    return recording;
  }

  /**
   * Record event
   */
  async recordEvent(
    recordingId: string,
    eventType: RecordableEventType,
    userId: string,
    workspaceId: string,
    sessionId: string,
    data: Record<string, unknown>,
    metadata?: Record<string, unknown>
  ): Promise<RecordedEvent> {
    const recording = this.recordings.get(recordingId);
    if (!recording) throw new Error('Recording not found');

    const now = Date.now();
    const eventId = `evt-${recordingId}-${now}-${Math.random().toString(36).slice(2, 9)}`;

    const event: RecordedEvent = {
      id: eventId,
      timestamp: now,
      eventType,
      userId,
      workspaceId,
      sessionId,
      data,
      metadata: metadata as any,
    };

    const recordingEvents = this.events.get(recordingId) || [];
    recordingEvents.push(event);
    this.events.set(recordingId, recordingEvents);

    // Update recording stats
    recording.eventCount++;
    recording.size += JSON.stringify(event).length;

    switch (eventType) {
      case 'file-change':
      case 'file-create':
      case 'file-delete':
        recording.fileChanges++;
        break;
      case 'terminal-output':
      case 'terminal-input':
        recording.terminalOutput++;
        break;
      case 'chat-message':
        recording.chatMessages++;
        break;
      case 'debug-breakpoint':
      case 'debug-step':
        recording.debugEvents++;
        break;
    }

    this.emit('event-recorded', { recordingId, eventType, eventId });

    return event;
  }

  /**
   * Get recording
   */
  async getRecording(recordingId: string): Promise<RecordingSession | undefined> {
    return this.recordings.get(recordingId);
  }

  /**
   * Get recording events
   */
  async getRecordingEvents(recordingId: string): Promise<RecordedEvent[]> {
    return this.events.get(recordingId) || [];
  }

  /**
   * Start playback
   */
  async startPlayback(request: PlaybackRequest): Promise<PlaybackResult> {
    const recording = this.recordings.get(request.recordingId);
    if (!recording) throw new Error('Recording not found');

    const recordingEvents = this.events.get(request.recordingId) || [];
    const startIdx = request.startEventIndex || 0;

    if (startIdx >= recordingEvents.length) {
      throw new Error('Start index out of bounds');
    }

    const speed = Math.max(0.5, Math.min(10, request.speed || 1));
    const currentEvent = recordingEvents[startIdx];

    const state: PlaybackState = {
      recordingId: request.recordingId,
      isPlaying: true,
      speed,
      position: {
        eventIndex: startIdx,
        timestamp: currentEvent.timestamp,
        progress: (startIdx / recordingEvents.length) * 100,
      },
      currentEvent,
      totalEvents: recordingEvents.length,
      totalDuration: recording.duration,
    };

    this.playbackStates.set(request.recordingId, state);

    // Log audit
    const auditEntry: RecordingAuditEntry = {
      id: `audit-play-${request.recordingId}-${Date.now()}`,
      userId: request.userId,
      userEmail: 'unknown',
      operation: 'played',
      status: 'success',
      recordingId: request.recordingId,
      timestamp: Date.now(),
      details: { speed, startEventIndex: startIdx },
    };

    await this.logAudit(request.userId, auditEntry);
    this.updateStats();
    this.emit('playback-started', { recordingId: request.recordingId, speed });

    return {
      recordingId: request.recordingId,
      eventIndex: startIdx,
      timestamp: currentEvent.timestamp,
      event: currentEvent,
      speed,
      progress: state.position.progress,
      nextEventIndex: startIdx + 1 < recordingEvents.length ? startIdx + 1 : undefined,
    };
  }

  /**
   * Pause playback
   */
  async pausePlayback(recordingId: string): Promise<void> {
    const state = this.playbackStates.get(recordingId);
    if (state) {
      state.isPlaying = false;
    }
    this.emit('playback-paused', { recordingId });
  }

  /**
   * Resume playback
   */
  async resumePlayback(recordingId: string): Promise<void> {
    const state = this.playbackStates.get(recordingId);
    if (state) {
      state.isPlaying = true;
    }
    this.emit('playback-resumed', { recordingId });
  }

  /**
   * Set playback speed
   */
  async setPlaybackSpeed(recordingId: string, speed: number): Promise<void> {
    const state = this.playbackStates.get(recordingId);
    if (state) {
      state.speed = Math.max(0.5, Math.min(10, speed));
    }
    this.emit('playback-speed-changed', { recordingId, speed: state?.speed });
  }

  /**
   * Seek to event
   */
  async seekToEvent(recordingId: string, eventIndex: number): Promise<PlaybackResult> {
    const state = this.playbackStates.get(recordingId);
    if (!state) throw new Error('Playback not started');

    const recordingEvents = this.events.get(recordingId) || [];
    if (eventIndex >= recordingEvents.length) {
      throw new Error('Event index out of bounds');
    }

    const event = recordingEvents[eventIndex];
    state.position.eventIndex = eventIndex;
    state.position.timestamp = event.timestamp;
    state.position.progress = (eventIndex / recordingEvents.length) * 100;
    state.currentEvent = event;

    return {
      recordingId,
      eventIndex,
      timestamp: event.timestamp,
      event,
      speed: state.speed,
      progress: state.position.progress,
    };
  }

  /**
   * Export to video
   */
  async exportToVideo(
    request: VideoExportRequest,
    ipAddress?: string,
    userAgent?: string
  ): Promise<VideoExportResult> {
    if (!this.config.videoExportEnabled) {
      throw new Error('Video export disabled');
    }

    const recording = this.recordings.get(request.recordingId);
    if (!recording) throw new Error('Recording not found');

    const now = Date.now();
    const duration = request.endTime || recording.endTime || now;

    // Simulate video export
    const videoUrl = `https://videos.example.com/${request.recordingId}.${request.format}`;
    const size = recording.size * 50; // Simulated compression

    const result: VideoExportResult = {
      recordingId: request.recordingId,
      videoUrl,
      format: request.format,
      size,
      duration: recording.duration,
      quality: request.quality,
      created: now,
      expiresAt: now + 90 * 24 * 60 * 60 * 1000,
    };

    // Log audit
    const auditEntry: RecordingAuditEntry = {
      id: `audit-exp-${request.recordingId}-${now}`,
      userId: request.userId,
      userEmail: 'unknown',
      operation: 'exported',
      status: 'success',
      recordingId: request.recordingId,
      ipAddress,
      userAgent,
      timestamp: now,
      details: { format: request.format, quality: request.quality, size },
    };

    await this.logAudit(request.userId, auditEntry);
    this.updateStats();
    this.emit('video-exported', { recordingId: request.recordingId, format: request.format });

    return result;
  }

  /**
   * Create shareable link
   */
  async createShareableLink(
    userId: string,
    userEmail: string,
    recordingId: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<ShareableLink> {
    const recording = this.recordings.get(recordingId);
    if (!recording) throw new Error('Recording not found');

    if (!this.config.shareableLinksEnabled) {
      throw new Error('Shareable links disabled');
    }

    const now = Date.now();
    const token = `share-${recordingId}-${now}-${Math.random().toString(36).slice(2, 9)}`;
    const expiresAt = now + 90 * 24 * 60 * 60 * 1000;

    const link: ShareableLink = {
      token,
      recordingId,
      createdBy: userId,
      createdAt: now,
      expiresAt,
      accessCount: 0,
      visibility: 'public',
      allowDownload: true,
      allowPlayback: true,
    };

    this.shareableLinks.set(token, link);
    recording.shareableUrl = `https://share.example.com/${token}`;
    recording.shareableUrlToken = token;

    // Log audit
    const auditEntry: RecordingAuditEntry = {
      id: `audit-share-${recordingId}-${now}`,
      userId,
      userEmail,
      operation: 'shared',
      status: 'success',
      recordingId,
      ipAddress,
      userAgent,
      timestamp: now,
      details: { token },
    };

    await this.logAudit(userId, auditEntry);
    this.emit('link-created', { recordingId, token });

    return link;
  }

  /**
   * Access recording via shareable link
   */
  async accessViaShareableLink(token: string, ipAddress?: string): Promise<RecordingSession> {
    const link = this.shareableLinks.get(token);
    if (!link) throw new Error('Link not found or expired');

    if (!link.allowPlayback) throw new Error('Playback not allowed');

    link.accessCount++;

    // Log audit as anonymous access
    const auditEntry: RecordingAuditEntry = {
      id: `audit-access-${token}-${Date.now()}`,
      userId: 'anonymous',
      userEmail: 'anonymous',
      operation: 'accessed',
      status: 'success',
      recordingId: link.recordingId,
      ipAddress,
      timestamp: Date.now(),
    };

    await this.logAudit('anonymous', auditEntry);

    const recording = this.recordings.get(link.recordingId);
    if (!recording) throw new Error('Recording not found');

    return recording;
  }

  /**
   * Delete recording
   */
  async deleteRecording(
    userId: string,
    userEmail: string,
    recordingId: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<void> {
    this.recordings.delete(recordingId);
    this.events.delete(recordingId);
    this.playbackStates.delete(recordingId);

    // Update metadata
    const userMeta = this.metadata.get(userId);
    if (userMeta) {
      const idx = userMeta.findIndex((m) => m.recordingId === recordingId);
      if (idx >= 0) {
        userMeta.splice(idx, 1);
      }
    }

    // Log audit
    const auditEntry: RecordingAuditEntry = {
      id: `audit-del-${recordingId}-${Date.now()}`,
      userId,
      userEmail,
      operation: 'deleted',
      status: 'success',
      recordingId,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    };

    await this.logAudit(userId, auditEntry);
    this.updateStats();
    this.emit('recording-deleted', { recordingId });
  }

  /**
   * List recordings for user
   */
  async listRecordings(userId: string): Promise<RecordingMetadata[]> {
    const userMeta = this.metadata.get(userId) || [];
    return userMeta.sort((a, b) => b.startTime - a.startTime);
  }

  /**
   * Query recordings
   */
  async queryRecordings(query: RecordingQuery): Promise<RecordingQueryResult> {
    let results: RecordingMetadata[] = [];

    if (query.userId) {
      results = this.metadata.get(query.userId) || [];
    } else {
      for (const userMeta of this.metadata.values()) {
        results.push(...userMeta);
      }
    }

    if (query.workspaceId) {
      results = results.filter((m) => m.workspaceId === query.workspaceId);
    }

    if (query.tags && query.tags.length > 0) {
      results = results.filter((m) =>
        query.tags!.some((tag) => m.tags.includes(tag))
      );
    }

    if (query.visibility) {
      results = results.filter((m) => m.visibility === query.visibility);
    }

    results.sort((a, b) => b.startTime - a.startTime);

    const limit = query.limit || 20;
    const offset = query.offset || 0;

    return {
      recordings: results.slice(offset, offset + limit),
      total: results.length,
      limit,
      offset,
    };
  }

  /**
   * Get audit log
   */
  async getAuditLog(userId: string, limit?: number): Promise<RecordingAuditEntry[]> {
    const log = this.auditLog.get(userId) || [];
    if (limit) {
      return log.slice(-limit);
    }
    return log;
  }

  /**
   * Get statistics
   */
  async getStatistics(): Promise<RecordingStatistics> {
    return { ...this.stats };
  }

  /**
   * Private: Log audit entry
   */
  private async logAudit(userId: string, entry: RecordingAuditEntry): Promise<void> {
    let log = this.auditLog.get(userId);
    if (!log) {
      log = [];
      this.auditLog.set(userId, log);
    }

    log.push(entry);

    if (log.length > this.config.maxAuditLogSize) {
      log.splice(0, log.length - this.config.maxAuditLogSize);
    }

    this.emit('audit-logged', { userId, entry });
  }

  /**
   * Private: Update statistics
   */
  private updateStats(): void {
    this.stats.totalRecordings = this.recordings.size;
    this.stats.recordingsByUser = {};
    this.stats.recordingsByWorkspace = {};
    let totalEvents = 0;
    let totalStorage = 0;

    for (const recording of this.recordings.values()) {
      this.stats.recordingsByUser[recording.userId] =
        (this.stats.recordingsByUser[recording.userId] || 0) + 1;
      this.stats.recordingsByWorkspace[recording.workspaceId] =
        (this.stats.recordingsByWorkspace[recording.workspaceId] || 0) + 1;
      totalEvents += recording.eventCount;
      totalStorage += recording.size;
    }

    this.stats.totalEvents = totalEvents;
    this.stats.averageEventsPerRecording =
      this.stats.totalRecordings > 0 ? totalEvents / this.stats.totalRecordings : 0;
    this.stats.totalStorage = totalStorage;
    this.stats.averageStoragePerRecording =
      this.stats.totalRecordings > 0 ? totalStorage / this.stats.totalRecordings : 0;
  }

  /**
   * Singleton pattern
   */
  private static instance: RecordingService;

  static getInstance(config?: Partial<RecordingServiceConfig>): RecordingService {
    if (!RecordingService.instance) {
      RecordingService.instance = new RecordingService(config);
    }
    return RecordingService.instance;
  }
}
