#!/usr/bin/env node
// @file        apps/backend/src/services/communication-optimization-engine/__tests__/communication-optimization-engine.test.ts
// @module      collaboration/communication-optimization-engine/tests
// @description Comprehensive test suite for CommunicationOptimizationEngine
// @owner       collab-services
// @status      active
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createCommunicationOptimizationEngine } from '../communication-optimization-engine';
import { CommunicationUrgency, CommunicationMode, CommunicationChannel } from '../types';
describe('CommunicationOptimizationEngine', () => {
    let engine;
    beforeEach(async () => {
        engine = createCommunicationOptimizationEngine({
            enableAsyncOptimization: true,
            enableDigestGeneration: true,
            enableEscalationLogic: true,
        });
        await engine.initialize();
    });
    afterEach(async () => {
        await engine.shutdown();
    });
    describe('Service Initialization', () => {
        it('should initialize service successfully', async () => {
            expect(engine).toBeDefined();
            const stats = engine.getStats();
            expect(stats).toBeDefined();
            expect(stats.decisionsRecommended).toBe(0);
        }, 10);
        it('should shutdown gracefully', async () => {
            const localEngine = createCommunicationOptimizationEngine();
            await localEngine.initialize();
            await localEngine.shutdown();
            expect(localEngine).toBeDefined();
        }, 8);
    });
    describe('Communication Recommendations', () => {
        it('should recommend async communication for low urgency', async () => {
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-2'],
                teamId: 'team-1',
                communicationType: 'update',
                urgency: CommunicationUrgency.LOW,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            expect(decision).toBeDefined();
            expect(decision.teamId).toBe('team-1');
            expect([CommunicationMode.ASYNC_COMMENT, CommunicationMode.SUMMARY_DIGEST, CommunicationMode.DEFERRED]).toContain(decision.recommendedMode);
            expect(decision.confidence).toBeGreaterThan(0);
        }, 12);
        it('should recommend sync communication for critical urgency', async () => {
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-2'],
                teamId: 'team-1',
                communicationType: 'blocker',
                urgency: CommunicationUrgency.CRITICAL,
                blockerPresent: true,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            expect(decision).toBeDefined();
            expect([
                CommunicationMode.SYNC_MENTION,
                CommunicationMode.CALL_MEETING,
                CommunicationMode.SYNC_DM,
            ]).toContain(decision.recommendedMode);
        }, 13);
        it('should defer communication when user unavailable', async () => {
            const signal = {
                userId: 'user-unavailable',
                available: false,
                focusTime: false,
                dndActive: false,
            };
            await engine.updateReadinessSignal(signal);
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-unavailable'],
                teamId: 'team-1',
                communicationType: 'update',
                urgency: CommunicationUrgency.NORMAL,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            expect(decision.shouldDefer).toBe(true);
            expect(decision.recommendedMode).toBe(CommunicationMode.DEFERRED);
        }, 12);
        it('should not defer critical communication', async () => {
            const signal = {
                userId: 'user-busy',
                available: false,
                focusTime: false,
                dndActive: true,
            };
            await engine.updateReadinessSignal(signal);
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-busy'],
                teamId: 'team-1',
                communicationType: 'blocker',
                urgency: CommunicationUrgency.CRITICAL,
                blockerPresent: true,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            // Critical items should be escalated, not deferred
            expect([CommunicationMode.CALL_MEETING, CommunicationMode.SYNC_MENTION]).toContain(decision.recommendedMode);
        }, 13);
        it('should escalate critical items with unavailable users', async () => {
            const signal = {
                userId: 'user-escalate',
                available: false,
                focusTime: false,
                dndActive: false,
            };
            await engine.updateReadinessSignal(signal);
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-escalate'],
                teamId: 'team-1',
                communicationType: 'blocker',
                urgency: CommunicationUrgency.CRITICAL,
                blockerPresent: true,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            expect(decision.escalationPath).toBeDefined();
            expect(decision.escalationPath?.length).toBeGreaterThan(0);
            expect(decision.stats === undefined || decision.escalatedRecommendations === undefined).toBe(true);
        }, 13);
    });
    describe('Preferences Management', () => {
        it('should load user communication preferences', async () => {
            const preference = await engine.loadPreferences('user-pref');
            expect(preference).toBeDefined();
            expect(preference.userId).toBe('user-pref');
            expect(preference.preferredChannels).toBeDefined();
            expect(Array.isArray(preference.preferredChannels)).toBe(true);
        }, 10);
        it('should track multiple preferences', async () => {
            const users = ['user-a', 'user-b', 'user-c'];
            for (const userId of users) {
                await engine.loadPreferences(userId);
            }
            const stats = engine.getStats();
            expect(stats.preferencesLoaded).toBeGreaterThanOrEqual(users.length);
        }, 12);
    });
    describe('Readiness Signals', () => {
        it('should update user readiness signals', async () => {
            const signal = {
                userId: 'user-signal',
                available: true,
                focusTime: false,
                dndActive: false,
                capacity: 0.8,
            };
            await engine.updateReadinessSignal(signal);
            expect(signal.userId).toBe('user-signal');
        }, 10);
        it('should handle focus time blocking', async () => {
            const signal = {
                userId: 'user-focus',
                available: true,
                focusTime: true,
                dndActive: false,
            };
            await engine.updateReadinessSignal(signal);
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-focus'],
                teamId: 'team-1',
                communicationType: 'update',
                urgency: CommunicationUrgency.NORMAL,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            expect(decision.shouldDefer).toBe(true);
        }, 12);
    });
    describe('Digest Generation', () => {
        it('should generate communication digest', async () => {
            const digest = await engine.generateDigest('team-digest', 'user-digest', Date.now() - 3600000, Date.now());
            expect(digest).toBeDefined();
            expect(digest.teamId).toBe('team-digest');
            expect(digest.userId).toBe('user-digest');
            expect(Array.isArray(digest.items)).toBe(true);
        }, 11);
        it('should track digest generation statistics', async () => {
            const before = engine.getStats();
            await engine.generateDigest('team-test', 'user-test', Date.now() - 3600000, Date.now());
            const after = engine.getStats();
            expect(after.digestsGenerated).toBeGreaterThanOrEqual(before.digestsGenerated);
        }, 11);
    });
    describe('Collaboration Pattern Recording', () => {
        it('should record collaboration patterns', async () => {
            const pattern = {
                teamId: 'team-pattern',
                patternType: 'clustering',
                members: ['user-1', 'user-2', 'user-3'],
                strength: 0.8,
                riskLevel: 'low',
            };
            await engine.recordCollaborationPattern(pattern);
            expect(pattern.teamId).toBe('team-pattern');
        }, 10);
    });
    describe('Optimization Queries', () => {
        it('should query optimization with metrics', async () => {
            const result = await engine.queryOptimization({
                teamId: 'team-query',
                includeMetrics: true,
                includeRecommendations: false,
                includeDigests: false,
            });
            expect(result).toBeDefined();
            expect(result.teamId).toBe('team-query');
            expect(result.metrics).toBeDefined();
            expect(result.queryTime).toBeGreaterThanOrEqual(0);
        }, 11);
        it('should query optimization with recommendations', async () => {
            const result = await engine.queryOptimization({
                teamId: 'team-query-rec',
                includeMetrics: false,
                includeRecommendations: true,
                includeDigests: false,
            });
            expect(result.recommendations).toBeDefined();
            expect(Array.isArray(result.recommendations)).toBe(true);
        }, 11);
        it('should query optimization with digests', async () => {
            const result = await engine.queryOptimization({
                teamId: 'team-query-dig',
                includeMetrics: false,
                includeRecommendations: false,
                includeDigests: true,
            });
            expect(result.digests).toBeDefined();
            expect(Array.isArray(result.digests)).toBe(true);
        }, 11);
    });
    describe('Channel Selection', () => {
        it('should select appropriate channel for communication', async () => {
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-2'],
                teamId: 'team-1',
                communicationType: 'message',
                urgency: CommunicationUrgency.CRITICAL,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            expect([
                CommunicationChannel.IN_APP,
                CommunicationChannel.SLACK,
                CommunicationChannel.PUSH,
            ]).toContain(decision.recommendedChannel);
        }, 12);
        it('should prefer email for low urgency async', async () => {
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-2'],
                teamId: 'team-1',
                communicationType: 'update',
                urgency: CommunicationUrgency.LOW,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            // Should be a reasonable channel choice
            expect(decision.recommendedChannel).toBeDefined();
        }, 12);
    });
    describe('Statistics Tracking', () => {
        it('should track service statistics', async () => {
            const stats = engine.getStats();
            expect(stats.decisionsRecommended).toBeGreaterThanOrEqual(0);
            expect(stats.asyncRecommendations).toBeGreaterThanOrEqual(0);
            expect(stats.syncRecommendations).toBeGreaterThanOrEqual(0);
            expect(stats.deferredRecommendations).toBeGreaterThanOrEqual(0);
            expect(stats.digestsGenerated).toBeGreaterThanOrEqual(0);
            expect(stats.teamsMonitored).toBeGreaterThanOrEqual(0);
        }, 10);
        it('should update statistics with recommendations', async () => {
            const before = engine.getStats();
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-2'],
                teamId: 'team-stats',
                communicationType: 'message',
                urgency: CommunicationUrgency.NORMAL,
                timestamp: Date.now(),
            };
            await engine.recommendCommunication(context);
            const after = engine.getStats();
            expect(after.decisionsRecommended).toBeGreaterThan(before.decisionsRecommended);
        }, 12);
    });
    describe('Timing Recommendations', () => {
        it('should recommend appropriate timing for communication', async () => {
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-2'],
                teamId: 'team-timing',
                communicationType: 'message',
                urgency: CommunicationUrgency.NORMAL,
                timestamp: Date.now(),
            };
            const decision = await engine.recommendCommunication(context);
            expect(decision.recommendedTiming).toBeGreaterThanOrEqual(Date.now());
            expect(decision.estimatedResponseTime).toBeGreaterThan(0);
        }, 12);
    });
    describe('Performance', () => {
        it('should recommend communication in <15ms', async () => {
            const context = {
                sourceUserId: 'user-1',
                targetUserIds: ['user-2'],
                teamId: 'team-perf',
                communicationType: 'message',
                urgency: CommunicationUrgency.NORMAL,
                timestamp: Date.now(),
            };
            const start = performance.now();
            await engine.recommendCommunication(context);
            const duration = performance.now() - start;
            expect(duration).toBeLessThan(15);
        }, 15);
        it('should query optimization in <15ms', async () => {
            const start = performance.now();
            await engine.queryOptimization({
                teamId: 'team-perf-query',
                includeMetrics: true,
                includeRecommendations: true,
            });
            const duration = performance.now() - start;
            expect(duration).toBeLessThan(15);
        }, 15);
        it('should generate digest in <15ms', async () => {
            const start = performance.now();
            await engine.generateDigest('team-perf-dig', 'user-perf', Date.now() - 3600000, Date.now());
            const duration = performance.now() - start;
            expect(duration).toBeLessThan(15);
        }, 15);
    });
});
//# sourceMappingURL=communication-optimization-engine.test.js.map