/**
 * Rich Presence System Service Tests
 * Test coverage for presence tracking, audit logging, and real-time updates
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { PresenceService } from '../presence-service.js';
import { PresenceStatus, ActivityContext, PresenceEvent } from '../types.js';

describe('PresenceService', () => {
  let service: PresenceService;

  beforeEach(async () => {
    service = new PresenceService();
    await service.initialize();
  });

  afterEach(async () => {
    await service.shutdown();
  });

  // ==================== Initialization Tests ====================

  it('should initialize successfully', async () => {
    expect(service).toBeDefined();
    const stats = await service.getStatistics();
    expect(stats.totalUsers).toBe(0);
  });

  it('should emit initialized event', () => {
    return new Promise<void>((resolve) => {
      const newService = new PresenceService();
      newService.once('initialized', () => {
        resolve();
      });
      newService.initialize();
    });
  });

  it('should emit shutdown event', () => {
    return new Promise<void>((resolve) => {
      const newService = new PresenceService();
      newService.initialize().then(() => {
        newService.once('shutdown', () => {
          resolve();
        });
        newService.shutdown();
      });
    });
  });

  // ==================== Presence Update Tests ====================

  it('should update user presence', async () => {
    const presence = await service.updatePresence(
      'user1',
      'user1@example.com',
      { status: 'online' }
    );

    expect(presence.userId).toBe('user1');
    expect(presence.status).toBe('online');
    expect(presence.userEmail).toBe('user1@example.com');
  });

  it('should emit presence-updated event', () => {
    return new Promise<void>((resolve) => {
      service.once('presence-updated', (data) => {
        expect(data.userId).toBe('user1');
        resolve();
      });
      service.updatePresence('user1', 'user1@example.com', { status: 'online' });
    });
  });

  it('should emit status-changed event when status changes', () => {
    return new Promise<void>((resolve) => {
      service
        .updatePresence('user1', 'user1@example.com', { status: 'online' })
        .then(() => {
          service.once('status-changed', (event: PresenceEvent) => {
            expect(event.userId).toBe('user1');
            expect(event.previousStatus).toBe('online');
            expect(event.newStatus).toBe('idle');
            resolve();
          });
          service.updatePresence('user1', 'user1@example.com', { status: 'idle' });
        });
    });
  });

  it('should update presence with activity context', async () => {
    const presence = await service.updatePresence('user1', 'user1@example.com', {
      status: 'online',
      currentActivity: {
        context: 'file',
        description: 'Editing main.ts',
        details: { path: '/src/main.ts' },
      },
    });

    expect(presence.currentActivity?.context).toBe('file');
    expect(presence.currentActivity?.description).toBe('Editing main.ts');
  });

  it('should preserve presence data across updates', async () => {
    await service.updatePresence('user1', 'user1@example.com', { status: 'online' });

    // Update just activity
    const updated = await service.updatePresence('user1', 'user1@example.com', {
      currentActivity: {
        context: 'function',
        description: 'In calculateTotal()',
      },
    });

    expect(updated.status).toBe('online'); // Should still be online
    expect(updated.currentActivity?.context).toBe('function');
  });

  // ==================== Mark Online/Offline Tests ====================

  it('should mark user as online', async () => {
    const presence = await service.markOnline('user1', 'user1@example.com');
    expect(presence.status).toBe('online');
  });

  it('should mark user as offline', async () => {
    await service.markOnline('user1', 'user1@example.com');
    await service.markOffline('user1', 'user1@example.com');

    const presence = await service.getPresence('user1');
    expect(presence).toBeUndefined();
  });

  it('should emit user-offline event', () => {
    return new Promise<void>((resolve) => {
      service.markOnline('user1', 'user1@example.com').then(() => {
        service.once('user-offline', (data) => {
          expect(data.userId).toBe('user1');
          resolve();
        });
        service.markOffline('user1', 'user1@example.com');
      });
    });
  });

  // ==================== Get Presence Tests ====================

  it('should retrieve user presence', async () => {
    await service.markOnline('user1', 'user1@example.com', 'workspace1');

    const presence = await service.getPresence('user1');
    expect(presence?.userId).toBe('user1');
    expect(presence?.workspaceId).toBe('workspace1');
  });

  it('should return undefined for offline user', async () => {
    const presence = await service.getPresence('nonexistent');
    expect(presence).toBeUndefined();
  });

  // ==================== Query Presence Tests ====================

  it('should query all presence', async () => {
    await service.markOnline('user1', 'user1@example.com', 'workspace1');
    await service.markOnline('user2', 'user2@example.com', 'workspace1');
    await service.markOnline('user3', 'user3@example.com', 'workspace2');

    const result = await service.queryPresence({});
    expect(result.total).toBe(3);
    expect(result.presence.length).toBe(3);
  });

  it('should filter presence by workspace', async () => {
    await service.markOnline('user1', 'user1@example.com', 'workspace1');
    await service.markOnline('user2', 'user2@example.com', 'workspace1');
    await service.markOnline('user3', 'user3@example.com', 'workspace2');

    const result = await service.queryPresence({ workspaceId: 'workspace1' });
    expect(result.total).toBe(2);
  });

  it('should filter presence by status', async () => {
    await service.updatePresence('user1', 'user1@example.com', { status: 'online' });
    await service.updatePresence('user2', 'user2@example.com', { status: 'idle' });
    await service.updatePresence('user3', 'user3@example.com', { status: 'busy' });

    const result = await service.queryPresence({ status: 'idle' });
    expect(result.total).toBe(1);
    expect(result.presence[0].userId).toBe('user2');
  });

  it('should filter presence by activity', async () => {
    await service.updatePresence('user1', 'user1@example.com', {
      currentActivity: { context: 'file', description: 'Editing' },
    });
    await service.updatePresence('user2', 'user2@example.com', {
      currentActivity: { context: 'debug', description: 'Debugging' },
    });

    const result = await service.queryPresence({ activity: 'file' });
    expect(result.total).toBe(1);
    expect(result.presence[0].userId).toBe('user1');
  });

  it('should paginate query results', async () => {
    for (let i = 1; i <= 5; i++) {
      await service.markOnline(`user${i}`, `user${i}@example.com`);
    }

    const page1 = await service.queryPresence({ limit: 2, offset: 0 });
    expect(page1.presence.length).toBe(2);
    expect(page1.limit).toBe(2);
    expect(page1.offset).toBe(0);

    const page2 = await service.queryPresence({ limit: 2, offset: 2 });
    expect(page2.presence.length).toBe(2);
  });

  // ==================== Workspace Presence Tests ====================

  it('should get workspace presence snapshot', async () => {
    await service.updatePresence(
      'user1',
      'user1@example.com',
      {
        status: 'online',
        currentActivity: { context: 'file', description: 'Editing' },
      },
      undefined,
      undefined,
      'workspace1'
    );
    await service.updatePresence(
      'user2',
      'user2@example.com',
      {
        status: 'idle',
        currentActivity: { context: 'task', description: 'Working on task' },
      },
      undefined,
      undefined,
      'workspace1'
    );

    const snapshot = await service.getWorkspacePresence('workspace1');
    expect(snapshot.workspaceId).toBe('workspace1');
    expect(snapshot.activeUsers).toBe(2);
    expect(snapshot.presenceByStatus.online).toBe(1);
    expect(snapshot.presenceByStatus.idle).toBe(1);
  });

  // ==================== Custom Status Tests ====================

  it('should set custom status', async () => {
    const presence = await service.setCustomStatus(
      'user1',
      'user1@example.com',
      'In a meeting',
      '📞'
    );

    expect(presence.customStatus?.text).toBe('In a meeting');
    expect(presence.customStatus?.emoji).toBe('📞');
  });

  it('should set custom status with expiration', async () => {
    const expiresAt = Date.now() + 3600000;
    const presence = await service.setCustomStatus(
      'user1',
      'user1@example.com',
      'Busy',
      '🔴',
      expiresAt
    );

    expect(presence.customStatus?.expiresAt).toBe(expiresAt);
  });

  // ==================== Activity Tests ====================

  it('should update activity', async () => {
    const presence = await service.updateActivity(
      'user1',
      'user1@example.com',
      'file',
      'Editing src/main.ts',
      { line: 42 }
    );

    expect(presence.currentActivity?.context).toBe('file');
    expect(presence.currentActivity?.description).toBe('Editing src/main.ts');
    expect(presence.currentActivity?.details?.line).toBe(42);
  });

  // ==================== Settings Tests ====================

  it('should get user settings', async () => {
    const settings = await service.updateSettings('user1', {
      showPresence: false,
    });

    const retrieved = await service.getSettings('user1');
    expect(retrieved?.showPresence).toBe(false);
  });

  it('should update user settings', async () => {
    const settings = await service.updateSettings('user1', {
      privacyLevel: 'private',
      broadcastActivity: false,
    });

    expect(settings.privacyLevel).toBe('private');
    expect(settings.broadcastActivity).toBe(false);
  });

  it('should emit settings-updated event', () => {
    return new Promise<void>((resolve) => {
      service.once('settings-updated', (data) => {
        expect(data.userId).toBe('user1');
        resolve();
      });
      service.updateSettings('user1', { showPresence: false });
    });
  });

  // ==================== Audit Logging Tests ====================

  it('should log audit entry', async () => {
    await service.updatePresence(
      'user1',
      'user1@example.com',
      { status: 'online' },
      '192.168.1.1',
      'Mozilla/5.0'
    );

    const log = await service.getAuditLog('user1');
    expect(log.length).toBeGreaterThan(0);
    expect(log[0].userId).toBe('user1');
    expect(log[0].operation).toBe('status-updated');
    expect(log[0].status).toBe('success');
    expect(log[0].ipAddress).toBe('192.168.1.1');
  });

  it('should track IP and user agent in audit', async () => {
    await service.updatePresence(
      'user1',
      'user1@example.com',
      { status: 'online' },
      '10.0.0.1',
      'Chrome/90'
    );

    const log = await service.getAuditLog('user1');
    expect(log[0].ipAddress).toBe('10.0.0.1');
    expect(log[0].userAgent).toBe('Chrome/90');
  });

  it('should emit audit-logged event', () => {
    return new Promise<void>((resolve) => {
      service.once('audit-logged', (data) => {
        expect(data.userId).toBe('user1');
        expect(data.entry).toBeDefined();
        resolve();
      });
      service.updatePresence('user1', 'user1@example.com', { status: 'online' });
    });
  });

  it('should limit audit log size', async () => {
    const smallService = new PresenceService({ maxAuditLogSize: 5 });
    await smallService.initialize();

    for (let i = 0; i < 10; i++) {
      await smallService.updatePresence('user1', 'user1@example.com', {
        status: 'online',
      });
    }

    const log = await smallService.getAuditLog('user1');
    expect(log.length).toBeLessThanOrEqual(5);

    await smallService.shutdown();
  });

  // ==================== History Tests ====================

  it('should track presence history', async () => {
    await service.updatePresence('user1', 'user1@example.com', { status: 'online' });
    await new Promise((resolve) => setTimeout(resolve, 1));
    await service.updatePresence('user1', 'user1@example.com', { status: 'idle' });

    const history = await service.getHistory('user1');
    expect(history.length).toBeGreaterThanOrEqual(2);
  });

  // ==================== Statistics Tests ====================

  it('should calculate statistics', async () => {
    await service.updatePresence('user1', 'user1@example.com', { status: 'online' });
    await service.updatePresence('user2', 'user2@example.com', { status: 'idle' });

    const stats = await service.getStatistics();
    expect(stats.totalUsers).toBe(2);
    expect(stats.usersByStatus.online).toBe(1);
    expect(stats.usersByStatus.idle).toBe(1);
  });

  it('should calculate activity statistics', async () => {
    await service.updatePresence('user1', 'user1@example.com', {
      currentActivity: { context: 'file', description: 'Editing' },
    });
    await service.updatePresence('user2', 'user2@example.com', {
      currentActivity: { context: 'file', description: 'Editing' },
    });
    await service.updatePresence('user3', 'user3@example.com', {
      currentActivity: { context: 'debug', description: 'Debugging' },
    });

    const stats = await service.getStatistics();
    expect(stats.usersByActivity.file).toBe(2);
    expect(stats.usersByActivity.debug).toBe(1);
  });

  // ==================== Multiple Users Tests ====================

  it('should handle multiple users', async () => {
    for (let i = 1; i <= 10; i++) {
      await service.markOnline(`user${i}`, `user${i}@example.com`, 'workspace1');
    }

    const stats = await service.getStatistics();
    expect(stats.totalUsers).toBe(10);
  });

  it('should handle multiple workspaces', async () => {
    await service.markOnline('user1', 'user1@example.com', 'workspace1');
    await service.markOnline('user2', 'user2@example.com', 'workspace2');
    await service.markOnline('user3', 'user3@example.com', 'workspace3');

    const stats = await service.getStatistics();
    expect(stats.workspaces).toBe(3);
  });

  // ==================== Error Handling Tests ====================

  it('should throw error if not initialized', async () => {
    const newService = new PresenceService();
    await expect(newService.updatePresence('user1', 'user1@example.com', {})).rejects.toThrow();
  });

  // ==================== Singleton Pattern Tests ====================

  it('should use singleton pattern', () => {
    const instance1 = PresenceService.getInstance();
    const instance2 = PresenceService.getInstance();
    expect(instance1).toBe(instance2);
  });

  // ==================== Get All Presence Tests ====================

  it('should get all active presence', async () => {
    await service.markOnline('user1', 'user1@example.com');
    await service.markOnline('user2', 'user2@example.com');
    await service.markOnline('user3', 'user3@example.com');

    const all = await service.getAllPresence();
    expect(all.length).toBe(3);
  });

  // ==================== Expiration Tests ====================

  it('should expire old entries', async () => {
    const expireService = new PresenceService({ ttl: 1000, cleanupInterval: 100 });
    await expireService.initialize();

    await expireService.markOnline('user1', 'user1@example.com');

    // Wait for expiration
    await new Promise((resolve) => setTimeout(resolve, 1500));

    const presence = await expireService.getPresence('user1');
    expect(presence).toBeUndefined();

    await expireService.shutdown();
  });
});
