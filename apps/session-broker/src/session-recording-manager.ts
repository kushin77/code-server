// @file        apps/session-broker/src/session-recording-manager.ts
// @module      session-management/recording
// @description Session recording and playback management for audit and review
//
// Manages recording of user sessions with metadata and playback capabilities.

import * as winston from 'winston';
import * as fs from 'fs';
import * as path from 'path';
import { RedisSessionStore, SessionContext } from './redis-session-store';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

export enum RecordingStatus {
  IDLE = 'idle',
  RECORDING = 'recording',
  PAUSED = 'paused',
  FINALIZING = 'finalizing',
  COMPLETED = 'completed',
  FAILED = 'failed',
}

export interface SessionRecording {
  id: string;
  sessionId: string;
  startedBy: string;
  startedAt: Date;
  status: RecordingStatus;
  pausedAt?: Date;
  completedAt?: Date;
  duration?: number; // milliseconds
  format: 'asciinema' | 'mp4' | 'webm';
  storageLocation: string; // NAS path
  metadata: {
    frameCount: number;
    size: number; // bytes
    audienceLevel: 'private' | 'team' | 'public';
    tags: string[];
    retentionDays: number;
  };
  playbackUrl?: string;
}

export interface SessionSnapshot {
  id: string;
  recordingId: string;
  timestamp: Date;
  frameIndex: number;
  thumbnailUrl?: string;
  description?: string;
}

/**
 * Manages session recordings and snapshots.
 * Idempotent: safe to start/stop/pause recording multiple times.
 */
export class SessionRecordingManager {
  private recordingStore: Map<string, SessionRecording> = new Map();
  private snapshotStore: Map<string, SessionSnapshot[]> = new Map();
  private nasBasePath: string;

  constructor(
    private sessionStore: RedisSessionStore,
    nasBasePath: string = process.env.NAS_MOUNT_PATH || '/mnt/nas/persistent/code-server-enterprise'
  ) {
    this.nasBasePath = nasBasePath;
    this.initializeDirectories();
  }

  /**
   * Initialize NAS directories for recordings and snapshots.
   */
  private initializeDirectories(): void {
    try {
      const recordingsDir = path.join(this.nasBasePath, 'session-recordings');
      const snapshotsDir = path.join(this.nasBasePath, 'session-snapshots');

      if (!fs.existsSync(recordingsDir)) {
        fs.mkdirSync(recordingsDir, { recursive: true });
        logger.info('Initialized session recordings directory', { path: recordingsDir });
      }

      if (!fs.existsSync(snapshotsDir)) {
        fs.mkdirSync(snapshotsDir, { recursive: true });
        logger.info('Initialized session snapshots directory', { path: snapshotsDir });
      }
    } catch (error) {
      logger.error('Failed to initialize recording directories', { error });
    }
  }

  /**
   * Start recording a session.
   * Idempotent: starting already-recording session returns existing recording.
   */
  async startRecording(
    sessionId: string,
    startedBy: string,
    format: 'asciinema' | 'mp4' | 'webm' = 'asciinema',
    audienceLevel: 'private' | 'team' | 'public' = 'private',
    retentionDays: number = 30
  ): Promise<SessionRecording | null> {
    try {
      const session = await this.sessionStore.getSession(sessionId);
      if (!session) {
        logger.error('Cannot start recording: session not found', { sessionId });
        return null;
      }

      // Check for existing active recording (idempotent)
      const existingRecording = Array.from(this.recordingStore.values()).find(
        r => r.sessionId === sessionId && (r.status === RecordingStatus.RECORDING || r.status === RecordingStatus.PAUSED)
      );

      if (existingRecording) {
        logger.info('Recording already active for session', { sessionId, recordingId: existingRecording.id });
        return existingRecording;
      }

      // Create new recording
      const recordingId = `rec-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      const storageLocation = path.join(this.nasBasePath, 'session-recordings', `${recordingId}.${format}`);

      const recording: SessionRecording = {
        id: recordingId,
        sessionId,
        startedBy,
        startedAt: new Date(),
        status: RecordingStatus.RECORDING,
        format,
        storageLocation,
        metadata: {
          frameCount: 0,
          size: 0,
          audienceLevel,
          tags: [],
          retentionDays,
        },
      };

      this.recordingStore.set(recording.id, recording);
      this.snapshotStore.set(recording.id, []);

      logger.info('Started session recording', { recordingId, sessionId, format, audienceLevel });
      return recording;
    } catch (error) {
      logger.error('Failed to start session recording', { error, sessionId });
      return null;
    }
  }

  /**
   * Pause an active recording.
   * Idempotent: pausing already-paused recording is a no-op.
   */
  async pauseRecording(recordingId: string): Promise<boolean> {
    try {
      const recording = this.recordingStore.get(recordingId);
      if (!recording) {
        logger.error('Recording not found', { recordingId });
        return false;
      }

      if (recording.status === RecordingStatus.PAUSED) {
        logger.info('Recording already paused', { recordingId });
        return true; // Idempotent
      }

      if (recording.status !== RecordingStatus.RECORDING) {
        logger.error('Cannot pause recording in state', { recordingId, status: recording.status });
        return false;
      }

      recording.status = RecordingStatus.PAUSED;
      recording.pausedAt = new Date();

      logger.info('Paused session recording', { recordingId });
      return true;
    } catch (error) {
      logger.error('Failed to pause recording', { error, recordingId });
      return false;
    }
  }

  /**
   * Resume a paused recording.
   * Idempotent: resuming already-recording recording is a no-op.
   */
  async resumeRecording(recordingId: string): Promise<boolean> {
    try {
      const recording = this.recordingStore.get(recordingId);
      if (!recording) {
        logger.error('Recording not found', { recordingId });
        return false;
      }

      if (recording.status === RecordingStatus.RECORDING) {
        logger.info('Recording already active', { recordingId });
        return true; // Idempotent
      }

      if (recording.status !== RecordingStatus.PAUSED) {
        logger.error('Cannot resume recording in state', { recordingId, status: recording.status });
        return false;
      }

      recording.status = RecordingStatus.RECORDING;

      logger.info('Resumed session recording', { recordingId });
      return true;
    } catch (error) {
      logger.error('Failed to resume recording', { error, recordingId });
      return false;
    }
  }

  /**
   * Stop recording and finalize the file.
   * Idempotent: stopping already-completed recording is a no-op.
   */
  async stopRecording(recordingId: string): Promise<SessionRecording | null> {
    try {
      const recording = this.recordingStore.get(recordingId);
      if (!recording) {
        logger.error('Recording not found', { recordingId });
        return null;
      }

      if (recording.status === RecordingStatus.COMPLETED) {
        logger.info('Recording already completed', { recordingId });
        return recording; // Idempotent
      }

      if (recording.status === RecordingStatus.FAILED) {
        logger.warn('Cannot complete failed recording', { recordingId });
        return null;
      }

      recording.status = RecordingStatus.FINALIZING;
      const completionTime = new Date();

      // Simulate file finalization
      recording.completedAt = completionTime;
      recording.duration = completionTime.getTime() - recording.startedAt.getTime();
      recording.status = RecordingStatus.COMPLETED;

      logger.info('Stopped session recording', {
        recordingId,
        duration: recording.duration,
        fileSize: recording.metadata.size,
      });

      return recording;
    } catch (error) {
      logger.error('Failed to stop recording', { error, recordingId });
      const recording = this.recordingStore.get(recordingId);
      if (recording) {
        recording.status = RecordingStatus.FAILED;
      }
      return null;
    }
  }

  /**
   * Capture a snapshot at current playback position.
   * Idempotent: creating snapshot with same details is a no-op.
   */
  async captureSnapshot(
    recordingId: string,
    frameIndex: number,
    description?: string
  ): Promise<SessionSnapshot | null> {
    try {
      const recording = this.recordingStore.get(recordingId);
      if (!recording) {
        logger.error('Recording not found', { recordingId });
        return null;
      }

      const snapshots = this.snapshotStore.get(recordingId) || [];

      // Check for duplicate snapshot at same frame (idempotent)
      const existingSnapshot = snapshots.find(s => s.frameIndex === frameIndex);
      if (existingSnapshot && existingSnapshot.description === description) {
        logger.info('Snapshot already exists at frame', { recordingId, frameIndex });
        return existingSnapshot; // Idempotent
      }

      const snapshot: SessionSnapshot = {
        id: `snap-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        recordingId,
        timestamp: new Date(),
        frameIndex,
        description,
      };

      snapshots.push(snapshot);
      this.snapshotStore.set(recordingId, snapshots);

      logger.info('Captured snapshot', { recordingId, snapshotId: snapshot.id, frameIndex });
      return snapshot;
    } catch (error) {
      logger.error('Failed to capture snapshot', { error, recordingId, frameIndex });
      return null;
    }
  }

  /**
   * Get all snapshots for a recording.
   */
  async getSnapshots(recordingId: string): Promise<SessionSnapshot[]> {
    try {
      return this.snapshotStore.get(recordingId) || [];
    } catch (error) {
      logger.error('Failed to get snapshots', { error, recordingId });
      return [];
    }
  }

  /**
   * Get recording by ID.
   */
  async getRecording(recordingId: string): Promise<SessionRecording | null> {
    try {
      return this.recordingStore.get(recordingId) || null;
    } catch (error) {
      logger.error('Failed to get recording', { error, recordingId });
      return null;
    }
  }

  /**
   * List all recordings for a session.
   */
  async listRecordings(sessionId: string): Promise<SessionRecording[]> {
    try {
      return Array.from(this.recordingStore.values()).filter(r => r.sessionId === sessionId);
    } catch (error) {
      logger.error('Failed to list recordings', { error, sessionId });
      return [];
    }
  }

  /**
   * Delete recording and associated snapshots.
   * Idempotent: deleting non-existent recording is a no-op.
   */
  async deleteRecording(recordingId: string): Promise<boolean> {
    try {
      const recording = this.recordingStore.get(recordingId);

      if (!recording) {
        logger.info('Recording not found for deletion', { recordingId });
        return true; // Idempotent
      }

      // Clean up snapshots
      this.snapshotStore.delete(recordingId);

      // Clean up file if it exists
      try {
        if (fs.existsSync(recording.storageLocation)) {
          fs.unlinkSync(recording.storageLocation);
        }
      } catch (e) {
        logger.warn('Could not delete recording file', { path: recording.storageLocation, error: e });
      }

      this.recordingStore.delete(recordingId);
      logger.info('Deleted recording', { recordingId });
      return true;
    } catch (error) {
      logger.error('Failed to delete recording', { error, recordingId });
      return false;
    }
  }

  /**
   * Cleanup expired recordings based on retention policy.
   * Idempotent: safe to run multiple times.
   */
  async cleanupExpiredRecordings(): Promise<number> {
    try {
      let deletedCount = 0;
      const now = new Date();

      for (const recording of this.recordingStore.values()) {
        if (recording.completedAt) {
          const retentionMs = recording.metadata.retentionDays * 24 * 60 * 60 * 1000;
          const expiryTime = new Date(recording.completedAt.getTime() + retentionMs);

          if (now > expiryTime) {
            await this.deleteRecording(recording.id);
            deletedCount++;
          }
        }
      }

      logger.info('Cleaned up expired recordings', { count: deletedCount });
      return deletedCount;
    } catch (error) {
      logger.error('Failed to cleanup expired recordings', { error });
      return 0;
    }
  }
}
