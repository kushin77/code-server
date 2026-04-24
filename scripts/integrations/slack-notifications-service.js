#!/usr/bin/env node
/**
 * @file        scripts/integrations/slack-notifications-service.js
 * @module      integrations/slack
 * @description Slack notifications with immutable messages and idempotent delivery
 *
 * IaC Principles:
 * - Immutable: Notification messages frozen once created
 * - Immutable: Delivery records frozen per attempt
 * - Idempotent: Same messageToken = same deliveryId
 * - Versioned: Message state versions for audit trail
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class SlackNotificationsService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.webhookUrl = options.webhookUrl || process.env.SLACK_WEBHOOK_URL || '';
        this.botToken = options.botToken || process.env.SLACK_BOT_TOKEN || '';
        
        // Immutable notification messages (frozen)
        this.messages = new Map(); // messageId → frozen message
        
        // Immutable delivery records (frozen)
        this.deliveries = new Map(); // deliveryId → frozen delivery
        
        // Token to deliveryId mapping (idempotency)
        this.deliveryTokens = new Map(); // token → deliveryId
        
        // Channel subscriptions (frozen)
        this.subscriptions = new Map(); // subscriptionId → frozen subscription
        
        // Delivery history
        this.deliveryHistory = [];
    }
    
    /**
     * Create notification message (immutable)
     */
    createNotification(messageData) {
        const messageId = `msg-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        const message = {
            // Identifiers (immutable)
            messageId,
            eventType: messageData.eventType,  // alert, incident, deployment, etc.
            
            // Content (immutable)
            title: messageData.title,
            description: messageData.description,
            severity: messageData.severity || 'info',  // critical, high, medium, low, info
            
            // Recipient (immutable)
            channel: messageData.channel,
            targetUserId: messageData.targetUserId,
            targetTeamId: messageData.targetTeamId,
            
            // Context (immutable)
            sourceService: messageData.sourceService,
            sourceId: messageData.sourceId,
            workspaceId: messageData.workspaceId,
            
            // Metadata (immutable)
            tags: Object.freeze(messageData.tags || []),
            attributes: Object.freeze(messageData.attributes || {}),
            actionButtons: Object.freeze((messageData.actionButtons || []).map(btn =>
                Object.freeze({
                    text: btn.text,
                    actionId: btn.actionId,
                    url: btn.url,
                })
            )),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: now,
            
            // Status (mutable)
            status: 'pending',  // pending, delivered, failed, acknowledged
            deliveryAttempts: 0,
            lastDeliveryAttemptAt: null,
            
            // Delivery tracking (immutable)
            deliveryIds: Object.freeze([]),
            
            version: 1,
        };
        
        Object.freeze(message);
        this.messages.set(messageId, message);
        
        this.emit('notification-created', {
            messageId,
            title: message.title,
            severity: message.severity,
            channel: message.channel,
        });
        
        return messageId;
    }
    
    /**
     * Deliver message (idempotent)
     */
    deliverMessage(messageId, deliveryToken) {
        // Idempotency check
        if (deliveryToken && this.deliveryTokens.has(deliveryToken)) {
            return this.deliveryTokens.get(deliveryToken);
        }
        
        const message = this.messages.get(messageId);
        if (!message) throw new Error(`Message ${messageId} not found`);
        
        const deliveryId = `dlv-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Create immutable delivery record
        const delivery = {
            // Identifiers (immutable)
            deliveryId,
            messageId,
            
            // Delivery info (immutable)
            channel: message.channel,
            targetUserId: message.targetUserId,
            targetTeamId: message.targetTeamId,
            
            // Message content (immutable - snapshot)
            messageSnapshot: Object.freeze({
                title: message.title,
                description: message.description,
                severity: message.severity,
            }),
            
            // Delivery attempt (immutable)
            attemptNumber: message.deliveryAttempts + 1,
            attemptedAt: new Date().toISOString(),
            attemptedAtMs: now,
            
            // Status (mutable)
            status: 'sent',  // sent, delivered, failed, acknowledged
            slackMessageId: null,
            slackTs: null,
            
            // Response (immutable when set)
            response: null,
            error: null,
            
            version: 1,
        };
        
        Object.freeze(delivery);
        this.deliveries.set(deliveryId, delivery);
        
        // Update message (create new version)
        const updatedMessage = {
            ...message,
            status: 'delivered',
            deliveryAttempts: message.deliveryAttempts + 1,
            lastDeliveryAttemptAt: delivery.attemptedAt,
            deliveryIds: Object.freeze([...message.deliveryIds, deliveryId]),
            version: message.version + 1,
        };
        
        Object.freeze(updatedMessage);
        this.messages.set(messageId, updatedMessage);
        
        if (deliveryToken) {
            this.deliveryTokens.set(deliveryToken, deliveryId);
        }
        
        this.recordDeliveryHistory(deliveryId, 'delivered');
        
        this.emit('message-delivered', {
            deliveryId,
            messageId,
            channel: message.channel,
            status: 'sent',
        });
        
        return deliveryId;
    }
    
    /**
     * Record delivery success (creates new delivery version)
     */
    recordDeliverySuccess(deliveryId, successData) {
        const delivery = this.deliveries.get(deliveryId);
        if (!delivery) throw new Error(`Delivery ${deliveryId} not found`);
        
        const updated = {
            ...delivery,
            status: 'delivered',
            slackMessageId: successData.slackMessageId,
            slackTs: successData.slackTs,
            response: Object.freeze(successData.response || {}),
            version: delivery.version + 1,
        };
        
        Object.freeze(updated);
        this.deliveries.set(deliveryId, updated);
        
        this.emit('delivery-success', {
            deliveryId,
            messageId: delivery.messageId,
            slackMessageId: successData.slackMessageId,
        });
    }
    
    /**
     * Record delivery failure (creates new delivery version)
     */
    recordDeliveryFailure(deliveryId, failureData) {
        const delivery = this.deliveries.get(deliveryId);
        if (!delivery) throw new Error(`Delivery ${deliveryId} not found`);
        
        const updated = {
            ...delivery,
            status: 'failed',
            error: Object.freeze({
                code: failureData.code,
                message: failureData.message,
                details: failureData.details,
            }),
            version: delivery.version + 1,
        };
        
        Object.freeze(updated);
        this.deliveries.set(deliveryId, updated);
        
        this.emit('delivery-failure', {
            deliveryId,
            messageId: delivery.messageId,
            errorCode: failureData.code,
        });
    }
    
    /**
     * Subscribe channel (immutable)
     */
    subscribeChannel(subscriptionData) {
        const subscriptionId = `sub-${crypto.randomBytes(8).toString('hex')}`;
        
        const subscription = {
            // Identifiers (immutable)
            subscriptionId,
            channel: subscriptionData.channel,
            workspaceId: subscriptionData.workspaceId,
            
            // Subscription settings (immutable)
            eventTypes: Object.freeze(subscriptionData.eventTypes || []),
            severityFilter: subscriptionData.severityFilter || 'info',
            enabled: true,
            
            // Timing (immutable)
            subscribedAt: new Date().toISOString(),
            subscribedAtMs: Date.now(),
            
            version: 1,
        };
        
        Object.freeze(subscription);
        this.subscriptions.set(subscriptionId, subscription);
        
        this.emit('channel-subscribed', {
            subscriptionId,
            channel: subscription.channel,
            eventTypes: subscription.eventTypes,
        });
        
        return subscriptionId;
    }
    
    /**
     * Get message (immutable snapshot)
     */
    getMessage(messageId) {
        const message = this.messages.get(messageId);
        return message ? Object.freeze({ ...message }) : null;
    }
    
    /**
     * Get delivery (immutable snapshot)
     */
    getDelivery(deliveryId) {
        const delivery = this.deliveries.get(deliveryId);
        return delivery ? Object.freeze({ ...delivery }) : null;
    }
    
    /**
     * Query messages (immutable array)
     */
    queryMessages(filters = {}) {
        let messages = Array.from(this.messages.values());
        
        if (filters.status) {
            messages = messages.filter(m => m.status === filters.status);
        }
        
        if (filters.severity) {
            messages = messages.filter(m => m.severity === filters.severity);
        }
        
        if (filters.channel) {
            messages = messages.filter(m => m.channel === filters.channel);
        }
        
        if (filters.eventType) {
            messages = messages.filter(m => m.eventType === filters.eventType);
        }
        
        messages.sort((a, b) => b.createdAtMs - a.createdAtMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            messages.slice(0, limit).map(m => Object.freeze(m))
        );
    }
    
    /**
     * Get notification statistics (immutable)
     */
    getNotificationStatistics() {
        const allMessages = Array.from(this.messages.values());
        const allDeliveries = Array.from(this.deliveries.values());
        
        const stats = {
            totalMessages: allMessages.length,
            
            byStatus: Object.freeze({
                pending: allMessages.filter(m => m.status === 'pending').length,
                delivered: allMessages.filter(m => m.status === 'delivered').length,
                failed: allMessages.filter(m => m.status === 'failed').length,
                acknowledged: allMessages.filter(m => m.status === 'acknowledged').length,
            }),
            
            bySeverity: Object.freeze({
                critical: allMessages.filter(m => m.severity === 'critical').length,
                high: allMessages.filter(m => m.severity === 'high').length,
                medium: allMessages.filter(m => m.severity === 'medium').length,
                low: allMessages.filter(m => m.severity === 'low').length,
                info: allMessages.filter(m => m.severity === 'info').length,
            }),
            
            totalDeliveries: allDeliveries.length,
            successfulDeliveries: allDeliveries.filter(d => d.status === 'delivered').length,
            failedDeliveries: allDeliveries.filter(d => d.status === 'failed').length,
            successRate: allDeliveries.length > 0
                ? ((allDeliveries.filter(d => d.status === 'delivered').length / allDeliveries.length) * 100).toFixed(2)
                : 0,
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Record delivery history
     */
    recordDeliveryHistory(deliveryId, action) {
        const delivery = this.deliveries.get(deliveryId);
        
        const record = Object.freeze({
            timestamp: new Date().toISOString(),
            timestampMs: Date.now(),
            action,
            deliveryId,
            messageId: delivery.messageId,
            status: delivery.status,
        });
        
        this.deliveryHistory.push(record);
    }
}

module.exports = SlackNotificationsService;
