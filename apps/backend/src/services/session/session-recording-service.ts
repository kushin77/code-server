#!/usr/bin/env node
// @file        apps/backend/src/services/session/session-recording-service.ts
// @module      session/recording
// @description Manages session recording with playback, export, and sharing capabilities

import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';

const logger = getLogger('SessionRecordingService');

// Recording data structures
export interface FileChange {
  timestamp: number;
  path: string;
  type: 'create' | 'modify' | 'delete' | 'rename';
  oldPath?: string;
  content?: string;
  diff?: string;
}

export interface TerminalEvent {
  timestamp: number;
  terminalId: string;
  type: 'input' | 'output' | 'close';
  data: string;
  cwd?: string;
  shell?: string;
}

export interface DebugEvent {
  timestamp: number;
  type: 'breakpoint' | 'step' | 'watch' | 'stack-trace' | 'variable-inspect';
  file?: string;
  line?: number;
  column?: number;
  expression?: string;
  value?: string;
  callStack?: Array<{ file: string; line: number; function: string }>;
}

export interface ChatMessage {
  timestamp: number;
  userId: string;
  username: string;
  message: string;
  type: 'message' | 'mention' | 'reaction';
  mentionedUsers?: string[];
  attachments?: Array<{ id: string; name: string; url: string }>;
}

export interface RecordingFrame {
  timestamp: number;
  files?: FileChange[];
  terminal?: TerminalEvent[];
  debug?: DebugEvent[];
  chat?: ChatMessage[];
  cursorPosition?: { x: number; y: number };
}

export interface SessionRecording {
  id: string;
  sessionId: string;
  userId: string;
  workspaceId: string;
  startTime: number;
  endTime?: number;
  duration: number;
  frames: RecordingFrame[];
  fileCount: number;
  terminalCount: number;
  debugEventCount: number;
  chatCount: number;
  isActive: boolean;
  isPaused: boolean;
  shareUrl?: string;
  shareToken?: string;
  expiresAt: number; // 90 days from creation
  exportedVideoPath?: string;
  exportedVideoUrl?: string;
}

export interface PlaybackState {
  recordingId: string;
  currentTime: number;
  duration: number;
  isPlaying: boolean;
  playbackSpeed: number; // 0.5-10
  loop: boolean;
  currentFrame: number;
  visibleLayers: {
    files: boolean;
    terminal: boolean;
    debug: boolean;
    chat: boolean;
  };
}

export interface ExportOptions {
  format: 'mp4' | 'webm' | 'gif' | 'json';
  quality: 'low' | 'medium' | 'high';
  speed: number; // 0.5-10
  width: number;
  height: number;
  includeVideo?: boolean;
  includeLayers?: {
    files: boolean;
    terminal: boolean;
    debug: boolean;
    chat: boolean;
  };
}

export class SessionRecordingService extends EventEmitter {
  private recordings: Map<string, SessionRecording> = new Map();
  private playback: Map<string, PlaybackState> = new Map();
  private shareTokens: Map<string, string> = new Map(); // token -> recordingId
  private static instance: SessionRecordingService;

  private constructor() {
    super();
    this.startCleanupTimer();
  }

  static getInstance(): SessionRecordingService {
    if (!SessionRecordingService.instance) {
      SessionRecordingService.instance = new SessionRecordingService();
    }
    return SessionRecordingService.instance;
  }

  reset(): void {
    this.recordings.clear();
    this.playback.clear();
    this.shareTokens.clear();
    this.removeAllListeners();
  }

  /**
   * Start recording a session
   */
  startRecording(sessionId: string, userId: string, workspaceId: string): SessionRecording {
    const id = `rec-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    const now = Date.now();
    const expiresAt = now + 90 * 24 * 60 * 60 * 1000; // 90 days

    const recording: SessionRecording = {
      id,
      sessionId,
      userId,
      workspaceId,
      startTime: now,
      duration: 0,
      frames: [],
      fileCount: 0,
      terminalCount: 0,
      debugEventCount: 0,
      chatCount: 0,
      isActive: true,
      isPaused: false,
      expiresAt,
    };

    this.recordings.set(id, recording);
    logger.debug(`Recording started: ${id} for session ${sessionId}`);
    this.emit('recordingStarted', { id, sessionId, userId, workspaceId });
    return recording;
  }

  /**
   * Record file change
   */
  recordFileChange(recordingId: string, change: FileChange): boolean {
    const recording = this.recordings.get(recordingId);
    if (!recording || !recording.isActive) {
      return false;
    }

    // Get or create frame for this timestamp
    const frameIndex = recording.frames.findIndex((f) => f.timestamp === change.timestamp);
    let frame: RecordingFrame;

    if (frameIndex >= 0) {
      frame = recording.frames[frameIndex];
    } else {
      frame = {
        timestamp: change.timestamp,
        files: [],
        terminal: [],
        debug: [],
        chat: [],
      };
      recording.frames.push(frame);
      recording.frames.sort((a, b) => a.timestamp - b.timestamp);
    }

    frame.files = frame.files || [];
    frame.files.push(change);
    recording.fileCount += 1;

    this.emit('fileChanged', { recordingId, change });
    return true;
  }

  /**
   * Record terminal event
   */
  recordTerminalEvent(recordingId: string, event: TerminalEvent): boolean {
    const recording = this.recordings.get(recordingId);
    if (!recording || !recording.isActive) {
      return false;
    }

    const frameIndex = recording.frames.findIndex((f) => f.timestamp === event.timestamp);
    let frame: RecordingFrame;

    if (frameIndex >= 0) {
      frame = recording.frames[frameIndex];
    } else {
      frame = {
        timestamp: event.timestamp,
        files: [],
        terminal: [],
        debug: [],
        chat: [],
      };
      recording.frames.push(frame);
      recording.frames.sort((a, b) => a.timestamp - b.timestamp);
    }

    frame.terminal = frame.terminal || [];
    frame.terminal.push(event);
    recording.terminalCount += 1;

    this.emit('terminalEvent', { recordingId, event });
    return true;
  }

  /**
   * Record debug event
   */
  recordDebugEvent(recordingId: string, event: DebugEvent): boolean {
    const recording = this.recordings.get(recordingId);
    if (!recording || !recording.isActive) {
      return false;
    }

    const frameIndex = recording.frames.findIndex((f) => f.timestamp === event.timestamp);
    let frame: RecordingFrame;

    if (frameIndex >= 0) {
      frame = recording.frames[frameIndex];
    } else {
      frame = {
        timestamp: event.timestamp,
        files: [],
        terminal: [],
        debug: [],
        chat: [],
      };
      recording.frames.push(frame);
      recording.frames.sort((a, b) => a.timestamp - b.timestamp);
    }

    frame.debug = frame.debug || [];
    frame.debug.push(event);
    recording.debugEventCount += 1;

    this.emit('debugEvent', { recordingId, event });
    return true;
  }

  /**
   * Record chat message
   */
  recordChatMessage(recordingId: string, message: ChatMessage): boolean {
    const recording = this.recordings.get(recordingId);
    if (!recording || !recording.isActive) {
      return false;
    }

    const frameIndex = recording.frames.findIndex((f) => f.timestamp === message.timestamp);
    let frame: RecordingFrame;

    if (frameIndex >= 0) {
      frame = recording.frames[frameIndex];
    } else {
      frame = {
        timestamp: message.timestamp,
        files: [],
        terminal: [],
        debug: [],
        chat: [],
      };
      recording.frames.push(frame);
      recording.frames.sort((a, b) => a.timestamp - b.timestamp);
    }

    frame.chat = frame.chat || [];
    frame.chat.push(message);
    recording.chatCount += 1;

    this.emit('chatRecorded', { recordingId, message });
    return true;
  }

  /**
   * Pause recording
   */
  pauseRecording(recordingId: string): boolean {
    const recording = this.recordings.get(recordingId);
    if (!recording || !recording.isActive) {
      return false;
    }

    recording.isPaused = true;
    this.emit('recordingPaused', { recordingId });
    return true;
  }

  /**
   * Resume recording
   */
  resumeRecording(recordingId: string): boolean {
    const recording = this.recordings.get(recordingId);
    if (!recording || !recording.isActive) {
      return false;
    }

    recording.isPaused = false;
    this.emit('recordingResumed', { recordingId });
    return true;
  }

  /**
   * Stop recording
   */
  stopRecording(recordingId: string): SessionRecording | null {
    const recording = this.recordings.get(recordingId);
    if (!recording || !recording.isActive) {
      return null;
    }

    const endTime = Date.now();
    recording.isActive = false;
    recording.endTime = endTime;
    recording.duration = endTime - recording.startTime;

    logger.debug(`Recording stopped: ${recordingId}, duration: ${recording.duration}ms`);
    this.emit('recordingStopped', { recordingId, duration: recording.duration });
    return recording;
  }

  /**
   * Get recording
   */
  getRecording(recordingId: string): SessionRecording | undefined {
    return this.recordings.get(recordingId);
  }

  /**
   * List recordings for session
   */
  listRecordingsForSession(sessionId: string): SessionRecording[] {
    return Array.from(this.recordings.values()).filter((r) => r.sessionId === sessionId);
  }

  /**
   * List recordings for user
   */
  listRecordingsForUser(userId: string): SessionRecording[] {
    return Array.from(this.recordings.values()).filter((r) => r.userId === userId);
  }

  /**
   * Delete recording
   */
  deleteRecording(recordingId: string): boolean {
    const recording = this.recordings.get(recordingId);
    if (!recording) {
      return false;
    }

    this.recordings.delete(recordingId);

    // Also remove any share tokens
    for (const [token, id] of this.shareTokens) {
      if (id === recordingId) {
        this.shareTokens.delete(token);
      }
    }

    this.emit('recordingDeleted', { recordingId });
    return true;
  }

  /**
   * Start playback
   */
  startPlayback(recordingId: string): PlaybackState | null {
    const recording = this.recordings.get(recordingId);
    if (!recording) {
      return null;
    }

    const playbackState: PlaybackState = {
      recordingId,
      currentTime: 0,
      duration: recording.duration,
      isPlaying: true,
      playbackSpeed: 1,
      loop: false,
      currentFrame: 0,
      visibleLayers: {
        files: true,
        terminal: true,
        debug: true,
        chat: true,
      },
    };

    this.playback.set(recordingId, playbackState);
    logger.debug(`Playback started: ${recordingId}`);
    this.emit('playbackStarted', { recordingId });
    return playbackState;
  }

  /**
   * Pause playback
   */
  pausePlayback(recordingId: string): boolean {
    const state = this.playback.get(recordingId);
    if (!state) {
      return false;
    }

    state.isPlaying = false;
    this.emit('playbackPaused', { recordingId });
    return true;
  }

  /**
   * Resume playback
   */
  resumePlayback(recordingId: string): boolean {
    const state = this.playback.get(recordingId);
    if (!state) {
      return false;
    }

    state.isPlaying = true;
    this.emit('playbackResumed', { recordingId });
    return true;
  }

  /**
   * Set playback speed (0.5 to 10)
   */
  setPlaybackSpeed(recordingId: string, speed: number): boolean {
    const state = this.playback.get(recordingId);
    if (!state || speed < 0.5 || speed > 10) {
      return false;
    }

    state.playbackSpeed = speed;
    this.emit('playbackSpeedChanged', { recordingId, speed });
    return true;
  }

  /**
   * Seek to time in playback
   */
  seek(recordingId: string, timeMs: number): boolean {
    const state = this.playback.get(recordingId);
    if (!state) {
      return false;
    }

    const recording = this.recordings.get(recordingId);
    if (!recording || timeMs < 0 || timeMs > recording.duration) {
      return false;
    }

    state.currentTime = timeMs;

    // Find frame index closest to this time
    let frameIndex = 0;
    for (let i = 0; i < recording.frames.length; i++) {
      if (recording.frames[i].timestamp - recording.startTime <= timeMs) {
        frameIndex = i;
      } else {
        break;
      }
    }
    state.currentFrame = frameIndex;

    this.emit('seeked', { recordingId, timeMs });
    return true;
  }

  /**
   * Toggle layer visibility
   */
  toggleLayer(recordingId: string, layer: 'files' | 'terminal' | 'debug' | 'chat'): boolean {
    const state = this.playback.get(recordingId);
    if (!state) {
      return false;
    }

    state.visibleLayers[layer] = !state.visibleLayers[layer];
    this.emit('layerToggled', { recordingId, layer, visible: state.visibleLayers[layer] });
    return true;
  }

  /**
   * Get playback state
   */
  getPlaybackState(recordingId: string): PlaybackState | undefined {
    return this.playback.get(recordingId);
  }

  /**
   * Stop playback
   */
  stopPlayback(recordingId: string): boolean {
    const state = this.playback.get(recordingId);
    if (!state) {
      return false;
    }

    this.playback.delete(recordingId);
    this.emit('playbackStopped', { recordingId });
    return true;
  }

  /**
   * Generate share URL token
   */
  generateShareToken(recordingId: string): string | null {
    const recording = this.recordings.get(recordingId);
    if (!recording) {
      return null;
    }

    // Generate random token
    const token = `share-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    this.shareTokens.set(token, recordingId);

    recording.shareToken = token;
    recording.shareUrl = `/api/sessions/recordings/share/${token}`;

    this.emit('shareTokenGenerated', { recordingId, token });
    return token;
  }

  /**
   * Get recording by share token
   */
  getRecordingByShareToken(token: string): SessionRecording | undefined {
    const recordingId = this.shareTokens.get(token);
    if (!recordingId) {
      return undefined;
    }

    return this.recordings.get(recordingId);
  }

  /**
   * Revoke share token
   */
  revokeShareToken(recordingId: string): boolean {
    const recording = this.recordings.get(recordingId);
    if (!recording || !recording.shareToken) {
      return false;
    }

    this.shareTokens.delete(recording.shareToken);
    recording.shareToken = undefined;
    recording.shareUrl = undefined;

    this.emit('shareTokenRevoked', { recordingId });
    return true;
  }

  /**
   * Export recording to video or JSON
   */
  async exportRecording(recordingId: string, options: ExportOptions): Promise<string | null> {
    const recording = this.recordings.get(recordingId);
    if (!recording) {
      return null;
    }

    this.emit('exportStarted', { recordingId, options });

    try {
      let exportPath = '';

      switch (options.format) {
        case 'mp4':
        case 'webm':
          // Simulate video export (normally would use ffmpeg)
          exportPath = `/exports/${recordingId}-${options.speed}x.${options.format}`;
          recording.exportedVideoPath = exportPath;
          recording.exportedVideoUrl = `https://ide.kushnir.cloud${exportPath}`;
          break;

        case 'gif':
          // Simulate GIF export
          exportPath = `/exports/${recordingId}.gif`;
          recording.exportedVideoPath = exportPath;
          recording.exportedVideoUrl = `https://ide.kushnir.cloud${exportPath}`;
          break;

        case 'json':
          // JSON export includes all recording data
          exportPath = `/exports/${recordingId}.json`;
          recording.exportedVideoPath = exportPath;
          recording.exportedVideoUrl = `https://ide.kushnir.cloud${exportPath}`;
          break;
      }

      this.emit('exportComplete', { recordingId, path: exportPath, url: recording.exportedVideoUrl });
      return exportPath;
    } catch (error) {
      logger.error(`Export failed for ${recordingId}: ${error}`);
      this.emit('exportFailed', { recordingId, error });
      return null;
    }
  }

  /**
   * Get frame at specific time
   */
  getFrameAtTime(recordingId: string, timeMs: number): RecordingFrame | null {
    const recording = this.recordings.get(recordingId);
    if (!recording) {
      return null;
    }

    const startTime = recording.startTime;
    const targetTime = startTime + timeMs;

    // Find frame closest to this time
    let closestFrame: RecordingFrame | null = null;
    let minDiff = Infinity;

    for (const frame of recording.frames) {
      const diff = Math.abs(frame.timestamp - targetTime);
      if (diff < minDiff) {
        minDiff = diff;
        closestFrame = frame;
      }
    }

    return closestFrame;
  }

  /**
   * Get recording statistics
   */
  getStatistics(): {
    totalRecordings: number;
    activeRecordings: number;
    totalDuration: number;
    averageDuration: number;
    totalEvents: number;
    recordingsByUser: Record<string, number>;
  } {
    const recordings = Array.from(this.recordings.values());
    const activeRecordings = recordings.filter((r) => r.isActive).length;
    const totalDuration = recordings.reduce((sum, r) => sum + r.duration, 0);

    const recordingsByUser: Record<string, number> = {};
    for (const recording of recordings) {
      recordingsByUser[recording.userId] = (recordingsByUser[recording.userId] || 0) + 1;
    }

    const totalEvents =
      recordings.reduce((sum, r) => sum + r.fileCount + r.terminalCount + r.debugEventCount + r.chatCount, 0);

    return {
      totalRecordings: recordings.length,
      activeRecordings,
      totalDuration,
      averageDuration: recordings.length > 0 ? totalDuration / recordings.length : 0,
      totalEvents,
      recordingsByUser,
    };
  }

  // Private helper methods

  private startCleanupTimer(): void {
    // Check every hour for expired recordings (90 days old)
    setInterval(() => {
      const now = Date.now();
      const toDelete: string[] = [];

      for (const [id, recording] of this.recordings) {
        if (recording.expiresAt <= now) {
          toDelete.push(id);
        }
      }

      for (const id of toDelete) {
        this.deleteRecording(id);
        logger.debug(`Auto-deleted expired recording: ${id}`);
        this.emit('recordingExpired', { recordingId: id });
      }
    }, 60 * 60 * 1000); // Every 1 hour
  }
}

export default SessionRecordingService.getInstance();
