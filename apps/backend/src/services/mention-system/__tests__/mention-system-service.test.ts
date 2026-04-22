import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MentionSystemService } from '../mention-system-service.js';
import { MentionTarget } from '../types.js';

describe('Mention System Service', () => {
  let service: MentionSystemService;

  // Helper: Create mock target
  function createTarget(type: MentionTarget['type'] = 'file'): MentionTarget {
    return {
      type,
      filePath: '/workspace/src/main.ts',
      lineNumber: 42,
      snippet: 'const value = "test";',
    };
  }

  beforeEach(async () => {
    service = new MentionSystemService();
    await service.initialize();
  });

  afterEach(async () => {
    await service.shutdown();
  });

  describe('Initialization', () => {
    it('should initialize successfully', async () => {
      expect(service).toBeDefined();
      const stats = await service.getStatistics();
      expect(stats.totalMentions).toBe(0);
    });

    it('should not initialize twice', async () => {
      await service.initialize();
      expect(service).toBeDefined();
    });

    it('should emit initialized event', async () => {
      return new Promise<void>((resolve) => {
        const svc = new MentionSystemService();
        svc.once('initialized', () => {
          svc.shutdown().then(() => resolve());
        });
        svc.initialize();
      });
    });
  });

  describe('Mention Creation', () => {
    it('should create mention', async () => {
      const target = createTarget('file');
      const mention = await service.createMention(
        'user-alice',
        'user-bob',
        target,
        '@user-bob check this code',
        'code',
        'workspace-1',
        'session-1',
        '192.168.1.1',
        'Chrome/95.0',
        'normal'
      );

      expect(mention.id).toBeDefined();
      expect(mention.userId).toBe('user-bob');
      expect(mention.createdBy).toBe('user-alice');
      expect(mention.priority).toBe('normal');
      expect(mention.acknowledged).toBe(false);
    });

    it('should create mention with different priorities', async () => {
      const target = createTarget('file');

      const normalMention = await service.createMention(
        'user-alice',
        'user-bob',
        target,
        'Check this',
        'code',
        undefined,
        undefined,
        undefined,
        undefined,
        'normal'
      );

      const urgentMention = await service.createMention(
        'user-alice',
        'user-bob',
        target,
        'Urgent!',
        'code',
        undefined,
        undefined,
        undefined,
        undefined,
        'urgent'
      );

      expect(normalMention.priority).toBe('normal');
      expect(urgentMention.priority).toBe('urgent');
    });

    it('should emit mention-created event', async () => {
      return new Promise<void>((resolve) => {
        service.once('mention-created', ({ notification }) => {
          expect(notification.userId).toBe('user-bob');
          resolve();
        });

        const target = createTarget();
        service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');
      });
    });

    it('should increment mention count', async () => {
      const target = createTarget();
      await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');
      await service.createMention('user-alice', 'user-bob', target, 'And this', 'code');

      const stats = await service.getStatistics();
      expect(stats.totalMentions).toBe(2);
    });

    it('should handle different context types', async () => {
      const target = createTarget();
      const contextTypes = ['code', 'comment', 'commit-message', 'pr-review', 'issue-comment', 'chat'] as const;

      for (const contextType of contextTypes) {
        const mention = await service.createMention(
          'user-alice',
          'user-bob',
          target,
          'Check this',
          contextType
        );
        expect(mention.contextType).toBe(contextType);
      }
    });
  });

  describe('Mention Retrieval', () => {
    it('should get mention by ID', async () => {
      const target = createTarget();
      const created = await service.createMention(
        'user-alice',
        'user-bob',
        target,
        'Check this',
        'code'
      );

      const retrieved = await service.getMention(created.id);
      expect(retrieved).toBeDefined();
      expect(retrieved?.id).toBe(created.id);
    });

    it('should return undefined for non-existent mention', async () => {
      const result = await service.getMention('non-existent-id');
      expect(result).toBeUndefined();
    });

    it('should get user mentions', async () => {
      const target = createTarget();
      await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');
      await service.createMention('user-charlie', 'user-bob', target, 'And this', 'code');
      await service.createMention('user-alice', 'user-charlie', target, 'Different user', 'code');

      const bobMentions = await service.getUserMentions('user-bob');
      expect(bobMentions.length).toBe(2);
      expect(bobMentions.every((m) => m.userId === 'user-bob')).toBe(true);
    });

    it('should get mentions by user', async () => {
      const target = createTarget();
      await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');
      await service.createMention('user-alice', 'user-charlie', target, 'And this', 'code');

      const aliceMentions = await service.getMentionsByUser('user-alice');
      expect(aliceMentions.length).toBe(2);
      expect(aliceMentions.every((m) => m.createdBy === 'user-alice')).toBe(true);
    });

    it('should get all mentions', async () => {
      const target = createTarget();
      await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');
      await service.createMention('user-charlie', 'user-bob', target, 'And this', 'code');

      const all = await service.getAllMentions();
      expect(all.length).toBe(2);
    });
  });

  describe('Mention Query', () => {
    beforeEach(async () => {
      const fileTarget = createTarget('file');
      const functionTarget = createTarget('function');

      await service.createMention(
        'user-alice',
        'user-bob',
        fileTarget,
        'Check code',
        'code',
        'workspace-1',
        'session-1',
        '192.168.1.1',
        'Chrome',
        'normal'
      );

      await service.createMention(
        'user-charlie',
        'user-bob',
        functionTarget,
        'Review function',
        'pr-review',
        'workspace-1',
        'session-2',
        '192.168.1.2',
        'Firefox',
        'high'
      );

      await service.createMention(
        'user-alice',
        'user-bob',
        fileTarget,
        'Check again',
        'comment',
        'workspace-2',
        'session-1',
        '192.168.1.1',
        'Chrome',
        'low'
      );
    });

    it('should query all mentions', async () => {
      const result = await service.queryMentions({});
      expect(result.length).toBe(3);
    });

    it('should filter by userId', async () => {
      const result = await service.queryMentions({ userId: 'user-bob' });
      expect(result.length).toBe(3);
      expect(result.every((m) => m.userId === 'user-bob')).toBe(true);
    });

    it('should filter by target type', async () => {
      const result = await service.queryMentions({ targetType: 'file' });
      expect(result.length).toBe(2);
      expect(result.every((m) => m.target.type === 'file')).toBe(true);
    });

    it('should filter by context type', async () => {
      const result = await service.queryMentions({ contextType: 'code' });
      expect(result.length).toBe(1);
    });

    it('should filter by priority', async () => {
      const result = await service.queryMentions({ priority: 'high' });
      expect(result.length).toBe(1);
      expect(result[0].priority).toBe('high');
    });

    it('should paginate results', async () => {
      const page1 = await service.queryMentions({ limit: 2, offset: 0 });
      expect(page1.length).toBe(2);

      const page2 = await service.queryMentions({ limit: 2, offset: 2 });
      expect(page2.length).toBe(1);
    });
  });

  describe('Mention Reading', () => {
    it('should mark mention as read', async () => {
      const target = createTarget();
      const created = await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');

      expect(created.readAt).toBeUndefined();

      await new Promise((resolve) => setTimeout(resolve, 1));
      const read = await service.readMention(created.id, 'user-bob', '192.168.1.1', 'Chrome');
      expect(read.readAt).toBeDefined();
      expect(read.readAt).toBeGreaterThan(created.createdAt);
    });

    it('should emit mention-read event', async () => {
      return new Promise<void>((resolve) => {
        service.once('mention-read', ({ mentionId }) => {
          expect(mentionId).toBeDefined();
          resolve();
        });

        const target = createTarget();
        service.createMention('user-alice', 'user-bob', target, 'Check this', 'code')
          .then((mention) => service.readMention(mention.id, 'user-bob'));
      });
    });

    it('should get unread mentions only', async () => {
      const target = createTarget();
      const m1 = await service.createMention('user-alice', 'user-bob', target, 'Check 1', 'code');
      const m2 = await service.createMention('user-alice', 'user-bob', target, 'Check 2', 'code');

      await service.readMention(m1.id, 'user-bob');

      const unread = await service.getUserMentions('user-bob', true);
      expect(unread.length).toBe(1);
      expect(unread[0].id).toBe(m2.id);
    });

    it('should calculate average response time', async () => {
      const target = createTarget();
      const m1 = await service.createMention('user-alice', 'user-bob', target, 'Check 1', 'code');

      await new Promise((resolve) => setTimeout(resolve, 10));
      await service.readMention(m1.id, 'user-bob');

      const stats = await service.getStatistics();
      expect(stats.averageResponseTime).toBeGreaterThan(0);
    });
  });

  describe('Mention Acknowledgment', () => {
    it('should acknowledge mention', async () => {
      const target = createTarget();
      const created = await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');

      expect(created.acknowledged).toBe(false);

      const ack = await service.acknowledgeMention(created.id, 'user-bob', '192.168.1.1', 'Chrome');
      expect(ack.acknowledged).toBe(true);
    });

    it('should emit mention-acknowledged event', async () => {
      return new Promise<void>((resolve) => {
        service.once('mention-acknowledged', ({ mentionId }) => {
          expect(mentionId).toBeDefined();
          resolve();
        });

        const target = createTarget();
        service.createMention('user-alice', 'user-bob', target, 'Check this', 'code')
          .then((mention) => service.acknowledgeMention(mention.id, 'user-bob'));
      });
    });
  });

  describe('Mention Deletion', () => {
    it('should delete mention', async () => {
      const target = createTarget();
      const created = await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');

      await service.deleteMention(created.id, 'user-bob', '192.168.1.1', 'Chrome');

      const result = await service.getMention(created.id);
      expect(result).toBeUndefined();
    });

    it('should emit mention-deleted event', async () => {
      return new Promise<void>((resolve) => {
        service.once('mention-deleted', ({ mentionId }) => {
          expect(mentionId).toBeDefined();
          resolve();
        });

        const target = createTarget();
        service.createMention('user-alice', 'user-bob', target, 'Check this', 'code')
          .then((mention) => service.deleteMention(mention.id, 'user-bob'));
      });
    });

    it('should reject non-existent mention deletion', async () => {
      await expect(service.deleteMention('non-existent', 'user-bob')).rejects.toThrow('not found');
    });
  });

  describe('Audit Logging', () => {
    it('should log mention creation', async () => {
      const target = createTarget();
      await service.createMention(
        'user-alice',
        'user-bob',
        target,
        'Check this',
        'code',
        'workspace-1',
        'session-1',
        '192.168.1.1',
        'Chrome'
      );

      const auditLog = await service.getAuditLog('user-bob');
      expect(auditLog.length).toBeGreaterThan(0);
      expect(auditLog[0].operation).toBe('created');
      expect(auditLog[0].status).toBe('success');
    });

    it('should log mention reading', async () => {
      const target = createTarget();
      const created = await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');

      await service.readMention(created.id, 'user-bob', '192.168.1.1', 'Chrome');

      const auditLog = await service.getAuditLog('user-bob');
      expect(auditLog.some((e) => e.operation === 'read')).toBe(true);
    });

    it('should log mention acknowledgment', async () => {
      const target = createTarget();
      const created = await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');

      await service.acknowledgeMention(created.id, 'user-bob', '192.168.1.1', 'Chrome');

      const auditLog = await service.getAuditLog('user-bob');
      expect(auditLog.some((e) => e.operation === 'acknowledged')).toBe(true);
    });

    it('should log mention deletion', async () => {
      const target = createTarget();
      const created = await service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');

      await service.deleteMention(created.id, 'user-bob', '192.168.1.1', 'Chrome');

      const auditLog = await service.getAuditLog('user-bob');
      expect(auditLog.some((e) => e.operation === 'deleted')).toBe(true);
    });

    it('should include IP and user agent in audit log', async () => {
      const target = createTarget();
      const ipAddress = '192.168.1.100';
      const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';

      await service.createMention(
        'user-alice',
        'user-bob',
        target,
        'Check this',
        'code',
        undefined,
        undefined,
        ipAddress,
        userAgent
      );

      const auditLog = await service.getAuditLog('user-bob');
      expect(auditLog[0].ipAddress).toBe(ipAddress);
      expect(auditLog[0].userAgent).toBe(userAgent);
    });

    it('should emit audit-logged event', async () => {
      return new Promise<void>((resolve) => {
        service.once('audit-logged', ({ userId, entry }) => {
          expect(userId).toBe('user-bob');
          expect(entry.operation).toBe('created');
          resolve();
        });

        const target = createTarget();
        service.createMention('user-alice', 'user-bob', target, 'Check this', 'code');
      });
    });
  });

  describe('Settings Management', () => {
    it('should get default settings', async () => {
      const settings = await service.getSettings('user-alice');
      expect(settings).toBeUndefined();
    });

    it('should create settings', async () => {
      const settings = await service.updateSettings('user-alice', {
        emailNotifications: true,
        pushNotifications: false,
        privacyLevel: 'private',
      });

      expect(settings.userId).toBe('user-alice');
      expect(settings.emailNotifications).toBe(true);
      expect(settings.pushNotifications).toBe(false);
      expect(settings.privacyLevel).toBe('private');
    });

    it('should update settings', async () => {
      await service.updateSettings('user-alice', {
        emailNotifications: true,
      });

      const updated = await service.updateSettings('user-alice', {
        emailNotifications: false,
        pushNotifications: true,
      });

      expect(updated.emailNotifications).toBe(false);
      expect(updated.pushNotifications).toBe(true);
    });

    it('should emit settings-updated event', async () => {
      return new Promise<void>((resolve) => {
        service.once('settings-updated', ({ userId }) => {
          expect(userId).toBe('user-alice');
          resolve();
        });

        service.updateSettings('user-alice', { emailNotifications: true });
      });
    });

    it('should block mentions from specific users', async () => {
      await service.updateSettings('user-bob', {
        privacyLevel: 'private',
        blockedUsers: ['user-charlie'],
      });

      const target = createTarget();

      // Charlie should be blocked
      await expect(
        service.createMention('user-charlie', 'user-bob', target, 'Check this', 'code')
      ).rejects.toThrow('blocked');
    });
  });

  describe('Statistics', () => {
    beforeEach(async () => {
      const fileTarget = createTarget('file');
      const functionTarget = createTarget('function');

      await service.createMention('user-alice', 'user-bob', fileTarget, 'Check file', 'code');
      await service.createMention('user-charlie', 'user-bob', functionTarget, 'Check func', 'pr-review', 'ws-1', 'sess-1', '192.168.1.1', 'Chrome', 'high');
      await service.createMention('user-alice', 'user-charlie', fileTarget, 'Check again', 'comment');
    });

    it('should track total mentions', async () => {
      const stats = await service.getStatistics();
      expect(stats.totalMentions).toBe(3);
    });

    it('should track mentions by type', async () => {
      const stats = await service.getStatistics();
      expect(stats.mentionsByType['file']).toBe(2);
      expect(stats.mentionsByType['function']).toBe(1);
    });

    it('should track mentions by user', async () => {
      const stats = await service.getStatistics();
      expect(stats.mentionsByUser['user-bob']).toBe(2);
      expect(stats.mentionsByUser['user-charlie']).toBe(1);
    });

    it('should track mentions by context', async () => {
      const stats = await service.getStatistics();
      expect(stats.mentionsByContext['code']).toBe(1);
      expect(stats.mentionsByContext['pr-review']).toBe(1);
      expect(stats.mentionsByContext['comment']).toBe(1);
    });

    it('should track priority distribution', async () => {
      const stats = await service.getStatistics();
      expect(stats.priorityDistribution['normal']).toBeGreaterThan(0);
      expect(stats.priorityDistribution['high']).toBe(1);
    });

    it('should count unread mentions', async () => {
      const stats = await service.getStatistics();
      expect(stats.unreadCount).toBe(3);

      // Read one
      const allMentions = await service.getAllMentions();
      await service.readMention(allMentions[0].id, allMentions[0].userId);

      const updatedStats = await service.getStatistics();
      expect(updatedStats.unreadCount).toBe(2);
    });
  });

  describe('Shutdown', () => {
    it('should shutdown gracefully', async () => {
      const svc = new MentionSystemService();
      await svc.initialize();
      const target = createTarget();
      await svc.createMention('user-alice', 'user-bob', target, 'Check this', 'code');
      await svc.shutdown();
      expect(true).toBe(true);
    });
  });

  describe('Singleton Pattern', () => {
    it('should use singleton instance', () => {
      const instance1 = MentionSystemService.getInstance();
      const instance2 = MentionSystemService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('Integration', () => {
    it('should handle complete mention workflow', async () => {
      // 1. Create mention
      const target = createTarget('file');
      const mention = await service.createMention(
        'user-alice',
        'user-bob',
        target,
        '@user-bob check this',
        'code',
        'workspace-1'
      );
      expect(mention).toBeDefined();

      // 2. Verify audit log
      const auditLog = await service.getAuditLog('user-bob');
      expect(auditLog.length).toBeGreaterThan(0);

      // 3. Read mention
      const read = await service.readMention(mention.id, 'user-bob');
      expect(read.readAt).toBeDefined();

      // 4. Acknowledge mention
      const ack = await service.acknowledgeMention(mention.id, 'user-bob');
      expect(ack.acknowledged).toBe(true);

      // 5. Get stats
      const stats = await service.getStatistics();
      expect(stats.totalMentions).toBe(1);
      expect(stats.unreadCount).toBe(0);

      // 6. Delete mention
      await service.deleteMention(mention.id, 'user-bob');
      const deleted = await service.getMention(mention.id);
      expect(deleted).toBeUndefined();
    });

    it('should manage multiple users and mentions', async () => {
      const target = createTarget();

      // Create mentions for different users
      await service.createMention('user-alice', 'user-bob', target, 'Check 1', 'code');
      await service.createMention('user-alice', 'user-bob', target, 'Check 2', 'code');
      await service.createMention('user-charlie', 'user-bob', target, 'Check 3', 'code');
      await service.createMention('user-alice', 'user-charlie', target, 'Check 4', 'code');

      // Query mentions for each user
      const bobMentions = await service.getUserMentions('user-bob');
      expect(bobMentions.length).toBe(3);

      const charlieMentions = await service.getUserMentions('user-charlie');
      expect(charlieMentions.length).toBe(1);

      // Check audit logs
      const bobAudit = await service.getAuditLog('user-bob');
      expect(bobAudit.length).toBe(3);

      const charlieAudit = await service.getAuditLog('user-charlie');
      expect(charlieAudit.length).toBe(1);

      // Verify stats
      const stats = await service.getStatistics();
      expect(stats.totalMentions).toBe(4);
      expect(stats.mentionsByUser['user-bob']).toBe(3);
      expect(stats.mentionsByUser['user-charlie']).toBe(1);
    });
  });
});
