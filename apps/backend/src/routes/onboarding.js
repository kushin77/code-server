// @file        apps/backend/src/routes/onboarding.ts
// @module      routes/onboarding
// @description Express routes for workspace onboarding wizard API
//              Endpoints: create session, execute step, navigate, complete
//
import { Router } from 'express';
import { onboardingService } from '../services/onboarding/onboarding-service';
import { logger } from '../lib/logger';
const router = Router();
/**
 * Middleware to validate session exists
 */
const validateSession = async (req, res, next) => {
    const { sessionId } = req.params;
    const session = onboardingService.getSession(sessionId);
    if (!session) {
        return res.status(404).json({
            error: 'Session not found',
            sessionId,
        });
    }
    req.session = session;
    next();
};
/**
 * POST /api/onboarding/sessions
 * Create new onboarding session
 */
router.post('/sessions', async (req, res) => {
    try {
        const { userId, workspaceId, teamId } = req.body;
        if (!userId || !workspaceId || !teamId) {
            return res.status(400).json({
                error: 'Missing required fields: userId, workspaceId, teamId',
            });
        }
        const session = await onboardingService.createSession(userId, workspaceId, teamId);
        logger.info('Onboarding session created via API', {
            sessionId: session.sessionId,
            userId,
            workspaceId,
            teamId,
        });
        res.status(201).json(session);
    }
    catch (error) {
        logger.error('Failed to create onboarding session', error);
        res.status(500).json({
            error: 'Failed to create onboarding session',
            message: error.message,
        });
    }
});
/**
 * GET /api/onboarding/sessions/:sessionId
 * Get onboarding session details
 */
router.get('/sessions/:sessionId', validateSession, (req, res) => {
    try {
        const session = onboardingService.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({
                error: 'Session not found',
            });
        }
        res.json(session);
    }
    catch (error) {
        logger.error('Failed to fetch onboarding session', error);
        res.status(500).json({
            error: 'Failed to fetch onboarding session',
            message: error.message,
        });
    }
});
/**
 * POST /api/onboarding/sessions/:sessionId/execute-step
 * Execute current step
 */
router.post('/sessions/:sessionId/execute-step', validateSession, async (req, res) => {
    try {
        const { sessionId } = req.params;
        const { autoRun = true } = req.body;
        const result = await onboardingService.executeStep(sessionId, autoRun);
        logger.info('Step executed', {
            sessionId,
            stepId: result.stepId,
            status: result.status,
            durationMs: result.durationMs,
        });
        res.json(result);
    }
    catch (error) {
        logger.error('Failed to execute step', error);
        res.status(500).json({
            error: 'Failed to execute step',
            message: error.message,
        });
    }
});
/**
 * POST /api/onboarding/sessions/:sessionId/skip-step
 * Skip current step
 */
router.post('/sessions/:sessionId/skip-step', validateSession, (req, res) => {
    try {
        const { sessionId } = req.params;
        onboardingService.skipStep(sessionId);
        const session = onboardingService.getSession(sessionId);
        logger.info('Step skipped', {
            sessionId,
            stepId: session?.steps[session.currentStepIndex - 1]?.id,
        });
        res.json({
            status: 'skipped',
            currentStep: onboardingService.getCurrentStep(sessionId),
            session,
        });
    }
    catch (error) {
        logger.error('Failed to skip step', error);
        res.status(500).json({
            error: 'Failed to skip step',
            message: error.message,
        });
    }
});
/**
 * POST /api/onboarding/sessions/:sessionId/next-step
 * Move to next step
 */
router.post('/sessions/:sessionId/next-step', validateSession, (req, res) => {
    try {
        const { sessionId } = req.params;
        const nextStep = onboardingService.nextStep(sessionId);
        logger.info('Moved to next step', {
            sessionId,
            nextStep: nextStep?.id,
        });
        res.json({
            currentStep: nextStep,
            session: onboardingService.getSession(sessionId),
        });
    }
    catch (error) {
        logger.error('Failed to move to next step', error);
        res.status(500).json({
            error: 'Failed to move to next step',
            message: error.message,
        });
    }
});
/**
 * POST /api/onboarding/sessions/:sessionId/prev-step
 * Move to previous step
 */
router.post('/sessions/:sessionId/prev-step', validateSession, (req, res) => {
    try {
        const { sessionId } = req.params;
        const prevStep = onboardingService.previousStep(sessionId);
        logger.info('Moved to previous step', {
            sessionId,
            prevStep: prevStep?.id,
        });
        res.json({
            currentStep: prevStep,
            session: onboardingService.getSession(sessionId),
        });
    }
    catch (error) {
        logger.error('Failed to move to previous step', error);
        res.status(500).json({
            error: 'Failed to move to previous step',
            message: error.message,
        });
    }
});
/**
 * GET /api/onboarding/sessions/:sessionId/current-step
 * Get current step
 */
router.get('/sessions/:sessionId/current-step', validateSession, (req, res) => {
    try {
        const { sessionId } = req.params;
        const currentStep = onboardingService.getCurrentStep(sessionId);
        res.json({
            currentStep,
            session: onboardingService.getSession(sessionId),
        });
    }
    catch (error) {
        logger.error('Failed to fetch current step', error);
        res.status(500).json({
            error: 'Failed to fetch current step',
            message: error.message,
        });
    }
});
/**
 * POST /api/onboarding/sessions/:sessionId/complete
 * Complete onboarding
 */
router.post('/sessions/:sessionId/complete', validateSession, async (req, res) => {
    try {
        const { sessionId } = req.params;
        const session = await onboardingService.completeOnboarding(sessionId);
        logger.info('Onboarding completed via API', {
            sessionId,
            userId: session.userId,
            durationMs: session.totalDurationMs,
        });
        res.json(session);
    }
    catch (error) {
        logger.error('Failed to complete onboarding', error);
        res.status(500).json({
            error: 'Failed to complete onboarding',
            message: error.message,
        });
    }
});
/**
 * GET /api/onboarding/stats
 * Get onboarding statistics
 */
router.get('/stats', async (req, res) => {
    try {
        const stats = await onboardingService.getStats();
        res.json(stats);
    }
    catch (error) {
        logger.error('Failed to fetch onboarding stats', error);
        res.status(500).json({
            error: 'Failed to fetch onboarding stats',
            message: error.message,
        });
    }
});
/**
 * POST /api/onboarding/sessions/:sessionId/auto-run-all
 * Auto-run all remaining steps
 */
router.post('/sessions/:sessionId/auto-run-all', validateSession, async (req, res) => {
    try {
        const { sessionId } = req.params;
        const session = onboardingService.getSession(sessionId);
        const results = [];
        while (session.currentStepIndex < session.steps.length) {
            const currentStep = session.steps[session.currentStepIndex];
            if (currentStep && currentStep.autoRunnable && !currentStep.completed) {
                const result = await onboardingService.executeStep(sessionId, true);
                results.push(result);
            }
            if (session.currentStepIndex < session.steps.length - 1) {
                onboardingService.nextStep(sessionId);
            }
            else {
                break;
            }
        }
        const updated = onboardingService.getSession(sessionId);
        logger.info('Auto-run all steps completed', {
            sessionId,
            stepsCompleted: results.length,
            completionPercentage: updated?.completionPercentage,
        });
        res.json({
            results,
            session: updated,
        });
    }
    catch (error) {
        logger.error('Failed to auto-run all steps', error);
        res.status(500).json({
            error: 'Failed to auto-run all steps',
            message: error.message,
        });
    }
});
export default router;
//# sourceMappingURL=onboarding.js.map