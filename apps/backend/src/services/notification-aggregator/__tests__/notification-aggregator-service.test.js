/**
 * Notification Aggregator Service Tests
 * @file        apps/backend/src/services/notification-aggregator/__tests__/notification-aggregator-service.test.ts
 * @module      services/notification-aggregator
 * @description Test suite for notification aggregation functionality
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { NotificationAggregator } from '../notification-aggregator-service.js';
describe('Notification Aggregator Service', () => {
    let service;
    beforeEach(() => {
        NotificationAggregator.reset();
        service = NotificationAggregator.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    // Initialization Tests
    describe('Initialization', () => {
        it('should initialize service', () => {
            expect(service).toBeDefined();
            expect(service.notifications).toBeDefined();
            expect(service.aggregationRules).toBeDefined();
        });
        it('should return same instance on subsequent calls', () => {
            const instance1 = NotificationAggregator.getInstance();
            const instance2 = NotificationAggregator.getInstance();
            expect(instance1).toBe(instance2);
        });
    });
    // Notification Creation Tests
    describe('Notification Creation', () => {
        it('should create notification', () => {
            const result = service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.notificationId).toBeDefined();
        });
        it('should emit notification-created event', () => {
            return new Promise((resolve) => {
                service.once('notification-created', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.createNotification({
                    userId: 'user1',
                    title: 'Test Alert',
                    message: 'This is a test alert',
                    priority: 'high',
                    category: 'alert',
                    status: 'pending',
                    channel: 'in-app',
                    destination: 'user1@example.com',
                    tags: ['test'],
                    aggregated: false,
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should increment statistics on creation', () => {
            service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const stats = service.getStatistics();
            expect(stats.totalNotifications).toBeGreaterThan(0);
        });
    });
    // Notification Sending Tests
    describe('Notification Sending', () => {
        it('should send notification', () => {
            const created = service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.sendNotification(created.notificationId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit notification-sent event', () => {
            return new Promise((resolve) => {
                const created = service.createNotification({
                    userId: 'user1',
                    title: 'Test Alert',
                    message: 'This is a test alert',
                    priority: 'high',
                    category: 'alert',
                    status: 'pending',
                    channel: 'in-app',
                    destination: 'user1@example.com',
                    tags: ['test'],
                    aggregated: false,
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('notification-sent', (event) => {
                    expect(event.data_object.notificationId).toBe(created.notificationId);
                    resolve();
                });
                service.sendNotification(created.notificationId, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Notification Status Tests
    describe('Notification Status', () => {
        it('should mark notification as read', () => {
            const created = service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.markAsRead(created.notificationId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit notification-read event', () => {
            return new Promise((resolve) => {
                const created = service.createNotification({
                    userId: 'user1',
                    title: 'Test Alert',
                    message: 'This is a test alert',
                    priority: 'high',
                    category: 'alert',
                    status: 'pending',
                    channel: 'in-app',
                    destination: 'user1@example.com',
                    tags: ['test'],
                    aggregated: false,
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('notification-read', (event) => {
                    expect(event.data_object.notificationId).toBe(created.notificationId);
                    resolve();
                });
                service.markAsRead(created.notificationId, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should archive notification', () => {
            const created = service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.archiveNotification(created.notificationId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit notification-archived event', () => {
            return new Promise((resolve) => {
                const created = service.createNotification({
                    userId: 'user1',
                    title: 'Test Alert',
                    message: 'This is a test alert',
                    priority: 'high',
                    category: 'alert',
                    status: 'pending',
                    channel: 'in-app',
                    destination: 'user1@example.com',
                    tags: ['test'],
                    aggregated: false,
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('notification-archived', (event) => {
                    expect(event.data_object.notificationId).toBe(created.notificationId);
                    resolve();
                });
                service.archiveNotification(created.notificationId, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Notification Retrieval Tests
    describe('Notification Retrieval', () => {
        it('should get user notifications', () => {
            service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const notifications = service.getNotifications('user1');
            expect(Array.isArray(notifications)).toBe(true);
            expect(notifications.length).toBeGreaterThan(0);
        });
        it('should get pending notifications', () => {
            service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const pending = service.getPendingNotifications('user1');
            expect(Array.isArray(pending)).toBe(true);
        });
    });
    // Aggregation Rule Tests
    describe('Aggregation Rules', () => {
        it('should create aggregation rule', () => {
            const result = service.createAggregationRule({
                userId: 'user1',
                strategy: 'time-based',
                category: 'alert',
                timeWindowMs: 60000,
                enabled: true,
            }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.ruleId).toBeDefined();
        });
        it('should emit aggregation-rule-created event', () => {
            return new Promise((resolve) => {
                service.once('aggregation-rule-created', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.createAggregationRule({
                    userId: 'user1',
                    strategy: 'time-based',
                    category: 'alert',
                    enabled: true,
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should update aggregation rule', () => {
            const created = service.createAggregationRule({
                userId: 'user1',
                strategy: 'time-based',
                category: 'alert',
                enabled: true,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.updateAggregationRule(created.ruleId, { enabled: false }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should delete aggregation rule', () => {
            const created = service.createAggregationRule({
                userId: 'user1',
                strategy: 'time-based',
                category: 'alert',
                enabled: true,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.deleteAggregationRule(created.ruleId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should get aggregation rules', () => {
            const rules = service.getAggregationRules('user1');
            expect(Array.isArray(rules)).toBe(true);
        });
    });
    // Notification Aggregation Tests
    describe('Notification Aggregation', () => {
        it('should aggregate notifications', () => {
            const notif1 = service.createNotification({
                userId: 'user1',
                title: 'Alert 1',
                message: 'Alert 1 message',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.aggregateNotifications([notif1.notificationId], 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.batchId).toBeDefined();
        });
        it('should emit notifications-aggregated event', () => {
            return new Promise((resolve) => {
                const notif1 = service.createNotification({
                    userId: 'user1',
                    title: 'Alert 1',
                    message: 'Alert 1 message',
                    priority: 'high',
                    category: 'alert',
                    status: 'pending',
                    channel: 'in-app',
                    destination: 'user1@example.com',
                    tags: ['test'],
                    aggregated: false,
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('notifications-aggregated', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.aggregateNotifications([notif1.notificationId], 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Delivery Policy Tests
    describe('Delivery Policies', () => {
        it('should create delivery policy', () => {
            const result = service.createDeliveryPolicy({
                userId: 'user1',
                channel: 'email',
                enabled: true,
            }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.policyId).toBeDefined();
        });
        it('should emit delivery-policy-created event', () => {
            return new Promise((resolve) => {
                service.once('delivery-policy-created', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.createDeliveryPolicy({
                    userId: 'user1',
                    channel: 'email',
                    enabled: true,
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should update delivery policy', () => {
            const created = service.createDeliveryPolicy({
                userId: 'user1',
                channel: 'email',
                enabled: true,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.updateDeliveryPolicy(created.policyId, { enabled: false }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should get delivery policies', () => {
            const policies = service.getDeliveryPolicies('user1');
            expect(Array.isArray(policies)).toBe(true);
        });
    });
    // Template Tests
    describe('Templates', () => {
        it('should create template', () => {
            const result = service.createTemplate({
                name: 'Alert Template',
                category: 'alert',
                subject: 'Alert: {{title}}',
                body: 'You have an alert: {{message}}',
            }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.templateId).toBeDefined();
        });
        it('should emit template-created event', () => {
            return new Promise((resolve) => {
                service.once('template-created', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.createTemplate({
                    name: 'Alert Template',
                    category: 'alert',
                    subject: 'Alert: {{title}}',
                    body: 'You have an alert: {{message}}',
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should get template', () => {
            const created = service.createTemplate({
                name: 'Alert Template',
                category: 'alert',
                subject: 'Alert: {{title}}',
                body: 'You have an alert: {{message}}',
            }, 'user1', '192.168.1.1', 'Mozilla');
            const template = service.getTemplate(created.templateId);
            expect(template).toBeDefined();
            expect(template?.name).toBe('Alert Template');
        });
    });
    // Statistics Tests
    describe('Statistics', () => {
        it('should get service statistics', () => {
            const stats = service.getStatistics();
            expect(stats).toBeDefined();
            expect(stats.totalNotifications).toBeGreaterThanOrEqual(0);
        });
        it('should get user statistics', () => {
            service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const stats = service.getStatistics('user1');
            expect(stats).toBeDefined();
            expect(stats.totalNotifications).toBeGreaterThan(0);
        });
    });
    // Audit Logging Tests
    describe('Audit Logging', () => {
        it('should emit audit-logged event', () => {
            return new Promise((resolve) => {
                service.once('audit-logged', (event) => {
                    expect(event.data_object.userId).toBeDefined();
                    resolve();
                });
                service.createNotification({
                    userId: 'user1',
                    title: 'Test Alert',
                    message: 'This is a test alert',
                    priority: 'high',
                    category: 'alert',
                    status: 'pending',
                    channel: 'in-app',
                    destination: 'user1@example.com',
                    tags: ['test'],
                    aggregated: false,
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should retrieve audit log', () => {
            const log = service.getAuditLog();
            expect(Array.isArray(log)).toBe(true);
        });
    });
    // Batch Operations Tests
    describe('Batch Operations', () => {
        it('should batch send notifications', () => {
            const notif1 = service.createNotification({
                userId: 'user1',
                title: 'Alert 1',
                message: 'Alert 1 message',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.batchSendNotifications([notif1.notificationId], 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.batchId).toBeDefined();
        });
        it('should emit batch-send-completed event', () => {
            return new Promise((resolve) => {
                const notif1 = service.createNotification({
                    userId: 'user1',
                    title: 'Alert 1',
                    message: 'Alert 1 message',
                    priority: 'high',
                    category: 'alert',
                    status: 'pending',
                    channel: 'in-app',
                    destination: 'user1@example.com',
                    tags: ['test'],
                    aggregated: false,
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('batch-send-completed', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.batchSendNotifications([notif1.notificationId], 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should retry failed notifications', () => {
            const result = service.retryFailedNotifications('user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit retry-completed event', () => {
            return new Promise((resolve) => {
                service.once('retry-completed', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.retryFailedNotifications('user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Cleanup Tests
    describe('Cleanup', () => {
        it('should cleanup archived notifications', () => {
            const created = service.createNotification({
                userId: 'user1',
                title: 'Test Alert',
                message: 'This is a test alert',
                priority: 'high',
                category: 'alert',
                status: 'pending',
                channel: 'in-app',
                destination: 'user1@example.com',
                tags: ['test'],
                aggregated: false,
            }, 'user1', '192.168.1.1', 'Mozilla');
            service.archiveNotification(created.notificationId, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.cleanupArchivedNotifications('user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect((result.deletedCount || 0) >= 0).toBe(true);
        });
        it('should emit cleanup-completed event', () => {
            return new Promise((resolve) => {
                service.once('cleanup-completed', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.cleanupArchivedNotifications('user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Configuration Tests
    describe('Configuration', () => {
        it('should update configuration', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (event) => {
                    expect(event.data_object.config).toBeDefined();
                    resolve();
                });
                service.updateConfig({ enableAggregation: false });
            });
        });
    });
    // Shutdown Tests
    describe('Shutdown', () => {
        it('should shutdown service cleanly', () => {
            service.shutdown();
            expect(service.notifications.size).toBe(0);
            expect(service.aggregationRules.size).toBe(0);
        });
    });
});
//# sourceMappingURL=notification-aggregator-service.test.js.map