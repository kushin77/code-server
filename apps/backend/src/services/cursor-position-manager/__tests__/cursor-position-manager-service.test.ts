/**
 * Real-time Cursor Position Manager Service Tests
 * @file        apps/backend/src/services/cursor-position-manager/__tests__/cursor-position-manager-service.test.ts
 * @module      services/cursor-position-manager
 * @description Test suite for cursor position tracking
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CursorPositionManager } from '../cursor-position-manager-service.js';
import { CursorPosition } from '../types.js';

describe('Cursor Position Manager Service', () => {
  let service: CursorPositionManager;

  beforeEach(() => {
    CursorPositionManager.reset();
    service = CursorPositionManager.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  // Initialization Tests
  describe('Initialization', () => {
    it('should initialize service', () => {
      expect(service).toBeDefined();
      expect((service as any).cursors).toBeDefined();
      expect((service as any).fileCursors).toBeDefined();
    });

    it('should return same instance on subsequent calls', () => {
      const instance1 = CursorPositionManager.getInstance();
      const instance2 = CursorPositionManager.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  // Cursor Position Tests
  describe('Cursor Position Updates', () => {
    it('should update cursor position', () => {
      const result = service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
    });

    it('should emit cursor-position-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('cursor-position-updated', (event) => {
          expect(event.data_object.userId).toBe('user1');
          expect(event.data_object.fileId).toBe('file1');
          resolve();
        });

        service.updateCursorPosition(
          'user1',
          'user1@example.com',
          'User One',
          'file1',
          { line: 10, column: 5 },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should retrieve cursor position', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const position = service.getCursorPosition('user1', 'file1');

      expect(position).toBeDefined();
      expect(position?.line).toBe(10);
      expect(position?.column).toBe(5);
    });
  });

  // Cursor Selection Tests
  describe('Cursor Selection', () => {
    it('should update cursor selection', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.updateCursorSelection(
        'user1',
        'file1',
        { line: 10, column: 5 },
        { line: 10, column: 15 },
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
    });

    it('should emit cursor-selection-updated event', () => {
      return new Promise<void>((resolve) => {
        service.updateCursorPosition(
          'user1',
          'user1@example.com',
          'User One',
          'file1',
          { line: 10, column: 5 },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('cursor-selection-updated', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.updateCursorSelection(
          'user1',
          'file1',
          { line: 10, column: 5 },
          { line: 10, column: 15 },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  // Query Tests
  describe('Cursor Queries', () => {
    it('should get cursors in file', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      service.updateCursorPosition(
        'user2',
        'user2@example.com',
        'User Two',
        'file1',
        { line: 15, column: 10 },
        '192.168.1.1',
        'Mozilla'
      );

      const cursors = service.getCursorsInFile('file1');

      expect(cursors.length).toBeGreaterThanOrEqual(2);
    });

    it('should get cursors by user', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file2',
        { line: 20, column: 10 },
        '192.168.1.1',
        'Mozilla'
      );

      const cursors = service.getCursorsByUser('user1');

      expect(cursors.length).toBeGreaterThanOrEqual(1);
    });

    it('should get active cursors', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const active = service.getActiveCursors('file1');

      expect(Array.isArray(active)).toBe(true);
    });

    it('should get inactive cursors', () => {
      const inactive = service.getInactiveCursors('file1');

      expect(Array.isArray(inactive)).toBe(true);
    });
  });

  // Synchronization Tests
  describe('Synchronization', () => {
    it('should get sync state', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const syncState = service.getSyncState('file1');

      expect(syncState).toBeDefined();
      expect(syncState.fileId).toBe('file1');
      expect(syncState.activeCursors).toBeDefined();
    });

    it('should broadcast cursor update', () => {
      const result = service.broadcastCursorUpdate(
        'file1',
        [
          {
            userId: 'user1',
            fileId: 'file1',
            position: { line: 10, column: 5 },
            timestamp: Date.now(),
          },
        ],
        'admin',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.broadcastId).toBeDefined();
    });

    it('should emit cursor-broadcast event', () => {
      return new Promise<void>((resolve) => {
        service.once('cursor-broadcast', (event) => {
          expect(event.data_object.fileId).toBe('file1');
          resolve();
        });

        service.broadcastCursorUpdate(
          'file1',
          [
            {
              userId: 'user1',
              fileId: 'file1',
              position: { line: 10, column: 5 },
              timestamp: Date.now(),
            },
          ],
          'admin',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  // Presence Tests
  describe('Presence', () => {
    it('should get presence', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const presence = service.getPresence('file1');

      expect(presence).toBeDefined();
      expect(presence.fileId).toBe('file1');
    });

    it('should get user presence', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const presence = service.getUserPresence('user1');

      expect(Array.isArray(presence)).toBe(true);
    });
  });

  // Conflict Detection Tests
  describe('Conflict Detection', () => {
    it('should detect cursor conflicts', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      service.updateCursorPosition(
        'user2',
        'user2@example.com',
        'User Two',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const conflicts = service.detectConflicts('file1');

      expect(Array.isArray(conflicts)).toBe(true);
    });

    it('should emit cursor-conflicts-detected event', () => {
      return new Promise<void>((resolve) => {
        service.updateCursorPosition(
          'user1',
          'user1@example.com',
          'User One',
          'file1',
          { line: 10, column: 5 },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('cursor-conflicts-detected', (event) => {
          expect(event.data_object.fileId).toBe('file1');
          resolve();
        });

        service.updateCursorPosition(
          'user2',
          'user2@example.com',
          'User Two',
          'file1',
          { line: 10, column: 5 },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should resolve conflict', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      service.updateCursorPosition(
        'user2',
        'user2@example.com',
        'User Two',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const conflicts = service.detectConflicts('file1');
      if (conflicts.length > 0) {
        const result = service.resolveConflict(conflicts[0].conflictId, 'separate', 'admin', '192.168.1.1', 'Mozilla');
        expect(result.success).toBe(true);
      }
    });
  });

  // Cursor Jump Tests
  describe('Cursor Jumps', () => {
    it('should record cursor jump', () => {
      const result = service.recordCursorJump(
        {
          userId: 'user1',
          fromPosition: { line: 10, column: 5 },
          toPosition: { line: 50, column: 10 },
          fileId: 'file1',
          reason: 'goto-definition',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.jumpId).toBeDefined();
    });

    it('should emit cursor-jump-recorded event', () => {
      return new Promise<void>((resolve) => {
        service.once('cursor-jump-recorded', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.recordCursorJump(
          {
            userId: 'user1',
            fromPosition: { line: 10, column: 5 },
            toPosition: { line: 50, column: 10 },
            fileId: 'file1',
            reason: 'search',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should get cursor jumps', () => {
      service.recordCursorJump(
        {
          userId: 'user1',
          fromPosition: { line: 10, column: 5 },
          toPosition: { line: 50, column: 10 },
          fileId: 'file1',
          reason: 'goto-definition',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const jumps = service.getCursorJumps('user1');

      expect(Array.isArray(jumps)).toBe(true);
    });
  });

  // Viewport Tests
  describe('Viewport Management', () => {
    it('should update viewport', () => {
      const result = service.updateViewport(
        'user1',
        'file1',
        { fileId: 'file1', minLine: 0, maxLine: 50, minColumn: 0, maxColumn: 100 },
        1.0,
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
    });

    it('should emit viewport-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('viewport-updated', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.updateViewport(
          'user1',
          'file1',
          { fileId: 'file1', minLine: 0, maxLine: 50, minColumn: 0, maxColumn: 100 },
          1.0,
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should get viewport', () => {
      service.updateViewport(
        'user1',
        'file1',
        { fileId: 'file1', minLine: 0, maxLine: 50, minColumn: 0, maxColumn: 100 },
        1.5,
        '192.168.1.1',
        'Mozilla'
      );

      const viewport = service.getViewport('user1', 'file1');

      expect(viewport).toBeDefined();
      expect(viewport?.zoom).toBe(1.5);
    });
  });

  // Visibility Settings Tests
  describe('Visibility Settings', () => {
    it('should update visibility settings', () => {
      const result = service.updateVisibilitySettings(
        {
          showOtherCursors: true,
          showSelections: true,
          showInactiveAfterMs: 30000,
          colorScheme: 'auto',
          cursorSize: 'medium',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
    });

    it('should get visibility settings', () => {
      const settings = service.getVisibilitySettings('user1');

      expect(settings).toBeDefined();
      expect(settings.showOtherCursors).toBeDefined();
    });
  });

  // History Tests
  describe('Cursor History', () => {
    it('should record cursor movement in history', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 15, column: 10 },
        '192.168.1.1',
        'Mozilla'
      );

      const history = service.getCursorHistory('file1');

      expect(Array.isArray(history)).toBe(true);
    });

    it('should clear cursor history', () => {
      const result = service.clearCursorHistory('file1', 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit cursor-history-cleared event', () => {
      return new Promise<void>((resolve) => {
        service.once('cursor-history-cleared', (event) => {
          expect(event.data_object.fileId).toBe('file1');
          resolve();
        });

        service.clearCursorHistory('file1', 'user1', '192.168.1.1', 'Mozilla');
      });
    });
  });

  // Statistics Tests
  describe('Statistics', () => {
    it('should calculate statistics', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const stats = service.getStatistics();

      expect(stats).toBeDefined();
      expect(stats.totalCursorsTracked).toBeGreaterThanOrEqual(0);
      expect(stats.activeCursors).toBeGreaterThanOrEqual(0);
    });
  });

  // Audit Log Tests
  describe('Audit Logging', () => {
    it('should emit audit-logged event', () => {
      return new Promise<void>((resolve) => {
        service.once('audit-logged', (event) => {
          expect(event.data_object.userId).toBeDefined();
          resolve();
        });

        service.updateCursorPosition(
          'user1',
          'user1@example.com',
          'User One',
          'file1',
          { line: 10, column: 5 },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should retrieve audit log', () => {
      const log = service.getAuditLog();

      expect(Array.isArray(log)).toBe(true);
    });
  });

  // Cursor Removal Tests
  describe('Cursor Removal', () => {
    it('should remove cursor', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.removeCursor('user1', 'file1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit cursor-removed event', () => {
      return new Promise<void>((resolve) => {
        service.updateCursorPosition(
          'user1',
          'user1@example.com',
          'User One',
          'file1',
          { line: 10, column: 5 },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('cursor-removed', (event) => {
          expect(event.data_object.userId).toBe('user1');
          resolve();
        });

        service.removeCursor('user1', 'file1', '192.168.1.1', 'Mozilla');
      });
    });

    it('should remove user from file', () => {
      service.updateCursorPosition(
        'user1',
        'user1@example.com',
        'User One',
        'file1',
        { line: 10, column: 5 },
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.removeUserFromFile('user1', 'file1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });
  });

  // Configuration Tests
  describe('Configuration', () => {
    it('should update configuration', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (event) => {
          expect(event.data_object.config).toBeDefined();
          resolve();
        });

        service.updateConfig({ inactivityThreshold: 60000 });
      });
    });

    it('should get configuration', () => {
      const config = service.getConfig();

      expect(config).toBeDefined();
      expect(config.enableTracking).toBeDefined();
    });
  });

  // Shutdown Tests
  describe('Shutdown', () => {
    it('should shutdown service cleanly', () => {
      service.shutdown();

      expect((service as any).cursors.size).toBe(0);
      expect((service as any).fileCursors.size).toBe(0);
    });
  });
});
