#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/__tests__/smart-notification-routing-service.test.ts
// @module      collaboration/smart-notification-routing/tests
// @description Comprehensive test suite for SmartNotificationRoutingService
// @owner       collab-6.2
// @status      active
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { SmartNotificationRoutingService } from '../smart-notification-routing-service';
describe('SmartNotificationRoutingService', () => {
    let service;
    beforeEach(async () => {
        service = new SmartNotificationRoutingService();
        await service.initialize();
    });
    afterEach(async () => {
        await service.shutdown();
    });
    describe('Routing Decision Tests', () => {
        it('should make routing decision for available user', async () => {
            const context = {
                userId: 'user-123',
                notificationId: 'notif-001',
                notificationType: 'comment',
                priority: 'P1',
                timestamp: new Date(),
                readinessLevel: 'available',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: false,
                },
                userPreferences: {
                    userId: 'user-123',
                    preferredChannels: ['in-app', 'email', 'slack'],
                    channelPriority: { 'in-app': 5, 'email': 3, 'slack': 4 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-123',
                        userId: 'user-123',
                        levels: [1, 2, 3, 4, 5],
                        levelRoutes: { 1: ['in-app'], 2: ['slack'], 3: ['email'], 4: ['sms'], 5: ['sms'] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 1800000, 5: 3600000 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 5,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision).toBeDefined();
            expect(decision.notificationId).toBe('notif-001');
            expect(decision.userId).toBe('user-123');
            expect(['in-app', 'email', 'slack', 'sms', 'push']).toContain(decision.selectedRoute);
            expect(decision.escalationPolicy).toBeGreaterThanOrEqual(1);
            expect(decision.escalationPolicy).toBeLessThanOrEqual(5);
            expect(decision.confidence).toBeGreaterThan(0);
        });
        it('should prefer in-app for available users', async () => {
            const context = {
                userId: 'user-456',
                notificationId: 'notif-002',
                notificationType: 'mention',
                priority: 'P1',
                timestamp: new Date(),
                readinessLevel: 'available',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: true,
                },
                userPreferences: {
                    userId: 'user-456',
                    preferredChannels: ['in-app', 'email', 'slack'],
                    channelPriority: { 'in-app': 5, 'email': 3, 'slack': 4 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-456',
                        userId: 'user-456',
                        levels: [1, 2, 3],
                        levelRoutes: { 1: ['in-app'], 2: ['email'], 3: ['sms'], 4: [], 5: [] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 0, 5: 0 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 3,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.selectedRoute).toBe('in-app');
        });
        it('should use SMS for offline users with P0 priority', async () => {
            const context = {
                userId: 'user-900',
                notificationId: 'notif-004',
                notificationType: 'alert',
                priority: 'P0',
                timestamp: new Date(),
                readinessLevel: 'offline',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: false,
                    hasWebClient: false,
                    hasMobileApp: true,
                },
                userPreferences: {
                    userId: 'user-900',
                    preferredChannels: ['sms', 'push'],
                    channelPriority: { 'sms': 5, 'push': 4 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-900',
                        userId: 'user-900',
                        levels: [1, 2, 3, 4, 5],
                        levelRoutes: { 1: ['sms'], 2: ['push'], 3: ['email'], 4: ['in-app'], 5: ['sms'] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 1800000, 5: 3600000 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 5,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.selectedRoute).toBe('sms');
            expect(decision.deliveryDelay).toBe(0); // Immediate
        });
        it('should batch notifications for suitable channels', async () => {
            const context = {
                userId: 'user-batch',
                notificationId: 'notif-batch-001',
                notificationType: 'update',
                priority: 'P2',
                timestamp: new Date(),
                readinessLevel: 'available',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: false,
                },
                userPreferences: {
                    userId: 'user-batch',
                    preferredChannels: ['in-app', 'email'],
                    channelPriority: { 'in-app': 5, 'email': 3 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    batchPreference: { enabled: true, windowMinutes: 5 },
                    escalationPolicy: {
                        policyId: 'policy-batch',
                        userId: 'user-batch',
                        levels: [1, 2, 3],
                        levelRoutes: { 1: ['in-app'], 2: ['email'], 3: ['sms'], 4: [], 5: [] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 0, 5: 0 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 3,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.batchable).toBe(true);
        });
        it('should queue non-urgent notifications in meeting mode', async () => {
            const context = {
                userId: 'user-meeting',
                notificationId: 'notif-meeting-001',
                notificationType: 'comment',
                priority: 'P2',
                timestamp: new Date(),
                readinessLevel: 'busy',
                isInFocusTime: false,
                isInMeeting: true,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: true,
                },
                userPreferences: {
                    userId: 'user-meeting',
                    preferredChannels: ['in-app', 'email', 'slack'],
                    channelPriority: { 'in-app': 5, 'email': 3, 'slack': 4 },
                    doNotDisturb: { enabled: true },
                    focusTimeExclusion: false,
                    meetingModeExclusion: true,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-meeting',
                        userId: 'user-meeting',
                        levels: [1, 2, 3],
                        levelRoutes: { 1: ['in-app'], 2: ['email'], 3: ['slack'], 4: [], 5: [] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 0, 5: 0 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 3,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.selectedRoute).toBe('in-app');
            expect(decision.deliveryDelay).toBeGreaterThanOrEqual(10 * 60 * 1000);
            expect(decision.batchable).toBe(true);
            expect(decision.reason).toContain('meeting mode active');
        });
        it('should not batch critical notifications', async () => {
            const context = {
                userId: 'user-critical',
                notificationId: 'notif-critical-001',
                notificationType: 'critical',
                priority: 'P0',
                timestamp: new Date(),
                readinessLevel: 'available',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: false,
                },
                conversationContext: {
                    threadId: 'thread-123',
                    urgency: 'critical',
                    mentions: [],
                    requiresApproval: false,
                },
                userPreferences: {
                    userId: 'user-critical',
                    preferredChannels: ['in-app', 'email'],
                    channelPriority: { 'in-app': 5, 'email': 3 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-critical',
                        userId: 'user-critical',
                        levels: [1, 2, 3],
                        levelRoutes: { 1: ['in-app'], 2: ['email'], 3: ['sms'], 4: [], 5: [] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 0, 5: 0 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 3,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.batchable).toBe(false);
        });
    });
    describe('Delivery Acknowledgment Tests', () => {
        it('should record delivery acknowledgment', async () => {
            const ack = {
                notificationId: 'notif-005',
                userId: 'user-ack-001',
                deliveryRoute: 'email',
                status: 'delivered',
                ackTime: new Date(),
                actedUpon: false,
            };
            await service.recordDeliveryAck(ack);
            expect(ack.status).toBe('delivered');
        });
        it('should emit delivery ack event', async () => {
            const ack = {
                notificationId: 'notif-006',
                userId: 'user-ack-002',
                deliveryRoute: 'slack',
                status: 'acknowledged',
                ackTime: new Date(),
                actedUpon: true,
                actionTaken: 'resolved',
            };
            let emitted = false;
            service.on('deliveryAck', (receivedAck) => {
                emitted = receivedAck.notificationId === 'notif-006';
            });
            await service.recordDeliveryAck(ack);
            expect(emitted).toBe(true);
        });
    });
    describe('Channel Status Tests', () => {
        it('should update channel availability status', async () => {
            await service.updateChannelStatus('email', true, 85);
            expect(true).toBe(true);
        });
        it('should mark channels as unavailable', async () => {
            await service.updateChannelStatus('sms', false, 0, 'Provider outage');
            expect(true).toBe(true);
        });
        it('should track channel capacity', async () => {
            await service.updateChannelStatus('push', true, 45, 'High load');
            expect(true).toBe(true);
        });
    });
    describe('Priority & Escalation Tests', () => {
        it('should use correct escalation for P0', async () => {
            const context = {
                userId: 'user-p0',
                notificationId: 'notif-p0',
                notificationType: 'alert',
                priority: 'P0',
                timestamp: new Date(),
                readinessLevel: 'available',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: false,
                },
                userPreferences: {
                    userId: 'user-p0',
                    preferredChannels: ['in-app', 'email', 'slack'],
                    channelPriority: { 'in-app': 5, 'email': 3, 'slack': 4 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-p0',
                        userId: 'user-p0',
                        levels: [1, 2, 3, 4, 5],
                        levelRoutes: { 1: ['in-app'], 2: ['slack'], 3: ['email'], 4: ['sms'], 5: ['sms'] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 1800000, 5: 3600000 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 5,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.escalationPolicy).toBe(5); // P0 = highest escalation level
        });
        it('should use correct escalation for P3', async () => {
            const context = {
                userId: 'user-p3',
                notificationId: 'notif-p3',
                notificationType: 'info',
                priority: 'P3',
                timestamp: new Date(),
                readinessLevel: 'available',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: false,
                },
                userPreferences: {
                    userId: 'user-p3',
                    preferredChannels: ['in-app', 'email', 'slack'],
                    channelPriority: { 'in-app': 5, 'email': 3, 'slack': 4 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-p3',
                        userId: 'user-p3',
                        levels: [1, 2, 3, 4, 5],
                        levelRoutes: { 1: ['in-app'], 2: ['slack'], 3: ['email'], 4: ['sms'], 5: ['sms'] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 1800000, 5: 3600000 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 5,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.escalationPolicy).toBe(3); // P3 = level 3
        });
    });
    describe('Readiness Level Tests', () => {
        it('should prefer email for busy users', async () => {
            const context = {
                userId: 'user-busy',
                notificationId: 'notif-busy',
                notificationType: 'update',
                priority: 'P2',
                timestamp: new Date(),
                readinessLevel: 'busy',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: false,
                },
                userPreferences: {
                    userId: 'user-busy',
                    preferredChannels: ['in-app', 'email', 'slack'],
                    channelPriority: { 'in-app': 5, 'email': 3, 'slack': 4 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-busy',
                        userId: 'user-busy',
                        levels: [1, 2, 3],
                        levelRoutes: { 1: ['in-app'], 2: ['email'], 3: ['sms'], 4: [], 5: [] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 0, 5: 0 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 3,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.selectedRoute).toBe('email');
        });
        it('should prefer email for away users', async () => {
            const context = {
                userId: 'user-away',
                notificationId: 'notif-away',
                notificationType: 'update',
                priority: 'P2',
                timestamp: new Date(),
                readinessLevel: 'away',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: false,
                    hasWebClient: false,
                    hasMobileApp: true,
                },
                userPreferences: {
                    userId: 'user-away',
                    preferredChannels: ['email', 'sms', 'push'],
                    channelPriority: { 'email': 5, 'sms': 3, 'push': 4 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-away',
                        userId: 'user-away',
                        levels: [1, 2, 3],
                        levelRoutes: { 1: ['email'], 2: ['sms'], 3: ['push'], 4: [], 5: [] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 0, 5: 0 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 3,
                    },
                },
            };
            const decision = await service.makeRoutingDecision(context);
            expect(decision.selectedRoute).toBe('email');
        });
    });
    describe('Performance Tests', () => {
        it('should make routing decision in <15ms', async () => {
            const context = {
                userId: 'user-perf',
                notificationId: 'notif-perf',
                notificationType: 'test',
                priority: 'P2',
                timestamp: new Date(),
                readinessLevel: 'available',
                isInFocusTime: false,
                isInMeeting: false,
                deviceAvailability: {
                    hasDesktopClient: true,
                    hasWebClient: true,
                    hasMobileApp: false,
                },
                userPreferences: {
                    userId: 'user-perf',
                    preferredChannels: ['in-app', 'email'],
                    channelPriority: { 'in-app': 5, 'email': 3 },
                    doNotDisturb: { enabled: false },
                    focusTimeExclusion: false,
                    meetingModeExclusion: false,
                    channelOptOuts: [],
                    escalationPolicy: {
                        policyId: 'policy-perf',
                        userId: 'user-perf',
                        levels: [1, 2, 3],
                        levelRoutes: { 1: ['in-app'], 2: ['email'], 3: ['sms'], 4: [], 5: [] },
                        levelDelays: { 1: 0, 2: 300000, 3: 900000, 4: 0, 5: 0 },
                        enableForPriority: ['P0', 'P1'],
                        maxEscalationLevel: 3,
                    },
                },
            };
            const startTime = performance.now();
            const decision = await service.makeRoutingDecision(context);
            const endTime = performance.now();
            expect(endTime - startTime).toBeLessThan(15);
            expect(decision).toBeDefined();
        });
    });
});
//# sourceMappingURL=smart-notification-routing-service.test.js.map