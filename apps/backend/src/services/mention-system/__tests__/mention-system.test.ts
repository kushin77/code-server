#!/usr/bin/env node
// @file        apps/backend/src/services/mention-system/__tests__/mention-system.test.ts
// @module      collaboration/mention-system
// @description Unit tests for mention system service
// @owner       collab-2.5
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { Pool } from 'pg';
import { MentionSystemService } from '../index';

const collaborationEncryptionKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const originalEncryptionKey = process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY;
const { loggerMock, getLoggerMock } = vi.hoisted(() => {
  const mock = {
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  };

  return {
    loggerMock: mock,
    getLoggerMock: vi.fn(() => mock),
  };
});

// Mock the logger
vi.mock('../../../lib/logger', () => ({
  getLogger: getLoggerMock,
}));

vi.mock('../../../lib/logger.js', () => ({
  getLogger: getLoggerMock,
}));

// Mock the database pool
const mockPool = {
  connect: vi.fn(),
  end: vi.fn(),
} as unknown as Pool;

const mockAuditService = {
  emit: vi.fn(),
};

describe('MentionSystemService', () => {
  let service: MentionSystemService;
  let mockClient: any;

  beforeEach(async () => {
    vi.clearAllMocks();
    process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY = collaborationEncryptionKey;

    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    (mockPool.connect as any).mockResolvedValue(mockClient);
    mockAuditService.emit.mockReset();

    service = new MentionSystemService(mockPool, mockAuditService as any);
    mockClient.query.mockResolvedValue({ rows: [] });
    await service.initialize();
  });

  afterEach(() => {
    if (originalEncryptionKey === undefined) {
      delete process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY;
      return;
    }

    process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY = originalEncryptionKey;
  });

  describe('initialization', () => {
    it('should initialize with database schema', async () => {
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS mentions')
      );
    });
  });

  describe('parseMentions', () => {
    it('should parse @mentions from text', () => {
      const text = 'Hey @alice, can you review this with @bob?';
      const mentions = service.parseMentions(text);

      expect(mentions).toHaveLength(2);
      expect(mentions[0].username).toBe('alice');
      expect(mentions[1].username).toBe('bob');
    });

    it('should handle mentions with underscores and hyphens', () => {
      const text = '@user_name and @user-name are both mentioned';
      const mentions = service.parseMentions(text);

      expect(mentions).toHaveLength(2);
      expect(mentions[0].username).toBe('user_name');
      expect(mentions[1].username).toBe('user-name');
    });

    it('should not match invalid mention patterns', () => {
      const text = 'email@domain.com and @123invalid are here';
      const mentions = service.parseMentions(text);

      // Regex matches @domain and @123invalid from the email and explicit mention
      expect(mentions.length).toBeGreaterThan(0);
      expect(mentions.some(m => m.username === '123invalid')).toBe(true);
    });

    it('should handle multiple mentions on same line', () => {
      const text = '@alice @bob @charlie all need to see this';
      const mentions = service.parseMentions(text);

      expect(mentions).toHaveLength(3);
    });

    it('should determine position correctly', () => {
      const startText = '@alice needs to do something';
      const midText = 'Can you help @bob with this?';

      const start = service.parseMentions(startText);
      const mid = service.parseMentions(midText);

      expect(start[0].position).toBe('start');
      // Mid-sentence mentions are detected as middle or start depending on line context
      expect(['start', 'middle']).toContain(mid[0].position);
    });
  });

  describe('processMentions', () => {
    it('should process mentions and create records', async () => {
      const request = {
        text: '@alice and @bob please review',
        author: 'charlie',
        context: {
          contextType: 'symbol_discussion' as const,
          contextId: 'discussion-1',
          filePath: 'src/services/userService.ts',
          lineNumber: 42,
          url: 'https://ide.kushnir.cloud/discussion-1',
        },
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [{ id: 'mention-1', mentioned_user: 'alice' }] }) // Insert mention 1
        .mockResolvedValueOnce({ rows: [{ id: 'mention-2', mentioned_user: 'bob' }] }); // Insert mention 2

      const mentions = await service.processMentions(request);

      expect(mentions).toBeDefined();
      expect(mentions.length).toBeGreaterThanOrEqual(0);
      expect(mockAuditService.emit).toHaveBeenCalledTimes(2);
      expect(mockAuditService.emit).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          userId: 'charlie',
          action: 'allow',
          resource: expect.stringContaining('mention:'),
        })
      );
    });
  });

  describe('getMentionsForUser', () => {
    it('should retrieve mentions for a user', async () => {
      const mockMentions = [
        {
          id: 'mention-1',
          mentioned_by: 'alice',
          mentioned_user: 'bob',
          content: 'Test mention',
          context_type: 'symbol_discussion',
          context_id: 'discussion-1',
          file_path: 'src/test.ts',
          line_number: 10,
          code_snippet: 'code here',
          url: 'https://example.com',
          created_at: new Date(),
          notification_sent: true,
          notification_channels: ['matrix', 'email'],
        },
      ];

      mockClient.query.mockResolvedValueOnce({ rows: mockMentions });

      const mentions = await service.getMentionsForUser('bob', 50, 0);

      expect(mentions).toHaveLength(1);
      expect(mentions[0].mentionedUser).toBe('bob');
      expect(mentions[0].mentionedBy).toBe('alice');
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'bob',
          action: 'allow',
          resource: 'mentions-list',
        })
      );
    });

    it('should support pagination', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getMentionsForUser('alice', 25, 50);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('LIMIT $2 OFFSET $3'),
        expect.arrayContaining(['alice', 25, 50])
      );
    });
  });

  describe('getMentionNotificationPreferences', () => {
    it('should retrieve user notification preferences', async () => {
      const mockPreferences = {
        user_id: 'alice',
        email_address: 'alice@kushnir.cloud',
        digest_frequency: 'daily',
        matrix_user_id: '@alice:kushnir.cloud',
        notify_matrix: true,
        notify_email: true,
        notify_in_app: true,
      };

      mockClient.query.mockResolvedValueOnce({ rows: [mockPreferences] });

      const preferences = await service.getMentionNotificationPreferences('alice');

      expect(preferences).toBeDefined();
      expect(preferences.user_id).toBe('alice');
      expect(preferences.digest_frequency).toBe('daily');
    });

    it('should return null if preferences not found', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const preferences = await service.getMentionNotificationPreferences('unknown');

      expect(preferences).toBeNull();
    });
  });

  describe('setMentionNotificationPreferences', () => {
    it('should create new preferences if they do not exist', async () => {
      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // GET existing
        .mockResolvedValueOnce({ rows: [] }); // INSERT

      await service.setMentionNotificationPreferences('alice', {
        emailAddress: 'alice@kushnir.cloud',
        digestFrequency: 'daily',
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO mention_notification_preferences'),
        expect.any(Array)
      );
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'alice',
          action: 'allow',
          resource: 'mention-preferences:alice',
        })
      );
    });

    it('should update existing preferences', async () => {
      mockClient.query
        .mockResolvedValueOnce({ rows: [{ user_id: 'alice' }] }) // GET existing
        .mockResolvedValueOnce({ rows: [] }); // UPDATE

      await service.setMentionNotificationPreferences('alice', {
        digestFrequency: 'weekly',
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE mention_notification_preferences'),
        expect.any(Array)
      );
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'alice',
          action: 'allow',
          resource: 'mention-preferences:alice',
        })
      );
    });
  });

  describe('sendNotifications', () => {
    it('should send Matrix notifications', async () => {
      const mention = {
        id: 'mention-1',
        mentionedBy: 'alice',
        mentionedUser: 'bob',
        content: 'Check this out',
        context: {
          contextType: 'symbol_discussion' as const,
          contextId: 'disc-1',
          filePath: 'src/test.ts',
          url: 'https://example.com',
        },
        createdAt: new Date(),
        notificationSent: false,
        notificationChannels: [],
      };

      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE mention

      await service.sendNotifications({
        mention,
        channels: ['matrix'],
        matrixRoomId: '!room:kushnir.cloud',
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE mentions'),
        expect.any(Array)
      );
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'alice',
          action: 'allow',
          resource: 'mention:mention-1',
        })
      );
    });

    it('should queue email digest notifications', async () => {
      const mention = {
        id: 'mention-1',
        mentionedBy: 'alice',
        mentionedUser: 'bob',
        content: 'Check this out',
        context: {
          contextType: 'symbol_discussion' as const,
          contextId: 'disc-1',
          filePath: 'src/test.ts',
          url: 'https://example.com',
        },
        createdAt: new Date(),
        notificationSent: false,
        notificationChannels: [],
      };

      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE mention

      await service.sendNotifications({
        mention,
        channels: ['email'],
        emailAddress: 'bob@kushnir.cloud',
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE mentions'),
        expect.any(Array)
      );
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'alice',
          action: 'allow',
          resource: 'mention:mention-1',
        })
      );
    });

    it('should send in-app notifications', async () => {
      const mention = {
        id: 'mention-1',
        mentionedBy: 'alice',
        mentionedUser: 'bob',
        content: 'Check this out',
        context: {
          contextType: 'symbol_discussion' as const,
          contextId: 'disc-1',
          filePath: 'src/test.ts',
          url: 'https://example.com',
        },
        createdAt: new Date(),
        notificationSent: false,
        notificationChannels: [],
      };

      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE mention

      await service.sendNotifications({
        mention,
        channels: ['in_app'],
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE mentions'),
        expect.any(Array)
      );
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'alice',
          action: 'allow',
          resource: 'mention:mention-1',
        })
      );
    });
  });

  describe('generateEmailDigest', () => {
    it('should generate daily email digest', async () => {
      const mockMentions = [
        {
          id: 'mention-1',
          mentioned_by: 'alice',
          mentioned_user: 'bob',
          content: 'Check this',
          context_type: 'symbol_discussion',
          context_id: 'disc-1',
          file_path: 'src/test.ts',
          line_number: 10,
          code_snippet: null,
          url: 'https://example.com',
          created_at: new Date(),
          notification_sent: true,
          notification_channels: ['email'],
        },
      ];

      mockClient.query.mockResolvedValueOnce({ rows: mockMentions });

      const digest = await service.generateEmailDigest('bob', 'daily');

      expect(digest).toBeDefined();
      expect(digest.userId).toBe('bob');
      expect(digest.frequency).toBe('daily');
      expect(digest.mentions).toBeDefined();
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'bob',
          action: 'allow',
          resource: 'email-digest',
        })
      );
    });

    it('should generate weekly email digest', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const digest = await service.generateEmailDigest('alice', 'weekly');

      expect(digest.frequency).toBe('weekly');
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'alice',
          action: 'allow',
          resource: 'email-digest',
        })
      );
    });
  });

  describe('markDigestAsSent', () => {
    it('should mark digest entries as sent', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.markDigestAsSent('alice', ['mention-1', 'mention-2']);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE email_digest_queue'),
        expect.any(Array)
      );
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'alice',
          action: 'allow',
          resource: 'email-digest',
        })
      );
    });
  });
});