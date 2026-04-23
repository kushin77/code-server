/**
 * Notification Aggregator Service
 * @file        apps/backend/src/services/notification-aggregator/notification-aggregator-service.ts
 * @module      services/notification-aggregator
 * @description Real-time notification aggregation and delivery service
 */
import { EventEmitter } from 'events';
/**
 * Notification Aggregator Service
 * Manages notification creation, aggregation, delivery, and lifecycle
 */
export class NotificationAggregator extends EventEmitter {
    constructor() {
        super();
        this.notifications = new Map();
        this.userNotifications = new Map(); // userId -> notificationIds
        this.aggregationRules = new Map();
        this.deliveryPolicies = new Map();
        this.templates = new Map();
        this.batches = new Map();
        this.deliveryHistory = new Map(); // notificationId -> results
        this.auditLog = new Map(); // userId -> entries
        this.stats = {
            totalNotifications: 0,
            pendingCount: 0,
            sentCount: 0,
            deliveredCount: 0,
            readCount: 0,
            failedCount: 0,
            aggregatedCount: 0,
            averageDeliveryTimeMs: 0,
            byCategory: {},
            byChannel: {},
            byPriority: {},
        };
        this.config = {
            enableAggregation: true,
            defaultChannel: 'in-app',
            defaultPriority: 'medium',
            retryPolicy: {
                maxRetries: 3,
                backoffMs: 1000,
                maxBackoffMs: 30000,
            },
            aggregationDefaults: {
                timeWindowMs: 60000, // 1 minute
                countThreshold: 5,
            },
            maxNotificationsPerUser: 1000,
            maxAuditEntries: 5000,
            cleanupIntervalMs: 86400000, // 1 day
            enableAnalytics: true,
        };
        this.initialize();
    }
    /**
     * Get or create singleton instance
     */
    static getInstance(config) {
        if (!NotificationAggregator.instance) {
            NotificationAggregator.instance = new NotificationAggregator();
        }
        if (config) {
            NotificationAggregator.instance.updateConfig(config);
        }
        return NotificationAggregator.instance;
    }
    /**
     * Reset singleton for testing
     */
    static reset() {
        NotificationAggregator.instance = undefined;
    }
    /**
     * Initialize service
     */
    initialize() {
        this.emit('initialized', {
            data_object: { service: 'notification-aggregator', status: 'initialized' },
            timestamp: Date.now(),
        });
    }
    /**
     * Create notification
     */
    createNotification(notification, userId, ipAddress, userAgent) {
        try {
            const notificationId = `notif-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const fullNotification = {
                ...notification,
                notificationId,
                retryCount: 0,
            };
            this.notifications.set(notificationId, fullNotification);
            if (!this.userNotifications.has(userId)) {
                this.userNotifications.set(userId, new Set());
            }
            this.userNotifications.get(userId).add(notificationId);
            this.stats.totalNotifications++;
            if (notification.status === 'pending') {
                this.stats.pendingCount++;
            }
            this.logAudit(userId, 'create-notification', notificationId, {
                category: notification.category,
                priority: notification.priority,
                channel: notification.channel,
            });
            this.emit('notification-created', {
                data_object: { notificationId, userId, priority: notification.priority },
                timestamp: Date.now(),
            });
            return { success: true, notificationId };
        }
        catch (error) {
            this.logAudit(userId, 'create-notification', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Send notification
     */
    sendNotification(notificationId, userId, ipAddress, userAgent) {
        try {
            const notification = this.notifications.get(notificationId);
            if (!notification) {
                return { success: false };
            }
            const startTime = Date.now();
            notification.status = 'sent';
            const deliveryResult = {
                notificationId,
                channel: notification.channel,
                status: 'sent',
                timestamp: startTime,
                deliveryTime: 0,
            };
            if (!this.deliveryHistory.has(notificationId)) {
                this.deliveryHistory.set(notificationId, []);
            }
            this.deliveryHistory.get(notificationId).push(deliveryResult);
            this.stats.sentCount++;
            if (this.stats.pendingCount > 0) {
                this.stats.pendingCount--;
            }
            this.logAudit(userId, 'send-notification', notificationId, {
                channel: notification.channel,
                deliveryTime: 0,
            });
            this.emit('notification-sent', {
                data_object: { notificationId, userId, channel: notification.channel },
                timestamp: startTime,
            });
            return { success: true, deliveryTime: 0 };
        }
        catch (error) {
            this.logAudit(userId, 'send-notification', notificationId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Mark notification as read
     */
    markAsRead(notificationId, userId, ipAddress, userAgent) {
        try {
            const notification = this.notifications.get(notificationId);
            if (!notification) {
                return { success: false };
            }
            notification.status = 'read';
            notification.readAt = Date.now();
            this.stats.readCount++;
            this.logAudit(userId, 'mark-as-read', notificationId, {});
            this.emit('notification-read', {
                data_object: { notificationId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'mark-as-read', notificationId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Archive notification
     */
    archiveNotification(notificationId, userId, ipAddress, userAgent) {
        try {
            const notification = this.notifications.get(notificationId);
            if (!notification) {
                return { success: false };
            }
            notification.status = 'archived';
            notification.archivedAt = Date.now();
            this.logAudit(userId, 'archive-notification', notificationId, {});
            this.emit('notification-archived', {
                data_object: { notificationId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'archive-notification', notificationId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get notifications
     */
    getNotifications(userId, limit) {
        const notificationIds = this.userNotifications.get(userId) || new Set();
        const notifications = [];
        for (const id of notificationIds) {
            const notif = this.notifications.get(id);
            if (notif) {
                notifications.push(notif);
            }
        }
        notifications.sort((a, b) => b.createdAt - a.createdAt);
        return notifications.slice(0, limit || 100);
    }
    /**
     * Get pending notifications
     */
    getPendingNotifications(userId) {
        const notifications = this.getNotifications(userId);
        return notifications.filter((n) => n.status === 'pending');
    }
    /**
     * Create aggregation rule
     */
    createAggregationRule(rule, userId, ipAddress, userAgent) {
        try {
            const ruleId = `rule-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const fullRule = {
                ...rule,
                ruleId,
                createdAt: Date.now(),
            };
            this.aggregationRules.set(ruleId, fullRule);
            this.logAudit(userId, 'create-aggregation-rule', '', {
                ruleId,
                category: rule.category,
                strategy: rule.strategy,
            });
            this.emit('aggregation-rule-created', {
                data_object: { ruleId, userId, strategy: rule.strategy },
                timestamp: Date.now(),
            });
            return { success: true, ruleId };
        }
        catch (error) {
            this.logAudit(userId, 'create-aggregation-rule', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Update aggregation rule
     */
    updateAggregationRule(ruleId, updates, userId, ipAddress, userAgent) {
        try {
            const rule = this.aggregationRules.get(ruleId);
            if (!rule) {
                return { success: false };
            }
            Object.assign(rule, updates);
            this.logAudit(userId, 'update-aggregation-rule', '', {
                ruleId,
            });
            this.emit('aggregation-rule-updated', {
                data_object: { ruleId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'update-aggregation-rule', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Delete aggregation rule
     */
    deleteAggregationRule(ruleId, userId, ipAddress, userAgent) {
        try {
            this.aggregationRules.delete(ruleId);
            this.logAudit(userId, 'delete-aggregation-rule', '', {
                ruleId,
            });
            this.emit('aggregation-rule-deleted', {
                data_object: { ruleId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'delete-aggregation-rule', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get aggregation rules
     */
    getAggregationRules(userId) {
        return Array.from(this.aggregationRules.values()).filter((r) => r.userId === userId);
    }
    /**
     * Aggregate notifications
     */
    aggregateNotifications(notificationIds, userId, ipAddress, userAgent) {
        try {
            const batchId = `batch-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const batch = {
                batchId,
                userId,
                notifications: [],
                createdAt: Date.now(),
                sendAt: Date.now() + this.config.aggregationDefaults.timeWindowMs,
                status: 'pending',
                channel: this.config.defaultChannel,
            };
            for (const id of notificationIds) {
                const notif = this.notifications.get(id);
                if (notif) {
                    notif.aggregated = true;
                    notif.aggregatedWith = notif.aggregatedWith || [];
                    notif.aggregatedWith.push(batchId);
                    batch.notifications.push(notif);
                }
            }
            this.batches.set(batchId, batch);
            this.stats.aggregatedCount += batch.notifications.length;
            this.logAudit(userId, 'aggregate-notifications', '', {
                batchId,
                notificationCount: batch.notifications.length,
            });
            this.emit('notifications-aggregated', {
                data_object: { batchId, userId, notificationCount: batch.notifications.length },
                timestamp: Date.now(),
            });
            return { success: true, batchId };
        }
        catch (error) {
            this.logAudit(userId, 'aggregate-notifications', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Create delivery policy
     */
    createDeliveryPolicy(policy, userId, ipAddress, userAgent) {
        try {
            const policyId = `policy-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const fullPolicy = {
                ...policy,
                policyId,
                createdAt: Date.now(),
            };
            this.deliveryPolicies.set(policyId, fullPolicy);
            this.logAudit(userId, 'create-delivery-policy', '', {
                policyId,
                channel: policy.channel,
            });
            this.emit('delivery-policy-created', {
                data_object: { policyId, userId, channel: policy.channel },
                timestamp: Date.now(),
            });
            return { success: true, policyId };
        }
        catch (error) {
            this.logAudit(userId, 'create-delivery-policy', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Update delivery policy
     */
    updateDeliveryPolicy(policyId, updates, userId, ipAddress, userAgent) {
        try {
            const policy = this.deliveryPolicies.get(policyId);
            if (!policy) {
                return { success: false };
            }
            Object.assign(policy, updates);
            this.logAudit(userId, 'update-delivery-policy', '', {
                policyId,
            });
            this.emit('delivery-policy-updated', {
                data_object: { policyId, userId },
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            this.logAudit(userId, 'update-delivery-policy', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get delivery policies
     */
    getDeliveryPolicies(userId) {
        return Array.from(this.deliveryPolicies.values()).filter((p) => p.userId === userId);
    }
    /**
     * Create template
     */
    createTemplate(template, userId, ipAddress, userAgent) {
        try {
            const templateId = `template-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const fullTemplate = {
                ...template,
                templateId,
                createdAt: Date.now(),
            };
            this.templates.set(templateId, fullTemplate);
            this.logAudit(userId, 'create-template', '', {
                templateId,
                name: template.name,
            });
            this.emit('template-created', {
                data_object: { templateId, userId, name: template.name },
                timestamp: Date.now(),
            });
            return { success: true, templateId };
        }
        catch (error) {
            this.logAudit(userId, 'create-template', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get template
     */
    getTemplate(templateId) {
        return this.templates.get(templateId);
    }
    /**
     * Get statistics
     */
    getStatistics(userId) {
        if (!userId) {
            return { ...this.stats };
        }
        const notifications = this.getNotifications(userId);
        const pending = notifications.filter((n) => n.status === 'pending').length;
        const sent = notifications.filter((n) => n.status === 'sent').length;
        const delivered = notifications.filter((n) => n.status === 'delivered').length;
        const read = notifications.filter((n) => n.status === 'read').length;
        return {
            totalNotifications: notifications.length,
            pendingCount: pending,
            sentCount: sent,
            deliveredCount: delivered,
            readCount: read,
            failedCount: 0,
            aggregatedCount: notifications.filter((n) => n.aggregated).length,
            averageDeliveryTimeMs: 0,
            byCategory: {},
            byChannel: {},
            byPriority: {},
        };
    }
    /**
     * Get audit log
     */
    getAuditLog(limit) {
        const entries = [];
        for (const [, userEntries] of this.auditLog) {
            entries.push(...userEntries);
        }
        entries.sort((a, b) => b.timestamp - a.timestamp);
        return entries.slice(0, limit || 100);
    }
    /**
     * Batch send notifications
     */
    batchSendNotifications(notificationIds, userId, ipAddress, userAgent) {
        try {
            const batchId = `send-batch-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            let successCount = 0;
            for (const id of notificationIds) {
                const result = this.sendNotification(id, userId, ipAddress, userAgent);
                if (result.success) {
                    successCount++;
                }
            }
            this.logAudit(userId, 'batch-send-notifications', '', {
                batchId,
                successCount,
                totalCount: notificationIds.length,
            });
            this.emit('batch-send-completed', {
                data_object: { batchId, userId, successCount },
                timestamp: Date.now(),
            });
            return { success: true, batchId, successCount };
        }
        catch (error) {
            this.logAudit(userId, 'batch-send-notifications', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Retry failed notifications
     */
    retryFailedNotifications(userId, ipAddress, userAgent) {
        try {
            const notifications = this.getNotifications(userId);
            let retriedCount = 0;
            for (const notif of notifications) {
                if (notif.status === 'failed' && notif.retryCount < this.config.retryPolicy.maxRetries) {
                    notif.retryCount++;
                    this.sendNotification(notif.notificationId, userId, ipAddress, userAgent);
                    retriedCount++;
                }
            }
            this.logAudit(userId, 'retry-failed-notifications', '', {
                retriedCount,
            });
            this.emit('retry-completed', {
                data_object: { userId, retriedCount },
                timestamp: Date.now(),
            });
            return { success: true, retriedCount };
        }
        catch (error) {
            this.logAudit(userId, 'retry-failed-notifications', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Cleanup archived notifications
     */
    cleanupArchivedNotifications(userId, ipAddress, userAgent) {
        try {
            const notifications = this.getNotifications(userId);
            let deletedCount = 0;
            for (const notif of notifications) {
                if (notif.status === 'archived') {
                    this.notifications.delete(notif.notificationId);
                    this.userNotifications.get(userId)?.delete(notif.notificationId);
                    deletedCount++;
                }
            }
            this.logAudit(userId, 'cleanup-archived-notifications', '', {
                deletedCount,
            });
            this.emit('cleanup-completed', {
                data_object: { userId, deletedCount },
                timestamp: Date.now(),
            });
            return { success: true, deletedCount };
        }
        catch (error) {
            this.logAudit(userId, 'cleanup-archived-notifications', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Log audit entry
     */
    logAudit(userId, action, notificationId, details) {
        if (!this.auditLog.has(userId)) {
            this.auditLog.set(userId, []);
        }
        const entry = {
            timestamp: Date.now(),
            userId,
            userEmail: `user-${userId}@example.com`,
            action,
            notificationId: notificationId || undefined,
            details: details || {},
        };
        const logs = this.auditLog.get(userId);
        logs.push(entry);
        if (logs.length > this.config.maxAuditEntries) {
            logs.splice(0, logs.length - this.config.maxAuditEntries);
        }
        this.emit('audit-logged', {
            data_object: entry,
            timestamp: Date.now(),
        });
    }
    /**
     * Update configuration
     */
    updateConfig(config) {
        this.config = { ...this.config, ...config };
        this.emit('config-updated', {
            data_object: { config: this.config },
            timestamp: Date.now(),
        });
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.notifications.clear();
        this.userNotifications.clear();
        this.aggregationRules.clear();
        this.deliveryPolicies.clear();
        this.templates.clear();
        this.batches.clear();
        this.deliveryHistory.clear();
        this.auditLog.clear();
        this.emit('shutdown', {
            data_object: { service: 'notification-aggregator', status: 'shutdown' },
            timestamp: Date.now(),
        });
    }
}
//# sourceMappingURL=notification-aggregator-service.js.map