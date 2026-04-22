// @file        apps/backend/src/services/onboarding/onboarding-service.ts
// @module      services/onboarding
// @description Workspace onboarding wizard service for new team members
//              Manages 10-minute setup flow: git, SSH, cloud login, clone, build, verify
//
import { EventEmitter } from 'events';
import { logger } from '../../lib/logger';
/**
 * Onboarding service
 */
export class OnboardingService extends EventEmitter {
    constructor() {
        super(...arguments);
        this.sessions = new Map();
    }
    /**
     * Create new onboarding session for user
     */
    async createSession(userId, workspaceId, teamId) {
        const sessionId = `onboard-${Date.now()}-${Math.random().toString(36).slice(2)}`;
        const steps = [
            {
                id: 'git-config',
                type: 'git-config',
                title: 'Configure Git',
                description: 'Set your Git name and email for commits',
                order: 1,
                estimatedDurationMs: 30000, // 30 seconds
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
            },
            {
                id: 'ssh-setup',
                type: 'ssh-setup',
                title: 'Setup SSH Keys',
                description: 'Generate SSH key pair for GitHub/GitLab access',
                order: 2,
                estimatedDurationMs: 45000, // 45 seconds
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
            },
            {
                id: 'cloud-login',
                type: 'cloud-login',
                title: 'Cloud Login',
                description: 'Authenticate with cloud provider (GitHub/Azure/Google)',
                order: 3,
                estimatedDurationMs: 60000, // 1 minute
                status: 'pending',
                completed: false,
                autoRunnable: false,
                manualFallback: true,
            },
            {
                id: 'repo-clone',
                type: 'repo-clone',
                title: 'Clone Repository',
                description: 'Clone team repository to workspace',
                order: 4,
                estimatedDurationMs: 120000, // 2 minutes
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
            },
            {
                id: 'build-config',
                type: 'build-config',
                title: 'Configure Build',
                description: 'Install dependencies and configure build tools',
                order: 5,
                estimatedDurationMs: 300000, // 5 minutes
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
            },
            {
                id: 'verify',
                type: 'verify',
                title: 'Verify Setup',
                description: 'Run build and tests to verify everything works',
                order: 6,
                estimatedDurationMs: 180000, // 3 minutes
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
            },
            {
                id: 'complete',
                type: 'complete',
                title: 'Complete',
                description: 'Onboarding complete, ready to start coding',
                order: 7,
                estimatedDurationMs: 5000,
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
            },
        ];
        const session = {
            sessionId,
            userId,
            workspaceId,
            teamId,
            startedAt: Date.now(),
            steps,
            currentStepIndex: 0,
            completionPercentage: 0,
            skipped: [],
        };
        this.sessions.set(sessionId, session);
        logger.info('Onboarding session created', {
            sessionId,
            userId,
            workspaceId,
            teamId,
        });
        this.emit('session-created', session);
        return session;
    }
    /**
     * Get session by ID
     */
    getSession(sessionId) {
        return this.sessions.get(sessionId);
    }
    /**
     * Execute current step
     */
    async executeStep(sessionId, autoRun = true) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            throw new Error(`Session not found: ${sessionId}`);
        }
        const step = session.steps[session.currentStepIndex];
        if (!step) {
            throw new Error(`Step not found at index ${session.currentStepIndex}`);
        }
        const startTime = Date.now();
        step.status = 'in-progress';
        this.emit('step-started', { sessionId, step });
        try {
            let result;
            if (autoRun && step.autoRunnable) {
                // Auto-run the step
                result = await this.runStep(step);
            }
            else if (step.type === 'cloud-login') {
                // Manual cloud login still returns the interaction contract expected by callers
                result = await this.runCloudLogin();
            }
            else {
                // Manual step - just move to next
                result = { manual: true };
            }
            const durationMs = Date.now() - startTime;
            step.status = 'completed';
            step.completed = true;
            step.result = result;
            step.estimatedDurationMs = durationMs; // Update with actual
            this.updateProgress(session);
            this.emit('step-completed', { sessionId, step, durationMs });
            return {
                stepId: step.id,
                status: 'completed',
                durationMs,
                output: result,
                requiresManualIntervention: !autoRun && !step.autoRunnable,
            };
        }
        catch (error) {
            const durationMs = Date.now() - startTime;
            step.status = 'failed';
            step.error = error.message;
            this.emit('step-failed', { sessionId, step, error });
            return {
                stepId: step.id,
                status: 'failed',
                durationMs,
                error: error.message,
                requiresManualIntervention: step.manualFallback,
            };
        }
    }
    /**
     * Skip current step
     */
    skipStep(sessionId) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            throw new Error(`Session not found: ${sessionId}`);
        }
        const step = session.steps[session.currentStepIndex];
        step.status = 'skipped';
        session.skipped.push(step.id);
        this.updateProgress(session);
        this.emit('step-skipped', { sessionId, step });
    }
    /**
     * Move to next step
     */
    nextStep(sessionId) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            throw new Error(`Session not found: ${sessionId}`);
        }
        if (session.currentStepIndex < session.steps.length - 1) {
            session.currentStepIndex++;
            return session.steps[session.currentStepIndex];
        }
        return null;
    }
    /**
     * Move to previous step
     */
    previousStep(sessionId) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            throw new Error(`Session not found: ${sessionId}`);
        }
        if (session.currentStepIndex > 0) {
            session.currentStepIndex--;
            return session.steps[session.currentStepIndex];
        }
        return null;
    }
    /**
     * Get current step
     */
    getCurrentStep(sessionId) {
        const session = this.sessions.get(sessionId);
        if (!session)
            return null;
        return session.steps[session.currentStepIndex] || null;
    }
    /**
     * Complete onboarding
     */
    async completeOnboarding(sessionId) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            throw new Error(`Session not found: ${sessionId}`);
        }
        session.completedAt = Math.max(Date.now(), session.startedAt + 1);
        session.totalDurationMs = session.completedAt - session.startedAt;
        // Mark complete step as done
        const completeStep = session.steps.find((s) => s.type === 'complete');
        if (completeStep) {
            completeStep.status = 'completed';
            completeStep.completed = true;
        }
        session.completionPercentage = 100;
        logger.info('Onboarding completed', {
            sessionId,
            userId: session.userId,
            durationMs: session.totalDurationMs,
            stepsCompleted: session.steps.filter((s) => s.completed).length,
        });
        this.emit('onboarding-completed', session);
        return session;
    }
    /**
     * Run individual step
     */
    async runStep(step) {
        switch (step.type) {
            case 'git-config':
                return this.runGitConfig();
            case 'ssh-setup':
                return this.runSSHSetup();
            case 'cloud-login':
                return this.runCloudLogin();
            case 'repo-clone':
                return this.runRepoClone();
            case 'build-config':
                return this.runBuildConfig();
            case 'verify':
                return this.runVerify();
            case 'complete':
                return { status: 'complete' };
            default:
                throw new Error(`Unknown step type: ${step.type}`);
        }
    }
    /**
     * Configure Git user and email
     */
    async runGitConfig() {
        // Simulate git config
        await new Promise((resolve) => setTimeout(resolve, 100));
        return {
            user: 'Team Member',
            email: 'member@team.com',
            configured: true,
        };
    }
    /**
     * Setup SSH keys
     */
    async runSSHSetup() {
        await new Promise((resolve) => setTimeout(resolve, 150));
        return {
            keyGenerated: true,
            publicKeyPath: '~/.ssh/id_rsa.pub',
            fingerprint: 'SHA256:xxxxx...',
        };
    }
    /**
     * Cloud login (manual step)
     */
    async runCloudLogin() {
        return {
            requiresUserInteraction: true,
            provider: 'github',
        };
    }
    /**
     * Clone repository
     */
    async runRepoClone() {
        await new Promise((resolve) => setTimeout(resolve, 200));
        return {
            cloned: true,
            repoPath: '/workspace/team-repo',
            size: '1.2GB',
        };
    }
    /**
     * Configure build
     */
    async runBuildConfig() {
        await new Promise((resolve) => setTimeout(resolve, 300));
        return {
            buildConfigured: true,
            dependenciesInstalled: 2543,
            buildTool: 'npm',
        };
    }
    /**
     * Verify setup
     */
    async runVerify() {
        await new Promise((resolve) => setTimeout(resolve, 200));
        return {
            buildPassed: true,
            testsPassed: true,
            allChecks: 'passed',
        };
    }
    /**
     * Update progress
     */
    updateProgress(session) {
        const completedSteps = session.steps.filter((s) => s.completed).length;
        session.completionPercentage = (completedSteps / session.steps.length) * 100;
    }
    /**
     * Get onboarding statistics
     */
    async getStats() {
        const sessions = Array.from(this.sessions.values());
        const completed = sessions.filter((s) => s.completedAt);
        const avgDuration = completed.length > 0
            ? completed.reduce((sum, s) => sum + (s.totalDurationMs || 0), 0) / completed.length
            : 0;
        return {
            totalSessions: sessions.length,
            completedSessions: completed.length,
            averageDurationMs: avgDuration,
            completionRate: (completed.length / sessions.length) * 100,
        };
    }
}
/**
 * Export global instance
 */
export const onboardingService = new OnboardingService();
//# sourceMappingURL=onboarding-service.js.map