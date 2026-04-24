#!/usr/bin/env node
// @file        apps/backend/src/services/mention-system/index.ts
// @module      collaboration/mention-system
// @description @mention parsing and notification system for code discussions
// @owner       collab-2.5
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger.js';
import { AuditService } from '../audit/audit-service.js';
import { CollaborationMessageEncryptionService } from '../collaboration-message-encryption/index.js';
import { NotificationAggregator } from '../notification-aggregator/notification-aggregator-service.js';
import { MatrixCollaborationTransportService } from '../collaboration-message-transport/index.js';

export interface MentionMatch {
  username: string;
  start: number;
  end: number;
  position: 'inline' | 'start' | 'middle' | 'end';
}

export interface NotificationContext {
  contextType: 'symbol_discussion' | 'comment' | 'thread' | 'code_review';
  contextId: string;
  filePath: string;
  lineNumber?: number;
  codeSnippet?: string;
  url: string;
}

export interface Mention {
  id: string;
  mentionedBy: string;
  mentionedUser: string;
  content: string;
  context: NotificationContext;
  createdAt: Date;
  notificationSent: boolean;
  notificationChannels: NotificationChannel[];
}

export type NotificationChannel = 'matrix' | 'email' | 'in_app';

export interface EmailDigestEntry {
  mention: Mention;
  summaryText: string;
}

export interface EmailDigest {
  userId: string;
  frequency: 'immediate' | 'daily' | 'weekly';
  mentions: EmailDigestEntry[];
  createdAt: Date;
  sentAt?: Date;
}

export interface ParseMentionsRequest {
  text: string;
  author: string;
  context: NotificationContext;
}

export interface SendNotificationRequest {
  mention: Mention;
  channels: NotificationChannel[];
  matrixRoomId?: string;
  emailAddress?: string;
}

export class MentionSystemService extends EventEmitter {
  private pool: Pool;
  private auditService?: AuditService;
  private matrixTransport?: MatrixCollaborationTransportService;
  private logger = getLogger('MentionSystemService');
  private initialized = false;
  private matrixBaseUrl = process.env.MATRIX_BASE_URL || 'https://matrix.kushnir.cloud';
  private emailFrom = process.env.MENTION_EMAIL_FROM || 'mentions@kushnir.cloud';
  private mentionRegex = /@([a-zA-Z0-9_-]+)/g;

  constructor(pool: Pool, auditService?: AuditService, matrixTransport?: MatrixCollaborationTransportService) {
    super();
    this.pool = pool;
    this.auditService = auditService;
    this.matrixTransport = matrixTransport;
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    try {
      await this.createTables();
      this.initialized = true;
      this.logger.info('Mention system database schema initialized');
    } catch (error) {
      this.logger.error('Failed to initialize mention system schema', { error });
      throw error;
    }
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Mentions table
      await client.query(`
        CREATE TABLE IF NOT EXISTS mentions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          mentioned_by TEXT NOT NULL,
          mentioned_user TEXT NOT NULL,
          content TEXT NOT NULL,
          context_type TEXT NOT NULL CHECK (context_type IN ('symbol_discussion', 'comment', 'thread', 'code_review')),
          context_id TEXT NOT NULL,
          file_path TEXT,
          line_number INTEGER,
          code_snippet TEXT,
          url TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          notification_sent BOOLEAN DEFAULT FALSE,
          notification_channels TEXT[] DEFAULT '{}',
          processed BOOLEAN DEFAULT FALSE
        )
      `);

      // User notification preferences table
      await client.query(`
        CREATE TABLE IF NOT EXISTS mention_notification_preferences (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL UNIQUE,
          email_address TEXT,
          digest_frequency TEXT DEFAULT 'daily' CHECK (digest_frequency IN ('immediate', 'daily', 'weekly')),
          matrix_user_id TEXT,
          notify_matrix BOOLEAN DEFAULT TRUE,
          notify_email BOOLEAN DEFAULT TRUE,
          notify_in_app BOOLEAN DEFAULT TRUE,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Email digest queue
      await client.query(`
        CREATE TABLE IF NOT EXISTS email_digest_queue (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          mention_id UUID NOT NULL REFERENCES mentions(id) ON DELETE CASCADE,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          sent_at TIMESTAMP WITH TIME ZONE
        )
      `);

      // Indexes
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_mentions_mentioned_user ON mentions(mentioned_user);
        CREATE INDEX IF NOT EXISTS idx_mentions_created_at ON mentions(created_at);
        CREATE INDEX IF NOT EXISTS idx_mentions_notification_sent ON mentions(notification_sent);
        CREATE INDEX IF NOT EXISTS idx_email_digest_user_id ON email_digest_queue(user_id);
        CREATE INDEX IF NOT EXISTS idx_email_digest_sent_at ON email_digest_queue(sent_at);
      `);

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  parseMentions(text: string): MentionMatch[] {
    const matches: MentionMatch[] = [];
    let match: RegExpExecArray | null;

    while ((match = this.mentionRegex.exec(text)) !== null) {
      const start = match.index;
      const end = match.index + match[0].length;
      const position = this.determinePosition(text, start);

      matches.push({
        username: match[1],
        start,
        end,
        position,
      });
    }

    return matches;
  }

  private determinePosition(text: string, index: number): 'inline' | 'start' | 'middle' | 'end' {
    const beforeMention = text.substring(0, index).trim();
    const afterMention = text.substring(index + 1).trim();

    // If nothing before mention (or very little), it's a start
    if (beforeMention === '@' || beforeMention.length < 5) {
      return 'start';
    }

    // If nothing after mention, it's an end
    if (afterMention.length === 0) {
      return 'end';
    }

    // Otherwise it's in the middle
    return 'middle';
  }

  async processMentions(request: ParseMentionsRequest): Promise<Mention[]> {
    const matches = this.parseMentions(request.text);
    const mentions: Mention[] = [];

    for (const match of matches) {
      try {
        const mention = await this.createMention({
          mentionedBy: request.author,
          mentionedUser: match.username,
          content: request.text,
          context: request.context,
        });

        mentions.push(mention);
        // SOC2: Audit mention creation
        this.auditService?.emit({
          userId: request.author,
          action: 'allow',
          resource: 'mention:' + mention.id,
          reason: 'Created mention for user ' + match.username,
          metadata: { mentionedUser: match.username, context: request.context }
        });

        this.logger.info('Created mention', { mentionedUser: match.username, contextId: request.context.contextId });
      } catch (error) {
        this.logger.error('Failed to create mention', { error, username: match.username });
      }
    }

    return mentions;
  }

  private async createMention(data: {
    mentionedBy: string;
    mentionedUser: string;
    content: string;
    context: NotificationContext;
  }): Promise<Mention> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `INSERT INTO mentions (
          mentioned_by, mentioned_user, content, context_type, context_id,
          file_path, line_number, code_snippet, url, notification_channels
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING *`,
        [
          data.mentionedBy,
          data.mentionedUser,
          data.content,
          data.context.contextType,
          data.context.contextId,
          data.context.filePath,
          data.context.lineNumber || null,
          data.context.codeSnippet || null,
          data.context.url,
          '{}',
        ]
      );

      const row = result.rows[0];
      return {
        id: row.id,
        mentionedBy: row.mentioned_by,
        mentionedUser: row.mentioned_user,
        content: row.content,
        context: {
          contextType: row.context_type,
          contextId: row.context_id,
          filePath: row.file_path,
          lineNumber: row.line_number,
          codeSnippet: row.code_snippet,
          url: row.url,
        },
        createdAt: row.created_at,
        notificationSent: row.notification_sent,
        notificationChannels: row.notification_channels || [],
      };
    } catch (error) {
      this.logger.error('Failed to create mention in database', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  async sendNotifications(request: SendNotificationRequest): Promise<void> {
    const client = await this.pool.connect();
    try {
      const channels: NotificationChannel[] = [];

      if (request.channels.includes('matrix') && request.matrixRoomId) {
        await this.sendMatrixNotification(request.mention, request.matrixRoomId);
        channels.push('matrix');
      }

      if (request.channels.includes('email') && request.emailAddress) {
        await this.queueEmailDigest(request.mention, request.emailAddress);
        channels.push('email');
      }

      if (request.channels.includes('in_app')) {
        await this.createInAppNotification(request.mention);
        channels.push('in_app');
      }

      // Update notification status
      await client.query(
        `UPDATE mentions SET notification_sent = TRUE, notification_channels = $1 WHERE id = $2`,
        [channels, request.mention.id]
      );

      // SOC2: Audit notification send
      this.auditService?.emit({
        userId: request.mention.mentionedBy,
        action: 'allow',
        resource: 'mention:' + request.mention.id,
        reason: 'Sent notifications for mention',
        metadata: {
          mentionedUser: request.mention.mentionedUser,
          channels: channels,
          contextId: request.mention.context.contextId,
          filePath: request.mention.context.filePath
        }
      });

      this.logger.info('Notifications sent for mention', { mentionId: request.mention.id, channels });
    } catch (error) {
      this.logger.error('Failed to send notifications', { error, mentionId: request.mention.id });
      throw error;
    } finally {
      client.release();
    }
  }

  private async sendMatrixNotification(mention: Mention, roomId: string): Promise<void> {
    try {
      const messageBody = this.formatMatrixNotification(mention);
      const encryptedMessage = new CollaborationMessageEncryptionService().encryptMessage(messageBody, {
        channel: 'matrix',
        roomId,
        mentionId: mention.id,
        mentionedBy: mention.mentionedBy,
        mentionedUser: mention.mentionedUser,
        contextId: mention.context.contextId,
      });

      // In production, use Matrix client SDK with encrypted payloads only.
      this.logger.info('Prepared encrypted Matrix notification', {
        roomId,
        user: mention.mentionedUser,
        keyId: encryptedMessage.keyId,
        payloadBytes: Buffer.byteLength(encryptedMessage.body, 'utf8'),
      });

      // Send the encrypted message through Matrix transport if available
      if (this.matrixTransport) {
        const payload = await this.matrixTransport.sendEncryptedMessage(
          roomId,
          messageBody,
          {
            mentionId: mention.id,
            mentionedBy: mention.mentionedBy,
            mentionedUser: mention.mentionedUser,
            contextType: mention.context.contextType,
            contextId: mention.context.contextId,
            filePath: mention.context.filePath,
            lineNumber: mention.context.lineNumber,
          }
        );

        this.logger.info('Sent encrypted Matrix notification', {
          roomId,
          user: mention.mentionedUser,
          keyId: payload.content.keyId,
        });
      } else {
        this.logger.warn('Matrix transport service not configured, skipping Matrix notification', {
          roomId,
          mention: mention.id,
        });
      }
    } catch (error) {
      this.logger.error('Failed to send Matrix notification', { error, roomId, mention: mention.id });
      throw error;
    }
  }

  private formatMatrixNotification(mention: Mention): string {
    const timestamp = mention.createdAt.toLocaleString();
    const codeLink = mention.context.url
      ? `[${mention.context.filePath}:${mention.context.lineNumber || 'start'}](${mention.context.url})`
      : `${mention.context.filePath}:${mention.context.lineNumber || 'start'}`;

    return `@${mention.mentionedUser}: You were mentioned by ${mention.mentionedBy} in ${codeLink} (${timestamp})\n\n${mention.content}`;
  }

  private async queueEmailDigest(mention: Mention, emailAddress: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO email_digest_queue (user_id, mention_id) VALUES ($1, $2)`,
        [mention.mentionedUser, mention.id]
      );

      this.logger.info('Queued mention for email digest', { user: mention.mentionedUser, mention: mention.id });
    } catch (error) {
      this.logger.error('Failed to queue email digest', { error, user: mention.mentionedUser });
      throw error;
    } finally {
      client.release();
    }
  }

  private async createInAppNotification(mention: Mention): Promise<void> {
    try {
      const notificationAggregator = NotificationAggregator.getInstance();
      
      const notificationContent = `You were mentioned by ${mention.mentionedBy} in ${mention.context.filePath}:${mention.context.lineNumber || 'start'}`;
      
      // Create notification through the aggregator service
      await notificationAggregator.createNotification({
        userId: mention.mentionedUser,
        title: `New mention from ${mention.mentionedBy}`,
        message: notificationContent,
        category: 'mention' as any,
        channel: 'in-app',
        priority: 'high',
        actionUrl: mention.context.url,
        metadata: {
          contextType: mention.context.contextType,
          contextId: mention.context.contextId,
          mentionId: mention.id,
        },
      });

      this.logger.info('Created in-app notification for mention', {
        user: mention.mentionedUser,
        mention: mention.id,
      });
    } catch (error) {
      this.logger.error('Failed to create in-app notification', {
        error,
        user: mention.mentionedUser,
        mention: mention.id,
      });
      // Don't throw - notification delivery is best-effort
    }
  }

  async getMentionNotificationPreferences(userId: string): Promise<any> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM mention_notification_preferences WHERE user_id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return result.rows[0];
    } catch (error) {
      this.logger.error('Failed to get mention notification preferences', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async setMentionNotificationPreferences(userId: string, preferences: {
    emailAddress?: string;
    digestFrequency?: 'immediate' | 'daily' | 'weekly';
    matrixUserId?: string;
    notifyMatrix?: boolean;
    notifyEmail?: boolean;
    notifyInApp?: boolean;
  }): Promise<void> {
    const client = await this.pool.connect();
    try {
      const existing = await this.getMentionNotificationPreferences(userId);

      if (existing) {
        await client.query(
          `UPDATE mention_notification_preferences SET
            email_address = COALESCE($2, email_address),
            digest_frequency = COALESCE($3, digest_frequency),
            matrix_user_id = COALESCE($4, matrix_user_id),
            notify_matrix = COALESCE($5, notify_matrix),
            notify_email = COALESCE($6, notify_email),
            notify_in_app = COALESCE($7, notify_in_app),
            updated_at = NOW()
           WHERE user_id = $1`,
          [
            userId,
            preferences.emailAddress || null,
            preferences.digestFrequency || null,
            preferences.matrixUserId || null,
            preferences.notifyMatrix ?? null,
            preferences.notifyEmail ?? null,
            preferences.notifyInApp ?? null,
          ]
        );
      } else {
        await client.query(
          `INSERT INTO mention_notification_preferences (
            user_id, email_address, digest_frequency, matrix_user_id,
            notify_matrix, notify_email, notify_in_app
          ) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [
            userId,
            preferences.emailAddress || null,
            preferences.digestFrequency || 'daily',
            preferences.matrixUserId || null,
            preferences.notifyMatrix ?? true,
            preferences.notifyEmail ?? true,
            preferences.notifyInApp ?? true,
          ]
        );
      }

      // SOC2: Audit preference changes
      this.auditService?.emit({
        userId: userId,
        action: 'allow',
        resource: 'mention-preferences:' + userId,
        reason: 'Updated mention notification preferences',
        metadata: {
          emailAddress: preferences.emailAddress ? '***@***' : undefined,
          digestFrequency: preferences.digestFrequency,
          notifyMatrix: preferences.notifyMatrix,
          notifyEmail: preferences.notifyEmail,
          notifyInApp: preferences.notifyInApp
        }
      });

      this.logger.info('Updated mention notification preferences', { userId });
    } catch (error) {
      this.logger.error('Failed to set mention notification preferences', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getMentionsForUser(userId: string, limit = 50, offset = 0): Promise<Mention[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT * FROM mentions WHERE mentioned_user = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
        [userId, limit, offset]
      );

      // SOC2: Audit read access
      this.auditService?.emit({
        userId: userId,
        action: 'allow',
        resource: 'mentions-list',
        reason: 'Retrieved mentions for user',
        metadata: {
          mentionCount: result.rows.length,
          limit: limit,
          offset: offset
        }
      });

      return result.rows.map(row => ({
        id: row.id,
        mentionedBy: row.mentioned_by,
        mentionedUser: row.mentioned_user,
        content: row.content,
        context: {
          contextType: row.context_type,
          contextId: row.context_id,
          filePath: row.file_path,
          lineNumber: row.line_number,
          codeSnippet: row.code_snippet,
          url: row.url,
        },
        createdAt: row.created_at,
        notificationSent: row.notification_sent,
        notificationChannels: row.notification_channels || [],
      }));
    } catch (error) {
      this.logger.error('Failed to get mentions for user', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async generateEmailDigest(userId: string, frequency: 'daily' | 'weekly' = 'daily'): Promise<EmailDigest> {
    const client = await this.pool.connect();
    try {
      const hoursBack = frequency === 'daily' ? 24 : 7 * 24;
      const since = new Date(Date.now() - hoursBack * 60 * 60 * 1000);

      const result = await client.query(
        `SELECT m.* FROM mentions m
         JOIN email_digest_queue edq ON edq.mention_id = m.id
         WHERE m.mentioned_user = $1 AND m.created_at >= $2 AND edq.sent_at IS NULL
         ORDER BY m.created_at DESC`,
        [userId, since]
      );

      const mentions = result.rows.map(row => ({
        mention: {
          id: row.id,
          mentionedBy: row.mentioned_by,
          mentionedUser: row.mentioned_user,
          content: row.content,
          context: {
            contextType: row.context_type,
            contextId: row.context_id,
            filePath: row.file_path,
            lineNumber: row.line_number,
            codeSnippet: row.code_snippet,
            url: row.url,
          },
          createdAt: row.created_at,
          notificationSent: row.notification_sent,
          notificationChannels: row.notification_channels || [],
        } as Mention,
        summaryText: this.formatEmailDigestEntry(row),
      }));

      // SOC2: Audit email digest generation
      this.auditService?.emit({
        userId: userId,
        action: 'allow',
        resource: 'email-digest',
        reason: 'Generated email digest for user',
        metadata: {
          frequency: frequency,
          mentionCount: mentions.length,
          periodHours: hoursBack
        }
      });

      return {
        userId,
        frequency,
        mentions,
        createdAt: new Date(),
      };
    } catch (error) {
      this.logger.error('Failed to generate email digest', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  private formatEmailDigestEntry(row: any): string {
    return `${row.mentioned_by} mentioned you in ${row.file_path}:${row.line_number || 'start'}\n"${row.content}"\nView: ${row.url}`;
  }

  async markDigestAsSent(userId: string, mentionIds: string[]): Promise<void> {
    // SOC2: Audit digest delivery
    this.auditService?.emit({
      userId: userId,
      action: 'allow',
      resource: 'email-digest',
      reason: 'Marked email digest as sent',
      metadata: { mentionCount: mentionIds.length }
    });

    const client = await this.pool.connect();
    try {
      await client.query(
        `UPDATE email_digest_queue SET sent_at = NOW() WHERE user_id = $1 AND mention_id = ANY($2)`,
        [userId, mentionIds]
      );

      this.logger.info('Marked digest as sent', { userId, mentionCount: mentionIds.length });
    } catch (error) {
      this.logger.error('Failed to mark digest as sent', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }
}
