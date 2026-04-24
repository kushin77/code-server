#!/usr/bin/env node
/**
 * @file        scripts/integrations/slack-notifications-api.js
 * @module      integrations/slack
 * @description REST API for Slack notifications integration
 */

const express = require('express');
const SlackNotificationsService = require('./slack-notifications-service');

const app = express();
const PORT = process.env.PORT || 9108;

// Initialize service
const slackService = new SlackNotificationsService({
    webhookUrl: process.env.SLACK_WEBHOOK_URL,
    botToken: process.env.SLACK_BOT_TOKEN,
});

// Event listeners
slackService.on('notification-created', (context) => {
    console.log(`[Slack] Notification: ${context.title} → ${context.channel}`);
});

slackService.on('message-delivered', (context) => {
    console.log(`[Slack] Delivered: ${context.deliveryId} to ${context.channel}`);
});

slackService.on('delivery-success', (context) => {
    console.log(`[Slack] Success: ${context.slackMessageId}`);
});

slackService.on('delivery-failure', (context) => {
    console.log(`[Slack] Failed: ${context.deliveryId} - ${context.errorCode}`);
});

slackService.on('channel-subscribed', (context) => {
    console.log(`[Slack] Subscribed: ${context.channel} to ${context.eventTypes.join(', ')}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'slack-notifications' });
});

// Create notification
app.post('/notifications', (req, res) => {
    try {
        const messageId = slackService.createNotification(req.body);
        
        const message = slackService.getMessage(messageId);
        
        res.status(201).json({
            status: 'created',
            messageId,
            title: message.title,
            severity: message.severity,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Deliver message (idempotent)
app.post('/notifications/:messageId/deliver', (req, res) => {
    try {
        const deliveryToken = req.headers['x-delivery-token'] || 
            `dlv-${req.params.messageId}-${Date.now()}`;
        
        const deliveryId = slackService.deliverMessage(req.params.messageId, deliveryToken);
        
        const delivery = slackService.getDelivery(deliveryId);
        
        res.json({
            status: 'sent',
            deliveryId,
            messageId: req.params.messageId,
            channel: delivery.channel,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record delivery success
app.post('/deliveries/:deliveryId/success', (req, res) => {
    try {
        slackService.recordDeliverySuccess(req.params.deliveryId, req.body);
        
        const delivery = slackService.getDelivery(req.params.deliveryId);
        
        res.json({
            status: 'success',
            deliveryId: req.params.deliveryId,
            slackMessageId: delivery.slackMessageId,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record delivery failure
app.post('/deliveries/:deliveryId/failure', (req, res) => {
    try {
        slackService.recordDeliveryFailure(req.params.deliveryId, req.body);
        
        res.json({
            status: 'failure_recorded',
            deliveryId: req.params.deliveryId,
            errorCode: req.body.code,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get message
app.get('/notifications/:messageId', (req, res) => {
    try {
        const message = slackService.getMessage(req.params.messageId);
        
        if (!message) {
            return res.status(404).json({ error: 'Message not found' });
        }
        
        res.json({
            messageId: message.messageId,
            title: message.title,
            description: message.description,
            severity: message.severity,
            channel: message.channel,
            status: message.status,
            deliveryAttempts: message.deliveryAttempts,
            createdAt: message.createdAt,
            version: message.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query messages
app.get('/notifications', (req, res) => {
    try {
        const filters = {
            status: req.query.status,
            severity: req.query.severity,
            channel: req.query.channel,
            eventType: req.query.eventType,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const messages = slackService.queryMessages(filters);
        
        res.json({
            total: messages.length,
            messages: messages.map(m => ({
                messageId: m.messageId,
                title: m.title,
                severity: m.severity,
                status: m.status,
                channel: m.channel,
                createdAt: m.createdAt,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get delivery
app.get('/deliveries/:deliveryId', (req, res) => {
    try {
        const delivery = slackService.getDelivery(req.params.deliveryId);
        
        if (!delivery) {
            return res.status(404).json({ error: 'Delivery not found' });
        }
        
        res.json({
            deliveryId: delivery.deliveryId,
            messageId: delivery.messageId,
            status: delivery.status,
            channel: delivery.channel,
            attemptNumber: delivery.attemptNumber,
            attemptedAt: delivery.attemptedAt,
            slackMessageId: delivery.slackMessageId,
            version: delivery.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Subscribe channel
app.post('/subscriptions', (req, res) => {
    try {
        const subscriptionId = slackService.subscribeChannel(req.body);
        
        const subscription = slackService.subscriptions.get(subscriptionId);
        
        res.status(201).json({
            status: 'subscribed',
            subscriptionId,
            channel: subscription.channel,
            eventTypes: subscription.eventTypes,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = slackService.getNotificationStatistics();
        
        res.json({
            totalMessages: stats.totalMessages,
            byStatus: stats.byStatus,
            bySeverity: stats.bySeverity,
            totalDeliveries: stats.totalDeliveries,
            successfulDeliveries: stats.successfulDeliveries,
            failedDeliveries: stats.failedDeliveries,
            successRatePercent: stats.successRate,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Slack Notifications API] Listening on port ${PORT}`);
    console.log(`[Slack Notifications API] POST /notifications - Create notification`);
    console.log(`[Slack Notifications API] POST /notifications/:id/deliver - Deliver (idempotent)`);
    console.log(`[Slack Notifications API] GET /notifications/:id - Get notification`);
    console.log(`[Slack Notifications API] GET /notifications - Query notifications`);
    console.log(`[Slack Notifications API] POST /deliveries/:id/success - Record success`);
    console.log(`[Slack Notifications API] POST /deliveries/:id/failure - Record failure`);
    console.log(`[Slack Notifications API] GET /deliveries/:id - Get delivery`);
    console.log(`[Slack Notifications API] POST /subscriptions - Subscribe channel`);
    console.log(`[Slack Notifications API] GET /statistics - Get statistics`);
});
