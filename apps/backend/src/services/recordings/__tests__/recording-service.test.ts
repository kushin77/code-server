/**
 * Session Recording Service Tests
 * Test coverage for recording, playback, and export functionality
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { RecordingService } from '../recording-service.js';
import { RecordableEventType } from '../types.js';

describe('RecordingService', () => {
  let service: RecordingService;

  beforeEach(async () => {
    service = new RecordingService();
    await service.initialize();
  });

  afterEach(async () => {
    await service.shutdown();
  });

  // ==================== Initialization Tests ====================

  it('should initialize successfully', async () => {
    expect(service).toBeDefined();
    const stats = await service.getStatistics();
    expect(stats.totalRecordings).toBe(0);
  });

  it('should emit initialized event', () => {
    return new Promise<void>((resolve) => {
      const newService = new RecordingService();
      newService.once('initialized', () => {
        resolve();
      });
      newService.initialize();
    });
  });

  it('should emit shutdown event', () => {
    return new Promise<void>((resolve) => {
      const newService = new RecordingService();
      newService.initialize().then(() => {
        newService.once('shutdown', () => {
          resolve();
        });
        newService.shutdown();
      });
    });
  });

  // ==================== Start Recording Tests ====================

  it('should start recording', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    expect(rec.isActive).toBe(true);
    expect(rec.eventCount).toBe(0);
  });

  it('should emit recording-started event', () => {
    return new Promise<void>((resolve) => {
      service.once('recording-started', (data) => {
        expect(data.userId).toBe('user1');
        resolve();
      });
      service.startRecording(
        'user1',
        'user1@example.com',
        'workspace1',
        'session1'
      );
    });
  });

  it('should assign unique recording IDs', async () => {
    const rec1 = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await new Promise((resolve) => setTimeout(resolve, 1));

    const rec2 = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session2'
    );

    expect(rec1.id).not.toBe(rec2.id);
  });

  // ==================== Stop Recording Tests ====================

  it('should stop recording', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const stopped = await service.stopRecording(
      'user1',
      'user1@example.com',
      rec.id
    );

    expect(stopped.isActive).toBe(false);
    expect(stopped.endTime).toBeDefined();
    expect(stopped.duration).toBeGreaterThanOrEqual(0);
  });

  it('should emit recording-stopped event', () => {
    return new Promise<void>((resolve) => {
      service
        .startRecording(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1'
        )
        .then((rec) => {
          service.once('recording-stopped', (data) => {
            expect(data.recordingId).toBe(rec.id);
            resolve();
          });
          service.stopRecording('user1', 'user1@example.com', rec.id);
        });
    });
  });

  // ==================== Event Recording Tests ====================

  it('should record event', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const event = await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      { path: 'src/index.ts', added: 10, removed: 5 }
    );

    expect(event.eventType).toBe('file-change');
    expect(event.data.path).toBe('src/index.ts');
  });

  it('should emit event-recorded event', () => {
    return new Promise<void>((resolve) => {
      service
        .startRecording(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1'
        )
        .then((rec) => {
          service.once('event-recorded', (data) => {
            expect(data.recordingId).toBe(rec.id);
            resolve();
          });
          service.recordEvent(
            rec.id,
            'file-change',
            'user1',
            'workspace1',
            'session1',
            {}
          );
        });
    });
  });

  it('should increment event count', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    for (let i = 0; i < 5; i++) {
      await service.recordEvent(
        rec.id,
        'file-change',
        'user1',
        'workspace1',
        'session1',
        {}
      );
    }

    const updated = await service.getRecording(rec.id);
    expect(updated?.eventCount).toBe(5);
  });

  it('should track file changes', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const eventTypes: RecordableEventType[] = ['file-change', 'file-create', 'file-delete'];
    for (const eventType of eventTypes) {
      await service.recordEvent(
        rec.id,
        eventType,
        'user1',
        'workspace1',
        'session1',
        {}
      );
    }

    const updated = await service.getRecording(rec.id);
    expect(updated?.fileChanges).toBe(3);
  });

  it('should track terminal output', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const eventTypes: RecordableEventType[] = ['terminal-output', 'terminal-input'];
    for (const eventType of eventTypes) {
      await service.recordEvent(
        rec.id,
        eventType,
        'user1',
        'workspace1',
        'session1',
        {}
      );
    }

    const updated = await service.getRecording(rec.id);
    expect(updated?.terminalOutput).toBe(2);
  });

  it('should track chat messages', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    for (let i = 0; i < 3; i++) {
      await service.recordEvent(
        rec.id,
        'chat-message',
        'user1',
        'workspace1',
        'session1',
        { message: 'test' }
      );
    }

    const updated = await service.getRecording(rec.id);
    expect(updated?.chatMessages).toBe(3);
  });

  it('should track debug events', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const eventTypes: RecordableEventType[] = ['debug-breakpoint', 'debug-step'];
    for (const eventType of eventTypes) {
      await service.recordEvent(
        rec.id,
        eventType,
        'user1',
        'workspace1',
        'session1',
        {}
      );
    }

    const updated = await service.getRecording(rec.id);
    expect(updated?.debugEvents).toBe(2);
  });

  // ==================== Get Recording Tests ====================

  it('should retrieve recording by ID', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const retrieved = await service.getRecording(rec.id);
    expect(retrieved?.id).toBe(rec.id);
  });

  it('should get recording events', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      {}
    );

    const events = await service.getRecordingEvents(rec.id);
    expect(events.length).toBe(1);
  });

  // ==================== Playback Tests ====================

  it('should start playback', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      {}
    );

    const result = await service.startPlayback({
      recordingId: rec.id,
      userId: 'user1',
    });

    expect(result.recordingId).toBe(rec.id);
    expect(result.speed).toBe(1);
  });

  it('should emit playback-started event', () => {
    return new Promise<void>((resolve) => {
      service
        .startRecording(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1'
        )
        .then(async (rec) => {
          await service.recordEvent(
            rec.id,
            'file-change',
            'user1',
            'workspace1',
            'session1',
            {}
          );

          service.once('playback-started', () => {
            resolve();
          });

          service.startPlayback({
            recordingId: rec.id,
            userId: 'user1',
          });
        });
    });
  });

  it('should support multi-speed playback (0.5-10x)', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      {}
    );

    for (const speed of [0.5, 1, 2, 5, 10]) {
      const result = await service.startPlayback({
        recordingId: rec.id,
        userId: 'user1',
        speed,
      });

      expect(result.speed).toBe(speed);
    }
  });

  it('should clamp playback speed to 0.5-10', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      {}
    );

    const result = await service.startPlayback({
      recordingId: rec.id,
      userId: 'user1',
      speed: 100,
    });

    expect(result.speed).toBe(10);
  });

  it('should pause playback', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      {}
    );

    await service.startPlayback({
      recordingId: rec.id,
      userId: 'user1',
    });

    await service.pausePlayback(rec.id);
    this.emit = () => {};
  });

  it('should resume playback', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      {}
    );

    await service.startPlayback({
      recordingId: rec.id,
      userId: 'user1',
    });

    await service.pausePlayback(rec.id);
    await service.resumePlayback(rec.id);
  });

  it('should seek to event', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    for (let i = 0; i < 5; i++) {
      await service.recordEvent(
        rec.id,
        'file-change',
        'user1',
        'workspace1',
        'session1',
        { index: i }
      );
    }

    await service.startPlayback({
      recordingId: rec.id,
      userId: 'user1',
    });

    const result = await service.seekToEvent(rec.id, 3);
    expect(result.eventIndex).toBe(3);
  });

  it('should set playback speed', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      {}
    );

    await service.startPlayback({
      recordingId: rec.id,
      userId: 'user1',
    });

    await service.setPlaybackSpeed(rec.id, 2);
  });

  // ==================== Video Export Tests ====================

  it('should export to video', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.recordEvent(
      rec.id,
      'file-change',
      'user1',
      'workspace1',
      'session1',
      {}
    );

    const result = await service.exportToVideo({
      recordingId: rec.id,
      userId: 'user1',
      format: 'mp4',
      quality: 'high',
      includeTerminal: true,
      includeEditor: true,
      includeChat: true,
    });

    expect(result.format).toBe('mp4');
    expect(result.quality).toBe('high');
  });

  it('should emit video-exported event', () => {
    return new Promise<void>((resolve) => {
      service
        .startRecording(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1'
        )
        .then(async (rec) => {
          await service.recordEvent(
            rec.id,
            'file-change',
            'user1',
            'workspace1',
            'session1',
            {}
          );

          service.once('video-exported', () => {
            resolve();
          });

          service.exportToVideo({
            recordingId: rec.id,
            userId: 'user1',
            format: 'mp4',
            quality: 'high',
            includeTerminal: true,
            includeEditor: true,
            includeChat: true,
          });
        });
    });
  });

  // ==================== Shareable Link Tests ====================

  it('should create shareable link', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const link = await service.createShareableLink(
      'user1',
      'user1@example.com',
      rec.id
    );

    expect(link.token).toBeDefined();
    expect(link.recordingId).toBe(rec.id);
  });

  it('should emit link-created event', () => {
    return new Promise<void>((resolve) => {
      service
        .startRecording(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1'
        )
        .then((rec) => {
          service.once('link-created', (data) => {
            expect(data.recordingId).toBe(rec.id);
            resolve();
          });
          service.createShareableLink('user1', 'user1@example.com', rec.id);
        });
    });
  });

  it('should access recording via shareable link', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const link = await service.createShareableLink(
      'user1',
      'user1@example.com',
      rec.id
    );

    const accessed = await service.accessViaShareableLink(link.token);
    expect(accessed.id).toBe(rec.id);
  });

  // ==================== Delete Recording Tests ====================

  it('should delete recording', async () => {
    const rec = await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    await service.deleteRecording('user1', 'user1@example.com', rec.id);

    const retrieved = await service.getRecording(rec.id);
    expect(retrieved).toBeUndefined();
  });

  it('should emit recording-deleted event', () => {
    return new Promise<void>((resolve) => {
      service
        .startRecording(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1'
        )
        .then((rec) => {
          service.once('recording-deleted', () => {
            resolve();
          });
          service.deleteRecording('user1', 'user1@example.com', rec.id);
        });
    });
  });

  // ==================== List & Query Tests ====================

  it('should list recordings for user', async () => {
    for (let i = 0; i < 3; i++) {
      await service.startRecording(
        'user1',
        'user1@example.com',
        'workspace1',
        `session${i}`
      );
    }

    const list = await service.listRecordings('user1');
    expect(list.length).toBe(3);
  });

  it('should query recordings', async () => {
    await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const result = await service.queryRecordings({ userId: 'user1' });
    expect(result.total).toBeGreaterThan(0);
  });

  it('should filter by workspace', async () => {
    for (let i = 0; i < 2; i++) {
      await service.startRecording(
        'user1',
        'user1@example.com',
        `workspace${i}`,
        'session1'
      );
    }

    const result = await service.queryRecordings({
      userId: 'user1',
      workspaceId: 'workspace0',
    });

    expect(result.recordings[0].workspaceId).toBe('workspace0');
  });

  // ==================== Audit Logging Tests ====================

  it('should log audit entry for recording start', async () => {
    await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      '192.168.1.1',
      'Mozilla/5.0'
    );

    const log = await service.getAuditLog('user1');
    expect(log.length).toBeGreaterThan(0);
    expect(log[0].operation).toBe('started');
    expect(log[0].ipAddress).toBe('192.168.1.1');
  });

  it('should emit audit-logged event', () => {
    return new Promise<void>((resolve) => {
      service.once('audit-logged', () => {
        resolve();
      });
      service.startRecording(
        'user1',
        'user1@example.com',
        'workspace1',
        'session1'
      );
    });
  });

  // ==================== Statistics Tests ====================

  it('should calculate statistics', async () => {
    await service.startRecording(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1'
    );

    const stats = await service.getStatistics();
    expect(stats.totalRecordings).toBe(1);
  });

  it('should track recordings by user', async () => {
    for (let i = 1; i <= 2; i++) {
      await service.startRecording(
        `user${i}`,
        `user${i}@example.com`,
        'workspace1',
        'session1'
      );
    }

    const stats = await service.getStatistics();
    expect(stats.recordingsByUser['user1']).toBe(1);
    expect(stats.recordingsByUser['user2']).toBe(1);
  });

  // ==================== Error Handling Tests ====================

  it('should throw error if not initialized', async () => {
    const newService = new RecordingService();
    await expect(
      newService.startRecording('user1', 'user1@example.com', 'ws1', 'session1')
    ).rejects.toThrow();
  });

  // ==================== Singleton Pattern Tests ====================

  it('should use singleton pattern', () => {
    const instance1 = RecordingService.getInstance();
    const instance2 = RecordingService.getInstance();
    expect(instance1).toBe(instance2);
  });

  // ==================== Multiple Users Tests ====================

  it('should handle multiple users', async () => {
    for (let i = 1; i <= 3; i++) {
      await service.startRecording(
        `user${i}`,
        `user${i}@example.com`,
        'workspace1',
        'session1'
      );
    }

    const stats = await service.getStatistics();
    expect(stats.totalRecordings).toBe(3);
  });
});
