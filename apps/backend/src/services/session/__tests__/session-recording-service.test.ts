#!/usr/bin/env node
// @file        apps/backend/src/services/session/__tests__/session-recording-service.test.ts
// @module      session/recording
// @description Comprehensive tests for session recording service

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import service, { SessionRecording, PlaybackState, ChatMessage, DebugEvent, TerminalEvent, FileChange } from '../session-recording-service';

describe('SessionRecordingService', () => {
  beforeEach(() => {
    service.reset();
  });

  afterEach(() => {
    service.reset();
  });

  describe('startRecording', () => {
    it('should start recording a session', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      expect(recording).toBeDefined();
      expect(recording.sessionId).toBe('session-123');
      expect(recording.userId).toBe('user1');
      expect(recording.workspaceId).toBe('workspace-123');
      expect(recording.isActive).toBe(true);
      expect(recording.isPaused).toBe(false);
      expect(recording.frames).toHaveLength(0);
    });

    it('should set expiration to 90 days', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const ninetyDaysMs = 90 * 24 * 60 * 60 * 1000;

      expect(recording.expiresAt - recording.startTime).toBeLessThanOrEqual(ninetyDaysMs);
      expect(recording.expiresAt - recording.startTime).toBeGreaterThan(ninetyDaysMs - 1000);
    });

    it('should emit recordingStarted event', () => {
      const spy = vi.spyOn(service, 'emit');
      service.startRecording('session-123', 'user1', 'workspace-123');

      expect(spy).toHaveBeenCalledWith(
        'recordingStarted',
        expect.objectContaining({
          sessionId: 'session-123',
          userId: 'user1',
        }),
      );
    });
  });

  describe('recordFileChange', () => {
    it('should record file change', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const change: FileChange = {
        timestamp: Date.now(),
        path: '/src/app.ts',
        type: 'modify',
        content: 'export const app = {}',
      };

      const result = service.recordFileChange(recording.id, change);

      expect(result).toBe(true);
      expect(recording.fileCount).toBe(1);
      expect(recording.frames).toHaveLength(1);
      expect(recording.frames[0].files).toContain(change);
    });

    it('should return false for inactive recording', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.stopRecording(recording.id);

      const change: FileChange = {
        timestamp: Date.now(),
        path: '/src/app.ts',
        type: 'create',
      };

      const result = service.recordFileChange(recording.id, change);
      expect(result).toBe(false);
    });

    it('should group changes by timestamp', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const now = Date.now();

      const change1: FileChange = { timestamp: now, path: '/file1.ts', type: 'create' };
      const change2: FileChange = { timestamp: now, path: '/file2.ts', type: 'create' };

      service.recordFileChange(recording.id, change1);
      service.recordFileChange(recording.id, change2);

      expect(recording.frames).toHaveLength(1);
      expect(recording.frames[0].files).toHaveLength(2);
    });
  });

  describe('recordTerminalEvent', () => {
    it('should record terminal event', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const event: TerminalEvent = {
        timestamp: Date.now(),
        terminalId: 'term-1',
        type: 'input',
        data: 'npm run dev',
        cwd: '/workspace',
        shell: '/bin/bash',
      };

      const result = service.recordTerminalEvent(recording.id, event);

      expect(result).toBe(true);
      expect(recording.terminalCount).toBe(1);
      expect(recording.frames[0].terminal).toContain(event);
    });

    it('should record multiple terminal events', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const timestamp = Date.now();

      const event1: TerminalEvent = { timestamp, terminalId: 'term-1', type: 'input', data: 'ls' };
      const event2: TerminalEvent = { timestamp, terminalId: 'term-1', type: 'output', data: 'file.ts' };

      service.recordTerminalEvent(recording.id, event1);
      service.recordTerminalEvent(recording.id, event2);

      expect(recording.terminalCount).toBe(2);
      expect(recording.frames[0].terminal).toHaveLength(2);
    });
  });

  describe('recordDebugEvent', () => {
    it('should record debug event', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const event: DebugEvent = {
        timestamp: Date.now(),
        type: 'breakpoint',
        file: '/src/app.ts',
        line: 42,
        column: 15,
      };

      const result = service.recordDebugEvent(recording.id, event);

      expect(result).toBe(true);
      expect(recording.debugEventCount).toBe(1);
      expect(recording.frames[0].debug).toContain(event);
    });

    it('should record variable inspection', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const event: DebugEvent = {
        timestamp: Date.now(),
        type: 'variable-inspect',
        expression: 'x + y',
        value: '42',
      };

      service.recordDebugEvent(recording.id, event);

      expect(recording.debugEventCount).toBe(1);
      expect(recording.frames[0].debug[0].value).toBe('42');
    });

    it('should record call stack', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const event: DebugEvent = {
        timestamp: Date.now(),
        type: 'stack-trace',
        callStack: [
          { file: '/src/app.ts', line: 42, function: 'handleRequest' },
          { file: '/src/middleware.ts', line: 10, function: 'execute' },
        ],
      };

      service.recordDebugEvent(recording.id, event);

      expect(recording.frames[0].debug[0].callStack).toHaveLength(2);
    });
  });

  describe('recordChatMessage', () => {
    it('should record chat message', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const message: ChatMessage = {
        timestamp: Date.now(),
        userId: 'user1',
        username: 'Alice',
        message: 'How does this work?',
        type: 'message',
      };

      const result = service.recordChatMessage(recording.id, message);

      expect(result).toBe(true);
      expect(recording.chatCount).toBe(1);
      expect(recording.frames[0].chat).toContain(message);
    });

    it('should record mentions', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const message: ChatMessage = {
        timestamp: Date.now(),
        userId: 'user1',
        username: 'Alice',
        message: '@Bob check this out',
        type: 'mention',
        mentionedUsers: ['user2'],
      };

      service.recordChatMessage(recording.id, message);

      expect(recording.frames[0].chat[0].mentionedUsers).toContain('user2');
    });
  });

  describe('pauseResumeRecording', () => {
    it('should pause recording', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const result = service.pauseRecording(recording.id);

      expect(result).toBe(true);
      expect(recording.isPaused).toBe(true);
      expect(recording.isActive).toBe(true); // Still active but paused
    });

    it('should resume recording', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.pauseRecording(recording.id);
      const result = service.resumeRecording(recording.id);

      expect(result).toBe(true);
      expect(recording.isPaused).toBe(false);
    });

    it('should emit pause/resume events', () => {
      const spy = vi.spyOn(service, 'emit');
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      service.pauseRecording(recording.id);
      service.resumeRecording(recording.id);

      expect(spy).toHaveBeenCalledWith('recordingPaused', expect.anything());
      expect(spy).toHaveBeenCalledWith('recordingResumed', expect.anything());
    });
  });

  describe('stopRecording', () => {
    it('should stop recording', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const result = service.stopRecording(recording.id);

      expect(result).toBeDefined();
      expect(result?.isActive).toBe(false);
      expect(result?.endTime).toBeDefined();
      expect(result?.duration).toBeGreaterThanOrEqual(0);
    });

    it('should calculate duration', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const delay = 100;
      // Simulate some delay
      const startTime = Date.now();
      while (Date.now() - startTime < delay) {
        // busy wait
      }

      const result = service.stopRecording(recording.id);
      expect(result?.duration).toBeGreaterThanOrEqual(delay - 50);
    });

    it('should emit recordingStopped event', () => {
      const spy = vi.spyOn(service, 'emit');
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      service.stopRecording(recording.id);

      expect(spy).toHaveBeenCalledWith(
        'recordingStopped',
        expect.objectContaining({
          recordingId: recording.id,
        }),
      );
    });
  });

  describe('getRecording', () => {
    it('should retrieve recording by ID', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const retrieved = service.getRecording(recording.id);

      expect(retrieved).toEqual(recording);
    });

    it('should return undefined for non-existent recording', () => {
      const result = service.getRecording('non-existent');
      expect(result).toBeUndefined();
    });
  });

  describe('listRecordings', () => {
    it('should list recordings for session', () => {
      service.startRecording('session-123', 'user1', 'workspace-123');
      service.startRecording('session-123', 'user1', 'workspace-456');
      service.startRecording('session-456', 'user1', 'workspace-789');

      const recordings = service.listRecordingsForSession('session-123');

      expect(recordings).toHaveLength(2);
      expect(recordings.every((r) => r.sessionId === 'session-123')).toBe(true);
    });

    it('should list recordings for user', () => {
      service.startRecording('session-123', 'user1', 'workspace-123');
      service.startRecording('session-456', 'user1', 'workspace-456');
      service.startRecording('session-789', 'user2', 'workspace-789');

      const recordings = service.listRecordingsForUser('user1');

      expect(recordings).toHaveLength(2);
      expect(recordings.every((r) => r.userId === 'user1')).toBe(true);
    });
  });

  describe('deleteRecording', () => {
    it('should delete recording', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const result = service.deleteRecording(recording.id);

      expect(result).toBe(true);
      expect(service.getRecording(recording.id)).toBeUndefined();
    });

    it('should return false for non-existent recording', () => {
      const result = service.deleteRecording('non-existent');
      expect(result).toBe(false);
    });

    it('should emit recordingDeleted event', () => {
      const spy = vi.spyOn(service, 'emit');
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      service.deleteRecording(recording.id);

      expect(spy).toHaveBeenCalledWith(
        'recordingDeleted',
        expect.objectContaining({
          recordingId: recording.id,
        }),
      );
    });
  });

  describe('Playback', () => {
    it('should start playback', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const playback = service.startPlayback(recording.id);

      expect(playback).toBeDefined();
      expect(playback?.isPlaying).toBe(true);
      expect(playback?.playbackSpeed).toBe(1);
      expect(playback?.currentTime).toBe(0);
    });

    it('should pause playback', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);
      const result = service.pausePlayback(recording.id);

      expect(result).toBe(true);
      const state = service.getPlaybackState(recording.id);
      expect(state?.isPlaying).toBe(false);
    });

    it('should resume playback', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);
      service.pausePlayback(recording.id);
      const result = service.resumePlayback(recording.id);

      expect(result).toBe(true);
      const state = service.getPlaybackState(recording.id);
      expect(state?.isPlaying).toBe(true);
    });

    it('should set playback speed (0.5x to 10x)', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      expect(service.setPlaybackSpeed(recording.id, 0.5)).toBe(true);
      expect(service.setPlaybackSpeed(recording.id, 2)).toBe(true);
      expect(service.setPlaybackSpeed(recording.id, 10)).toBe(true);

      expect(service.setPlaybackSpeed(recording.id, 0.1)).toBe(false); // Too slow
      expect(service.setPlaybackSpeed(recording.id, 15)).toBe(false); // Too fast

      const state = service.getPlaybackState(recording.id);
      expect(state?.playbackSpeed).toBe(10);
    });

    it('should seek in recording', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      
      // Add some events
      const startTime = Date.now();
      service.recordFileChange(recording.id, {
        timestamp: startTime,
        path: '/file0.ts',
        type: 'create',
      });
      
      // Wait to ensure duration is > 0
      await new Promise((resolve) => setTimeout(resolve, 100));
      
      service.stopRecording(recording.id);
      service.startPlayback(recording.id);

      // Seek to a time within the recording
      const result = service.seek(recording.id, 50);

      expect(result).toBe(true);
      const state = service.getPlaybackState(recording.id);
      expect(state?.currentTime).toBe(50);
    }, 15000);

    it('should reject invalid seek times', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.stopRecording(recording.id);
      service.startPlayback(recording.id);

      expect(service.seek(recording.id, -1000)).toBe(false);
      expect(service.seek(recording.id, recording.duration + 1000)).toBe(false);
    });

    it('should toggle layer visibility', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const result = service.toggleLayer(recording.id, 'files');

      expect(result).toBe(true);
      const state = service.getPlaybackState(recording.id);
      expect(state?.visibleLayers.files).toBe(false);

      service.toggleLayer(recording.id, 'files');
      expect(state?.visibleLayers.files).toBe(true);
    });

    it('should stop playback', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);
      const result = service.stopPlayback(recording.id);

      expect(result).toBe(true);
      expect(service.getPlaybackState(recording.id)).toBeUndefined();
    });
  });

  describe('Sharing', () => {
    it('should generate share token', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const token = service.generateShareToken(recording.id);

      expect(token).toBeDefined();
      expect(token).toMatch(/^share-/);
      expect(recording.shareToken).toBe(token);
      expect(recording.shareUrl).toContain(token);
    });

    it('should retrieve recording by share token', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const token = service.generateShareToken(recording.id);

      const retrieved = service.getRecordingByShareToken(token!);

      expect(retrieved).toEqual(recording);
    });

    it('should revoke share token', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const token = service.generateShareToken(recording.id);
      const result = service.revokeShareToken(recording.id);

      expect(result).toBe(true);
      expect(recording.shareToken).toBeUndefined();
      expect(service.getRecordingByShareToken(token!)).toBeUndefined();
    });

    it('should emit shareTokenGenerated event', () => {
      const spy = vi.spyOn(service, 'emit');
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      service.generateShareToken(recording.id);

      expect(spy).toHaveBeenCalledWith(
        'shareTokenGenerated',
        expect.objectContaining({
          recordingId: recording.id,
          token: expect.any(String),
        }),
      );
    });
  });

  describe('Export', () => {
    it('should export to MP4', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const result = await service.exportRecording(recording.id, {
        format: 'mp4',
        quality: 'high',
        speed: 1,
        width: 1920,
        height: 1080,
      });

      expect(result).toBeDefined();
      expect(result).toContain('.mp4');
      expect(recording.exportedVideoPath).toBe(result);
    });

    it('should export to WebM', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const result = await service.exportRecording(recording.id, {
        format: 'webm',
        quality: 'medium',
        speed: 2,
        width: 1280,
        height: 720,
      });

      expect(result).toBeDefined();
      expect(result).toContain('.webm');
    });

    it('should export to GIF', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const result = await service.exportRecording(recording.id, {
        format: 'gif',
        quality: 'low',
        speed: 1,
        width: 800,
        height: 600,
      });

      expect(result).toBeDefined();
      expect(result).toContain('.gif');
    });

    it('should export to JSON', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const result = await service.exportRecording(recording.id, {
        format: 'json',
        quality: 'high',
        speed: 1,
        width: 0,
        height: 0,
      });

      expect(result).toBeDefined();
      expect(result).toContain('.json');
    });

    it('should set exportedVideoUrl', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      await service.exportRecording(recording.id, {
        format: 'mp4',
        quality: 'high',
        speed: 1,
        width: 1920,
        height: 1080,
      });

      expect(recording.exportedVideoUrl).toBeDefined();
      expect(recording.exportedVideoUrl).toContain('https://ide.kushnir.cloud');
    });

    it('should emit exportStarted and exportComplete events', async () => {
      const spy = vi.spyOn(service, 'emit');
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      await service.exportRecording(recording.id, {
        format: 'mp4',
        quality: 'high',
        speed: 1,
        width: 1920,
        height: 1080,
      });

      expect(spy).toHaveBeenCalledWith('exportStarted', expect.anything());
      expect(spy).toHaveBeenCalledWith('exportComplete', expect.anything());
    });
  });

  describe('getFrameAtTime', () => {
    it('should retrieve frame at specific time', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const now = Date.now();

      const change: FileChange = {
        timestamp: now,
        path: '/src/app.ts',
        type: 'modify',
      };

      service.recordFileChange(recording.id, change);

      const frame = service.getFrameAtTime(recording.id, 0);
      expect(frame).toBeDefined();
      expect(frame?.files).toContain(change);
    });

    it('should return null for non-existent recording', () => {
      const result = service.getFrameAtTime('non-existent', 0);
      expect(result).toBeNull();
    });
  });

  describe('getStatistics', () => {
    it('should return statistics', () => {
      service.startRecording('session-1', 'user1', 'workspace-1');
      service.startRecording('session-2', 'user2', 'workspace-2');
      const rec3 = service.startRecording('session-3', 'user1', 'workspace-3');
      service.stopRecording(rec3.id);

      const stats = service.getStatistics();

      expect(stats.totalRecordings).toBe(3);
      expect(stats.activeRecordings).toBe(2);
      expect(stats.recordingsByUser['user1']).toBe(2);
      expect(stats.recordingsByUser['user2']).toBe(1);
    });

    it('should calculate total events', () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const now = Date.now();

      service.recordFileChange(recording.id, { timestamp: now, path: '/file.ts', type: 'create' });
      service.recordFileChange(recording.id, { timestamp: now, path: '/file2.ts', type: 'modify' });
      service.recordTerminalEvent(recording.id, { timestamp: now, terminalId: 'term-1', type: 'input', data: 'ls' });

      const stats = service.getStatistics();

      expect(stats.totalEvents).toBe(3);
    });
  });

  describe('singleton pattern', () => {
    it('should return same instance', () => {
      const instance1 = service;
      const instance2 = service;

      expect(instance1).toBe(instance2);
    });

    it('should reset properly', () => {
      service.startRecording('session-123', 'user1', 'workspace-123');
      expect(service.getStatistics().totalRecordings).toBe(1);

      service.reset();
      expect(service.getStatistics().totalRecordings).toBe(0);
    });
  });
});
