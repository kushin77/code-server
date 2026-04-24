#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/smart-notification-routing-service.ts
// @module      collaboration/smart-notification-routing
// @description Intelligent multi-channel notification routing based on context and preferences
// @owner       collab-6.2
// @status      active
import { EventEmitter } from 'events';
/**
 * SmartNotificationRoutingService - Intelligent multi-channel notification delivery
 */
export class SmartNotificationRoutingService extends EventEmitter {
    constructor(_pool, _auditService) {
        super();
        this.userPreferences = new Map();
        this.channelStatus = new Map();
        this.routingDecisions = new Map();
        this.deliveryAcks = new Map();
        this.userStatuses = new Map();
        // Signal weights for routing decision
        this.weights = {
            readiness: 0.35,
            priority: 0.30,
            preferences: 0.20,
            timeOfDay: 0.10,
            deviceAvailability: 0.05,
        };
        this.initializeChannelStatus();
    }
    /**
     * Initialize service
     */
    async initialize() {
        // Initialize channel status
        this.initializeChannelStatus();
    }
    /**
     * Initialize channel status
     */
    initializeChannelStatus() {
        const channels = ['in-app', 'email', 'slack', 'sms', 'push'];
        for (const channel of channels) {
            this.channelStatus.set(channel, {
                channel,
                isAvailable: true,
                capacity: 100,
                lastUpdated: new Date(),
            });
        }
    }
    /**
     * Make routing decision for notification
     */
    async makeRoutingDecision(context) {
        // Score channels based on context
        const scores = this.scoreChannels(context);
        // Select primary route
        const selectedRoute = Object.entries(scores)
            .sort(([, scoreA], [, scoreB]) => scoreB - scoreA)[0][0];
        // Get secondary routes (for escalation)
        const secondaryRoutes = Object.entries(scores)
            .sort(([, scoreA], [, scoreB]) => scoreB - scoreA)
            .slice(1, 3)
            .map(([route]) => route);
        // Determine escalation level
        const escalationLevel = this.getEscalationLevel(context.priority);
        // Calculate delivery delay
        const deliveryDelay = this.calculateDeliveryDelay(context, selectedRoute);
        const meetingModePaused = this.shouldPauseForMeeting(context);
        const queuedDelay = meetingModePaused ? Math.max(deliveryDelay, this.getMeetingModeDelay(context.priority)) : deliveryDelay;
        const decision = {
            notificationId: context.notificationId,
            userId: context.userId,
            selectedRoute,
            secondaryRoutes,
            escalationPolicy: escalationLevel,
            deliveryDelay: queuedDelay,
            batchable: !context.conversationContext?.urgency?.includes('critical'),
            reason: `Selected ${selectedRoute} for readiness=${context.readinessLevel}, priority=${context.priority}`,
            confidence: Math.round((scores[selectedRoute] + 50) / 2),
            timestamp: new Date(),
        };
        if (meetingModePaused) {
            decision.selectedRoute = 'in-app';
            decision.secondaryRoutes = decision.secondaryRoutes.filter((route) => route !== 'in-app');
            decision.batchable = true;
            decision.reason = `${decision.reason}; meeting mode active, queued non-urgent delivery`;
        }
        this.routingDecisions.set(context.notificationId, decision);
        return decision;
    }
    /**
     * Score each channel for notification
     */
    scoreChannels(context) {
        const scores = {
            'in-app': 0,
            'email': 0,
            'slack': 0,
            'sms': 0,
            'push': 0,
        };
        // Base score from readiness
        const readinessScores = {
            available: 100,
            busy: 70,
            away: 30,
            offline: 0,
        };
        const baseScore = readinessScores[context.readinessLevel] || 50;
        // Priority weighting
        const priorityScores = {
            P0: 100,
            P1: 80,
            P2: 50,
            P3: 30,
        };
        const priorityScore = priorityScores[context.priority] || 50;
        // For available users, prefer in-app
        if (context.readinessLevel === 'available') {
            scores['in-app'] = baseScore + priorityScore;
            scores['slack'] = baseScore + priorityScore - 10;
            scores['email'] = baseScore + priorityScore - 20;
            scores['push'] = baseScore + priorityScore - 30;
            scores['sms'] = baseScore + priorityScore - 40;
        }
        else if (context.readinessLevel === 'busy') {
            scores['email'] = baseScore + priorityScore;
            scores['slack'] = baseScore + priorityScore - 5;
            scores['in-app'] = baseScore + priorityScore - 15;
            scores['push'] = baseScore + priorityScore - 25;
            scores['sms'] = baseScore + priorityScore - 35;
        }
        else if (context.readinessLevel === 'away') {
            scores['email'] = baseScore + priorityScore;
            scores['push'] = baseScore + priorityScore;
            scores['slack'] = baseScore + priorityScore - 10;
            scores['sms'] = baseScore + priorityScore - 20;
            scores['in-app'] = baseScore + priorityScore - 30;
        }
        else {
            // offline
            scores['sms'] = priorityScore;
            scores['push'] = priorityScore - 10;
            scores['email'] = priorityScore - 20;
            scores['slack'] = 0;
            scores['in-app'] = 0;
        }
        return scores;
    }
    /**
     * Get escalation level based on priority
     */
    getEscalationLevel(priority) {
        const p = parseInt(priority.replace('P', ''), 10);
        return Math.max(1, Math.min(5, 6 - p));
    }
    /**
     * Calculate delivery delay
     */
    calculateDeliveryDelay(context, route) {
        // Immediate delivery for critical
        if (context.conversationContext?.urgency === 'critical' || context.priority === 'P0') {
            return 0;
        }
        // Batch window delay for batching-supported channels
        if (route === 'in-app' || route === 'email' || route === 'push') {
            return 30000; // 30 second batch window
        }
        return 1000; // 1 second default
    }
    shouldPauseForMeeting(context) {
        if (context.priority === 'P0' || context.conversationContext?.urgency === 'critical') {
            return false;
        }
        return Boolean(context.isInMeeting ||
            context.userPreferences.meetingModeExclusion ||
            context.userPreferences.doNotDisturb.enabled);
    }
    getMeetingModeDelay(priority) {
        const parsedPriority = Number.parseInt(priority.replace(/^P/i, ''), 10);
        if (parsedPriority <= 1) {
            return 2 * 60 * 1000;
        }
        if (parsedPriority === 2) {
            return 10 * 60 * 1000;
        }
        return 15 * 60 * 1000;
    }
    /**
     * Store normalized user status for routing and presence consumers.
     */
    async updateUserStatus(userId, status, context = {}) {
        const meetingModeActive = context.calendarStatus === 'in-meeting';
        const currentStatus = meetingModeActive ? 'dnd' : status;
        const nextStatus = {
            userId,
            currentStatus,
            calendarStatus: context.calendarStatus,
            location: context.location,
            currentDevice: context.currentDevice,
            meetingModeActive,
            lastStatusChange: new Date(),
        };
        this.userStatuses.set(userId, nextStatus);
        this.emit('userStatusUpdated', nextStatus);
        return nextStatus;
    }
    /**
     * Read the latest stored user status.
     */
    async getUserStatus(userId) {
        return this.userStatuses.get(userId) ?? null;
    }
    /**
     * Record delivery acknowledgment
     */
    async recordDeliveryAck(ack) {
        this.deliveryAcks.set(ack.notificationId, ack);
        this.emit('deliveryAck', ack);
    }
    /**
     * Get user preferences
     */
    async getUserPreferences(userId) {
        if (this.userPreferences.has(userId)) {
            return this.userPreferences.get(userId);
        }
        return null;
    }
    /**
     * Update channel status
     */
    async updateChannelStatus(channel, available, capacity, reason) {
        const status = {
            channel,
            isAvailable: available,
            capacity,
            lastUpdated: new Date(),
            reason,
        };
        this.channelStatus.set(channel, status);
    }
    /**
     * Shutdown service
     */
    async shutdown() {
        this.removeAllListeners();
        this.userPreferences.clear();
        this.routingDecisions.clear();
        this.deliveryAcks.clear();
    }
}
/**
 * Factory function to create service instance
 */
export function createSmartNotificationRoutingService() {
    return new SmartNotificationRoutingService();
}
export * from './types';
//# sourceMappingURL=smart-notification-routing-service.js.map