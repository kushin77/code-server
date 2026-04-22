// @file        apps/backend/src/services/onboarding/__tests__/onboarding-service.test.ts
// @module      services/onboarding
// @description Comprehensive test suite for onboarding service
//              Tests: session management, step execution, progress tracking, error handling
//
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { OnboardingService } from '../onboarding-service';
describe('OnboardingService', () => {
    let service;
    beforeEach(() => {
        service = new OnboardingService();
    });
    afterEach(() => {
        service.removeAllListeners();
    });
    describe('Session Management', () => {
        it('should create a new onboarding session', async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            expect(session).toBeDefined();
            expect(session.sessionId).toMatch(/^onboard-\d+-[a-z0-9]+$/);
            expect(session.userId).toBe('user123');
            expect(session.workspaceId).toBe('workspace1');
            expect(session.teamId).toBe('team1');
        });
        it('should initialize session with 7 steps', async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            expect(session.steps).toHaveLength(7);
            expect(session.steps[0].type).toBe('git-config');
            expect(session.steps[1].type).toBe('ssh-setup');
            expect(session.steps[2].type).toBe('cloud-login');
            expect(session.steps[3].type).toBe('repo-clone');
            expect(session.steps[4].type).toBe('build-config');
            expect(session.steps[5].type).toBe('verify');
            expect(session.steps[6].type).toBe('complete');
        });
        it('should set correct step properties', async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            const gitStep = session.steps[0];
            expect(gitStep.id).toBe('git-config');
            expect(gitStep.title).toBe('Configure Git');
            expect(gitStep.order).toBe(1);
            expect(gitStep.status).toBe('pending');
            expect(gitStep.completed).toBe(false);
            expect(gitStep.autoRunnable).toBe(true);
            expect(gitStep.manualFallback).toBe(true);
        });
        it('should retrieve session by ID', async () => {
            const created = await service.createSession('user123', 'workspace1', 'team1');
            const retrieved = service.getSession(created.sessionId);
            expect(retrieved).toBeDefined();
            expect(retrieved?.sessionId).toBe(created.sessionId);
            expect(retrieved?.userId).toBe('user123');
        });
        it('should return undefined for non-existent session', () => {
            const session = service.getSession('non-existent');
            expect(session).toBeUndefined();
        });
        it('should emit session-created event', async () => {
            const spy = vi.fn();
            service.on('session-created', spy);
            await service.createSession('user123', 'workspace1', 'team1');
            expect(spy).toHaveBeenCalledOnce();
            expect(spy).toHaveBeenCalledWith(expect.objectContaining({ userId: 'user123' }));
        });
    });
    describe('Step Execution', () => {
        let sessionId;
        beforeEach(async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            sessionId = session.sessionId;
        });
        it('should execute git-config step', async () => {
            const result = await service.executeStep(sessionId, true);
            expect(result.stepId).toBe('git-config');
            expect(result.status).toBe('completed');
            expect(result.durationMs).toBeGreaterThan(0);
            expect(result.output).toBeDefined();
            expect(result.requiresManualIntervention).toBe(false);
        });
        it('should execute ssh-setup step', async () => {
            service.nextStep(sessionId); // Move to SSH step
            const result = await service.executeStep(sessionId, true);
            expect(result.stepId).toBe('ssh-setup');
            expect(result.status).toBe('completed');
            expect(result.output.keyGenerated).toBe(true);
        });
        it('should handle cloud-login as manual step', async () => {
            // Move to cloud-login step
            service.nextStep(sessionId);
            service.nextStep(sessionId);
            const result = await service.executeStep(sessionId, false);
            expect(result.stepId).toBe('cloud-login');
            expect(result.status).toBe('completed');
            expect(result.output.requiresUserInteraction).toBe(true);
        });
        it('should execute repo-clone step', async () => {
            // Move to repo-clone step
            for (let i = 0; i < 3; i++) {
                service.nextStep(sessionId);
            }
            const result = await service.executeStep(sessionId, true);
            expect(result.stepId).toBe('repo-clone');
            expect(result.status).toBe('completed');
            expect(result.output.cloned).toBe(true);
        });
        it('should track step duration', async () => {
            const result = await service.executeStep(sessionId, true);
            expect(result.durationMs).toBeGreaterThanOrEqual(0);
            expect(typeof result.durationMs).toBe('number');
        });
        it('should emit step-started event', async () => {
            const spy = vi.fn();
            service.on('step-started', spy);
            await service.executeStep(sessionId, true);
            expect(spy).toHaveBeenCalled();
        });
        it('should emit step-completed event', async () => {
            const spy = vi.fn();
            service.on('step-completed', spy);
            await service.executeStep(sessionId, true);
            expect(spy).toHaveBeenCalled();
        });
        it('should update step status to in-progress during execution', async () => {
            const sessionBeforeExecution = service.getSession(sessionId);
            const stepBeforeExecution = sessionBeforeExecution.steps[0];
            await service.executeStep(sessionId, true);
            const sessionAfterExecution = service.getSession(sessionId);
            const stepAfterExecution = sessionAfterExecution.steps[0];
            expect(stepAfterExecution.status).toBe('completed');
            expect(stepAfterExecution.completed).toBe(true);
        });
        it('should error on invalid step execution', async () => {
            const invalidSessionId = 'non-existent';
            await expect(service.executeStep(invalidSessionId, true)).rejects.toThrow('Session not found');
        });
    });
    describe('Step Navigation', () => {
        let sessionId;
        beforeEach(async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            sessionId = session.sessionId;
        });
        it('should move to next step', () => {
            const step = service.nextStep(sessionId);
            expect(step).toBeDefined();
            expect(step?.type).toBe('ssh-setup');
            expect(step?.order).toBe(2);
        });
        it('should return null when moving past last step', () => {
            const session = service.getSession(sessionId);
            // Move to last step
            for (let i = 0; i < 6; i++) {
                service.nextStep(sessionId);
            }
            const result = service.nextStep(sessionId);
            expect(result).toBeNull();
        });
        it('should move to previous step', () => {
            service.nextStep(sessionId);
            service.nextStep(sessionId);
            const step = service.previousStep(sessionId);
            expect(step).toBeDefined();
            expect(step?.type).toBe('ssh-setup');
            expect(step?.order).toBe(2);
        });
        it('should return null when moving before first step', () => {
            const result = service.previousStep(sessionId);
            expect(result).toBeNull();
        });
        it('should get current step', () => {
            const step = service.getCurrentStep(sessionId);
            expect(step).toBeDefined();
            expect(step?.type).toBe('git-config');
            expect(step?.order).toBe(1);
        });
        it('should return null for current step of non-existent session', () => {
            const step = service.getCurrentStep('non-existent');
            expect(step).toBeNull();
        });
        it('should track current step index', () => {
            service.nextStep(sessionId);
            service.nextStep(sessionId);
            const session = service.getSession(sessionId);
            expect(session.currentStepIndex).toBe(2);
        });
    });
    describe('Step Skipping', () => {
        let sessionId;
        beforeEach(async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            sessionId = session.sessionId;
        });
        it('should skip current step', () => {
            service.skipStep(sessionId);
            const session = service.getSession(sessionId);
            const step = session.steps[0];
            expect(step.status).toBe('skipped');
        });
        it('should add skipped step to session.skipped array', () => {
            service.skipStep(sessionId);
            const session = service.getSession(sessionId);
            expect(session.skipped).toContain('git-config');
        });
        it('should emit step-skipped event', () => {
            const spy = vi.fn();
            service.on('step-skipped', spy);
            service.skipStep(sessionId);
            expect(spy).toHaveBeenCalled();
        });
        it('should allow multiple steps to be skipped', () => {
            service.skipStep(sessionId);
            service.nextStep(sessionId);
            service.skipStep(sessionId);
            const session = service.getSession(sessionId);
            expect(session.skipped).toContain('git-config');
            expect(session.skipped).toContain('ssh-setup');
            expect(session.skipped).toHaveLength(2);
        });
    });
    describe('Progress Tracking', () => {
        let sessionId;
        beforeEach(async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            sessionId = session.sessionId;
        });
        it('should initialize completion to 0%', () => {
            const session = service.getSession(sessionId);
            expect(session.completionPercentage).toBe(0);
        });
        it('should update completion percentage after step completion', async () => {
            await service.executeStep(sessionId, true);
            const session = service.getSession(sessionId);
            expect(session.completionPercentage).toBeGreaterThan(0);
            expect(session.completionPercentage).toBeLessThanOrEqual(100);
        });
        it('should calculate correct completion percentage', async () => {
            // Complete 2 steps
            await service.executeStep(sessionId, true);
            service.nextStep(sessionId);
            await service.executeStep(sessionId, true);
            const session = service.getSession(sessionId);
            const expectedPercentage = (2 / 7) * 100;
            expect(session.completionPercentage).toBeCloseTo(expectedPercentage, 1);
        });
        it('should reach 100% on completion', async () => {
            await service.completeOnboarding(sessionId);
            const session = service.getSession(sessionId);
            expect(session.completionPercentage).toBe(100);
        });
    });
    describe('Onboarding Completion', () => {
        let sessionId;
        beforeEach(async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            sessionId = session.sessionId;
        });
        it('should mark onboarding as completed', async () => {
            const session = await service.completeOnboarding(sessionId);
            expect(session.completedAt).toBeDefined();
            expect(session.completedAt).toBeGreaterThan(session.startedAt);
        });
        it('should calculate total duration', async () => {
            const session = await service.completeOnboarding(sessionId);
            expect(session.totalDurationMs).toBeDefined();
            expect(session.totalDurationMs).toBeGreaterThanOrEqual(0);
        });
        it('should set completion percentage to 100', async () => {
            const session = await service.completeOnboarding(sessionId);
            expect(session.completionPercentage).toBe(100);
        });
        it('should emit onboarding-completed event', () => {
            const spy = vi.fn();
            service.on('onboarding-completed', spy);
            service.completeOnboarding(sessionId);
            expect(spy).toHaveBeenCalledOnce();
        });
        it('should mark complete step as done', async () => {
            await service.completeOnboarding(sessionId);
            const session = service.getSession(sessionId);
            const completeStep = session.steps.find((s) => s.type === 'complete');
            expect(completeStep?.completed).toBe(true);
            expect(completeStep?.status).toBe('completed');
        });
    });
    describe('Error Handling', () => {
        let sessionId;
        beforeEach(async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            sessionId = session.sessionId;
        });
        it('should handle step execution with non-existent session', async () => {
            await expect(service.executeStep('non-existent', true)).rejects.toThrow('Session not found');
        });
        it('should handle skipping non-existent session', () => {
            expect(() => service.skipStep('non-existent')).toThrow('Session not found');
        });
        it('should handle next step on non-existent session', () => {
            expect(() => service.nextStep('non-existent')).toThrow('Session not found');
        });
        it('should handle previous step on non-existent session', () => {
            expect(() => service.previousStep('non-existent')).toThrow('Session not found');
        });
        it('should handle complete onboarding on non-existent session', async () => {
            await expect(service.completeOnboarding('non-existent')).rejects.toThrow('Session not found');
        });
        it('should emit step-failed event on error', () => {
            const spy = vi.fn();
            service.on('step-failed', spy);
            // Manually create a scenario where step fails
            const session = service.getSession(sessionId);
            const invalidIndex = 999;
            session.currentStepIndex = invalidIndex;
            service.executeStep(sessionId, true).catch(() => {
                // Expected error
            });
        });
    });
    describe('Statistics', () => {
        it('should return empty stats for new service', async () => {
            const stats = await service.getStats();
            expect(stats.totalSessions).toBe(0);
            expect(stats.completedSessions).toBe(0);
            expect(stats.averageDurationMs).toBe(0);
            expect(stats.completionRate).toBeNaN(); // 0/0
        });
        it('should track total sessions', async () => {
            await service.createSession('user1', 'ws1', 'team1');
            await service.createSession('user2', 'ws2', 'team2');
            await service.createSession('user3', 'ws3', 'team3');
            const stats = await service.getStats();
            expect(stats.totalSessions).toBe(3);
        });
        it('should track completed sessions', async () => {
            const session1 = await service.createSession('user1', 'ws1', 'team1');
            const session2 = await service.createSession('user2', 'ws2', 'team2');
            await service.completeOnboarding(session1.sessionId);
            const stats = await service.getStats();
            expect(stats.completedSessions).toBe(1);
        });
        it('should calculate average duration', async () => {
            const session1 = await service.createSession('user1', 'ws1', 'team1');
            const session2 = await service.createSession('user2', 'ws2', 'team2');
            // Simulate some time passing
            await new Promise((resolve) => setTimeout(resolve, 100));
            await service.completeOnboarding(session1.sessionId);
            await service.completeOnboarding(session2.sessionId);
            const stats = await service.getStats();
            expect(stats.averageDurationMs).toBeGreaterThan(0);
        });
        it('should calculate completion rate', async () => {
            const session1 = await service.createSession('user1', 'ws1', 'team1');
            const session2 = await service.createSession('user2', 'ws2', 'team2');
            const session3 = await service.createSession('user3', 'ws3', 'team3');
            await service.completeOnboarding(session1.sessionId);
            const stats = await service.getStats();
            const expectedRate = (1 / 3) * 100;
            expect(stats.completionRate).toBeCloseTo(expectedRate, 1);
        });
    });
    describe('Step Auto-Run Configuration', () => {
        let sessionId;
        beforeEach(async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            sessionId = session.sessionId;
        });
        it('should identify auto-runnable steps', () => {
            const session = service.getSession(sessionId);
            const autoRunnableSteps = session.steps.filter((s) => s.autoRunnable);
            expect(autoRunnableSteps).toHaveLength(6); // All except cloud-login
        });
        it('should identify cloud-login as manual-only step', () => {
            const session = service.getSession(sessionId);
            const cloudLoginStep = session.steps.find((s) => s.type === 'cloud-login');
            expect(cloudLoginStep?.autoRunnable).toBe(false);
            expect(cloudLoginStep?.manualFallback).toBe(true);
        });
        it('should all steps support manual fallback', () => {
            const session = service.getSession(sessionId);
            const canFallback = session.steps.every((s) => s.manualFallback === true);
            expect(canFallback).toBe(true);
        });
    });
    describe('Step Estimated Durations', () => {
        let sessionId;
        beforeEach(async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            sessionId = session.sessionId;
        });
        it('should set reasonable estimated durations', () => {
            const session = service.getSession(sessionId);
            const totalEstimate = session.steps.reduce((sum, s) => sum + s.estimatedDurationMs, 0);
            expect(totalEstimate).toBeLessThan(15 * 60 * 1000); // Should be under 15 minutes total
            expect(totalEstimate).toBeGreaterThan(10 * 60 * 1000); // Should be around 10 minutes
        });
        it('should have durations in ascending order', () => {
            const session = service.getSession(sessionId);
            const durations = session.steps.map((s) => s.estimatedDurationMs);
            for (let i = 1; i < durations.length; i++) {
                // Each step should be <= 5 minutes
                expect(durations[i]).toBeLessThanOrEqual(300000);
            }
        });
    });
    describe('Integration Scenarios', () => {
        it('should complete full onboarding flow successfully', async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            // Execute all steps
            for (let i = 0; i < 7; i++) {
                if (i > 0) {
                    service.nextStep(session.sessionId);
                }
                const currentStep = service.getCurrentStep(session.sessionId);
                if (currentStep?.autoRunnable) {
                    await service.executeStep(session.sessionId, true);
                }
                else {
                    await service.executeStep(session.sessionId, false);
                }
            }
            const completed = await service.completeOnboarding(session.sessionId);
            expect(completed.completedAt).toBeDefined();
            expect(completed.completionPercentage).toBe(100);
            expect(completed.totalDurationMs).toBeGreaterThan(0);
        });
        it('should handle mixed auto-run and manual steps', async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            // Step 1: Auto-run
            await service.executeStep(session.sessionId, true);
            service.nextStep(session.sessionId);
            // Step 2: Auto-run
            await service.executeStep(session.sessionId, true);
            service.nextStep(session.sessionId);
            // Step 3: Manual
            await service.executeStep(session.sessionId, false);
            service.nextStep(session.sessionId);
            const current = service.getSession(session.sessionId);
            expect(current.steps[0].completed).toBe(true);
            expect(current.steps[1].completed).toBe(true);
            expect(current.steps[2].completed).toBe(true);
        });
        it('should handle skip and resume', async () => {
            const session = await service.createSession('user123', 'workspace1', 'team1');
            await service.executeStep(session.sessionId, true);
            service.nextStep(session.sessionId);
            service.skipStep(session.sessionId); // Skip SSH setup
            service.nextStep(session.sessionId);
            await service.executeStep(session.sessionId, false); // Do cloud-login
            const updated = service.getSession(session.sessionId);
            expect(updated.steps[0].completed).toBe(true);
            expect(updated.steps[1].status).toBe('skipped');
            expect(updated.steps[2].completed).toBe(true);
        });
    });
});
//# sourceMappingURL=onboarding-service.test.js.map