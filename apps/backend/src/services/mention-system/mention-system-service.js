/**
 * Mention System Service
 * SOC2-grade audit logging for @mentions in code, comments, commits
 */
import { EventEmitter } from 'events';
/**
 * Mention System Service
 * Track @mentions with SOC2 audit logging
 */
export class MentionSystemService extends EventEmitter {
    constructor(config, auditService) {
        super();
        this.isInitialized = false;
        this.mentions = new Map();
        this.auditLog = new Map(); // Per-user audit trails
        this.settings = new Map();
        this.stats = {
            totalMentions: 0,
            mentionsByType: {},
            mentionsByUser: {},
            mentionedByUser: {},
            mentionsByTarget: {},
            mentionsByContext: {},
            unreadCount: 0,
            averageResponseTime: 0,
            priorityDistribution: {},
        };
        this.auditService = auditService;
        this.config = {
            enabled: true,
            auditLoggingEnabled: true,
            maxMentionsPerMessage: 10,
            maxMentionsPerDay: 100,
            retentionDays: 90,
            enableEmailNotifications: true,
            enablePushNotifications: true,
            enableAcknowledgment: true,
            enablePriority: true,
            maxAuditLogSize: 10000,
            ...config,
        };
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        this.emit('initialized');
    }
    /**
     * Shutdown service
     */
    async shutdown() {
        this.emit('shutdown');
    }
    /**
     * Create mention
     */
    async createMention(createdBy, mentionedUserId, target, context, contextType, workspaceId, sessionId, ipAddress, userAgent, priority = 'normal') {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        // Check settings for privacy
        const mentionedSettings = await this.getSettings(mentionedUserId);
        if (mentionedSettings?.privacyLevel === 'private' && createdBy !== mentionedUserId) {
            // Check if creator is blocked
            if (mentionedSettings.blockedUsers?.includes(createdBy)) {
                const auditEntry = {
                    id: `audit-${Date.now()}-blocked`,
                    mentionId: `mention-${Date.now()}`,
                    userId: createdBy,
                    mentionedUserId,
                    sessionId,
                    workspaceId,
                    operation: 'created',
                    targetType: target.type,
                    targetPath: target.filePath,
                    ipAddress,
                    userAgent,
                    timestamp: Date.now(),
                    status: 'denied',
                    reason: 'User has blocked mentions from this creator',
                };
                await this.logAudit(mentionedUserId, auditEntry);
                throw new Error('User has blocked mentions from you');
            }
        }
        // Create mention notification
        const notification = {
            id: `mention-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
            mentionId: `user-mention-${createdBy}-${mentionedUserId}-${Date.now()}`,
            userId: mentionedUserId,
            createdBy,
            target,
            context,
            contextType,
            workspaceId,
            sessionId,
            createdAt: Date.now(),
            acknowledged: false,
            priority,
        };
        this.mentions.set(notification.id, notification);
        // Log audit entry
        const auditEntry = {
            id: `audit-${notification.id}`,
            mentionId: notification.mentionId,
            userId: createdBy,
            mentionedUserId,
            sessionId,
            workspaceId,
            operation: 'created',
            targetType: target.type,
            targetPath: target.filePath,
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            status: 'success',
        };
        await this.logAudit(mentionedUserId, auditEntry);
        if (this.auditService) {
            this.auditService.emit({
                userId: createdBy,
                action: 'create',
                resourceType: 'mention',
                resource: `mention:${notification.id}`,
                metadata: {
                    mentionedUserId,
                    targetType: target.type,
                    targetPath: target.filePath,
                    contextType,
                    priority,
                    contextLength: context.length,
                },
                reason: 'SOC2: Mention created for user tracking',
            });
        }
        this.updateStats();
        this.emit('mention-created', { notification });
        // Send notifications
        if (this.config.enableEmailNotifications && mentionedSettings?.emailNotifications) {
            this.emit('email-notification', { mentionId: notification.id, userId: mentionedUserId });
        }
        if (this.config.enablePushNotifications && mentionedSettings?.pushNotifications) {
            this.emit('push-notification', { mentionId: notification.id, userId: mentionedUserId });
        }
        return notification;
    }
    /**
     * Get mention
     */
    async getMention(mentionId) {
        return this.mentions.get(mentionId);
    }
    /**
     * Query mentions
     */
    async queryMentions(query) {
        let results = Array.from(this.mentions.values());
        // Filter by user
        if (query.userId) {
            results = results.filter((m) => m.userId === query.userId);
        }
        // Filter by mentioned user
        if (query.mentionedUserId) {
            results = results.filter((m) => m.createdBy === query.mentionedUserId);
        }
        // Filter by target type
        if (query.targetType) {
            results = results.filter((m) => m.target.type === query.targetType);
        }
        // Filter by context type
        if (query.contextType) {
            results = results.filter((m) => m.contextType === query.contextType);
        }
        // Filter by priority
        if (query.priority) {
            results = results.filter((m) => m.priority === query.priority);
        }
        // Filter unread only
        if (query.unreadOnly) {
            results = results.filter((m) => !m.readAt);
        }
        // Filter by time range
        if (query.startTime) {
            results = results.filter((m) => m.createdAt >= query.startTime);
        }
        if (query.endTime) {
            results = results.filter((m) => m.createdAt <= query.endTime);
        }
        // Sort by creation time (newest first)
        results.sort((a, b) => b.createdAt - a.createdAt);
        // Paginate
        const limit = query.limit || 20;
        const offset = query.offset || 0;
        return results.slice(offset, offset + limit);
    }
    /**
     * Mark mention as read
     */
    async readMention(mentionId, userId, ipAddress, userAgent) {
        const mention = this.mentions.get(mentionId);
        if (!mention)
            throw new Error(`Mention not found: ${mentionId}`);
        const timestamp = Date.now();
        mention.readAt = timestamp;
        // Log audit entry
        const auditEntry = {
            id: `audit-${mentionId}-read`,
            mentionId: mention.mentionId,
            userId: mention.createdBy,
            mentionedUserId: mention.userId,
            sessionId: mention.sessionId,
            workspaceId: mention.workspaceId,
            operation: 'read',
            targetType: mention.target.type,
            targetPath: mention.target.filePath,
            ipAddress,
            userAgent,
            timestamp,
            status: 'success',
        };
        await this.logAudit(mention.userId, auditEntry);
        this.updateStats();
        this.emit('mention-read', { mentionId });
        return mention;
    }
    /**
     * Acknowledge mention
     */
    async acknowledgeMention(mentionId, userId, ipAddress, userAgent) {
        if (!this.config.enableAcknowledgment) {
            throw new Error('Acknowledgment is disabled');
        }
        const mention = this.mentions.get(mentionId);
        if (!mention)
            throw new Error(`Mention not found: ${mentionId}`);
        mention.acknowledged = true;
        // Log audit entry
        const auditEntry = {
            id: `audit-${mentionId}-ack`,
            mentionId: mention.mentionId,
            userId: mention.createdBy,
            mentionedUserId: mention.userId,
            sessionId: mention.sessionId,
            workspaceId: mention.workspaceId,
            operation: 'acknowledged',
            targetType: mention.target.type,
            targetPath: mention.target.filePath,
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            status: 'success',
        };
        await this.logAudit(mention.userId, auditEntry);
        if (this.auditService) {
            this.auditService.emit({
                userId,
                action: 'update',
                resourceType: 'mention',
                resource: `mention:${mentionId}`,
                metadata: {
                    mentionedUserId: mention.userId,
                    createdBy: mention.createdBy,
                    targetType: mention.target.type,
                    targetPath: mention.target.filePath,
                },
                reason: 'SOC2: Mention acknowledged by recipient',
            });
        }
        this.updateStats();
        this.emit('mention-acknowledged', { mentionId });
        return mention;
    }
    /**
     * Delete mention
     */
    async deleteMention(mentionId, userId, ipAddress, userAgent) {
        const mention = this.mentions.get(mentionId);
        if (!mention)
            throw new Error(`Mention not found: ${mentionId}`);
        // Log audit entry
        const auditEntry = {
            id: `audit-${mentionId}-delete`,
            mentionId: mention.mentionId,
            userId: mention.createdBy,
            mentionedUserId: mention.userId,
            sessionId: mention.sessionId,
            workspaceId: mention.workspaceId,
            operation: 'deleted',
            targetType: mention.target.type,
            targetPath: mention.target.filePath,
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            status: 'success',
        };
        await this.logAudit(mention.userId, auditEntry);
        if (this.auditService) {
            this.auditService.emit({
                userId,
                action: 'delete',
                resourceType: 'mention',
                resource: `mention:${mentionId}`,
                metadata: {
                    mentionedUserId: mention.userId,
                    createdBy: mention.createdBy,
                    targetType: mention.target.type,
                    targetPath: mention.target.filePath,
                },
                reason: 'SOC2: Mention deleted by user',
            });
        }
        this.mentions.delete(mentionId);
        this.updateStats();
        this.emit('mention-deleted', { mentionId });
    }
    /**
     * Get user mentions (as recipient)
     */
    async getUserMentions(userId, unreadOnly = false) {
        return this.queryMentions({ userId, unreadOnly });
    }
    /**
     * Get mentions created by user
     */
    async getMentionsByUser(createdBy) {
        const results = [];
        for (const mention of this.mentions.values()) {
            if (mention.createdBy === createdBy) {
                results.push(mention);
            }
        }
        return results;
    }
    /**
     * Get audit log for user
     */
    async getAuditLog(userId, limit) {
        const log = this.auditLog.get(userId) || [];
        if (limit) {
            return log.slice(-limit);
        }
        return log;
    }
    /**
     * Get user settings
     */
    async getSettings(userId) {
        return this.settings.get(userId);
    }
    /**
     * Update user settings
     */
    async updateSettings(userId, settings) {
        let userSettings = this.settings.get(userId);
        if (!userSettings) {
            userSettings = {
                userId,
                emailNotifications: this.config.enableEmailNotifications,
                pushNotifications: this.config.enablePushNotifications,
                mentionHighlighting: true,
                auditLogging: this.config.auditLoggingEnabled,
                privacyLevel: 'internal',
                createdAt: Date.now(),
                updatedAt: Date.now(),
            };
        }
        userSettings = {
            ...userSettings,
            ...settings,
            userId,
            updatedAt: Date.now(),
        };
        this.settings.set(userId, userSettings);
        if (this.auditService) {
            this.auditService.emit({
                userId,
                action: 'update',
                resourceType: 'mention-settings',
                resource: `mention-settings:${userId}`,
                metadata: {
                    changedFields: Object.keys(settings),
                    privacyLevel: userSettings.privacyLevel,
                    emailNotifications: userSettings.emailNotifications,
                    pushNotifications: userSettings.pushNotifications,
                },
                reason: 'SOC2: Mention settings updated',
            });
        }
        this.emit('settings-updated', { userId });
        return userSettings;
    }
    /**
     * Get statistics
     */
    async getStatistics() {
        return { ...this.stats };
    }
    /**
     * Get all mentions
     */
    async getAllMentions() {
        return Array.from(this.mentions.values());
    }
    /**
     * Private: Log audit entry
     */
    async logAudit(userId, entry) {
        let log = this.auditLog.get(userId);
        if (!log) {
            log = [];
            this.auditLog.set(userId, log);
        }
        log.push(entry);
        // Keep only maxAuditLogSize entries
        if (log.length > this.config.maxAuditLogSize) {
            log.splice(0, log.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', { userId, entry });
    }
    /**
     * Private: Update statistics
     */
    updateStats() {
        this.stats.totalMentions = this.mentions.size;
        // Count by type
        this.stats.mentionsByType = {};
        this.stats.mentionsByUser = {};
        this.stats.mentionedByUser = {};
        this.stats.mentionsByTarget = {};
        this.stats.mentionsByContext = {};
        this.stats.priorityDistribution = {};
        let unreadCount = 0;
        let totalResponseTime = 0;
        let responseCount = 0;
        for (const mention of this.mentions.values()) {
            // Type
            this.stats.mentionsByType[mention.target.type] =
                (this.stats.mentionsByType[mention.target.type] || 0) + 1;
            // User
            this.stats.mentionsByUser[mention.userId] = (this.stats.mentionsByUser[mention.userId] || 0) + 1;
            this.stats.mentionedByUser[mention.createdBy] =
                (this.stats.mentionedByUser[mention.createdBy] || 0) + 1;
            // Target
            const targetKey = mention.target.filePath || `${mention.target.type}:${mention.target.fileId}`;
            this.stats.mentionsByTarget[targetKey] = (this.stats.mentionsByTarget[targetKey] || 0) + 1;
            // Context
            this.stats.mentionsByContext[mention.contextType] =
                (this.stats.mentionsByContext[mention.contextType] || 0) + 1;
            // Priority
            this.stats.priorityDistribution[mention.priority] =
                (this.stats.priorityDistribution[mention.priority] || 0) + 1;
            // Unread
            if (!mention.readAt)
                unreadCount++;
            // Response time
            if (mention.readAt) {
                totalResponseTime += mention.readAt - mention.createdAt;
                responseCount++;
            }
        }
        this.stats.unreadCount = unreadCount;
        this.stats.averageResponseTime = responseCount > 0 ? totalResponseTime / responseCount : 0;
    }
    static getInstance(config) {
        if (!MentionSystemService.instance) {
            MentionSystemService.instance = new MentionSystemService(config);
        }
        return MentionSystemService.instance;
    }
}
//# sourceMappingURL=mention-system-service.js.map